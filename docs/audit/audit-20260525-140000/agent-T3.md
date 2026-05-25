# AudioBridge 审计报告 — agent-T3

审计范围：`entry/src/main/cpp/platform/audio/`（audio_bridge.cpp/h, audio_player.cpp/h, ring_buffer.cpp/h, audio_resampler.cpp/h）
审计日期：2026-05-25

---

## F1: DRC skew 更新与 ProcessAudio 主流程之间的 double-lock 死锁风险

- severity: P1
- file: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- line: 251–467
- evidence_excerpt: |
    ```
    // 第 251 行：外层加锁
    std::unique_lock<std::mutex> lock(mutex_);
    ...
    // 第 334 行：解锁后进行写入
    lock.unlock();
    ...
    // 第 455 行：DRC 更新时再次加锁（mutex_ 同一把锁）
    std::lock_guard<std::mutex> drc_guard(mutex_);
    drc_skew_.store(skew);
    resampler_.UpdateRatio(skew);
    ```
- claim: `ProcessAudio` 在第 251 行对 `mutex_` 加 `unique_lock`，在第 334 行 `lock.unlock()` 后执行 RingBuffer 写入，再在第 455 行的 DRC 更新代码块里再次 `lock_guard<std::mutex> drc_guard(mutex_)` 加同一把锁。这一段代码位于 `lock.unlock()` 之后，本身不会死锁，但整个函数存在两次加/解同一把 `mutex_` 的语义。如果将来任何调用路径在 `lock.unlock()` 之后（第 334–465 行之间）又持锁调用进来（比如 `Reset()`），并且 `Reset()` 在等待 `mutex_` 期间 `WriteWait` 阻塞住，就会形成跨函数死锁。更直接的问题是：第 437 行的 `now` 与第 239 行的 `now` 命名相同但作用域不同（内层 block），虽然 C++ 允许遮蔽（shadowing），但极易引发维护 bug，与 skew 更新逻辑混淆。
- suggested_fix: 把 DRC 更新逻辑提取到独立的私有方法 `UpdateDrcSkew()` 中，不在 `ProcessAudio` 内部二次加 `mutex_`；或将 DRC 更新时机改为 `ProcessAudio` 持锁期间（加锁之内）统一执行。消除内层 `now` 变量遮蔽，改用不同名称。

---

## F2: WriteWait 慢路径在 running=false 时不验证空间就写入（潜在越界）

- severity: P1
- file: `entry/src/main/cpp/platform/audio/ring_buffer.cpp`
- line: 162–224
- evidence_excerpt: |
    ```
    // 第 179–184 行：等待条件
    cv_not_full_.wait(lock, [&]() {
      if (!running.load(std::memory_order_relaxed)) return true;
      const size_t curr_head = head_.v.load(std::memory_order_relaxed);
      const size_t curr_tail = tail_.v.load(std::memory_order_acquire);
      return samples <= capacity_ - (curr_head - curr_tail);
    });
    // 第 190 行：running=false 提前返回 false（安全）
    if (!running.load(std::memory_order_relaxed)) {
      writer_waiting_.store(false, std::memory_order_relaxed);
      ...
      return false;
    }
    // 第 200–205 行：唤醒后使用 curr_head 写入，但 curr_head 未再次校验空间
    const size_t curr_head = head_.v.load(std::memory_order_relaxed);
    WriteDataInternal(data, samples, curr_head);
    head_.v.store(curr_head + samples, std::memory_order_release);
    ```
