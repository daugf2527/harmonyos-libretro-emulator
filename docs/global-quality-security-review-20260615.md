# 全局质量与安全审查报告 2026-06-15

## 范围与结论

本轮审查覆盖 `entry/src/main/cpp/` native 引擎、NAPI 边界、`entry/src/main/ets/` 运行态页面与仓储层，排除 `deprecated/legacy/`、`entry/build/` 与二进制 ROM 资源。验证口径为静态审查、现有 drift/hygiene 脚本和用户提供的 2026-06-14 运行日志；未执行 hvigor 编译、未真机复测、未做 72 小时长测。

高优先级修复已落地：native core/ROM/filesDir/disk image 路径白名单、导入 ROM 删除路径二次校验、ROM 内容基础校验、仓库签名材料脱敏、native/ArkTS 路径安全日志脱敏、`dlerror()`/LastErrorInfo 脱敏、金手指输入/持久化边界、CUE 依赖写盘防穿越、内置/导入 ROM 扫描去重/过滤与伪资源清理、音频缓冲档位应用修正、切换进度 stale 回调拦截、多个 ArkTS 页面 await 后状态写入守卫。NAPI/API 契约漂移检查当前 `P5:0`。

## 已修复高优先级问题

| 编号 | 等级 | 问题 | 修复 |
| --- | --- | --- | --- |
| S-H1 | 高危 | `dlopen` 加载 native core 若允许用户可写目录，等价于同进程执行未受信任 native 代码。 | `ValidateCorePath()` 仅允许应用打包 core 目录；移除 `/files/cores` 白名单，并在 `LoadCore`、`SwitchGameAsync`、`testCoreLoader` 链路拦截。 |
| S-H2 | 高危 | ROM、磁盘镜像、filesDir 从 ArkTS/NAPI 输入进入 native 后可能被指向沙箱外。 | 新增/接入 `ValidateRomPath()`、`ValidateDiskImagePath()`、`ValidateFilesDir()`，覆盖 `LoadRom`、`SwitchGameAsync`、`SetFilesDir`、`DiskControlReplaceImageIndex`。 |
| S-H3 | 高危 | 根 `build-profile.json5` 含本地签名材料字段和值，存在凭据入库风险。 | 移除 `signingConfigs/material`，保留 SDK 26 与 `nativeCompiler` 配置；签名应走本机/CI 环境变量。 |
| S-H4 | 高危 | 部分打包 rawfile 虽有 ROM 扩展名但内容是 HTML/下载错误页，可能被传入 core 解析。 | 删除已确认的 HTML/404/空伪 ROM 资源；`RuntimeRomSourceScanner` 改为单次递归扫描、按支持 core 扩展过滤并去重；`ROMLoader::ValidateROM()` 继续在加载层拦截 HTML/XML 文档。 |
| S-H5 | 高危 | 库记录/扫描结果中的 `romFile` 若被污染，删除入口只按 `sourceType=IMPORTED` 调用 `fs.unlink`，缺少导入目录二次边界。 | 新增 `deleteImportedRomFile()`，只允许删除 `${filesDir}/roms/imported/<safeName>` 单文件；`LibraryPage` 与 `RomManagerPage` 删除入口统一调用该函数。 |
| S-M1 | 中危 | 金手指 code/label 是用户输入并持久化后传给 core，缺少统一长度/字符边界会放大 core 解析风险，且日志可能泄露用户输入。 | `RuntimeCheatRepository`/`RuntimeCheatController` 与 `refactoredCheatSet` 均限制 code 长度 `1..240`、可打印 ASCII；native 限制 index `0..1023`；同步失败日志只记录 `index/enabled/code_len`。 |
| S-M2 | 中危 | CUE 依赖写盘函数依赖上游清洗，单函数边界不足。 | `TempFileManager::WriteDependencyFile()` 增加 `IsSafeRelativePath()`，拒绝绝对路径、反斜杠、`..` 和空 basename。 |
| S-M3 | 中危 | 路径日志以 public 形式输出完整 ROM/core/filesDir/临时解包沙箱路径，用户日志可暴露目录结构和文件名上下文。 | `security::DescribePathForLog()`、`LogHelper.describePathForLog()` 与 `SanitizeErrorMessageForLog()` 统一日志/错误脱敏；NAPI、Engine、VFS、ROM/rawfile/temp 落盘、ArkTS runtime 日志仅输出路径类别和安全扩展名。 |
| S-M4 | 中危 | 导入 ROM、运行时磁盘镜像、存档/SRAM 备份文件名缺少统一长度和控制字符边界，可能导致异常文件名、过长路径、日志污染或依赖匹配不稳定。 | `RomImportService`、`RuntimeDiskImageImportService`、`SaveStateRepository`、`RuntimeSramRepository` 统一移除控制字符/路径分隔符，替换危险符号，拒绝纯点号前缀并限制文件名长度。 |
| ST-M2 | 中危 | 导入 ROM 列表扫描读取 `${filesDir}/roms/imported`，但运行/库记录路径曾拼成 `${filesDir}/roms/<file>`，导致导入 ROM 启动/删除路径不一致。 | `RuntimeRomSourceScanner` 复用 `buildImportedRomFilePath()` 生成运行和库记录路径，导入、启动、删除目录保持一致。 |
| ST-M1 | 中危 | ArkTS 页面 async 任务在页面离开或新任务开始后仍可能写 `@Local` 状态。 | `LibretroGamePage`、`CoreLoaderTest`、`MultiplayerInputPage`、`TestGambatte` 增加 pageActive/token 守卫；P7 候选降为 0。 |
| P-M1 | 中危 | 音频缓冲延迟设置只升不降，运行时从高缓冲切回低/标准档不会生效，且提前设置可能被初始化吞掉。 | `AudioBridge::SetMinimumLatencyMs()` 改为先保存请求值并每次重算目标水位；初始化后按保存值应用，最低不低于平台地板。 |

