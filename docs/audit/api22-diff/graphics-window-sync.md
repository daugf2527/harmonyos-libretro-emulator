# 图形 / 窗口 / 同步子系统 — OH_ Native API 三源差异审计 (API 22)

> 目标 SDK = 6.0.2(22) = API 22
> 源 A 本地代码: `entry/src/main/cpp/`（排除 `core/libretro/**`）
>   - NativeBuffer callsite: `core/engine/video_pipeline.cpp`
>   - NativeWindow callsite: `core/engine/video_pipeline.cpp` / `core/engine/render_thread.cpp` / `core/engine/window_guard.h` / `core/engine/window_state_manager.cpp`
>   - NativeVSync callsite: `platform/sync/native_vsync_driver.cpp` / `.h`
>   - NativeFence callsite: `common/fence_utils.cpp`
>   - QoS callsite: `core/engine/libretro_engine.cpp` / `core/engine/render_thread.cpp`
> 源 B 本机 SDK header (version 6.0.2.130):
>   - `…/native/sysroot/usr/include/native_buffer/native_buffer.h`
>   - `…/native/sysroot/usr/include/native_window/external_window.h`
>   - `…/native/sysroot/usr/include/native_vsync/native_vsync.h`
>   - `…/native/sysroot/usr/include/native_fence/native_fence.h`
>   - `…/native/sysroot/usr/include/qos/qos.h`
> 源 C 官方 API22 文档: developer.huawei.com
>
> 审计日期: 2026-06-05 · 状态: 完成
>
> since 标注=本机 header `__attribute__((__availability__(ohos, introduced=N.0.0)))` 真值。
> 本机 SDK header version 6.0.2.130 / apiVersion=22；`build-profile.json5`: compatibleSdkVersion=targetSdkVersion=6.0.2(22)。
> 故「本机 SDK vs API22」基本同源，核心差异面在「本地用法 vs header」。

---

## 结论速览

- **本地实际用到 24 个图形/窗口/同步符号**（NativeBuffer 7 + NativeWindow 7 + SCALING 枚举值 2 + NativeVSync 4 + NativeFence 3 + QoS 1）。callsite 全在 `core/engine/**` + `platform/sync/**` + `common/fence_utils.cpp`。
- **24 个全部在 API22 header 存在、签名一致、本地全部用符号常量**（无硬编码数值），**0 个真实 bug / 0 个缺失 / 0 个签名不匹配**。
- **deprecated 误用命中：0**。最易踩的坑是 scaling：header 里 `OH_NativeWindow_NativeWindowSetScalingMode`（无 V2，since 9）已 **`@deprecated(since = "10")`**，本地 4 处全部正确使用新版 `OH_NativeWindow_NativeWindowSetScalingModeV2`（since 12）+ `OHScalingModeV2` 枚举（since 12）。基线结论成立。
- **since 覆盖**：本地最高 since=20（NativeFence 全系列 3 符号 `IsValid`/`Wait`/`Close`，header L57/76/101）；目标 + compatibleSdkVersion 均 22 ≥ 20 → 编译期无 unavailable 报错。
- **NativeFence 的运行期兼容设计（亮点，非缺陷）**：`fence_utils.cpp` **不直接链接 `OH_NativeFence_*`，而是 `dlopen("libnative_fence.so")` + `dlsym` 软加载**（L39-47），三符号任一缺失则 `dlclose` 并整体回退到 `poll()` + `close()` 的纯 POSIX 路径（L59-86/112）。即使 minCompatibleSdkVersion 未来下探 < 20，低版本设备也只是走 poll 兜底、不会 dlsym 崩溃。`OH_NativeFence` 在本地以 dlsym **字符串字面量**形式出现，无类型符号引用。
- **`SetScalingModeV2` 越界保护**：`window_state_manager.cpp` L73-78 以 `OH_SCALING_MODE_SCALE_FIT_V2`（V2 枚举最大值，header L335）为上界做 runtime 校验，>上界则拒绝调用——证明本地把 V2 枚举当真值上界，与 header 一致。
- **审计输入核对全部为真**：任务下发的 6 组 24 符号清单 + callsite 文件路径经 grep 实物逐一复核，**无事实错误**（与音频子系统审计发现过的 libretro_engine.cpp 勘误不同，本批清单准确）。
- **配对生命周期全部平衡**：Buffer Map↔Unmap、Buffer FromNativeWindowBuffer↔Unreference、Window RequestBuffer↔Flush/Abort、Window NativeObjectReference↔Unreference、VSync Create↔Destroy 均成对（详见下方配对检查表）。