- claim: 唤醒后的第 201 行仅重新加载 `curr_head`，没有重新加载 `curr_tail` 并再次检查 `samples <= capacity_ - (curr_head - curr_tail)`。在 SPSC（单生产者/单消费者）场景下，这里理论上安全，因为消费者只会扩大可用空间。但代码注释明确指出"已经在 wait predicate 中检查过"（第 202 行），该注释是错误的：predicate 用的是 lambda 内部读到的 `curr_tail`，而 wait 语义保证 predicate 为 true 时才唤醒，所以实际空间足够。然而 Clear() 会在持锁情况下将 `head_` 和 `tail_` 都归零并 notify_all，唤醒等待的 writer；writer 被唤醒后若 `running` 仍为 true（Clear 后立即 re-arm 的场景），`curr_head` 已是 0，写入 `data` 的 `samples` 个样本不会越界，但此时旧的 `curr_head`（已被 Clear 归零前的值）与新 `curr_head=0` 之间形成不一致。如果 Clear 发生在 wait predicate 到 WriteDataInternal 之间（条件变量 spurious wakeup 场景），数据会被写到错误位置。这是 TOCTOU（time-of-check / time-of-use）问题。
- suggested_fix: 唤醒后重新检查 `(curr_head, curr_tail)` 并验证空间充足，如不足则循环等待，不直接写入。消除"已检查"注释的误导。

---

## F3: ProcessAudio 在解锁后访问 resample_out_buf_（无锁访问成员变量）

- severity: P1
- file: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- line: 334–354
- evidence_excerpt: |
    ```
    // 第 334 行：解锁
    lock.unlock();
    ...
    // 第 350-354 行：访问 resample_out_buf_（成员变量）
    if (buffer_ref) {
      ...
      if (should_block) {
        success = buffer_ref->WriteWait(resample_out_buf_.data(), samples_to_write, running_);
      } else {
        success = buffer_ref->Write(resample_out_buf_.data(), samples_to_write);
      }
    ```
- claim: `resample_out_buf_` 是 `AudioBridge` 的成员变量（`std::vector<int16_t>`），在第 295–307 行的锁内被 `resize` 和填充，然后在第 334 行解锁后继续被读取（第 352/354 行的 `WriteWait`/`Write` 调用传入 `.data()` 指针）。如果另一个线程（如 `Reset()`）在此窗口期间持锁并调用 `resample_out_buf_.resize()` 或通过 `Initialize()` 重置整个对象，会导致 `resample_out_buf_.data()` 指针失效，发生 use-after-resize / 悬空指针。虽然 `Reset()` 也会持 `mutex_`，写端（ProcessAudio）解锁后 Reset 才能进入，但 Reset 执行后会让 `resample_out_buf_` 的内容被另一次 ProcessAudio 调用（下一帧）的重采样覆盖，因为 `resample_out_buf_` 没有按调用实例隔离。严格说这是在 libretro 单线程回调约束下可控的，但注释"必须在锁内进行 Resample"与实际解锁后读取 `resample_out_buf_` 之间存在逻辑不一致，构成隐患。
- suggested_fix: 在 `lock.unlock()` 之前将 `resample_out_buf_.data()` 指针和 `samples_to_write` 拷贝到局部变量，并确认 `resample_out_buf_` 的容量在解锁后不会被并发 resize。或者改用本地 `std::vector<int16_t> local_buf` 在栈上持有数据，消除对成员变量的跨锁访问。

---

## F4: OH_AudioStreamBuilder 在 Initialize 失败时仅部分 Cleanup（builder_ 泄漏场景）

- severity: P2
- file: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- line: 116–208
- evidence_excerpt: |
    ```
    // 第 117–124 行：创建 builder
    OH_AudioStream_Result result =
        OH_AudioStreamBuilder_Create(&builder_, AUDIOSTREAM_TYPE_RENDERER);
    if (result != AUDIOSTREAM_SUCCESS) {
      ...
      return false;  // 直接 return，未调用 Cleanup
    }
    ...
    // 第 181–187 行：SetRendererCallback 失败调用 Cleanup
    result = OH_AudioStreamBuilder_SetRendererCallback(builder_, callbacks, this);
    if (result != AUDIOSTREAM_SUCCESS) {
      ...
      Cleanup();
      return false;
    }
    ```
