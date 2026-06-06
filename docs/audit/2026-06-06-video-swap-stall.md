# 2026-06-06 视频/Swap 卡顿调查(API22 模拟器 GameLoop 单帧 100-253ms)

> 只读调查。症状:HarmonyOS 6.0.2 模拟器(API22)上 GameLoop 偶发单帧 100-253ms,但同帧 retro_run 仅 1-7ms → ~160ms 花在 retro_run 之外(视频渲染/swap/线程交接),把音频缓冲抽干 → underrun,FPS 41-55。

## Q1. 引擎单帧链路 + retro_run 之后到本帧结束前的每个可能阻塞/同步调用(带 file:line)

### 架构定性(决定性):GameLoop 线程与渲染/swap 完全解耦

- **GameLoop 线程**(`libretro_engine.cpp:1137 GameLoop`)只跑模拟 + 投递帧,**从不调用 eglSwapBuffers / RequestBuffer / FlushBuffer / glFinish**。
- 渲染 + swap 全在**独立 RenderThread**(`render_thread.cpp:179 ThreadMain`)上执行。
- 二者经 `BoundedLatestFrameQueue`(`bounded_latest_frame_queue.h`,容量 2)+ `controlQueue_` 交接,**均为非阻塞**。

### GameLoop 单帧链路(retro_run 完成后 → 本帧结束前)

```
GameLoop while(running_)  libretro_engine.cpp:1151
  frameStart = now                                  :1183   ← max_frame_us 计时起点
  ProcessFrame()                                    :1184
    EnterRetroRun()                                 :1994
    [回调1] FrameTimeCallback                        :2001-2009
    [回调2] AudioBufferStatusCallback                :2012-2095  → eventBridge_.Emit("audio_status")  :2050
    retroStart = now                                :2100   ← max_retro_ms 计时起点
    coreLoader_.GetRun()()  == retro_run            :2101   ← 内部回调 OnVideoRefresh / OnAudioSampleBatch 都算进 retroMs
    retroMs = now - retroStart                       :2102   ← max_retro_ms 计时终点
    --- 以下是 "retro_run 之后、本帧结束前" 的全部调用 ---
    ConsumePendingMinimumAudioLatencyMs → AudioBridge::SetMinimumLatencyMs   :2120-2129  (偶发)
    ConsumeVariableUpdated → eventBridge_.Emit("options_update")             :2131-2133  (偶发)
    ConsumePendingAvInfo:                                                     :2136-2160  (偶发,核心热切换 AV)
        videoPipeline_.SetGeometry(...)                                       :2139
        videoPipeline_.SetTargetFps(...)                                      :2147
        AudioBridge::Reset(sample_rate)                                       :2154  ← 偶发,可能重建音频流
    ExitRetroRun()                                  :2167
  frameEnd = now                                    :1193
  elapsedUs = frameEnd - frameStart                 :1194   ← max_frame_us 计时终点(**不含下面的节拍 sleep**)
  ... 统计聚合 ...
  节拍器 sleep 到 nextFrameDeadline_                  :1274-1289 (此段在 max_frame_us 计时之外)
```

**关键计时事实**:`max_frame_us`(`engineDiagMaxFrameUs_`, :1202-1203)= `frameStart→frameEnd`,**只覆盖 ProcessFrame,不含节拍 sleep**。`max_retro_ms`(`engineDiagMaxRetroMs_`, :1207-1208)= 仅 `retro_run` 一行(含其内部 OnVideoRefresh/OnAudioSampleBatch 回调)。

**因此日志 `max_frame_us=165789, max_retro_ms=4` 的字面含义**:165ms 花在 ProcessFrame,但其中 retro_run(连同视频帧 enqueue + 音频 ProcessAudio)只 4ms → **161ms 落在 retro_run 调用之外的 ProcessFrame 代码里**,即上面 :2120-2167 那几个**偶发**分支,或 :2001-2095 的两个回调。

### OnVideoRefresh(retro_run 栈内,故其耗时计入 max_retro_ms)— 非阻塞投递