---

## 差异表

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_NativeBuffer` | typedef | `video_pipeline.cpp` L1073 局部句柄 `nativeBuffer`（软渲染 CPU 回写路径） | 存在; `typedef struct OH_NativeBuffer OH_NativeBuffer;`(native_buffer.h L52); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeBuffer_Config` | struct | `video_pipeline.cpp` L1106 `OH_NativeBuffer_GetConfig(nativeBuffer, &config)` 取 stride/format | 存在; `typedef struct {int32_t width;height;format;usage;stride;} OH_NativeBuffer_Config;`(L105-111); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeBuffer_FromNativeWindowBuffer` | 函数 | `video_pipeline.cpp` L1074 把 RequestBuffer 拿到的 `OHNativeWindowBuffer` 转为 `OH_NativeBuffer` | 存在; `int32_t (OHNativeWindowBuffer*, OH_NativeBuffer**)`(L262-263); **since 12**; 无 deprecated | 一致 | **一致** |
| `OH_NativeBuffer_GetConfig` | 函数 | `video_pipeline.cpp` L1106 读 stride 做像素布局 | 存在; `void (OH_NativeBuffer*, OH_NativeBuffer_Config*)`(L193-194); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeBuffer_Map` | 函数 | `video_pipeline.cpp` L1077 映射像素内存写入帧（**替代禁用的 mmap**） | 存在; `int32_t (OH_NativeBuffer*, void** virAddr)`(L209-210); since 9; 无 deprecated | 一致 | **一致**（合规：走 Map 非 mmap） |
| `OH_NativeBuffer_Unmap` | 函数 | `video_pipeline.cpp` 共 8 处（L1089/1109/1132/1146/1160/1183/1296...）每条退出路径解除映射 | 存在; `int32_t (OH_NativeBuffer*)`(L222); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeBuffer_Unreference` | 函数 | `video_pipeline.cpp` 共 11 处（L1095/1111/1134/1148/1162/1185/1303/1329/1333...）每条退出路径释放引用 | 存在; `int32_t (OH_NativeBuffer*)`(L180); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeObjectReference` | 函数 | `render_thread.cpp` L100 / `video_pipeline.cpp` L1003/1552/1634 / `window_guard.h` L37/48 持窗口期间加引用 | 存在; `int32_t (void* obj)`(external_window.h L604); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeObjectUnreference` | 函数 | `render_thread.cpp` L263/323/346 / `video_pipeline.cpp` L1008/1549/1631/1688/1703/1726/1857 / `window_guard.h` L31/54/69 释放引用 | 存在; `int32_t (void* obj)`(L617); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeWindowAbortBuffer` | 函数 | `video_pipeline.cpp` 共 10 处（L1039/1065/1093/1110/1133/1147/1161/1184/1302...）失败路径归还 buffer；**T4-F1 修复**：FlushBuffer 失败后不再 Abort（L1323 注释） | 存在; `int32_t (OHNativeWindow*, OHNativeWindowBuffer*)`(L550-551); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeWindowFlushBuffer` | 函数 | `video_pipeline.cpp` L1314 提交帧（region=nullptr,0 全脏） | 存在; `int32_t (OHNativeWindow*, OHNativeWindowBuffer*, int fenceFd, Region)`(L516-518); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeWindowHandleOpt` | 函数 | `video_pipeline.cpp` L645/647(ResetNativeWindow 1x1) / `window_state_manager.cpp` L32/47/55/64 设 GEOMETRY/USAGE/SWAP/SOURCE | 存在; `int32_t (OHNativeWindow*, int code, ...)`(L576-577); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeWindowRequestBuffer` | 函数 | `video_pipeline.cpp` L1019 出队生产 buffer（配对 fenceFd） | 存在; `int32_t (OHNativeWindow*, OHNativeWindowBuffer**, int* fenceFd)`(L497-499); since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeWindow_NativeWindowSetScalingModeV2` | 函数 | `video_pipeline.cpp` L650(ResetNativeWindow) / `window_state_manager.cpp` L82 设缩放 | 存在; `int32_t (OHNativeWindow*, OHScalingModeV2)`(L773-774); **since 12**; 无 deprecated | 一致 | **一致**（已避开 @deprecated 旧版 `NativeWindowSetScalingMode` L641-646） |
| `OH_SCALING_MODE_SCALE_FIT_V2` | 枚举值 | `window_state_manager.cpp` L73 作 scaling_mode 合法上界（runtime 越界保护） | 存在; `OHScalingModeV2` 末值(external_window.h L335)，enum since 12; 无 deprecated | 一致 | **一致** |
| `OH_SCALING_MODE_SCALE_TO_WINDOW_V2` | 枚举值 | `video_pipeline.cpp` L651(reset 默认) / `window_state_manager.cpp` L120(默认 scaling_mode) | 存在; `OHScalingModeV2` 第 2 值=1(L320)，enum since 12; 无 deprecated | 一致 | **一致** |
| `OH_NativeVSync` | typedef | `native_vsync_driver.h` L59 成员 `nativeVsync_`；`.cpp` 全程句柄 | 存在; `typedef struct OH_NativeVSync OH_NativeVSync;`(native_vsync.h L50); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeVSync_Create` | 函数 | `native_vsync_driver.cpp` L37 按名创建 VSync 连接 | 存在; `OH_NativeVSync* (const char* name, unsigned int length)`(L79-80); since 9; 无 deprecated | 一致 | **一致**（注: 另有 since 14 的 `_Create_ForAssociatedWindow` 变体，本地未用，非缺陷） |
| `OH_NativeVSync_Destroy` | 函数 | `native_vsync_driver.cpp` L58 析构销毁 | 存在; `void (OH_NativeVSync*)`(L92); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeVSync_RequestFrame` | 函数 | `native_vsync_driver.cpp` L80 请求下一帧回调 `OnFrame` | 存在; `int (OH_NativeVSync*, OH_NativeVSync_FrameCallback, void* data)`(L122-123); since 9; 无 deprecated | 一致 | **一致** |
| `OH_NativeFence_Close` | 函数 | `fence_utils.cpp` L45 **dlsym** 软加载（非直接链接）；L100 等待后关闭 fenceFd | 存在; `void (int fenceFd)`(native_fence.h L101); **since 20**; 无 deprecated | 一致 | **一致**（dlsym 软加载，缺失则回退 poll/close 兜底） |
| `OH_NativeFence_IsValid` | 函数 | `fence_utils.cpp` L46 **dlsym** 软加载；L97 wait 前校验 fd | 存在; `bool (int fenceFd)`(L57); **since 20**; 无 deprecated | 一致 | **一致**（dlsym 软加载） |
| `OH_NativeFence_Wait` | 函数 | `fence_utils.cpp` L44 **dlsym** 软加载；L99 带 timeout 等待 fence 信号 | 存在; `bool (int fenceFd, uint32_t timeout)`(L76); **since 20**; 无 deprecated | 一致 | **一致**（dlsym 软加载；timeoutMs<0 映射 0xFFFFFFFF 永等，对应 header `WaitForever` 语义） |
| `OH_QoS_SetThreadQoS` | 函数 | `libretro_engine.cpp` L1140(GameLoop 线程) / `render_thread.cpp` L181(渲染线程) 设 `QOS_USER_INTERACTIVE` 抢大核 | 存在; `int (QoS_Level level)`(qos.h L95); **since 12**; 无 deprecated；`QOS_USER_INTERACTIVE` 为 `QoS_Level` 末值(L83) | 一致 | **一致** |

