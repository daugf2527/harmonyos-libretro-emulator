# 资源 / 文件IO / 日志 子系统 — OH_ Native API 三源差异审计 (API 22)

> 目标 SDK = HarmonyOS 6.0.2(22) = API 22 · 本机 SDK header version = 6.0.2.130 (apiVersion=22)
> 源 A 本地代码:
>   - `entry/src/main/cpp/platform/resource/platform_resource_manager.cpp` (ResourceManager rawfile 读取/列举)
>   - `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp` (NAPI 层 ResourceManager Init/Release + rawfile 递归列举)
>   - `entry/src/main/cpp/platform/resource/rom_loader.cpp` (FileUri 转换)
>   - `entry/src/main/cpp/common/diagnostics/logger_provider.cpp` + `common/log_prefix.h` (OH_LOG_Print)
>   - `entry/src/main/cpp/tests/integration/test_gambatte_rom.cpp` (测试,用同组 rawfile API)
> 源 B 本机 SDK header (权威, API22 真值):
>   - `…/native/sysroot/usr/include/rawfile/raw_file.h` + `raw_dir.h` + `raw_file_manager.h`
>   - `…/native/sysroot/usr/include/filemanagement/file_uri/oh_file_uri.h`
>   - `…/native/sysroot/usr/include/hilog/log.h`
> 源 C 官方 API22 文档: developer.huawei.com (header `@since`/`@deprecated` 注释即 API22 真值,无需 web 补充)
>
> 审计日期: 2026-06-05 · 状态: 完成

---

## 结论速览

- **本地用到 13 个 OH_ 资源/文件/日志符号**(10 ResourceManager + 2 FileUri + 1 Log)。
- **全部 13 个在 API22 header 存在、签名一致、本地全用符号常量(无硬编码),0 个真实 bug / 0 个缺失 / 0 个签名不匹配**。
- **deprecated 命中: 0**。header 内 `OH_ResourceManager_GetRawFileDescriptor` + `OH_ResourceManager_ReleaseRawFileDescriptor`(@deprecated since 12,应改用 `*Data` 版)—— 经 grep **本地完全未用**,走 64 位 `OpenRawFile64`/`ReadRawFile64`/`CloseRawFile64` 流程,**规避正确**。
- **64 位变体选择正确**: 本地全用 `*RawFile64`(since 11) 而非 32 位 since-8 旧版(`OpenRawFile`/`ReadRawFile`/`GetRawFileSize`)。32 位版用 `long`/`size_t` 有大文件截断风险;对模拟器可能 >2GB 的光盘镜像/ROM,64 位 `int64_t` 是正确选择。**非 deprecated,但属正确的前瞻选型**。
- **FileUri 内存配对正确**(最易藏泄漏点,已核实): `OH_FileUri_GetPathFromUri`(rom_loader.cpp L200) 分配的 `pathResult`,在 L207 拷入 std::string 后 **L208 `free(pathResult)`** 正确释放;错误路径(L202)提前 return,header 保证失败时不产出有效内存 → **无泄漏**。
- **OH_LOG_Print 日志规范合规**: type=`LOG_APP`、占位符全用 `%{public}s/%{public}d`(符合项目日志规范)、domain 走 `LOG_DOMAIN` 宏(0xD000-0xFFFF 由 `check_regression_guards.sh` 另行守护,本审计不重复)。
- **since 覆盖**: 本地实际用到符号最高 since=**12**(FileUri 全系列);目标 + compatibleSdkVersion 均 22 ≥ 12 → **无低版本 dlsym 风险**。

---

## 差异表

> since 标注 = 本机 header `__attribute__((__availability__(ohos, introduced=N.0.0)))` 真值。

