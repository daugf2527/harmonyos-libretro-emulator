# 音频 (OHAudio) 子系统 — OH_ Native API 三源差异审计 (API 22)

> 目标 SDK = 6.0.2(22) = API 22（`build-profile.json5`: compatibleSdkVersion=6.0.2(22) / targetSdkVersion=6.0.2(22)）
> 源 A 本地代码:
>   - `entry/src/main/cpp/platform/audio/audio_player.cpp` + `audio_player.h`（OHAudio 全部实际 callsite 集中处）
>   - `core/engine/libretro_engine.cpp` L1139 —— 仅一行注释提及「音频线程已由 OH_AudioWorkgroup 覆盖」，**无任何 OHAudio API 调用**（见下方核实）
> 源 B 本机 SDK header (version 6.0.2.130, apiVersion=22):
>   - `…/native/sysroot/usr/include/ohaudio/native_audiostreambuilder.h`
>   - `…/native/sysroot/usr/include/ohaudio/native_audiorenderer.h`
>   - `…/native/sysroot/usr/include/ohaudio/native_audiostream_base.h`
>   - `…/native/sysroot/usr/include/ohaudio/native_audio_common.h`
>   - `…/native/sysroot/usr/include/ohaudio/native_audio_resource_manager.h`
> 源 C 官方 API22 文档: developer.huawei.com（web 交叉验证，两次命中确认 deprecated/since 措辞）
>
> 审计日期: 2026-06-05 · 状态: 完成

---

## 结论速览

- **本地实际用到 37 个 OHAudio 符号**（22 函数 + 6 typedef/句柄 + 9 枚举/枚举值，其中清单含 enum 类型本身；callsite 全部在 `audio_player.cpp`/`.h`）。
- **全部 37 个在 API22 header 中存在、签名一致、本地全部用符号常量**（无硬编码数值），**0 个真实 bug / 0 个缺失 / 0 个签名不匹配**。
- **deprecated 误用命中：0**。基线声称的 `OH_AudioStreamBuilder_SetRendererCallback` + `OH_AudioRenderer_Callbacks`（header @deprecated since 20）—— 经 grep 全 cpp 树（排除 `core/libretro/**`）**确认本地完全未使用**。本地正确使用四个新拆分回调（WriteData/Interrupt/OutputDeviceChange/Error）。基线结论成立。
- **`SetRendererWriteDataCallbackAdvanced`（since 20, partial-write）确认未用** —— grep 0 命中，是架构选择（补静音返回 VALID 维持连续播放），非缺陷。
- **Workgroup 系列 since 全部 = 20**，目标与 compatibleSdkVersion 均为 22 ≥ 20 → **无低版本 dlsym 风险**；且本地有 null-guard + `workgroup_disabled_` 优雅降级，运行期失败可自禁用。
- **审计输入勘误 1 处（重要）**：任务下发清单称「`core/engine/libretro_engine.cpp` 用到 OH_AudioWorkgroup」—— **事实错误**。该文件 L1139 仅一行注释字符串提到 OH_AudioWorkgroup，**没有任何 OHAudio API 调用**。所有 Workgroup callsite 全在 `audio_player.cpp`。不影响代码正确性，属审计输入勘误。
- 回调 typedef 签名一致性核对通过：`OH_AudioRenderer_OnWriteDataCallback`（native_audiostream_base.h L879，返回 `OH_AudioData_Callback_Result`）与本地 `OnWriteDataCallback`（audio_player.cpp L440）签名完全匹配。

---

## 差异表

> since 标注=本机 header `__attribute__((__availability__(ohos, introduced=N.0.0)))` 真值。
> 本地用法行号基于 `audio_player.cpp`（无前缀）/ `audio_player.h`（标 .h）。