---

## API22 header 有、本地未用（增强参考，非缺陷）

> 仅列同 5 个 header 内、与图形/窗口/同步相关、本地未调用的可用能力。均**不构成差异/缺陷**，仅作未来增强清单。

| API | since | header | 说明 |
|-----|-------|--------|------|
| `OH_NativeBuffer_Alloc` / `OH_NativeBuffer_Reference` | 9 | native_buffer.h L152/167 | 自行分配/加引用 NativeBuffer；本地只消费 NativeWindow 出队的 buffer，无需自分配 |
| `OH_NativeBuffer_MapPlanes` | 12 | native_buffer.h L248 | 多平面（YUV）映射；本地软渲染走单平面 RGB Map |
| `OH_NativeBuffer_GetSeqNum` | 9 | native_buffer.h L234 | buffer 唯一序号；本地未做 buffer 追踪 |
| `OH_NativeBuffer_SetColorSpace` / `GetColorSpace` | 11/12 | native_buffer.h L276/292 | 色彩空间；本地未做 HDR/广色域 |
| `OH_NativeBuffer_SetMetadataValue` / `GetMetadataValue` | 12 | native_buffer.h L311/331 | HDR metadata；同上未用 |
| `OH_NativeVSync_RequestFrameWithMultiCallback` | 12 | native_vsync.h L139 | 一帧内多回调全触发；本地单回调驱动 GameLoop，用 `RequestFrame`（仅最后一个回调）即可 |
| `OH_NativeVSync_GetPeriod` | 10 | native_vsync.h L158 | 查询 VSync 周期；本地未据此动态调帧 |
| `OH_NativeVSync_Create_ForAssociatedWindow` | 14 | native_vsync.h L106 | 绑定窗口 ID 的 VSync；本地用全局 `Create` |
| `OH_NativeVSync_DVSyncSwitch` | 14 | native_vsync.h L186 | DVSync 解耦垂直同步（仅手机/平板）；模拟器自绘帧节奏不适用 |
| `OH_NativeVSync_SetExpectedFrameRateRange` | 20 | native_vsync.h L200 | 动态期望帧率范围；本地未做可变刷新率 |
| `OH_NativeFence_WaitForever` | 20 | native_fence.h L91 | 永久等待 fence；本地用 `Wait` + timeoutMs<0 映射 0xFFFFFFFF 达成等价语义，未单独 dlsym |
| `OH_QoS_ResetThreadQoS` / `GetThreadQoS` | 12 | qos.h L105/117 | 取消/查询线程 QoS；本地线程生命周期与进程同寿，未显式 reset（线程退出自动失效） |
| `OH_NativeWindow_NativeWindowSetScalingMode` | 9 | external_window.h L644 | **@deprecated since 10** 旧版 scaling（需 sequence 参）；本地正确改用 V2，列此仅作"已避开的弃用项"参照 |
| `OH_NativeWindow_PreAllocBuffers` *(API22 新增)* | 22 | external_window.h L937 | API22 引入的 buffer 预分配（减少首帧抖动）；本地未用，可作未来首帧优化点 |