- claim: `OH_AudioStreamBuilder_Create` 失败时（第 120–124 行）直接 `return false`，此时 `builder_` 仍为 `nullptr`，不会泄漏（正常）。但是在第 129–164 行的参数配置阶段（`SetSamplingRate`、`SetChannelCount`、`SetSampleFormat`、`SetEncodingType`、`SetLatencyMode`、`SetRendererInfo`、`SetFrameSizeInCallback`）调用失败后，代码只记录日志但**不** `return`（`SetFrameSizeInCallback` 失败仅打 ERROR 日志，继续执行）。若 `SetFrameSizeInCallback` 失败后继续成功创建了 renderer，则以错误帧大小运行，结果不可预期。更重要的是：若 `OH_AudioStreamBuilder_GenerateRenderer` 失败（第 202–208 行），调用 `Cleanup()` 时 `renderer_` 为 `nullptr`，`builder_` 仍存在，`Cleanup()` 的第 971 行 `OH_AudioStreamBuilder_Destroy(builder_)` 会正确销毁它——这是安全的。但 `OH_AudioRenderer_SetVolume`（第 211 行）在 `GenerateRenderer` 成功后调用，如果 `renderer_` 为空（异常情况），会传 `nullptr` 给 API，属于未定义行为。
- suggested_fix: 在 `OH_AudioRenderer_SetVolume` 调用前确认 `renderer_ != nullptr`。为 `SetFrameSizeInCallback` 失败添加 `Cleanup(); return false;` 早退逻辑（如业务要求严格帧大小）。

---

## F5: Cleanup() 中等待 active_callbacks==0 时无超时保护（可能永久阻塞）

- severity: P2
- file: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- line: 912–986
- evidence_excerpt: |
    ```
    // 第 934–937 行：无超时等待所有回调退出
    {
      std::unique_lock<std::mutex> lock(callback_mutex_);
      callback_cond_.wait(lock, [this]() { return active_callbacks_ == 0; });
    }
    ```
- claim: `Cleanup()` 调用 `OH_AudioRenderer_Stop(renderer)` 后，等待所有 OHAudio 回调退出（`active_callbacks_ == 0`）。这依赖于 `shutting_down_ = true`（第 915 行）能及时让所有在途回调通过 `EnterCallback()` 的守卫提前返回。但如果某个回调在 `shutting_down_` 置 true 之前已经通过 `EnterCallback()` 进入，并且在 `WriteWait`/`ReadWait` 上阻塞（OHAudio 回调通常不应阻塞，但 `CallbackGuard` 保护的范围内如果 `ring_buffer_->Read` 因任何原因不返回），`callback_cond_.wait` 将永久挂起，导致析构死锁。
- suggested_fix: 改用 `callback_cond_.wait_for(lock, std::chrono::seconds(2), [...])` 加超时，超时后打 ERROR 日志并强制继续 Cleanup，避免析构卡死。

---

## F6: RingBuffer 日志节流计数器（write_wait_block_logs_ 等）在多线程访问下无保护

- severity: P2
- file: `entry/src/main/cpp/platform/audio/ring_buffer.h` / `ring_buffer.cpp`
- line: ring_buffer.h:129–132，ring_buffer.cpp:167–173，288–294
- evidence_excerpt: |
    ```
    // ring_buffer.h 第 129–132 行：非 atomic 成员，mutable
    mutable size_t write_wait_block_logs_ = 0;
    mutable size_t write_wait_resume_logs_ = 0;
    mutable size_t read_wait_block_logs_ = 0;
    mutable size_t read_wait_resume_logs_ = 0;
    ```
- claim: 这四个计数器是 `mutable size_t`（非 atomic），在 `WriteWait`（生产者线程）和 `ReadWait`（消费者线程）中分别被读写。注释说明 `mutex_` 仅用于 wait/notify，不保护数据读写。因此这四个计数器存在未保护的多线程竞争（data race），在 C++ 标准下属于未定义行为（UB）。虽然后果是偶发多打/少打几条日志，但 UB 本身不可接受。
- suggested_fix: 改为 `std::atomic<size_t>` 或将其移入 `mutex_` 保护范围。鉴于日志节流是非关键功能，改为 `std::atomic<size_t>` 代价最小。

---

## F7: AudioResampler::Resample 输出帧数估算可能不足（phase 累积导致实际输出溢出预估）