## 安全审查

### 高危

1. 已修复：未受信任 native core 注入风险。
   - 触发面：第三方 core、用户可写 core 目录、`dlopen`。
   - 影响：同进程任意 native 代码执行，读取/修改进程内存、存档、输入状态。
   - 状态：已改为打包 core 白名单。后续若重新支持第三方 core，必须先实现签名/哈希校验、版本准入、隔离进程或沙箱策略。

2. 已修复：native 文件路径越界风险。
   - 触发面：ROM、disk control、filesDir、rawfile 落地路径。
   - 影响：沙箱外文件读取/写入、错误 system/save 目录污染。
   - 状态：NAPI 入口与 engine 层均有路径校验；rawfile `roms/` 相对路径保留但拒绝 `..`。

3. 已修复：签名材料入库风险。
   - 触发面：根 `build-profile.json5` 的签名配置。
   - 影响：本地 debug/release 签名材料泄露、CI/协作者环境污染。
   - 状态：已移除仓库内签名材料；后续使用本机 DevEco 配置或 CI `SIGN_*` 环境变量。

4. 已修复：伪 ROM 网页内容进入 core parser。
   - 触发面：rawfile 或沙箱路径中扩展名像 ROM，但文件头实际为 `<!DOCTYPE`、`<html`、`<?xml` 等网页/下载错误内容。
   - 影响：无效内容被同进程 libretro core 解析，放大崩溃和解析漏洞触发面。
   - 状态：已删除 `240pTestSuite.gba`、`Anguna.gba`、`240p_md.zip`、`popcorn.prg`、`Watara_Supervision_PD.sv`、`MagicFloor.nds` 等伪/空资源；`RuntimeRomSourceScanner` 不再重复扫描子目录，且只返回能匹配支持 core 的文件；`ROMLoader::ValidateROM()` 仍在加载层保底拦截明显 HTML/XML 文档。

5. 已修复：导入 ROM 删除越界风险。
   - 触发面：`LibraryPage.deleteGame()`、`RomManagerPage.executeDelete()` 从库记录/扫描项读取 `romFile/filePath` 后直接 `fs.unlink`。
   - 影响：若本地库索引被污染，可能删除导入目录外的沙箱文件。
   - 状态：删除入口统一走 `deleteImportedRomFile()`；该函数要求路径必须位于 `${filesDir}/roms/imported/` 下、basename 经清洗后完全一致，并拒绝子目录、`..`、反斜杠和 `.importing` 临时文件。