### ResourceManager (rawfile) — raw_file_manager.h / raw_file.h / raw_dir.h

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_ResourceManager_InitNativeResourceManager` | 函数 | engine_lifecycle_napi.cpp L87/176/282 + test L225 由 js ResMgr 取 native mgr | 存在; `(napi_env, napi_value) -> NativeResourceManager*`(manager.h L77); **since 8**; 无 deprecated | 一致 | **一致** |
| `OH_ResourceManager_ReleaseNativeResourceManager` | 函数 | engine_lifecycle_napi.cpp 10 处(L106/119/185/222/242/259/295/308/325/342,含异步 ctx 多分支清理) + test 3 处 | 存在; `(NativeResourceManager*)`(manager.h L89); **since 8** | 一致 | **一致** |
| `OH_ResourceManager_OpenRawDir` | 函数 | engine_lifecycle_napi.cpp L132/148(递归) + platform_resource_manager.cpp L169 | 存在; `(const NativeResourceManager*, const char*) -> RawDir*`(manager.h L108); **since 8** | 一致 | **一致** |
| `OH_ResourceManager_CloseRawDir` | 函数 | engine_lifecycle_napi.cpp L150/156 + prm L183 | 存在; `(RawDir*)`(raw_dir.h L100); **since 8** | 一致 | **一致** |
| `OH_ResourceManager_GetRawFileCount` | 函数 | engine_lifecycle_napi.cpp L137 + prm L175 遍历目录 | 存在; `(RawDir*) -> int`(raw_dir.h L88); **since 8** | 一致 | **一致** |
| `OH_ResourceManager_GetRawFileName` | 函数 | engine_lifecycle_napi.cpp L139 + prm L177 按 index 取名 | 存在; `(RawDir*, int) -> const char*`(raw_dir.h L75); **since 8** | 一致 | **一致** |
| `OH_ResourceManager_OpenRawFile64` | 函数 | platform_resource_manager.cpp L101 + test L238 | 存在; `(const NativeResourceManager*, const char*) -> RawFile64*`(manager.h L144); **since 11** | 一致 | **一致**(64 位变体) |
| `OH_ResourceManager_GetRawFileSize64` | 函数 | platform_resource_manager.cpp L105 + test L252 | 存在; `(RawFile64*) -> int64_t`(raw_file.h L299); **since 11** | 一致 | **一致** |
| `OH_ResourceManager_ReadRawFile64` | 函数 | platform_resource_manager.cpp L123 + test L282 | 存在; `(const RawFile64*, void*, int64_t) -> int64_t`(raw_file.h L271); **since 11** | 一致 | **一致** |
| `OH_ResourceManager_CloseRawFile64` | 函数 | platform_resource_manager.cpp L109/117/124(多分支) + test L256/269/285 | 存在; `(RawFile64*)`(raw_file.h L323); **since 11** | 一致 | **一致** |

### FileUri — filemanagement/file_uri/oh_file_uri.h

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_FileUri_IsValidUri` | 函数 | rom_loader.cpp L193 转换前校验 URI 合法性 | 存在; `(const char* uri, unsigned int length) -> bool`(L113); **since 12** | 一致 | **一致** |
| `OH_FileUri_GetPathFromUri` | 函数 | rom_loader.cpp L200 URI→路径; 返回 `FileManagement_ErrCode`,判 `!=0` 失败,result 用 free() 释放(L208) | 存在; `(const char* uri, unsigned int length, char** result) -> FileManagement_ErrCode`(L83); **since 12**; 契约要求 result 由调用方 `free()` | 一致 | **一致**(返回码 + free 配对均正确) |