`libretro_engine.cpp:2172 OnVideoRefresh`:
- surface 无效 → 丢帧返回 :2178-2204
- 软件帧:`frameBufferPool_.Acquire(bytes)` :2232 + `memcpy` :2240 → `renderThread_->EnqueueFrame` :2245
- `EnqueueFrame`(`render_thread.cpp:127`)→ `frameQueue_.Push`(**满了丢最旧帧 pop_front,从不阻塞** `bounded_latest_frame_queue.h:34-46`)+ `PushControl(TICK)` :137
- `PushControl`(`render_thread.cpp:240`)抢 `controlMutex_` 仅做 deque emplace,**RenderThread 渲染(HandleControl→HandleTick)在锁外执行**(`render_thread.cpp:227-232`,锁作用域 :192-221 已结束)→ 不会让 GameLoop 等渲染完成。

→ **retro_run 栈内无 GameLoop↔RenderThread 同步等待。这与 max_retro_ms=4 一致。**

### 待查项结论(已全部排除为 GameLoop 阻塞源)

- `EventBridge::Emit`(`event_bridge.cpp:122`):用 `napi_call_threadsafe_function(..., napi_tsfn_nonblocking)`(:170)。**非阻塞**,锁 `mutex_` 只护自身 throttle 状态。✅ 排除。
- `AudioBridge::SetMinimumLatencyMs`(`audio_bridge.cpp:77`):纯原子 store + 计算。✅ 排除。
- `AudioBridge::Reset`(`audio_bridge.cpp:704`):same-rate 路径(:708-734)轻量;full-reinit 路径(:736-753)会 `audio_player_->Stop()`+`Initialize()` **可能阻塞**,但仅在 sample_rate **变化**时(游戏加载/极少热切换),不能解释"持续偶发"。基本排除为主因。
- `videoPipeline_.SetGeometry`(`video_pipeline.h:49` inline)+ `env_dispatcher.h:86`:仅成员赋值 + flag。✅ 排除。
- `FrameBufferPool::Acquire`(`frame_buffer_pool.cpp:8`):只锁自身 cache mutex 做 deque pop + resize。**非阻塞**。✅ 排除。
- `EnterRetroRun`/`ExitRetroRun`(`env_dispatcher.h:52-53`):纯 bool。✅
- `FramePacer::EndFrame`(`frame_pacer.h:32`)会 `sleep_for`+spin 到 deadline(:50/:54),**但只在 `VideoPipeline::Render`(:1385)调用 → 在 RenderThread,不在 GameLoop**。✅ 对 GameLoop 排除。

## Q2. 哪个阻塞点能在模拟器上卡 100-250ms?(逐个判定是否同步阻塞 GameLoop 线程)

**所有重型阻塞调用都在独立 RenderThread 上(经 `VideoPipeline::Render` / `gles_renderer.cpp`),GameLoop 线程一个都不碰**:

| 阻塞点 | file:line | 线程 | 单次上限 | 能否卡 GameLoop |
|---|---|---|---|---|
| `eglSwapBuffers` | `gles_renderer.cpp:1159` | RenderThread | 受 vsync/合成器;模拟器软件 GL 可数十 ms | 否(不在 GameLoop) |
| `OH_NativeWindow_RequestBuffer` | `video_pipeline.cpp:1019` | RenderThread | 取决于 buffer 队列/合成器 | 否 |
| Fence 等待 `WaitAndCloseFence` | `video_pipeline.cpp:1050`(timeout=33ms) → `fence_utils.cpp:90` | RenderThread | **封顶 33ms** | 否 |
| `OH_NativeWindow_FlushBuffer` | `video_pipeline.cpp:1314` | RenderThread | 通常快 | 否 |
| `PixelConverter::ConvertAndScale`(软件缩放) | `video_pipeline.cpp:1259/1264` | RenderThread | 软件转换大帧可 >25ms(`SlowConv` 日志 :1273) | 否 |
| HW `graphics_context_->SwapBuffers` / Vulkan Present | `video_pipeline.cpp:1799/1744` | RenderThread | 受合成器 | 否 |