### 中危

1. 已修复：金手指输入未统一约束。
   - 触发面：暂停菜单添加/启停金手指。
   - 影响：core 内部 cheat parser 崩溃、配置文件膨胀、日志暴露用户输入。
   - 状态：ArkTS 持久化层限制条数、code/label/id/romFile 长度并剔除控制字符；控制器与 native 均限制 code 为可打印 ASCII 且最长 240；原始 code/label 不再入日志。

2. 已修复：导入/存档/SRAM 文件名边界不足。
   - 触发面：文件选择器导入 ROM/多盘镜像、CUE/M3U 依赖名、存档 manifest 读取、SRAM 备份目录名。
   - 影响：过长路径、控制字符日志污染、异常文件名导致读写失败或依赖匹配不稳定。
   - 状态：清洗函数统一移除控制字符/路径分隔符，替换危险符号，限制文件名长度；空清洗结果会回退或拒绝。

3. 已修复：路径/错误日志暴露完整沙箱路径。
   - 触发面：core/ROM/disk/filesDir 校验失败或成功日志，Engine 消息日志，VFS 拒绝日志，rawfile/temp ROM 落盘日志。
   - 影响：hilog 或 ArkTS `GetLastErrorInfo` 中暴露应用沙箱目录结构、ROM 文件路径上下文。
   - 状态：native 日志与 `dlerror()`/`dlsym` LastError 只保留路径类别和安全扩展名；ArkTS runtime/test/import/save/SRAM 日志同样改为 `LogHelper.describePathForLog()`。校验、系统调用和 libretro `game_info.path` 仍使用原始路径，避免影响实际加载。

4. 部分缓解：存档、SRAM、配置、金手指配置为沙箱内明文。
   - 证据：`SaveStateRepository` 写 `.state`/`manifest.json`；`RuntimeCheatRepository` 写 `runtime/cheats.json`。
   - 当前未发现 token/password/API key 等远端 secret；但存档和金手指属于用户数据。
   - 已缓解：金手指持久化内容已做长度/字符集边界，失败日志不输出 code/label。
   - 建议：若目标包含隐私/共享设备场景，增加按用户选择的加密层或系统级加密说明，并避免将 ROM 文件名、路径、存档内容打到日志。

5. 部分缓解：压缩包/镜像解析风险仍主要转移给 libretro core。
   - 证据：`.zip/.7z` 是 ROM 扩展支持，未发现 app 侧通用 unzip；CUE/M3U 依赖名有 basename/sanitize 处理。
   - 风险：恶意 ROM、损坏镜像、压缩包 parser 漏洞可在同进程 core 中触发崩溃或内存破坏。
   - 建议：建立 core admission 测试集、崩溃隔离和黑名单；高风险 core 不应默认启用。

### 低危

1. 权限面较窄。
   - `module.json5` 仅申请 `ohos.permission.VIBRATE`，未发现网络、文件管理、相机、麦克风等额外系统权限。

2. 业务联网面未发现。
   - 静态搜索未发现 `fetch`、`http.createHttp`、`WebSocket`、socket 业务调用。当前没有联机数据传输加密/用户信息泄露证据；若后续加入联机功能，需默认 TLS、证书校验、最小化遥测。

## 稳定性审查

### 崩溃

| 问题 | 复现概率 | 影响范围 | 结论/修复 |
| --- | --- | --- | --- |
| 恶意/损坏 ROM 或 core 内存越界 | 中 | 单进程全局，可能直接崩溃 | 同进程 core 无法可靠兜底；已收紧 core/ROM 路径，仍需隔离进程和准入测试。 |
| 伪 ROM HTML/下载页触发 core 异常 | 高 | 内置资源和导入 ROM 加载链路 | 已删除已确认伪/空 rawfile；扫描层去重并按支持 core 过滤；native `ValidateROM()` 仍拦截明显 HTML/XML 文档。 |
| async 页面销毁后写状态 | 中 | 测试页、输入页、游戏页切换 | 已修复 P7 候选，脚本结果 `NO_GUARD=0`。 |
| GLES deinit context not current | 低到中 | 页面销毁/切换窗口 | 日志显示当前路径已防御式跳过 `glDelete*` 避免 UB，仍建议真机确认是否泄漏。 |

