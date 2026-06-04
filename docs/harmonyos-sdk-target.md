# HarmonyOS SDK Target

当前项目统一目标版本：

- `compatibleSdkVersion`: `6.0.2(22)`
- `targetSdkVersion`: `6.0.2(22)`
- 本机可用模拟器镜像：`HarmonyOS-6.0.2`
- 本机镜像元数据：`apiVersion = 22`
- 本机 DevEco / SDK 目录：`D:\Program Files\DevEco Studio\sdk\default`
- `sdk-pkg.json` / native `oh-uni-package.json`：`apiVersion = 22`，`version = 6.0.2.130`

Native 音频路径按 API22 口径维护：

- `OH_AudioStreamBuilder_SetRendererCallback` 与 `OH_AudioRenderer_Callbacks` 在本机 API22 头文件中标记为 `@deprecated since 20`。
- 使用 `OH_AudioStreamBuilder_SetRendererWriteDataCallback` 注册写数据回调。
- 使用 `OH_AudioStreamBuilder_SetRendererInterruptCallback` 注册中断回调。
- 使用 `OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback` 注册输出设备变化回调。
- 使用 `OH_AudioStreamBuilder_SetRendererErrorCallback` 注册渲染器错误回调。
- 不再注册 `OH_AudioRenderer_OnWriteData` legacy 写数据回调，避免双回调或优先级差异。
- 暂不切换到 `OH_AudioStreamBuilder_SetRendererWriteDataCallbackAdvanced`：该 API20+ 回调允许返回部分写入长度；当前模拟器音频策略是在数据不足时补静音并返回有效，维持连续播放语义更稳。若后续要做更激进的低延迟/省电策略，再单独评估 partial-write 语义。
- 音频诊断日志使用 `[API22]` 标签。

Native 资源读取按 API22 口径维护：

- 本机 API22 头文件中 `OH_ResourceManager_OpenRawFile64`、`OH_ResourceManager_GetRawFileSize64`、`OH_ResourceManager_ReadRawFile64`、`OH_ResourceManager_CloseRawFile64` 均为 `@since 11`。
- 生产资源加载路径使用 `RawFile64` 读取 rawfile，避免 `long`/`int` 尺寸与读取长度截断。
- 集成测试辅助路径同样使用 `RawFile64`，避免 native SDK 扫描面残留低版本 RawFile 读取 API。
- descriptor 类接口不使用；API22 头文件中旧 `OH_ResourceManager_GetRawFileDescriptor` / `OH_ResourceManager_ReleaseRawFileDescriptor` 已标记 `@deprecated since 12`，若后续需要 descriptor，使用 `GetRawFileDescriptorData` / `ReleaseRawFileDescriptorData`。

NativeWindow / NativeBuffer 按 API22 口径维护：

- NativeBuffer 像素访问保持 `OH_NativeBuffer_FromNativeWindowBuffer` + `OH_NativeBuffer_Map/Unmap` 流程，不直接 mmap BufferHandle。
- 缩放模式使用 `OHScalingModeV2` 与 `OH_NativeWindow_NativeWindowSetScalingModeV2`；旧 `OHScalingMode` 在 API22 头文件中为 deprecated 口径，不再新增使用。
- `SET_BUFFER_GEOMETRY`、`SET_SWAP_INTERVAL` 等常量由 API22 `external_window.h` 提供，不再保留低版本 fallback 宏，避免掩盖 SDK 目标不一致。

已扫描但暂不直接改行为的高版本 native API：

- NativeVSync：API22 头文件提供 `OH_NativeVSync_Create_ForAssociatedWindow`（since 14）、`OH_NativeVSync_RequestFrameWithMultiCallback`（since 12）、`OH_NativeVSync_SetExpectedFrameRateRange`（since 20）。当前 `NativeVSyncDriver` 仍使用单回调 `OH_NativeVSync_RequestFrame`；切到多回调或设置 expected frame-rate 会改变帧调度语义，需结合真机帧 pacing 再做。
- NAPI TSFN：API22 头文件提供 `napi_call_threadsafe_function_with_priority`（since 12），priority 包含 immediate/high/low/idle。当前事件桥和进度回调仍使用普通 `napi_call_threadsafe_function`；切换 priority 会改变 ArkTS 队列调度语义，后续需按事件类型设计优先级。
- XComponent：API22 头文件提供 key/mouse modifier 与 lock-state 查询接口；当前输入映射未消费修饰键状态。后续如要支持组合键、键盘锁状态或更完整鼠标输入，可在 `PluginManager` 输入路径中单独接入。

后续升级到 HarmonyOS 6.1.x 前，先确认 DevEco SDK Manager 中已安装对应 SDK、native 头文件与模拟器镜像，再更新此文件和 `build-profile.json5`。
