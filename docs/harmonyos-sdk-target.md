# HarmonyOS SDK Target

当前项目统一目标版本：

- `compatibleSdkVersion`: `6.0.2(22)`
- `targetSdkVersion`: `6.0.2(22)`
- 本机可用模拟器镜像：`HarmonyOS-6.0.2`
- 本机镜像元数据：`apiVersion = 22`

Native 音频路径按 API22 口径维护：

- 使用 `OH_AudioStreamBuilder_SetRendererWriteDataCallback` 注册写数据回调。
- 使用 `OH_AudioStreamBuilder_SetRendererInterruptCallback` 注册中断回调。
- 不再注册 `OH_AudioRenderer_OnWriteData` legacy 写数据回调，避免双回调或优先级差异。
- 音频诊断日志使用 `[API22]` 标签。

后续升级到 HarmonyOS 6.1.x 前，先确认 DevEco SDK Manager 中已安装对应 SDK、native 头文件与模拟器镜像，再更新此文件和 `build-profile.json5`。