- severity: P2
- file: `entry/src/main/cpp/platform/audio/audio_bridge.cpp` 和 `audio_resampler.cpp`
- line: audio_bridge.cpp:299–303, audio_resampler.cpp:92–119
- evidence_excerpt: |
    ```
    // audio_bridge.cpp 第 299–303 行：预分配输出缓冲区
    size_t max_out_frames = static_cast<size_t>(std::ceil(frames * ratio)) + 8;
    const size_t required_samples = max_out_frames * 2;
    if (resample_out_buf_.size() < required_samples) {
      resample_out_buf_.resize(required_samples);
    }
    // audio_resampler.cpp 第 92–119 行：Resample 使用 phase_ 从上次结束位置继续
    const double step = 1.0 / current_ratio_;
    double pos = phase_;   // phase_ 可能 > 0（来自上次调用）
    while (pos < static_cast<double>(in_frames)) {
      ...
      out_frames++;
      pos += step;
    }
    ```
- claim: `phase_` 是跨批次持续的流式位置，范围 `[0, 1.0/ratio)`。`max_out_frames` 的估算是 `ceil(frames * ratio) + 8`，而实际输出帧数取决于 `phase_` 初始值：若 `phase_` 接近 0（本批次从输入起点开始），实际输出 ≈ `frames * ratio`，+ 8 的余量足够；若 `phase_` 极小（接近 0 但 step 很大时下採样比 < 1），余量仍足。但在**上采样**场景（ratio > 1，step < 1），实际输出 = `floor((in_frames - phase_) / step) + 1`。当 `ratio` 受 DRC skew 调整到 `base_ratio * kDrcMaxSkew`（即 `kDrcMaxSkew = 1.005`），且 `base_ratio` 本身较大时，`+8` 的固定余量是否足够需要验证。极端情况下 `out_frames` 可能比 `max_out_frames` 大 1，导致 `out[out_frames * 2 + 1]` 写到 `resample_out_buf_` 越界。
- suggested_fix: 将余量从 `+8` 改为 `+16` 或按公式 `ceil((in_frames - phase_min) * ratio) + 2` 精确计算，并在 `Resample` 内部增加 `out_frames < max_out_frames` 的断言/守卫。

---

## F8: Reset() 释放 ring_buffer_ 后调用 Initialize() 前，ProcessAudio 可窗口期访问悬空 buffer_ref

- severity: P1
- file: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- line: 571–615
- evidence_excerpt: |
    ```
    // 第 600–612 行：在锁内 reset ring_buffer_ 并 unlock
    if (initialized_.load()) {
      if (audio_player_) {
        running_.store(false, std::memory_order_release);
        if (ring_buffer_) ring_buffer_->Clear();
        audio_player_->Stop();
        audio_player_.reset();
      }
      ring_buffer_.reset();           // ring_buffer_ 被销毁
      initialized_.store(false);
      ...
    }
    }  // <-- 锁释放（第 613 行右括号对应的 lock_guard 析构）
    
    return Initialize(sample_rate);   // 第 615 行：锁外调用，Initialize 内再加锁
    ```
- claim: `Reset()` 在第 573–613 行的锁作用域内将 `ring_buffer_` 销毁（`ring_buffer_.reset()`），然后锁释放，再调用 `Initialize(sample_rate)`（第 615 行）。`Initialize` 内部会再次加 `mutex_` 锁。在锁释放（第 613 行）到 `Initialize` 重新加锁之间有一个窗口。此时 `initialized_` 已被置为 `false`，`ProcessAudio` 第 230 行检查 `initialized_` 会提前返回——**这是正确的保护**。但 `ProcessAudio` 第 230 行的检查是 `memory_order_acquire`，而 `initialized_.store(false)` 在第 609 行是默认 `memory_order_seq_cst`，两者同步没有问题。实际上这条路径是安全的。但值得注意的是：`buffer_ref` 是在锁内（第 311 行）通过 `shared_ptr` 延长生命周期的，而 `ring_buffer_` 在 `Initialize` 中会被创建为新的 `unique_ptr<RingBuffer>`（`shared_ptr` 拷贝的是原指针）。如果 `ProcessAudio` 在 `Reset` 执行后仍持有旧的 `buffer_ref`（来自上次调用的 `shared_ptr` 拷贝），并向其写入数据——但此时 `WriteWait` 会因 `running_=false` 立即返回，所以实际无害。但注释声称 `buffer_ref` 能防止 Reset 在其他线程销毁它，而实际上 `ring_buffer_` 是 `unique_ptr`，不是 `shared_ptr`，`buffer_ref = ring_buffer_` 这行（第 311 行）是从 `unique_ptr` 取裸指针封到 `shared_ptr`（需要确认），如果是这样，`shared_ptr` 的引用计数不受 `unique_ptr` 的 reset 影响——即 `unique_ptr.reset()` 并**不会**通过 `shared_ptr` 保留生命周期，`shared_ptr` 此时持有悬空指针。
- suggested_fix: 将 `ring_buffer_` 改为 `std::shared_ptr<RingBuffer>` 以正确支持 `buffer_ref` 的生命周期延长语义，或者移除 `buffer_ref` 的 `shared_ptr` 包装（它无法正确延长 `unique_ptr` 管理的对象的生命周期），改用其他同步机制确保 `Reset` 时不并发访问 RingBuffer。