### StreamBuilder — native_audiostreambuilder.h

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_AudioStreamBuilder` | typedef(句柄) | `.h` L174 成员 `builder_` | 存在; `typedef struct OH_AudioStreamBuilderStruct …`(base.h L616); since 10; 无 deprecated | 一致 | **一致** |
| `OH_AudioStreamBuilder_Create` | 函数 | L118-119 `(&builder_, AUDIOSTREAM_TYPE_RENDERER)` | 存在; `(OH_AudioStreamBuilder**, OH_AudioStream_Type)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_Destroy` | 函数 | L934 Cleanup 销毁 builder | 存在; `(OH_AudioStreamBuilder*)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_GenerateRenderer` | 函数 | L219 `(builder_, &renderer_)` | 存在; `(OH_AudioStreamBuilder*, OH_AudioRenderer**)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetChannelCount` | 函数 | L133 设声道数 | 存在; `(OH_AudioStreamBuilder*, int32_t)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetEncodingType` | 函数 | L139 `AUDIOSTREAM_ENCODING_TYPE_RAW` | 存在; `(OH_AudioStreamBuilder*, OH_AudioStream_EncodingType)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetFrameSizeInCallback` | 函数 | L156 设 10ms 帧;失败 fatal+Cleanup | 存在; `(OH_AudioStreamBuilder*, int32_t)`; **since 11** | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetLatencyMode` | 函数 | L148 `AUDIOSTREAM_LATENCY_MODE_NORMAL` | 存在; `(OH_AudioStreamBuilder*, OH_AudioStream_LatencyMode)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetRendererErrorCallback` | 函数 | L208-209 设 `OnRendererError` | 存在; `(OH_AudioStreamBuilder*, OH_AudioRenderer_OnErrorCallback, void*)`; **since 20** | 一致 | **一致**（新拆分回调，替代 deprecated 结构体） |
| `OH_AudioStreamBuilder_SetRendererInfo` | 函数 | L151 `AUDIOSTREAM_USAGE_GAME` | 存在; `(OH_AudioStreamBuilder*, OH_AudioStream_Usage)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetRendererInterruptCallback` | 函数 | L188-189 设 `OnInterruptEvent` | 存在; `(OH_AudioStreamBuilder*, OH_AudioRenderer_OnInterruptCallback, void*)`; **since 20** | 一致 | **一致**（新拆分回调） |
| `OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback` | 函数 | L198-199 设 `OnOutputDeviceChange` | 存在; `(OH_AudioStreamBuilder*, OH_AudioRenderer_OutputDeviceChangeCallback, void*)`; **since 11** | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetRendererWriteDataCallback` | 函数 | L177-179 设 `OnWriteDataCallback`（核心数据回调） | 存在; `(OH_AudioStreamBuilder*, OH_AudioRenderer_OnWriteDataCallback, void*)`; **since 12** | 一致 | **一致**（官方推荐，替代 @deprecated SetRendererCallback） |
| `OH_AudioStreamBuilder_SetSampleFormat` | 函数 | L136 `AUDIOSTREAM_SAMPLE_S16LE` | 存在; `(OH_AudioStreamBuilder*, OH_AudioStream_SampleFormat)`; since 10 | 一致 | **一致** |
| `OH_AudioStreamBuilder_SetSamplingRate` | 函数 | L130 设采样率 | 存在; `(OH_AudioStreamBuilder*, int32_t)`; since 10 | 一致 | **一致** |

### Renderer — native_audiorenderer.h (+ 回调 typedef 在 base.h)

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_AudioRenderer` | typedef(句柄) | `.h` L175 成员 `renderer_` | 存在; `typedef struct OH_AudioRendererStruct …`(base.h L624); since 10 | 一致 | **一致** |
| `OH_AudioRenderer_OnWriteDataCallback` | typedef | L177 `writeDataCb`；本地实现 `OnWriteDataCallback`(L440, `.h` L126) | 存在; `OH_AudioData_Callback_Result (*)(OH_AudioRenderer*, void*, void*, int32_t)`(base.h L879); **since 12** | 一致 | **一致**（本地实现签名 == typedef，逐参核对通过） |
| `OH_AudioRenderer_Pause` | 函数 | L322 / L410 暂停 | 存在; `(OH_AudioRenderer*)`; since 10 | 一致 | **一致** |
| `OH_AudioRenderer_Release` | 函数 | L928 Cleanup 释放 | 存在; `(OH_AudioRenderer*)`; since 10 | 一致 | **一致** |
| `OH_AudioRenderer_SetVolume` | 函数 | L229 设音量 1.0f | 存在; `(OH_AudioRenderer*, float)`; **since 12** | 一致 | **一致** |
| `OH_AudioRenderer_Start` | 函数 | L285 / L435 启动 | 存在; `(OH_AudioRenderer*)`; since 10 | 一致 | **一致** |
| `OH_AudioRenderer_Stop` | 函数 | L358 / L887 停止 | 存在; `(OH_AudioRenderer*)`; since 10 | 一致 | **一致** |

