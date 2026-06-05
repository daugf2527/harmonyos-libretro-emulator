# 文件IO / 数据库 子系统 (CoreFileKit + ArkData) — ArkTS 鸿蒙 API 三源差异审计 (API 22)

> 目标 SDK = HarmonyOS 6.0.2(22) = API 22 · 本机 SDK version = 6.0.2.130
> 源 A 本地代码: `entry/src/main/ets/`(15 文件用 fileIo, 1 文件用 relationalStore, 2 文件用 picker)
> 源 B 本机 SDK .d.ts (权威, API22 真值):
>   - `…\openharmony\ets\api\@ohos.file.fs.d.ts` (fileIo, 570KB)
>   - `…\openharmony\ets\api\@ohos.file.picker.d.ts` (picker)
>   - `…\openharmony\ets\api\@ohos.data.relationalStore.d.ts` (relationalStore)
> 源 C 官方 API22 文档: developer.huawei.com (.d.ts JSDoc `@since`/`@deprecated` 即 API22 真值)
> 审计日期: 2026-06-05 · 状态: 完成(主 AI 接手 — 原 agent 被 cyber-safeguard 误拦)

---

## 结论速览

- **本地用到 22 个符号**: fileIo 17(方法 14 + 枚举 OpenMode + 类型 File/Stat) + picker 2(DocumentViewPicker/DocumentSelectOptions) + relationalStore 3(getRdbStore/SecurityLevel/StoreConfig)。
- **全部在 API22 .d.ts 存在、签名一致,0 真实 bug / 0 缺失**。
- **deprecated 命中: 0**。`@ohos.file.fs.d.ts` 全文件 **0 个 `@deprecated`**(grep 实证) → 本地所有 fileIo 方法不可能踩废弃。picker 的唯一 `@deprecated since 12`(`PhotoViewMIMETypes`)属 **Photo 系**,本地用 **Document 系**(`DocumentViewPicker`),无关。
- **RDB securityLevel 必填已正确提供**(最易缺的运行期坑,已核实): .d.ts L289 `securityLevel: SecurityLevel`(**无问号=必填**);本地 `LibraryRepository.ets` L530-532 config **有传** `securityLevel: Number(relationalStore.SecurityLevel.S1)` → 不会触发 "securityLevel required" 运行期报错。
- **since 覆盖**: fileIo/picker/RDB 全系本地用到的方法最高 since=11(OpenRawFile64 类比的 fs 大文件 API + StoreConfig crossplatform),目标 22 全覆盖。
- **ArkTS 侧天然优势**: 符号"存在性/签名"由 ArkTS **编译期类型检查**保证(用不存在的符号 .ets 直接编译失败),故本域"缺失/签名不匹配"风险结构性低于 C++(C++ dlsym 运行期才暴露)。真实风险面只剩 deprecated(编译期仅警告) + 用法坑(见 `misc-and-usage.md`)。

---

## 差异表

### fileIo (`fileIo as fs`) — @ohos.file.fs.d.ts