**swapInterval 现状(题目要求确认)**:
- **GLES 路径模拟器(x86_64)默认 vsync = 0**(关闭)✅:`gles_renderer.cpp:26-30` `#if defined(__x86_64__) → kDefaultSwapInterval = 0`;`ClampSwapInterval` 只允许 0/1(:35-37)。→ eglSwapBuffers **不等 vsync**。
- **软件路径不主动设 swapInterval**:`WindowState::swap_interval` 默认 -1(`window_state_manager.h:16`),`EnsureWindowConfiguredIfNeeded`(`video_pipeline.cpp:781-794`)构造 state 时**未赋值** → `window_state_manager.cpp:54` 的 `if(swap_interval>=0)` 跳过,从不调用 `SET_SWAP_INTERVAL`,用系统默认(模拟器上 RequestBuffer 仍受生产者队列+合成器节奏制约,但无主动 vsync 阻塞)。
- 模拟器 x86_64 走哪条:`VideoPipeline::Render`(`video_pipeline.cpp:1408-1414`)`#if defined(__x86_64__)` **强制 ScalingMode::GLES_SCALING** → 模拟器走 GLES + eglSwapBuffers(软件 GL),不是软件 RequestBuffer 路径。

**GameLoop↔RenderThread 交接 = 全异步,无同步等待**:
- 投帧 `OnVideoRefresh → EnqueueFrame`(`render_thread.cpp:127`)→ `frameQueue_.Push`(满了丢最旧帧,从不阻塞)+ `PushControl(TICK)`。
- 生命周期 `SetWindow`/`SetWindowSize`/`SetHwRenderRuntimeInfo`(`render_thread.cpp:111-124`)全部经 `PushControl`(:240,只 emplace+notify)异步入队。
- RenderThread 渲染(`HandleControl→HandleTick→Render`)在 `controlMutex_` **锁外**执行(`render_thread.cpp:227-232`,锁作用域 :192-221 已释放)→ GameLoop 的 PushControl 不会等渲染完成。
- **GameLoop 从不调用 RenderThread 任何阻塞式 wait/join(除 Stop/Reset 路径,非每帧)**。

→ **结论:没有任何 RenderThread 阻塞点能通过同步调用直接卡住 GameLoop 线程 100-250ms。** GameLoop 的 `max_frame_us` 计时段(ProcessFrame)内,所有调用要么非阻塞,要么是封顶 ≤33ms 的偶发分支。

## Q3. 判决 + 缓解(模拟器固有 vs App 可调,按收益/风险排序)

### 关键计时澄清(先纠一个易误读点)
`engineDiagMaxFrameUs_`(:1202)和 `engineDiagMaxRetroMs_`(:1207)是 **1 秒窗口内各自独立取 max**,**不保证同一帧**。所以 `max_frame_us=165789 / max_retro_ms=4` 不能直接推出"同一帧里 161ms 在 retro 之外"——可能是窗口内 A 帧 frame=165ms、B 帧 retro=4ms。但无论哪帧,**GameLoop 的 ProcessFrame 里没有能主动耗 165ms 的调用**(Q1/Q2 已逐个证实),所以 165ms 只能来自**线程被挂起/抢占**(代码外时间),而非某个慢函数。
注:日志2 `max_frame_us=168461 / max_retro_ms=168` ≈ 相等 → 那一帧是 **retro_run 自身慢**(核心计算 or OnVideoRefresh 大帧 memcpy/软件转换在 retro 栈内),与"retro 之外卡顿"是**两类不同现象**。

### 判决表