### Workgroup / ResourceManager — native_audio_resource_manager.h（全部 @since 20）

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_AudioResourceManager` | typedef(句柄) | `.h` L180 成员 `resource_manager_` | 存在; `typedef struct OH_AudioResourceManager …`(L55); **since 20** | 一致 | **一致**（since 20 ≤ 22，覆盖） |
| `OH_AudioManager_GetAudioResourceManager` | 函数 | L233 取 resource manager 单例 | 存在; `(OH_AudioResourceManager**)`; **since 20** | 一致 | **一致** |
| `OH_AudioResourceManager_CreateWorkgroup` | 函数 | L236 创建 "libretro_audio" 工作组 | 存在; `(OH_AudioResourceManager*, const char*, OH_AudioWorkgroup**)`; **since 20** | 一致 | **一致** |
| `OH_AudioResourceManager_ReleaseWorkgroup` | 函数 | L916 Cleanup 释放工作组 | 存在; `(OH_AudioResourceManager*, OH_AudioWorkgroup*)`; **since 20** | 一致 | **一致** |
| `OH_AudioWorkgroup` | typedef(句柄) | `.h` L181 成员 `workgroup_` | 存在; `typedef struct OH_AudioWorkgroup …`(L80); **since 20** | 一致 | **一致** |
| `OH_AudioWorkgroup_AddCurrentThread` | 函数 | L467 音频线程首回调时入组取 token | 存在; `(OH_AudioWorkgroup*, int32_t* tokenId)`; **since 20** | 一致 | **一致** |
| `OH_AudioWorkgroup_RemoveThread` | 函数 | L909 Cleanup 移除线程 | 存在; `(OH_AudioWorkgroup*, int32_t tokenId)`; **since 20** | 一致 | **一致** |
| `OH_AudioWorkgroup_Start` | 函数 | L522 帧处理前通知开始(start_ns, deadline) | 存在; `(OH_AudioWorkgroup*, uint64_t startTime, uint64_t deadlineTime)`; **since 20** | 一致 | **一致**（注1: 单位语义见下） |
| `OH_AudioWorkgroup_Stop` | 函数 | L636 帧处理后通知结束 | 存在; `(OH_AudioWorkgroup*)`; **since 20** | 一致 | **一致** |

### 枚举 / 结果类型 — native_audio_common.h / native_audiostream_base.h

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_AudioCommon_Result` | enum | Workgroup/ResourceManager 返回值判定（用 `AUDIOCOMMON_RESULT_SUCCESS`=0，L234/240/469/524/637） | 存在; common.h L56-96; **since 12**; SUCCESS=0，错误码 6800xxx | 一致 | **一致** |
| `OH_AudioData_Callback_Result` | enum | OnWriteDataCallback 返回 `AUDIO_DATA_CALLBACK_RESULT_VALID`(=0)/`_INVALID`(=-1) | 存在; base.h L857-862; **since 12** | 一致 | **一致** |
| `OH_AudioInterrupt_ForceType` | enum | `.h` L146 OnInterruptEvent 参数 type | 存在; base.h L423-436; since 10 | 一致 | **一致** |
| `OH_AudioInterrupt_Hint` | enum | L779 switch hint（`_PAUSE`/`_RESUME`/`_STOP`） | 存在; base.h L443-492; since 10（MUTE/UNMUTE since 20） | 一致 | **一致** |
| `OH_AudioStream_DeviceChangeReason` | enum | L840 OnOutputDeviceChange 参数 reason | 存在; base.h L767-789; **since 11** | 一致 | **一致** |
| `OH_AudioStream_Result` | enum | StreamBuilder/Renderer 返回值判定（用 `AUDIOSTREAM_SUCCESS`=0） | 存在; base.h L55-90; since 10 | 一致 | **一致** |

> 注1（Workgroup_Start 单位）：header 注释写 startTime/deadlineTime「The unit of time is milliseconds」，但本地 L508-523 用 `clock_gettime(CLOCK_MONOTONIC)` 计算的是**纳秒**（start_ns + work_ns）。这是**潜在单位语义不一致**，但**不构成 API 兼容性差异**（签名一致，且 Workgroup 失败时本地 `workgroup_disabled_` 会优雅禁用，仅丢失大核调度优化、不影响出声）。归类「行为/调优待确认」而非 API22 差异 —— 详见 top3。