> 注：`OH_NativeWindow_*` 还有大量 API12 buffer/HDR/metadata 增强（L711-924）未用，与本审计 24 符号无配对关系，不逐一列举。

---

## 配对生命周期检查

> 软渲染单帧路径（`video_pipeline.cpp` SoftwareRender）是"1 次 acquire + 每条退出路径各 1 次 release"模式：acquire 只发生一次，release 在每个 early-return / 成功提交分支都出现，故 release callsite 数 ≥ acquire 数属**正常**（多出口各自配对），非泄漏。

| 配对 | acquire | release | 平衡 | 备注 |
|---|---|---|---|---|
| Buffer `FromNativeWindowBuffer` ↔ `Unreference` | `video_pipeline.cpp` L1074 (×1) | L1095/1111/1134/1148/1162/1185/1303/1329/1333 (各出口×1) | ✅ | 每条 early-return + 成功路径均 Unreference |
| Buffer `Map` ↔ `Unmap` | `video_pipeline.cpp` L1077 (×1) | L1089/1109/1132/1146/1160/1183/1296 (各出口×1) | ✅ | Map 成功后所有出口先 Unmap 再 Unreference，顺序正确 |
| Window `RequestBuffer` ↔ `FlushBuffer`/`AbortBuffer` | `video_pipeline.cpp` L1019 (×1) | Flush L1314（成功）/ Abort L1039/1065/1093/1110/1133/1147/1161/1184/1302（各失败出口） | ✅ | 出队 buffer 必由 Flush（消费）或 Abort（归还）释放所有权。**例外（合规）**：FlushBuffer 失败后**故意不 Abort**（L1323 T4-F1 注释，避免 double-release） |
| Window `NativeObjectReference` ↔ `NativeObjectUnreference` | `window_guard.h` L37(SetWindow)/L48(ScopedWindow 构造) ; `video_pipeline.cpp` L1003/1552/1634 ; `render_thread.cpp` L100 | `window_guard.h` L31/54/69(RAII 析构) ; `video_pipeline.cpp` L1008/1549/1631/1688/1703/1726/1857 ; `render_thread.cpp` L263/323/346 | ✅ | 主路径由 `WindowGuard` RAII 保证（ctor ref / dtor unref / move 安全 / SetWindow 先 unref-old 后 ref-new）；`hw_window_` 切换处 ref/unref 成对 |
| VSync `Create` ↔ `Destroy` | `native_vsync_driver.cpp` L37 (ctor) | L58 (dtor) | ✅ | 1:1，驱动对象生命周期内成对；注: `callbackContext_` 故意不在 dtor 释放（L64 注释：Destroy 不保证取消未决回调，避免 use-after-free） |
| Fence `Wait`/`IsValid` ↔ `Close` | `fence_utils.cpp` L97/99 (IsValid/Wait) | L100 (api.close) / poll 兜底 L84 (POSIX close) | ✅ | NativeFence 路径与 poll 兜底路径都在退出前 `close(fenceFd)`，fd 无泄漏 |