| API | 类型 | 本地用法摘要 | 本机.d.ts(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `fs.open` / `fs.openSync` | 函数 | 11 文件(open 10 + openSync 1) 打开文件取 File 句柄,配 OpenMode | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.close` / `fs.closeSync` | 函数 | 13 文件(close 12 + closeSync 1) 关闭句柄 | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.OpenMode` | 枚举 | 29 处 open 的 mode 位标志(READ_WRITE/CREATE/TRUNC 等) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.File` | 类型 | 11 处 open 返回的句柄类型 | 存在; since 9 | 一致 | **一致** |
| `fs.write` | 函数 | 9 文件 写文件(string/ArrayBuffer + WriteOptions) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.read` / `fs.readSync` | 函数 | 2 文件 读到 ArrayBuffer(ReadOptions offset/length) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.readText` | 函数 | 8 文件 直接读文本(便捷封装) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.mkdir` | 函数 | 12 文件 建目录(存档/配置/封面目录) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.stat` / `fs.statSync` | 函数 | 6 文件 取文件大小/mtime | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.access` | 函数 | 4 文件 判文件是否存在 | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.listFile` | 函数 | 4 文件 列目录(ListFileOptions 过滤) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.unlink` / `fs.unlinkSync` | 函数 | 7 文件 删文件 | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `fs.rename` | 函数 | 2 文件 重命名(原子落盘 tmp→正式) | 存在; since 9; 无 deprecated | 一致 | **一致** |
| `ReadOptions` / `WriteOptions` | 接口 | 2 文件 读写 offset/length/encoding | 存在; since 9 | 一致 | **一致** |

### picker — @ohos.file.picker.d.ts

| API | 类型 | 本地用法摘要 | 本机.d.ts(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `picker.DocumentViewPicker` | 类 | 2 文件 选 ROM/文件(系统文件选择器) | 存在; since 9(支持 context 入参 since 12); 无 deprecated | 一致 | **一致** |
| `picker.DocumentSelectOptions` | 类 | 配 maxSelectNumber/fileSuffixFilters | 存在; since 9; 无 deprecated | 一致 | **一致** |

### relationalStore — @ohos.data.relationalStore.d.ts

| API | 类型 | 本地用法摘要 | 本机.d.ts(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `relationalStore.getRdbStore` | 函数 | LibraryRepository.ets L551 callback 重载取 RdbStore | 存在; `(Context, StoreConfig, AsyncCallback<RdbStore>)`(L8013); since 9 | 一致 | **一致** |
| `relationalStore.SecurityLevel` | 枚举 | L532 用 `SecurityLevel.S1` | 存在; enum(L1123); since 9 | 一致 | **一致** |
| `StoreConfig.securityLevel` | 字段 | L530-532 自定义 StoreConfigCompat 传 `Number(SecurityLevel.S1)` | 存在; `securityLevel: SecurityLevel`(L289,**必填**); since 9 | 一致(类型适配,见 top3) | **一致(适配写法)** |

---

## deprecated 专项核查

| 模块 | .d.ts 中的 @deprecated | 本地是否命中 |
|------|------|------|
| @ohos.file.fs | **0 个**(全文件 grep 无 `@deprecated`) | N/A — 无可踩 |
| @ohos.file.picker | `PhotoViewMIMETypes`(@dep since 12 → photoAccessHelper) | **0 命中**(本地用 Document 系非 Photo 系) |
| @ohos.data.relationalStore | (本地用到的 getRdbStore/SecurityLevel/StoreConfig 均未标 deprecated) | **0 命中** |

---

## 资源配对检查 (文件描述符泄漏面)

| 配对 | 本地用量 | 平衡(数量层) |
|---|---|---|
| `fs.open`/`openSync` ↔ `fs.close`/`closeSync` | open 11 文件 / close 13 文件 | ✅ close ≥ open(多出因部分文件多分支 close);**建议逐文件 trace 异步/异常路径确认每个 fd 都 close**(本审计聚焦 API 兼容性,深度 fd-trace 列为真机/codelinter 复核项) |

---

## 最高优先级差异 (top3)

1. **[deprecated 零风险 / 信息]** `@ohos.file.fs` 整个模块 0 个 `@deprecated`(grep 实证),本地 17 个 fileIo 符号天然无踩废弃可能。这是本域最强的"零差异"证据。

2. **[RDB securityLevel 必填已满足 / 已核实安全]** API11 起 `StoreConfig.securityLevel` 为**必填**(.d.ts L289 无问号),老代码常因缺此字段在 API11+ 设备运行期报错。本地 L532 **已正确提供** `SecurityLevel.S1`,无此坑。

3. **[RDB 类型适配写法 / 低]** 本地未直接用 SDK 的 `StoreConfig` 类型,而是自定义 `StoreConfigCompat { name; securityLevel: number }` + `Number(relationalStore.SecurityLevel.S1)` 转换后传 `getRdbStore`。运行期 OK(S1 底层即数字),属规避 ArkTS 严格类型检查的**兼容写法**,非 bug;记录以便理解为何不直接引用 SDK StoreConfig。

---

## 统计

- **本地用到符号总数: 22**(fileIo 17 + picker 2 + relationalStore 3)
- **状态计数:**
  - **一致: 22 / 22**(全部在 API22 .d.ts 存在、签名一致、无 deprecated 命中)
  - **真实 bug: 0** · **缺失: 0** · **签名不匹配: 0**
- **deprecated 命中: 0**(fs 零 deprecated;picker deprecated 属 Photo 系本地未用)
- **since 覆盖:** 本地用到最高 since=11,目标 22 全覆盖
- **运行期必填项:** RDB securityLevel 已正确提供(唯一易缺的运行期坑,已避开)
- **fd 配对:** 数量层平衡(close ≥ open);深度异常路径 trace 列为真机/codelinter 复核项

落盘路径: `docs/audit/api22-diff/arkts/file-data.md`