---

## API22 header 有、本地未用（音频相关新能力，供后续可选增强参考，非缺陷）

| API | since | 文件 | 说明 |
|-----|-------|------|------|
| `OH_AudioStreamBuilder_SetRendererWriteDataCallbackAdvanced` | 20 | streambuilder.h | partial-write 回调（返回 [0,size] 任意长度）。本地架构选择补静音返回 VALID，未用——基线已记录，非缺陷 |
| `OH_AudioRenderer_GetUnderflowCount` | 12 | renderer.h | 系统侧 underflow 计数；本地自行用 RingBuffer underruns 统计，可作交叉校验 |
| `OH_AudioRenderer_GetAudioTimestampInfo` | 15 | renderer.h | 适配变速的帧时间戳，A/V 同步用；本项目音频不做 AV-sync 锚点 |
| `OH_AudioRenderer_SetSpeed` / `GetSpeed` | 11 | renderer.h | 播放变速（0.25–4.0）；模拟器快进/慢放可选接入点 |
| `OH_AudioRenderer_SetDefaultOutputDevice` | 12 | renderer.h | 仅 VOICE/VIDEO_COMMUNICATION usage 生效；GAME usage 不适用 |
| `OH_AudioRenderer_SetSilentModeAndMixWithOthers` | 12 | renderer.h | 静音并与其它流混音 |
| `OH_AudioRenderer_GetFastStatus` / `OnFastStatusChange` | 20 | renderer.h | 查询/回调 fast 状态；当前用 NORMAL latency，无需 |
| `OH_AudioStreamBuilder_SetVolumeMode` + `OH_AudioStream_VolumeMode` | 19 | streambuilder.h/base.h | app 独立音量百分比模式 |
| `OH_AudioStreamBuilder_SetChannelLayout` | 12 | streambuilder.h | 声道布局（环绕声）；当前固定立体声 |
| `OH_AudioStreamBuilder_SetRendererPrivacy` + `OH_AudioStream_PrivacyType` | 12 | streambuilder.h/base.h | 录屏/投屏隐私（SHARED since 21） |

> 以上均为「本地未用」的 API22 可用能力，**不构成差异/缺陷**，仅作音频子系统未来增强清单。

---

## 最高优先级差异（3 条）

1. **[审计输入勘误 / 高]** 任务下发清单称「`core/engine/libretro_engine.cpp` 用到 OH_AudioWorkgroup」—— **事实错误**。全 cpp 树 grep `OH_Audio`（排除 `core/libretro/**`）仅命中 3 文件，其中 `libretro_engine.cpp` 唯一命中是 **L1139 一行注释字符串**（"音频线程已由 OH_AudioWorkgroup 覆盖"），**无任何 OHAudio API 调用**。所有 Workgroup callsite 全在 `audio_player.cpp`（AddCurrentThread L467 / Start L522 / Stop L636 / RemoveThread L909 / CreateWorkgroup L236 / ReleaseWorkgroup L916）。
   - **落地影响：无**。审计已按真实 callsite 完成；勿据"libretro_engine.cpp 用 Workgroup"去那里找代码。

2. **[行为/调优语义 / 中]** `OH_AudioWorkgroup_Start` 的 startTime/deadlineTime header 注释口径为**毫秒**，本地 L508-523 传入的是 `clock_gettime(CLOCK_MONOTONIC)` 计算的**纳秒**（`start_ns` + `work_ns`）。
   - **这不是 API22 兼容性差异**（符号/签名一致，API 都在），而是**单位口径疑似不一致**的调优正确性问题：若系统按毫秒解释，传入纳秒数会让 deadline 远超真实截止，大核调度提示可能无效（退化为普通调度），但**不影响出声**（Workgroup 仅做 CPU 资源优化，失败/无效时 `workgroup_disabled_` 路径仍正常补静音播放）。
   - **建议**：真机 profile 验证 Workgroup 是否真生效；若需修，统一为 header 注释的毫秒口径。**本审计不改业务代码**，仅记录。
   - 注：header 注释措辞 ms vs 实参 ns 是已知社区歧义点，官方 header 与示例存在不一致历史；以真机行为为准。