### 日志 — hilog/log.h

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_LOG_Print` | 函数(变参) | log_prefix.h L13 `LOGF` 宏底座 + logger_provider.cpp L18; type=LOG_APP,占位符 `%{public}s` | 存在; `(LogType, LogLevel, unsigned int domain, const char* tag, const char* fmt, ...) -> int`(L181),带 `__format__(os_log,5,6)`; **since 8** | 一致 | **一致**(占位符/domain 规范合规) |

---

## API22 header 有、本地未用(增强参考,非缺陷)

| API | since | 文件 | 说明 |
|-----|-------|------|------|
| `OH_ResourceManager_GetRawFileDescriptorData` / `ReleaseRawFileDescriptorData` | 12 | raw_file.h | fd+offset+length 方式访问 rawfile(可配合 mmap);本地用 Read64 一次性读入内存,未用 fd 路径 |
| `OH_ResourceManager_GetRawFileDescriptor64` | 11 | raw_file.h | 64 位 fd 描述符;同上未用 |
| `OH_ResourceManager_SeekRawFile64` / `GetRawFileOffset64` / `GetRawFileRemainingLength64` | 11 | raw_file.h | 随机访问/偏移;本地一次性整读不 seek |
| `OH_ResourceManager_IsRawDir` | 12 | raw_file_manager.h | 判定 rawfile 路径是否目录;本地用 OpenRawDir 返回值隐式判定 |
| `OH_FileUri_GetUriFromPath` / `GetFullDirectoryUri` | 12 | oh_file_uri.h | path→uri / 取所在目录 uri;本地只需 uri→path 单向 |
| `OH_FileUri_GetFileName` | 13 | oh_file_uri.h | 从 uri 取末段文件名;本地自行 substring 处理 |
| 32 位 rawfile 全系列(`OpenRawFile`/`ReadRawFile`/`GetRawFileSize`/`SeekRawFile`/`GetRawFileOffset`) | 8 | raw_file.h/manager.h | **本地有意避开**,改用 64 位变体规避大文件截断 |

> 以上均为「本地未用」的 API22 可用能力,**不构成差异/缺陷**。

---

## 配对生命周期检查(全部平衡)

| 配对 | acquire | release | 平衡 |
|---|---|---|---|
| Init ↔ Release NativeResourceManager (NAPI 层临时 mgr) | L87 / L176 / L282 | 每条成功/失败/异步分支各 1 次 Release 并置 nullptr 防双释放(L106/119/185/222/242/259/295/308/325/342) | ✅ |
| OpenRawDir ↔ CloseRawDir | napi L132/L148 · prm L169 | napi L156/L150 · prm L183 | ✅ |
| OpenRawFile64 ↔ CloseRawFile64 | prm L101 · test L238 | prm L109/L117/L124(每错误/成功分支) · test L256/L269/L285 | ✅ |
| FileUri GetPathFromUri ↔ free(result) | rom_loader.cpp L200(分配 pathResult) | rom_loader.cpp L208 `free(pathResult)` | ✅(错误路径 L202 提前 return,header 保证不产出有效内存) |

> 注: `platform_resource_manager.cpp` 的 `native_mgr` 为该类成员(长生命周期,外部注入),其 Init/Release 不在本文件内;本文件 callsite 仅做 Open/Read/Close 等只读/配对操作。NAPI 层(engine_lifecycle_napi.cpp)才是 Init→用→Release 的临时 mgr 完整闭环。`GetRawFileCount`/`GetRawFileName` 为只读,无需配对。

---

## 最高优先级差异(top3)

1. **[deprecated 规避正确 / 信息]** header 内 `OH_ResourceManager_GetRawFileDescriptor` + `OH_ResourceManager_ReleaseRawFileDescriptor`(both **@deprecated since 12**,useinstead `*RawFileDescriptorData`)。grep 全 cpp 树(排除 `core/libretro/**`)**本地 0 命中** —— 本地走 64 位 Open/Read/Close 内存读取流程,从不碰 descriptor 系列。**无缺陷,规避正确**。

2. **[64 位前瞻选型 / 信息]** 本地全用 `*RawFile64`(since 11) 而非 32 位 since-8 旧版。32 位 `OH_ResourceManager_GetRawFileSize` 返回 `long`、`ReadRawFile` 用 `size_t length`,在大文件上有截断/溢出风险。模拟器 ROM 多数 <2GB,但 PS1/街机光盘镜像可能逼近或超过 —— 64 位选型对该场景是**正确防御**,非差异。

3. **[FileUri result 内存契约 / 已核实安全]** `OH_FileUri_GetPathFromUri` 的 `result` 出参 header 明确要求调用方 `free()`。本地 rom_loader.cpp **L208 已正确 free**,且 `OH_FileUri_IsValidUri`(L193)先行校验 + 返回码判定(L202)双重防护。这是本子系统**唯一需要手动内存管理的 API**,已核实无泄漏 —— 记录为"已验证安全点"而非缺陷。

---

## 统计

- **本地用到符号总数: 13**(ResourceManager 函数 10 + FileUri 函数 2 + Log 函数 1)
- **状态计数:**
  - **一致: 13 / 13**(全部在 API22 header 存在、签名一致、用符号常量、无 deprecated 命中)
  - **有差异(代码层面): 0**
  - **真实 bug: 0** · **缺失: 0** · **签名不匹配: 0**
- **deprecated 命中: 0**(descriptor 系列 @deprecated since 12 本地未用)
- **since 覆盖:** 本地实际用到最高 since=12(FileUri);since 分布 = since8 ×7(Init/Release/OpenRawDir/CloseRawDir/GetCount/GetName/LOG_Print) + since11 ×4(RawFile64 系列) + since12 ×2(FileUri)。目标 + compatibleSdkVersion 均 22,全覆盖。
- **内存/句柄配对: 4 组全平衡**(Init↔Release / OpenRawDir↔CloseRawDir / OpenRawFile64↔CloseRawFile64 / FileUri GetPathFromUri↔free),无泄漏面。

落盘路径: `docs/audit/api22-diff/resource-system.md`