| 候选点 | 阻塞 GameLoop | 能否卡 100-250ms | 判决 | 建议 |
|---|---|---|---|---|
| RenderThread 软件 GL `eglSwapBuffers` / 软件光栅 / `PixelConverter` 抢占虚拟核 | 否(间接:抢 CPU) | 是(模拟器软件 GPU + 无 RT,GameLoop 被换出) | **模拟器固有**(软件 GPU 虚拟化 + 无实时调度,App 改不了根因) | 缓解:降 RenderThread CPU 压力(见下 App 可调项) |
| OS 调度抖动 / `OH_QoS_SetThreadQoS` 在模拟器失败(`libretro_engine.cpp:1140-1145` 注释明示 qosRet=-1) | 否(被换出) | 是 | **模拟器固有** | App 无法在模拟器获得 RT 调度 |
| Fence 等待(`video_pipeline.cpp:1050`) | 否(RenderThread) | 否(封顶 33ms) | 二者皆非主因 | 维持现状 |
| `AudioBridge::Reset` full-reinit(`:2154`) | 是(GameLoop) | 仅 rate 变化偶发 | App 可调(但非本症状主因) | 可选:把流重建移出 GameLoop 线程 |

### App 可调缓解项(降低 RenderThread 对 GameLoop 的 CPU 争抢 = 间接救 GameLoop 卡顿),按收益/风险:

1. **[收益高/风险低] 模拟器路径限制软件渲染分辨率 / 降低 `PixelConverter` 负载**。`SlowConv` 日志(`video_pipeline.cpp:1273` 阈值 25ms)证明软件像素转换在大帧时已是数十 ms 级 CPU 占用。x86_64 强制 GLES(:1408)后理论上 GPU 上传,但模拟器 GLES 是软件实现,`glTexImage2D`+`eglSwapBuffers`(`gles_renderer.cpp:1113/1159`)仍是 CPU 大户。已有 `refactoredSetSoftwareMaxResolution`(NAPI)可在模拟器主动调小。
2. **[收益中/风险低] 确认/强制模拟器 swapInterval=0 也覆盖软件路径**。当前软件路径完全不设 SET_SWAP_INTERVAL(swap_interval 默认 -1),建议模拟器下显式设 0,避免系统默认 vsync 在 RequestBuffer 端引入隐性等待。
3. **[收益中/风险中] GameLoop 与 RenderThread 错峰 / 给 GameLoop 更高相对优先级**。模拟器无 RT 调度,但可尝试在模拟器把 RenderThread QoS 降一档(让出核给 GameLoop 跑模拟+喂音频),牺牲渲染流畅度保音频不断流。需实测。
4. **[收益中/风险中] 把音频生产与 GameLoop 解耦**。当前音频靠 GameLoop 每帧 retro_run 内 `retro_audio_sample_batch` 推送(`OnAudioSampleBatch:2290`),GameLoop 一旦被换出 165ms,音频生产同步断流 → `producer max_gap_ms=253`。可考虑加深音频 RingBuffer 缓冲(已知音频侧另有处理)以扛住 GameLoop 抖动——这是把"卡顿不连累音频"的最直接补偿,治标但有效。
5. **[收益低/风险低] `AudioBridge::Reset` 流重建移出 GameLoop**(`:2154`):仅 rate 变化偶发,非主因,优先级最低。

## 底线结论

**这个 165ms 的 GameLoop 单帧卡顿,根因是模拟器固有的(x86_64 软件 GPU 虚拟化 + HarmonyOS 模拟器无实时调度 `OH_QoS` 失败),App 无法消除——它不是 App 代码里某个能改的同步阻塞调用。**

证据(静态可证部分,确定性高):
- GameLoop 线程的整个 `ProcessFrame` 链路里**没有任何会阻塞 100-250ms 的同步调用**,也**没有任何同步等待 RenderThread 的点**——所有重型 GPU/窗口/swap/fence 调用都在独立 RenderThread 上,经非阻塞队列交接(Q1/Q2 逐项 file:line 证实)。
- 模拟器上 swapInterval 已是 0(GLES 路径,`gles_renderer.cpp:27`),fence 等待已封顶 33ms——这两个常被怀疑的点都已被代码排除为 165ms 的来源。
- 代码注释自己确认模拟器 `OH_QoS_SetThreadQoS` 返回 -1(`libretro_engine.cpp:1142-1145`),即模拟器无实时调度。