### 卡死

| 问题 | 复现概率 | 影响范围 | 结论/修复 |
| --- | --- | --- | --- |
| `retro_run` 长帧 | 中 | 游戏运行、音频供给、UI jank | 用户日志出现 Gambatte `Slow retro_run: 208 ms`；会导致音频 underrun 和帧抖动。需继续定位 core 执行、帧同步和调度。 |
| 快速切换任务 stale progress | 中 | 游戏切换页 | 已在 progress callback 增加 token 检查，避免旧切换覆盖新 UI 状态。 |
| 多 async 任务竞争 core 测试链路 | 中 | `TestGambatte` | 已拆分 test/auto/coreCheck token，并禁用并行入口。 |

### 异常

| 问题 | 复现概率 | 影响范围 | 结论/修复 |
| --- | --- | --- | --- |
| `read_text.cpp ret=-2` | 高 | 默认配置/布局读取 | 多数对应配置文件首次不存在，当前按默认配置降级，低风险；建议减少系统 error 噪声。 |
| `FileSecurity realpath failed ... gbc_bios.bin` | 中 | BIOS/system 文件缺失 | 现在会按允许目录处理不存在文件的父目录；仍应在 UI 提示缺 BIOS。 |
| `ThreadSampler initialize failed`、QoS failed | 中 | 系统诊断/调度 | 暂按平台噪声处理，不作为业务崩溃根因。 |

## 性能审查

当前可量化数据来自用户日志，不代表全机型曲线：

| 指标 | 观测值 | 瓶颈模块 | 建议优先级 |
| --- | --- | --- | --- |
| CPU 长帧 | `retro_run 208 ms (Gambatte)` | `LibretroEngine::ProcessFrame` / core 执行 | P1：记录 per-frame core/video/audio 分段耗时，隔离 core 长帧与渲染阻塞。 |
| GC 暂停 | YoungGC `53.012 ms`，OldGC `95.832 ms` | ArkTS 页面/列表/对象分配 | P1：减少运行页高频对象创建、避免大列表重建，长测观察 GC 次数。 |
| 音频 underrun | RingBuffer `need=1920`，got `0..1906`；OHAudio `usage=0%` | `AudioBridge` / `RingBuffer` / game loop 供给 | P0/P1：提高 producer 稳定性，加入 underrun 计数聚合；长帧时考虑动态缓冲策略。 |
| 音频回调 | callback slow `5017 us`，jitter `107 ms` | `AudioPlayer::OnWriteDataCallback` 和系统调度 | P1：回调内继续保持无锁/低分配，检查 workgroup/QoS 失败后的退化策略。 |
| 音频缓冲档位 | UI 预设 `[48,128,300]ms`；native 曾只允许非 0 latency 增大目标水位 | `AudioBridge::SetMinimumLatencyMs` | 已修复：运行时切档可升可降，提前设置不会被初始化丢弃；仍需真机/模拟器验证 underrun 改善幅度。 |
| 渲染 swap 噪声 | DGLES `sync get ret 0 error 1`、surface destroy need sync | `GLESRenderer` / EGL surface 生命周期 | P2：真机确认是否只为驱动诊断；若伴随掉帧，降低 per-frame upload 和 surface 重建频率。 |

未量化项：平均 FPS、最低 FPS、帧率波动率、CPU 单/多核占用、内存/显存峰值、功耗发热、低中高配置衰减曲线。需要真机 perf/hilog 采样、72 小时 soak、不同设备矩阵才能给出可信数值。

## 兼容性审查

静态与日志只能证明“内置 ROM 扫描”和部分 Gambatte 运行链路，不能证明逐游戏通关。