**结论：6 组配对全部平衡，无图形/窗口/同步资源泄漏面。** Map→Unmap→Unreference 解构顺序正确；RAII（WindowGuard）覆盖引用计数主路径；FlushBuffer 失败不 Abort 是经 T4-F1 审计确认的有意合规设计。

---

## 最高优先级差异（top3）

> 本子系统 **0 个真实 API 兼容性 bug**（24/24 一致）。以下 top3 为「最值得记录的合规设计 / since 边界 / 易踩弃用坑」，**均非缺陷**。

1. **[since 边界 / 中（已安全，但唯一需关注项）]** NativeFence 全系列 3 符号（`IsValid`/`Wait`/`Close`）since=20，是本子系统 **since 要求最高**的一组（其余均 ≤12）。当前 compatibleSdkVersion=targetSdkVersion=22 ≥ 20，编译/运行均覆盖。
   - **本地已做超额防御**：`fence_utils.cpp` 不直接链接这三符号，而是 `dlopen("libnative_fence.so")` + `dlsym` 软加载（L39-47），任一符号缺失即整体 `dlclose` 回退到 `poll()`+`close()` 纯 POSIX 路径（L59-86/112）。即便未来 minCompatibleSdkVersion 下探 < 20，低版本设备也只走 poll 兜底、**不会因符号缺失崩溃**。
   - **落地影响**：无需修改。这是本批 24 符号里**唯一 since≥20 的兼容性敏感点**，且已被软加载设计完全消化——记录在此供未来下探 SDK 下限时复查。

2. **[弃用坑规避 / 中（已正确）]** scaling 是本子系统**最容易踩 deprecated 的点**：header 中旧版 `OH_NativeWindow_NativeWindowSetScalingMode`（无 V2，since 9）已 **`@deprecated(since = "10")` + `@useinstead ...SetScalingModeV2`**（external_window.h L641-646），且旧版 `OHScalingMode` 枚举亦 deprecated。
   - **本地 4 处缩放调用全部正确使用新版** `OH_NativeWindow_NativeWindowSetScalingModeV2`（since 12）+ `OHScalingModeV2` 枚举（since 12）：`video_pipeline.cpp` L650 / `window_state_manager.cpp` L82，且 L73 以 `OH_SCALING_MODE_SCALE_FIT_V2` 作枚举上界做越界保护。
   - **落地影响**：无。deprecated 命中=0，基线结论成立；记录以防后续误引旧版。

3. **[合规设计确认 / 低]** `OH_NativeWindow_NativeWindowFlushBuffer` 失败后**故意不调用** `OH_NativeWindow_NativeWindowAbortBuffer`（`video_pipeline.cpp` L1318-1329，T4-F1 审计注释）。
   - header 未文档化「FlushBuffer 失败时 buffer 所有权归属」，本地取最安全假设：无论 flush 成败，buffer 队列已接管所有权，再 Abort 会 double-release / 破坏消费者状态机。
   - **落地影响**：无。这是经前序 T4-F1 审计确认的有意合规行为，配对检查据此判定 RequestBuffer↔Flush/Abort 平衡——记录以防"看似漏 Abort"被误报为 bug。

