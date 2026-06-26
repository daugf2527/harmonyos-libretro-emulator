# 2026-06-07 音频 D020 对抗复审(主 AI 接手,agent B 被 cyber safeguard 误拦 0 产出)

> 立场:挑刺,假设 D020 改错了。结论:D020 本身无 bug;但挖到一个**真实的实时音频反模式(F1)**,外网已坐实。

## Q1. 平台双 profile 时序 / Reset 复用 — 无 bug(但有一处 robustness note)

- **时序正确**:`SetRtSchedulingAvailable(qosRet==0)` 在引擎 GameLoop 入口(`libretro_engine.cpp:1140-1145`,线程启动即调),早于游戏加载触发的 `AudioBridge::Reset→Initialize`。实测启动日志顺序 `[QoS]...ret=-1` 在 `AudioBridge initialized` 之前 → profile 选择读到的是正确的 flag。✓
- **robustness note(非 bug)**:`rt_scheduling_available_` 默认 false;profile 仅在**首次** full `Initialize` 落地;`Reset` 同采样率复用路径(`audio_bridge.cpp:704-734`)不重选 profile。同一平台不变所以无害,但若未来出现"首次 Initialize 早于 flag 注入"的路径,会锁死模拟器档。建议:Reset 复用路径也重读 flag 重选 profile(防御性)。

## Q2. DRC 阈值成员 线程安全 — 无 bug

`drc_low_threshold_/drc_high_threshold_`(普通 float)写于 `Initialize`(GameLoop,load 时)、读于 `ProcessAudio` DRC 段(GameLoop,retro_run 内)→ **同一 GameLoop 线程,顺序执行,无数据竞争**。✓

## Q3. F1【真实发现,App 可修,外网坐实】音频回调内持锁 = 实时音频反模式

**事实**:消费回调 `AudioPlayer::OnWriteDataCallback`(OHAudio 实时线程)在 workgroup 路径取 `state_mutex_`:
- `:464` AddCurrentThread、`:506` `OH_AudioWorkgroup_Start`、`:637` `OH_AudioWorkgroup_Stop` 均 `std::lock_guard<std::mutex> lock(player->state_mutex_)`。

而**生产者 `AudioBridge::ProcessAudio`(GameLoop)** 持 `AudioBridge::mutex_` 时调 `audio_player_->IsPlaying()`(`:274`,取 `state_mutex_`)+ `ProcessPendingInterruptActions`。中断回调(`OnInterruptEvent`)也取 `state_mutex_`。

**外网坐实**(华为 capi-ohaudio 文档 + Android Avoiding-PI + OpenHarmony playback guide):**OnWriteData 回调绝不能取 mutex**,否则优先级反转 → 爆音/underrun;回调应只做无锁 ring buffer memcpy + 原子读状态。

**严重度分平台**:
- **模拟器(当前症状)**:workgroup Start 失败(6800301)后 `workgroup_disabled_=true` → 回调跳过 state_mutex_ → 仅 startup 一次(那条 `callback slow: cost=26907us`)→ **不是当前 underrun 主因**(主因仍是 GameLoop 抢占 + FramePacer 忙等,已修)。
- **真机**:workgroup 正常 → 回调**每次**取 state_mutex_ 围绕 Start/Stop → 与生产者 IsPlaying() 竞争 → 优先级反转潜在风险(锁很短,severity 低,但违反 RT 铁律)。

**修法(App 可修,留作后续)**:workgroup handle/token 在 init/cleanup 后稳定,回调内对其改用原子读 + 去掉 state_mutex_;或把 workgroup Start/Stop 移出回调。需谨慎(改实时回调),非当前症状,优先级在 FramePacer/UI 之后。

## 底线
D020 无 bug、可保留。F1 是真机相关的潜在 robustness 缺陷(外网坐实的反模式),不是模拟器当前 underrun 的因。当前模拟器 underrun 的 App 杠杆是 FramePacer 忙等门控(已修 05dc30b)+ 深缓冲(D020 已做)。