| 分类 | 当前证据 | 问题 |
| --- | --- | --- |
| 完美运行 | 暂无可确认清单 | 缺逐游戏全流程、通关和真机帧率数据。 |
| 可运行有瑕疵 | Gambatte 日志显示能进入运行，但存在 `retro_run 208 ms`、音频 underrun、GC/Jank | 需要按 ROM 逐项记录启动、剧情、战斗、存档、读档。 |
| 无法运行 | 静态曾发现若干打包 rawfile 是 HTML/下载页而非真实 ROM | 已删除已确认伪/空资源；历史设计文档中的 GBA/NDS 样本仍需以真实合法样本替换；BIOS 依赖、fullpath core、压缩包/多文件镜像仍需测试矩阵。 |

建议兼容矩阵字段：core、ROM 区域版本、格式、启动结果、首帧时间、10 分钟平均 FPS、最低 FPS、音频 underrun 次数、存读档结果、特殊外设/联机要求、最终分级。

## 输入链路审查

当前支持链路包括 ArkTS 虚拟按键、键盘/XComponent key、输入端口分配和输入映射。已修复 `MultiplayerInputPage` 刷新设备 async stale 写状态风险。未量化物理输入到画面响应耗时；需要真机高速摄像或输入时间戳到帧呈现时间戳埋点。

按设备类型：

| 设备 | 当前结论 | 待验证 |
| --- | --- | --- |
| 触控/虚拟手柄 | 已接入运行页 | 触控到游戏响应延迟、误触、横竖屏/折叠态。 |
| 键盘 | 有 XComponent key 回调与映射 | 多键冲突、长按、焦点丢失。 |
| 第三方手柄 | 有设备列表与端口分配 UI | 热插拔、多设备同接、断开恢复、死区/灵敏度。 |
| 体感/方向盘 | NAPI 有 sensor/send analog 基础接口 | 适配策略和延迟未验证。 |

补充修复：音频高缓冲切回低/标准档现在会真实降低 native 目标水位，避免用户在调试 underrun 后长期承受不必要的输入到出声延迟。

## 渲染链路审查

当前移动端按 GLES/Vulkan 能力处理，日志显示 GLES 路径存在 driver/surface 噪声但未见明确业务崩溃。`EGL context not current during Deinit` 已使用保守释放策略。需要真机截图和像素检查验证花屏、贴图错误、后处理、宽屏、Mipmap/AA。

按子模块：

| 子模块 | 问题 | 触发条件 | 影响 |
| --- | --- | --- | --- |
| EGL surface 生命周期 | surface destroy need sync、context not current | 页面切换/窗口恢复 | 可能造成资源回收延迟或驱动噪声。 |
| GLES texture upload | DGLES swap/sync 噪声 | 持续渲染 | 需确认是否伴随掉帧。 |
| HW render/core API | 不同 core GLES/Vulkan 支持差异 | PS1/NDS/街机等 | 需要 core-by-core 图像正确性验证。 |

## 内核/模拟核心审查

本项目作为 libretro frontend，不实现各目标平台 CPU 指令集翻译；指令覆盖率、时序模拟、多核调度主要由各 core 决定。frontend 可控边界是 core 加载准入、环境回调、输入/音频/视频时序、异常隔离。

风险与方案：

| 领域 | 风险 | 方案 |
| --- | --- | --- |
| 指令集/时序 | core 内部 bug 导致游戏逻辑异常/卡死 | 逐 core 版本锁定、兼容矩阵、关键 ROM 回归集。 |
| 多核调度 | frontend game loop、audio callback、render 争用 | 增加分段耗时指标和线程状态 dump；避免 UI 线程阻塞。 |
| 异常/中断 | 非法指令或 OOB 在 native core 内不可恢复 | core 隔离进程、crash quarantine、自动禁用异常 core。 |

## API 更新与漂移

已完成本地 API 契约一致性检查：`scan_code_drift.sh` 的 NAPI/API 契约项 `P5:0`。根 `build-profile.json5` 当前为 `compatibleSdkVersion=26.0.0`、`targetSdkVersion=26.0.0`、`runtimeOS=HarmonyOS`，并保留 `nativeCompiler=BiSheng`。