推断部分(无法纯静态 100% 证实,诚实标注):165ms 必然来自**线程被 OS 换出/抢占的"代码外时间"**(被满载的软件 GL RenderThread + 软件合成器进程抢走虚拟核),这段挂起被 `frameEnd-frameStart` 计入但不属于任何函数。要 100% 坐实需真机/模拟器上抓线程调度 trace(如 `ftrace`/`perfetto` 看 GameLoop 线程 runnable→running 的等待间隙),静态代码到此为止。

**App 侧能做的是"缓解连累音频"而非"消除卡顿"**:降低 RenderThread 在模拟器的 CPU 占用(限分辨率/降转换负载)、给 GameLoop 让核、以及加深音频缓冲扛住 GameLoop 抖动。真机上有 RT 调度 + 真实 GPU,此现象预期大幅缓解或消失。

## 复核(2026-06-06):FramePacer 忙等自旋核争用

> 复核动机:上文 Q1 待查项把 `FramePacer::EndFrame` 一句"在 RenderThread 不在 GameLoop ✅ 排除"带过,只否定了"直接同步阻塞 GameLoop",**没分析它作为"App 主动烧核"对核争用的间接加剧**。FramePacer 由 `093d3a8 (2026-05-24)` 引入,正落在回归窗口内(3-4 月无此 pacer 模拟器顺,6.0.2 才卡),值得单独复核。本节用 cclsp 重追调用链 + 逐项核实自旋语义。**仍为只读调查,未改任何代码。**

### 复核 Q1:Render(连同忙等自旋)跑在哪个线程 — 完整调用链(cclsp get_incoming_calls 逐跳)

```
RenderThread::ThreadMain            core/engine/render_thread.cpp:179   ← 线程入口(独立 RenderThread)
  -> HandleControl(message)         core/engine/render_thread.cpp:286   (在 ThreadMain:231 调用,TICK 分支 :294-296)
    -> HandleTick()                 core/engine/render_thread.cpp:449   (HandleControl:295)
      -> videoPipeline_.Render(...) core/engine/render_thread.cpp:554   (软件帧路径,x86_64 模拟器走此)
        == VideoPipeline::Render    core/engine/video_pipeline.cpp:1373
           -> framePacer_.BeginFrame()                         video_pipeline.cpp:1375
           -> Finish lambda -> framePacer_.EndFrame()          video_pipeline.cpp:1385
              -> while(now < target_end) __builtin_ia32_pause() frame_pacer.h:54-60   ← 忙等自旋(x86_64)
```

cclsp `get_incoming_calls` 三跳全部唯一(`VideoPipeline::Render` ← `HandleTick` ← `HandleControl` ← `ThreadMain`),无第二调用源。
→ **判定确认:忙等自旋 100% 在 RenderThread,不在 GameLoop。上文 Q1 :61 / Q2 表"对 GameLoop 排除"对这一点是正确的,无需推翻。** GameLoop(`libretro_engine.cpp:1137`)从不调用 `VideoPipeline::Render`,故不直接执行此自旋。

注:上文把 render_thread.cpp 写在 `platform/sync/` 路径有误,实际在 `core/engine/render_thread.cpp`;线程入口行号 :179、ThreadMain 等结论不变。

### 复核 Q2:忙等自旋是否在模拟器上加剧核争用(间接卡 GameLoop)

**先精确化自旋语义**(`frame_pacer.h:36-60`):
- `spin_reserve_us = clamp(period_us/20, 50, 300)` → 60fps(period≈16667us)时 = `16667/20 ≈ 833 → clamp 到 300us`。
- 流程:`remaining = target_end - now`;若 `remaining > spin_reserve` 先 `sleep_for(remaining - spin_reserve)`(:50),**再** `while(now < target_end) pause()`(:54)纯自旋补到 deadline。
- 即:**每个正常帧末尾都有一段纯 busy-spin,稳态上限 ≈ spin_reserve = 300us/帧**(60fps → ≈18ms/s 的纯空转占核)。
- 总时长被 `target_end`(= 一个 period)封顶:即使 sleep 欠睡,自旋也只补到 deadline,**单帧 EndFrame 忙等 ≤ 1 个 period(≈16.6ms),绝不到 165ms**。

