# HarmonyOS SDK Target

当前项目目标版本：

- `compatibleSdkVersion`: `26.0.0`
- `targetSdkVersion`: `26.0.0`
- 目标平台：HarmonyOS 7.0 / API 26 Developer Beta 1。DevEco Studio 26 / hvigor 6.26
  的 `build-profile.json5` 使用 SDK Manager 注册的 `26.0.0` 格式，不使用旧展示格式
  `7.0.0(26)`。
- `runtimeOS`: `HarmonyOS`

## 本机工具链状态

截至 2026-06-14，本机 API26 工具链已安装：

- DevEco Studio: `D:\DevEco Studio`，`product-info.json` 版本 `26.0.0.461`
- Command Line Tools: `D:\command-line-tools`，`version.txt` 版本 `26.0.0.461`
- Hvigor: `6.26.1`
- ohpm: `26.0.0.410`
- hdc: `3.2.0e`
- HarmonyOS SDK: `D:\command-line-tools\sdk\default`
- `sdk-pkg.json` / `ets` / `native` / `toolchains` / `previewer`: `apiVersion = 26`，`version = 26.0.0.23`，`releaseType = Beta1`
- HMS Native SDK: `D:\command-line-tools\sdk\default\hms\native\sysroot\usr`
- Native link libs confirmed in API26 SDK: `libqos.so`、`libohaudio.so`、`libnative_window.so`

旧 API22 工具链仍保留在 `D:\hongmeng\command-line-tools` 和
`D:\Program Files\DevEco Studio`，不要再让仓库 wrapper 默认命中旧路径。

## API26 升级执行顺序

1. 使用 `D:\command-line-tools` 作为本仓 API26 命令行工具路径。
2. 确认 API26 的 `ets`、`native`、`toolchains`、`previewer` 包均已安装。
3. 确认 HMS Native SDK 同步存在；`entry/src/main/cpp/CMakeLists.txt` 会从 OpenHarmony SDK 路径推导
   `hms/native/sysroot/usr` 并链接 `libqos.so`。
4. 用 `scripts/check/check_harmony_api26_env.ps1` 确认本机 SDK 元数据已经是 API26。
5. 用户在 DevEco / hvigor 中执行完整编译和真机或 API26 模拟器冒烟。

## Native 音频路径

当前 OHAudio 路径沿用 API20+ write-data callback 方案：

- 使用 `OH_AudioStreamBuilder_SetRendererWriteDataCallback` 注册写数据回调。
- 使用 `OH_AudioStreamBuilder_SetRendererInterruptCallback` 注册中断回调。
- 使用 `OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback` 注册输出设备变化回调。
- 使用 `OH_AudioStreamBuilder_SetRendererErrorCallback` 注册渲染器错误回调。
- 不注册 `OH_AudioRenderer_OnWriteData` legacy 写数据回调，避免双回调或优先级差异。
- 暂不切换到 `OH_AudioStreamBuilder_SetRendererWriteDataCallbackAdvanced`：该 API20+ 回调允许返回部分写入长度；当前模拟器音频策略是在数据不足时补静音并返回有效，维持连续播放语义更稳。

API26 SDK 落盘后，需要重新检查 OHAudio 头文件中的 deprecated/since 标注。

## Native 资源读取

生产资源加载路径继续使用 `RawFile64` 读取 rawfile：

- `OH_ResourceManager_OpenRawFile64`
- `OH_ResourceManager_GetRawFileSize64`
- `OH_ResourceManager_ReadRawFile64`
- `OH_ResourceManager_CloseRawFile64`

descriptor 类接口当前不使用。API26 SDK 落盘后，应重新确认旧 descriptor 接口与
`GetRawFileDescriptorData` / `ReleaseRawFileDescriptorData` 的 deprecated 状态。

## NativeWindow / NativeBuffer

- NativeBuffer 像素访问保持 `OH_NativeBuffer_FromNativeWindowBuffer` +
  `OH_NativeBuffer_Map/Unmap` 流程，不直接 mmap BufferHandle。
- 缩放模式继续使用 `OHScalingModeV2` 与 `OH_NativeWindow_NativeWindowSetScalingModeV2`。
- `SET_BUFFER_GEOMETRY`、`SET_SWAP_INTERVAL` 等常量继续按 SDK header 提供值使用，不恢复低版本 fallback 宏。

## API26 后续重点复核

- NativeVSync：确认 `OH_NativeVSync_Create_ForAssociatedWindow`、
  `OH_NativeVSync_RequestFrameWithMultiCallback`、`OH_NativeVSync_SetExpectedFrameRateRange`
  在 API26 中的行为与调度语义。
- NAPI TSFN：确认 `napi_call_threadsafe_function_with_priority` 是否适合事件桥和进度回调；切换优先级会改变 ArkTS 队列调度语义，不能随 SDK 升级顺手改。
- XComponent：确认 key/mouse modifier、lock-state、UI input event callback 在 API26 的推荐入口，后续再决定是否接入组合键、手柄轴或触控笔。
- ArkTS：本仓 codelinter 不能替代编译。API26 升级后必须通过 DevEco / hvigor 实编验证 ArkTS 类型、V1/V2 装饰器和 API 兼容性。