官方文档复核口径：华为 Hvigor/SDK 文档要求 SDK 版本满足 `compatibleSdkVersion <= targetSdkVersion <= compileSdkVersion`，具体版本字符串以 SDK Manager/本机 SDK 注册值为准。本机脚本 `scripts/check/check_harmony_api26_env.ps1` 已确认 `D:\command-line-tools\sdk\default` 下 `sdk-pkg`、`native`、`ets`、`toolchains`、`previewer` 均为 `apiVersion=26 version=26.0.0.23`，且 HMS native sysroot 存在。旧 API22 SDK 仍在 `D:\hongmeng\command-line-tools\sdk\default`，不得让仓库 wrapper 默认命中旧路径。

后续 API 更新流程已写入 `AGENTS.md`：先确认 `targetSdkVersion`/`compatibleSdkVersion`、本地 SDK `.d.ts/.h` 和官方文档，再同步 NAPI 注册、`index.d.ts`、导出清单和漂移脚本。当前仍未执行 hvigor 编译，因此 API26 适配只证明配置和本机 SDK 元数据一致，不能替代实编验证。

## 验证结果

已运行静态验证：

| 命令 | 结果 |
| --- | --- |
| `perl scripts/gc/check_async_state_guard.pl $(rg 'async ' entry/src/main/ets --glob '*.ets' -l)` | 通过，`NO_GUARD(candidates)=0` |
| `git diff --check -- <本轮任务文件>` | 通过 |
| `bash scripts/ci/check_regression_guards.sh` | 通过，`Static regression guards passed` |
| `bash scripts/ci/check_repo_hygiene.sh` | 通过，`Repository hygiene checks passed` |
| `& .\scripts\check\check_harmony_api26_env.ps1` | 通过；API26 SDK 包存在，`sdk-pkg/native/ets/toolchains/previewer apiVersion=26 version=26.0.0.23`，HMS native sysroot 存在 |
| `bash scripts/gc/scan_code_drift.sh` | 失败于既有 P2 inline color 债务；新报告 `docs/gc-code-drift-20260615-145945.md` 显示 `P1:0 P2:723 P3:0 P4:0 P5:0 P6:0 P7:0` |
| `ROMLoader::ValidateROM()` 静态复核 | 已覆盖 rawfile/VFS 两条加载链路，拦截空文件、超大文件、全零文件、明显 HTML/XML 文档 |
| `RuntimeCheatRepository`/`RuntimeCheatController` 静态复核 | 已限制金手指条数、code/label/id/romFile 长度与控制字符，控制器失败日志不再输出用户 label 或 code |
| 导入/存档/SRAM 文件名边界静态复核 | `RomImportService`、`RuntimeDiskImageImportService`、`SaveStateRepository`、`RuntimeSramRepository` 已限制控制字符、路径分隔符、危险符号、纯点号前缀和超长文件名 |
| 路径日志扫描 | 已复核 NAPI、Engine、VFS、ROM/rawfile/temp 落盘链路与 ArkTS runtime/test/import/save/SRAM 日志；剩余 `*.c_str()` 命中为系统调用、libretro 必需路径指针或已脱敏后的日志参数 |
| rawfile ROM 资源头部扫描 | 已删除 6 个 HTML/404/空伪资源；剩余 `entry/src/main/resources/rawfile/roms` 未命中 `<!DOCTYPE`、`<html`、`404 Not Found`、Git LFS pointer |

## 剩余风险

1. 未编译、未真机、未 72 小时长测；无法证明崩溃率、内存泄漏、功耗发热、逐游戏通关。
2. 同进程 libretro core 仍是最大安全/稳定风险；路径白名单和 ROM 基础校验降低触发面，但不能抵御打包 core 自身漏洞。
3. 部分历史设计文档仍引用已删除的伪 GBA/NDS 样本；需要后续以真实合法样本更新兼容矩阵与自动测试设计。
4. 用户数据当前为沙箱内明文；若产品要求更高隐私，需要加密和导出/备份策略。
5. 性能瓶颈需要真机分段埋点确认，不能只靠系统日志判断 DGLES 噪声是否等于掉帧根因。