3. **[since 边界 / 低（已安全）]** Workgroup + ResourceManager 全系列 9 个符号 since=20，是本子系统 **since 要求最高**的一组。当前 compatibleSdkVersion=targetSdkVersion=22 ≥ 20，**完全覆盖、无 dlsym 风险**。
   - 本地额外有双重兜底：`OH_AudioManager_GetAudioResourceManager`/`CreateWorkgroup` 失败均为非致命（L243-252 仅 WARN 继续），运行期 `AddCurrentThread`/`Start`/`Stop` 任一失败 → `workgroup_disabled_` 自禁用（L476/527/639）。
   - **记录而非缺陷**：仅在未来 minCompatibleSdkVersion 下探 < 20 时需重新评估（届时低版本设备这 9 个符号会 dlsym 失败，但因非致命设计不会崩）。

---

## 统计

- **本地用到的 OHAudio 符号总数：37**（按任务清单口径，下分组合计 15+7+9+6=37）
  - **StreamBuilder 15**：句柄 `OH_AudioStreamBuilder` ×1 + 函数 ×14（Create/Destroy/GenerateRenderer/SetChannelCount/SetEncodingType/SetFrameSizeInCallback/SetLatencyMode/SetRendererErrorCallback/SetRendererInfo/SetRendererInterruptCallback/SetRendererOutputDeviceChangeCallback/SetRendererWriteDataCallback/SetSampleFormat/SetSamplingRate）
  - **Renderer 7**：句柄 `OH_AudioRenderer` ×1 + typedef `OH_AudioRenderer_OnWriteDataCallback` ×1 + 函数 ×5（Pause/Release/SetVolume/Start/Stop）
  - **Workgroup/ResMgr 9**：句柄 `OH_AudioWorkgroup` + `OH_AudioResourceManager` ×2 + 函数 ×7（WG: AddCurrentThread/RemoveThread/Start/Stop；ResMgr: CreateWorkgroup/ReleaseWorkgroup；Manager: GetAudioResourceManager）
  - **enum 类型 6**：`OH_AudioCommon_Result` / `OH_AudioData_Callback_Result` / `OH_AudioInterrupt_ForceType` / `OH_AudioInterrupt_Hint` / `OH_AudioStream_DeviceChangeReason` / `OH_AudioStream_Result`
  - 合计：函数 26 + 句柄/typedef 5 + enum 6 = 37。（差异表另把 `OH_AudioRenderer_OutputDeviceChangeCallback` 经 Set* 隐式传入，未单列计数）
- **状态计数：**
  - **一致：37 / 37**（全部在 API22 header 存在、签名一致、本地用符号常量、无 deprecated 命中）
  - **有差异（代码层面）：0**
  - **行为/调优待确认：1**（Workgroup_Start ms vs ns 单位口径；非 API 兼容性差异）
  - **审计输入勘误：1**（清单称 libretro_engine.cpp 用 Workgroup，实为注释）
- **deprecated 命中：0**
  - `OH_AudioStreamBuilder_SetRendererCallback` + `OH_AudioRenderer_Callbacks`（@deprecated since 20，header base.h L226/L642）—— **本地确认未使用**（grep 0 命中），改用四个新拆分回调。
  - `OH_AudioStreamBuilder_SetRendererWriteDataCallbackAdvanced`（since 20）—— 确认未用（架构选择，非缺陷）。
- **since 覆盖：** 本地最高 since=20（Workgroup/ResourceManager 全系列 9 符号）；目标 + compatibleSdkVersion 均 22 ≥ 20，全覆盖。
- **配对生命周期检查（全部平衡）：**
  | 配对 | acquire | release | 平衡 |
  |---|---|---|---|
  | StreamBuilder Create↔Destroy | L119 | L934 | ✅ |
  | Renderer GenerateRenderer↔Release | L219 | L928 | ✅ |
  | Renderer Start↔Stop | L285 | L358 / L887(Cleanup) | ✅ |
  | Workgroup CreateWorkgroup↔ReleaseWorkgroup | L236 | L916 | ✅ |
  | Workgroup AddCurrentThread↔RemoveThread | L467 | L909 | ✅ |
  | Workgroup Start↔Stop | L522 | L636（同一回调作用域内成对） | ✅ |
  - 无不配平 → 无 OHAudio 资源泄漏面。Cleanup 顺序正确：先停回调（shutting_down_ + 2s bounded wait L897）→ RemoveThread → ReleaseWorkgroup → Release renderer → Destroy builder，且全程持 `state_mutex_`。

落盘路径: `docs/audit/api22-diff/audio-subsystem.md`