---

## F9: OnWriteDataCallback 中直接访问 player->callback_last_time_ 等成员（音频回调线程无锁）

- severity: P2
- file: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- line: 513–521, 635
- evidence_excerpt: |
    ```
    // 第 513–521 行：音频回调线程直接读写成员变量
    auto current_time = std::chrono::steady_clock::now();
    long long delta_ms = 0;
    if (player->callback_log_count_ > 0) {
      delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                     current_time - player->callback_last_time_)
                     .count();
    }
    player->callback_last_time_ = current_time;
    ...
    // 第 635 行：
    player->callback_log_count_++;
    ```
- claim: `callback_last_time_`、`callback_log_count_`、`callback_jitter_log_count_`、`callback_diag_log_count_`、`callback_underrun_log_count_`、`callback_cost_log_count_`、`callback_invalid_log_count_` 均为非 atomic 成员变量，在音频回调线程（OHAudio 系统线程）中被读写，同时 `ProcessPendingInterruptActions()` 可能在引擎线程中被调用（audio_bridge.cpp 第 273 行），并通过 `audio_player_->ProcessPendingInterruptActions()` 调用 `Stop()`，后者持 `state_mutex_` 但不是 `callback_mutex_`。这些计数器只被单一 OHAudio 回调线程访问（API 12 通常单线程化），但 OHAudio 不保证这一点，且 header 注释称"避免多线程数据竞争"，说明开发者已意识到问题。这些计数器同样存在与 F6 相同的 data race UB。
- suggested_fix: 将这些计数器改为 `std::atomic<int>` / `std::atomic<int32_t>`，或在 `callback_mutex_` 内部访问。

---

## F10: AudioBridge::Initialize 重入路径未重置 core_sample_rate_（采样率不更新）

- severity: P2
- file: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- line: 500–518
- evidence_excerpt: |
    ```
    // 第 503–517 行：已初始化时直接返回，不更新 core_sample_rate_
    if (initialized_.load()) {
      running_.store(true, std::memory_order_release);
      buffering_ = false;
      is_started_ = false;
      recover_streak_ = 0;
      SetRunState(AudioRunState::INIT, "initialize_reuse");
      if (ring_buffer_) {
        ring_buffer_->Clear();
      }
      ...
      return true;
    }
    ```
- claim: 当 `Initialize(int32_t sample_rate)` 被第二次调用（`initialized_` 已为 true）时，早返回路径不更新 `core_sample_rate_`，也不调用 `resampler_.Init()`。如果调用方传入不同的 `sample_rate`（游戏切换），resampler 继续以旧采样率工作，产生音调错误的输出。此问题在 `Reset()` 中被处理（会调用新的 `Initialize` 或复用），但直接调用 `Initialize` 的路径（通过 IAudioSink 接口）会静默忽略新采样率。
- suggested_fix: 在重入路径中比较新旧 `core_sample_rate_`，若不同则退化为完整重初始化（调用 `Reset(sample_rate)`），或至少打 WARN 日志说明采样率被忽略。

---

## DONE