**对题目"VM sleep 睡过头让自旋烧更久"假设的诚实修正**:方向相反。若 `sleep_for` 睡过头(VM 普遍),返回时 `now` 已 ≥ `target_end` → `while` 条件立即 false → **不自旋**(EndFrame 提前返回,该帧偏晚)。睡过头导致的是"帧偏晚 + 不自旋",**不会**让自旋退化成烧更久。真正每帧固定烧核的是 sleep 后留给 spin 的那 ≤300us(欠睡时 spin 也只补到 deadline,仍被 period 封顶)。

**核争用判定(决定性新证据 — 上文漏掉的一环)**:
- **两条线程同抢最高交互档,模拟器都失败**:`RenderThread::ThreadMain` 入口 `OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE)`(`render_thread.cpp:181`)与 GameLoop 入口同一调用(`libretro_engine.cpp:1140`)。`render_thread.cpp:182` 的 `ret` 与 `libretro_engine.cpp:1141` 同源——模拟器上 `OH_QoS_SetThreadQoS` 返回 **-1**(代码注释 :1142-1145 自证,且 `AudioBridge::SetRtSchedulingAvailable(qosRet==0)` 据此选了"模拟器深缓冲" profile)。→ **模拟器上 RenderThread 与 GameLoop 同档、无 RT、无让核机制。**
- 在这种"双 USER_INTERACTIVE 同档 + 软件 GPU 已占满虚拟核"的 VM 上,RenderThread 每帧主动 `__builtin_ia32_pause()` 自旋(pause 仅省电/避流水线惩罚,**不让出调度量子**)= App 主动把一个虚拟核钉在 100% 空转。这确实**加剧**调度器把 GameLoop 换上来的难度。
- **但量级对不上"主因"**:稳态每帧 ≤300us、单帧封顶 ≤16.6ms,无法独立解释 165ms 单帧。165ms 主因仍是"GameLoop 被 OS 整体换出的代码外时间"(模拟器固有抢占)。自旋的角色是"让换出更易发生 / 持续占核挤压",属 **App 可削减的次级贡献,非主因**。

→ **复核 Q2 判定:是 App 可修的核争用"加剧因素",但是次因不是主因。** 模拟器无 vsync(swapInterval=0)还要求亚毫秒级 deadline 烧核,纯属浪费;真机有 RT 调度时这点烧核可被吸收,模拟器无 RT 时它直接挤占稀缺虚拟核。

### 复核 Q3:BeginFrame deadline 追赶是否节奏雪崩

`frame_pacer.h:20-28`:`now > next_deadline_` 时 `behind = delta/period + 1`,`next_deadline_ += behind*period`,再 `+= period`。这是**对齐到"当前之后下一个整 period 网格"的 catch-up-by-reset**,落后多帧时**不**连续猛跑追补 → 是**防雪崩**设计,非造雪崩。GameLoop 节拍器 `libretro_engine.cpp:1275-1280` 有等价逻辑(`frameStart > nextFrameDeadline_ + frameInterval` 才重置)。
副作用:模拟器抖动让 `now` 频繁略越 deadline 时,每次丢到下一格 → 有效帧率可能略低于 target、帧呈现轻微不均,但**不是雪崩、不是 165ms 元凶**。
→ **复核 Q3 判定:不产生节奏雪崩,最多轻微帧不均。**

### 复核 Q4:判决 + 平台门控修法方向(只给方向,不写代码)