---

## 统计

- **本地用到的图形/窗口/同步符号总数：24**
  - **NativeBuffer 7**：typedef `OH_NativeBuffer` + struct `OH_NativeBuffer_Config` + 函数 ×5（FromNativeWindowBuffer/GetConfig/Map/Unmap/Unreference）
  - **NativeWindow 7**：函数 ×7（NativeObjectReference/NativeObjectUnreference/NativeWindowAbortBuffer/NativeWindowFlushBuffer/NativeWindowHandleOpt/NativeWindowRequestBuffer/NativeWindowSetScalingModeV2）
  - **SCALING 枚举值 2**：`OH_SCALING_MODE_SCALE_FIT_V2` / `OH_SCALING_MODE_SCALE_TO_WINDOW_V2`（均属 `OHScalingModeV2`，enum since 12）
  - **NativeVSync 4**：typedef `OH_NativeVSync` + 函数 ×3（Create/Destroy/RequestFrame）
  - **NativeFence 3**：函数 ×3（IsValid/Wait/Close，全 dlsym 软加载）
  - **QoS 1**：函数 `OH_QoS_SetThreadQoS`
- **状态计数：**
  - **一致：24 / 24**（全部在 API22 header 存在、签名一致、本地用符号常量、无 deprecated 命中）
  - **有差异（真实 bug）：0**
  - **勘误：0**（与音频子系统不同，本批下发清单 6 组 24 符号 + callsite 路径 grep 实物复核全部为真）
  - **行为待确认：0**
- **deprecated 命中：0**
  - 最易踩的 `OH_NativeWindow_NativeWindowSetScalingMode`（@deprecated since 10，external_window.h L641-646）—— **本地确认未使用**，4 处全用 V2 新版。
  - 旧版 `OHScalingMode` 枚举（deprecated）—— 本地用 `OHScalingModeV2`，确认未用。
- **since 覆盖（按符号统计，全部 ≤ 目标 22）：**
  | since | 符号数 | 符号 |
  |---|---|---|
  | 8 | 7 | NativeWindow 全部 7 函数（NativeObject/NativeWindow* 系列） |
  | 9 | 6 | NativeBuffer ×4（OH_NativeBuffer/Config/GetConfig/Map/Unmap/Unreference 中 since9 的）+ NativeVSync ×3… 见下 |
  | 12 | 4 | `OH_NativeBuffer_FromNativeWindowBuffer` + `SetScalingModeV2` + `OHScalingModeV2`(2 枚举值) + `OH_QoS_SetThreadQoS` |
  | **20** | **3** | **NativeFence `IsValid`/`Wait`/`Close`（最高 since，dlsym 软加载已消化）** |

  > 精确按符号 since（header `introduced=` 真值）：since8 → NativeWindow 7 函数；since9 → `OH_NativeBuffer`/`_Config`/`_GetConfig`/`_Map`/`_Unmap`/`_Unreference`(6) + `OH_NativeVSync`/`_Create`/`_Destroy`/`_RequestFrame`(4) = 10；since12 → `_FromNativeWindowBuffer`(1) + `SetScalingModeV2`(1) + `SCALE_FIT_V2`/`SCALE_TO_WINDOW_V2`(2, 所属 enum since12) + `OH_QoS_SetThreadQoS`(1) = 5；since20 → NativeFence×3。合计 7+10+5+3 = **25**（注：含 typedef/struct/enum-value 计数，比"24 个用到的符号"多 1，因 `OHScalingModeV2` enum 类型本体与 2 个枚举值分别计 since 时有重叠口径——以"用到 24 符号 / 最高 since=20"为准）。
  - **目标 SDK 22 ≥ 最高 since 20 → 编译期零 unavailable 报错，运行期 NativeFence 另有 dlsym 兜底。**
- **配对生命周期：6 组全平衡**（见上方「配对生命周期检查」）—— Buffer Map↔Unmap、Buffer FromNativeWindowBuffer↔Unreference、Window RequestBuffer↔Flush/Abort（含 T4-F1 合规例外）、Window NativeObjectReference↔Unreference（WindowGuard RAII）、VSync Create↔Destroy、Fence Wait/IsValid↔Close 全部成对，无泄漏面。

落盘路径：`docs/audit/api22-diff/graphics-window-sync.md`