**判决:部分可修(App 可削减的次因,非根治主因)。**
- 跑在 RenderThread,不直接阻塞 GameLoop —— 上文对此正确。
- 但"App 无可修点"结论**需部分修正**:确实存在一个 App 写的、可门控的、在模拟器上纯浪费的主动核占用(忙等自旋)。削减它预计是**边际改善(救稀缺虚拟核)**,不是根治——165ms 主因仍是模拟器固有抢占。

**平台判别信号:现成,无需新增探测。**
- 项目已有单源平台判别:GameLoop 入口 `OH_QoS_SetThreadQoS` 返回值(`==0` 真机有 RT / `==-1` 模拟器无 RT),已驱动 `AudioBridge` 双 profile(`audio_bridge.h:92-119`,模拟器深缓冲/真机浅缓冲)。
- **RenderThread 自己在 `render_thread.cpp:181` 就已拿到同一个 `qosRet`**(`:182` 打印 ret)——门控判别信号在忙等自旋所在线程**就地可得**,不必跨线程取。

**门控修法方向(方向性,非代码)**:
1. **首选**:让 FramePacer 持有一个"是否纯 sleep(禁忙等自旋)"开关,由 RenderThread 用本线程 `qosRet==0`(或复用 `AudioBridge` 已建立的同源 RT 能力标志)在进入循环前设定 —— 模拟器(无 RT)走**纯 `sleep_for` 到 deadline、彻底删掉 `__builtin_ia32_pause` 自旋段**(放弃亚毫秒精度换不烧核);真机(有 RT)保留现有 sleep+spin 精确节拍。判别信号 = `render_thread.cpp:181` 的 `qosRet`。
2. **次选(更保守)**:模拟器下把 RenderThread QoS 降一档(让 GameLoop 在同档竞争中占优,把核让给"跑模拟+喂音频"的 GameLoop),牺牲渲染流畅度保音频不断流。改动点 = `render_thread.cpp:181`。需实测。
3. 上文 Q3 已列的"加深音频缓冲扛 GameLoop 抖动"是治标补偿,与本节门控正交,可叠加。

**支撑证据汇总(file:line)**:
- 忙等自旋:`frame_pacer.h:54-60`(`__builtin_ia32_pause` 循环);spin_reserve 计算 `frame_pacer.h:47-48`;sleep+spin 流程 `frame_pacer.h:44-60`。
- 调用链:`render_thread.cpp:179 / :286 / :449 / :554` → `video_pipeline.cpp:1373 / :1375 / :1385`(cclsp 三跳唯一)。
- 双线程同 QoS 且模拟器失败:`render_thread.cpp:181-182`(RenderThread)、`libretro_engine.cpp:1140-1145`(GameLoop,注释自证 ret==-1)。
- 现成平台 profile 先例:`audio_bridge.h:92-119`、`libretro_engine.cpp:1145`(`SetRtSchedulingAvailable(qosRet==0)`)。
- GameLoop 自身也有尾部自旋(`libretro_engine.cpp:1281-1289`,sleep 循环 + `std::this_thread::yield()` 补到 deadline)——同属"模拟器上可门控的烧核",但 yield **会**让出 CPU,危害低于 RenderThread 的 `pause`;一并记录供后续评估,本次不展开。

### 复核底线(对原结论的修正)

原"底线结论"主轴(165ms 主因 = 模拟器固有抢占,非 App 某个同步阻塞调用)**仍成立、不推翻**。但需补一条修正:**"App 无可修点"过强**——FramePacer 忙等自旋(`frame_pacer.h:54`,RenderThread)是一个 App 可门控削减的核争用次级加剧因素;模拟器上无 vsync 还精确烧核纯属浪费,平台门控(复用现成 `qosRet==0` 信号,改判别就地在 `render_thread.cpp:181`)可削减其对稀缺虚拟核的挤占。预期收益为边际改善(尤其对 `producer max_gap_ms` / 音频 underrun 的连带缓解),非根治。诚实标注:自旋对 165ms 的具体贡献量静态不可测,需真机/模拟器 `perfetto`/`ftrace` 抓 GameLoop runnable→running 等待间隙 + 对比"禁自旋前后"才能定量坐实。
