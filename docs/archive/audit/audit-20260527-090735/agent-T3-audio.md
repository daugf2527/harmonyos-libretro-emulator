# T3 Audio Bridge Subsystem Audit — 2026-05-27

**Scope**: `platform/audio/audio_bridge.{cpp,h}`, `audio_player.{cpp,h}`, `ring_buffer.{cpp,h}`, `audio_resampler.{cpp,h}`

**Overall posture note**: No P0 issues were found. The subsystem has been substantially hardened since an earlier audit (DRC resampler lock, Clear() race fix, Cleanup() shutdown guard). Two P1 issues remain.

---

## F1: `resample_out_buf_` accessed after lock is released — stale pointer on concurrent Reset

- severity: P1
- file: entry/src/main/cpp/platform/audio/audio_bridge.cpp
- line: 334-353
- evidence_excerpt: |
    // Audit T3-F3: capture buffer pointer and sample count before releasing lock
    const int16_t* const out_buf_data = resample_out_buf_.data();
    const size_t samples_to_write = out_frames * 2;

    // 在调用可能阻塞的 WriteWait 之前解锁
    lock.unlock();
    ...
    if (buffer_ref) {
      auto write_start = std::chrono::steady_clock::now();
      if (should_block) {
        success = buffer_ref->WriteWait(out_buf_data, samples_to_write, running_);
      } else {
        success = buffer_ref->Write(out_buf_data, samples_to_write);
      }
- claim: `resample_out_buf_` is a `std::vector<int16_t>` member of `AudioBridge`. Its `.data()` pointer is captured at line 334 while `mutex_` is held. The lock is then released at line 338. After the unlock, `Reset()` on another thread (e.g., the engine thread changing sample rate mid-game) acquires `mutex_`, calls `Initialize()` which calls `ring_buffer_.reset()` / `audio_player_.reset()`, and returns. Neither `Reset()` nor `Initialize()` touches `resample_out_buf_` directly, so the buffer itself is not freed. However, `Initialize()` may call `resampler_.Init()` and re-enter `ProcessAudio()` from a new call chain that calls `resample_out_buf_.resize()` — because `Initialize()` at line 501 sets `initialized_ = true` and returns, allowing the next `ProcessAudio()` call to enter and resize the vector. If `resize()` causes a reallocation, the previously captured `out_buf_data` becomes a dangling pointer (UAF). The race window is: Engine-thread calls `Reset()`, which unlocks and calls `Initialize()`; simultaneously the audio-production thread is in the `WriteWait()` block using the stale pointer. This is a P1 rather than P0 because it requires a concurrent rate-change mid-game, which is infrequent but well-defined in `retro_get_system_av_info` flows.
- suggested_fix: Either (a) copy the resampled content into a local `std::vector<int16_t>` before unlocking so the write uses a stack/local-owned buffer that cannot be reallocated by another thread; or (b) hold a separate per-call local buffer (allocated under the lock before unlock, transferred via move semantics) and pass its `.data()` to `WriteWait`. Avoid capturing a raw pointer from a member vector across a lock boundary.

---

## F2: `drc_last_update_` written outside the mutex after the lock is released

- severity: P1
- file: entry/src/main/cpp/platform/audio/audio_bridge.cpp
- line: 437-467
- evidence_excerpt: |
    {
      auto now = std::chrono::steady_clock::now();
      // 简单的原子检查，无需加锁
      // 注意：GetUsage 内部是原子的，这里不需要加 AudioBridge 的大锁
      if (drc_last_update_.time_since_epoch().count() == 0 ||
          std::chrono::duration_cast<std::chrono::milliseconds>(now -
                                                                drc_last_update_)
                  .count() >= kDrcUpdateIntervalMs) {
        float usage = buffer_ref ? buffer_ref->GetUsage() : 0.0f;
        double skew = drc_skew_.load();
        ...
      }
      drc_last_update_ = now;
    }
- claim: `drc_last_update_` is a plain `std::chrono::steady_clock::time_point` member (not atomic, not guarded). It is read at line 441-443 and written at line 466, both outside `mutex_`. `ProcessAudio()` is called from the engine thread (via the libretro `retro_audio_sample_batch` callback); no second caller is expected — but note that `AudioSampleCallback()` (single-frame path, line 629) calls `ProcessAudio(samples, 1)` from the same thread, so in practice this is single-producer and the data race does not manifest at runtime. However, the C++ memory model declares concurrent non-atomic read/write on the same object as Undefined Behaviour regardless of observed thread scheduling. If anything changes the threading model (e.g., a future resampler thread), this will silently become a real data race. Additionally, the read of `drc_last_update_` at line 441 happens entirely outside the lock, while `Reset()` / `Initialize()` at line 599/521 call `resampler_.Init()` and `drc_skew_.store(1.0)` under the lock but do not reset `drc_last_update_` — meaning after a Reset the throttle might believe it last ran "just now" if the old timestamp is stale from a prior session, suppressing the first DRC update for up to `kDrcUpdateIntervalMs` (50 ms).
- suggested_fix: Declare `drc_last_update_` as `std::atomic<int64_t>` storing nanoseconds-since-epoch, or protect it with a dedicated lightweight atomic flag. Also reset it in `Reset()` alongside `drc_skew_.store(1.0)` to ensure the first DRC step after a rate change is not delayed by a stale timestamp.

---

## F3: `recover_streak_` mutated without the mutex after `lock.unlock()`

- severity: P2
- file: entry/src/main/cpp/platform/audio/audio_bridge.cpp
- line: 375-390
- evidence_excerpt: |
    if (!success) {
      recover_streak_ = std::min<uint32_t>(recover_streak_ + 1, 100);
      SetRunState(AudioRunState::RECOVERING, "producer_write_failed");
      LOGF(LOG_WARN,
           "%{public}s %{public}s producer drop: write failed (blocking=%{public}d)",
           kAudioChainPrefix, kAudioDiagPrefix, should_block ? 1 : 0);
    } else {
      if (recover_streak_ > 0) {
        recover_streak_--;
      }
- claim: `recover_streak_` is a plain `uint32_t` member. It is read and written at lines 376-384 after `lock.unlock()` at line 338. Concurrently, `Reset()` / `Pause()` / `Stop()` / `Start()` all write `recover_streak_ = 0` while holding `mutex_`. This is a data race under the C++ memory model (non-atomic object accessed from two threads without synchronization). The practical consequence is at most a stale or missed counter increment — not a crash — but it is UB. The counter is only used to drive `SetRunState(RECOVERING)`, so the worst visible outcome is a spurious state transition logged once.
- suggested_fix: Declare `recover_streak_` as `std::atomic<uint32_t>` (using `fetch_add`/`fetch_sub` / compare-exchange) or move the post-unlock mutations back under the lock using a re-lock scope.

---

## F4: `callback_last_time_` is a non-atomic member written on the audio callback thread without synchronization

- severity: P2
- file: entry/src/main/cpp/platform/audio/audio_player.cpp
- line: 514-521
- evidence_excerpt: |
    auto current_time = std::chrono::steady_clock::now();
    long long delta_ms = 0;
    if (player->callback_log_count_ > 0) {
      delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                     current_time - player->callback_last_time_)
                     .count();
    }
    player->callback_last_time_ = current_time;
- claim: `callback_last_time_` is declared `mutable std::chrono::steady_clock::time_point callback_last_time_{}` (audio_player.h line 192). It is read and written on the OHAudio callback thread (lines 517-521 of `OnWriteDataCallback`, and symmetrically in `OnWriteDataLegacy`). `Cleanup()` runs on a different thread (the engine or NAPI thread) and may read the state of `AudioPlayer` members while the callback is still in flight (the 2-second `wait_for` at line 937 is the drain window). During that drain window, both the callback thread and the cleanup thread can be active. While `Cleanup()` does not directly touch `callback_last_time_`, the real hazard is that `OnWriteDataLegacy` also uses `callback_last_time_` identically (line 518 mirrors the same pattern), and both API11 and API12 callbacks can be registered simultaneously (both are registered in `Initialize()` at lines 181 and 192-198). If both fire on different threads (unlikely but not impossible on some OHAudio versions), the time_point is a data race. Even under single-callback-thread semantics, `std::chrono::time_point` is not declared trivially copyable on all ARM toolchains and technically requires atomic access for cross-thread visibility.
- suggested_fix: Convert `callback_last_time_` to `std::atomic<int64_t>` storing nanoseconds since a fixed epoch (or steady_clock epoch), reading/writing with relaxed ordering since it is only used for jitter logging and does not need precision ordering.

---

## F5: Both API11 (`OnWriteDataLegacy`) and API12 (`OnWriteDataCallback`) callbacks are registered simultaneously; double-firing risk

- severity: P1
- file: entry/src/main/cpp/platform/audio/audio_player.cpp
- line: 175-198
- evidence_excerpt: |
    OH_AudioRenderer_Callbacks callbacks;
    memset(&callbacks, 0, sizeof(OH_AudioRenderer_Callbacks));
    // API 11 回调：在旧版本上由 builder callbacks 使用
    callbacks.OH_AudioRenderer_OnWriteData = OnWriteDataLegacy;
    callbacks.OH_AudioRenderer_OnInterruptEvent = OnInterruptEvent;

    result = OH_AudioStreamBuilder_SetRendererCallback(builder_, callbacks, this);
    ...
    // API 12+ 推荐: 使用 SetRendererWriteDataCallback 设置写入回调
    OH_AudioRenderer_OnWriteDataCallback writeDataCb = OnWriteDataCallback;
    result = OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder_, writeDataCb, this);
- claim: Both `OH_AudioStreamBuilder_SetRendererCallback` (the API 11 `OH_AudioRenderer_OnWriteData` slot) and `OH_AudioStreamBuilder_SetRendererWriteDataCallback` (API 12+ dedicated write-data callback) are set unconditionally on the same builder. On devices running HarmonyOS API 12+, if the system honours both registrations and calls both callbacks per render cycle, each callback independently reads the ring buffer. The first callback partially consumes samples; the second finds the buffer partially drained and writes silence for the remainder. The net effect is every render frame delivering half-amplitude audio plus silence artefacts. The HarmonyOS documentation states that when both are registered, the API 12 callback takes precedence and the `OH_AudioRenderer_OnWriteData` slot is ignored — but this behaviour is device/API-level and not guaranteed to be backward-compatible. The unconditional dual registration is fragile: if a future OS update changes the precedence rule, double-drain becomes a real audio corruption path.
- suggested_fix: Guard the `SetRendererWriteDataCallback` registration behind a compile-time or runtime API-level check (e.g., `__OHOS_API_VERSION >= 12`). On API 11, register only the legacy slot; on API 12+, register only the new callback slot and leave `OH_AudioRenderer_OnWriteData` as null. This eliminates the dual-registration ambiguity entirely.

---

## F6: `WriteWait` slow path loads `curr_head` with `memory_order_relaxed` before writing

- severity: P2
- file: entry/src/main/cpp/platform/audio/ring_buffer.cpp
- line: 200-205
- evidence_excerpt: |
    // 醒来后再次检查并写入
    const size_t curr_head = head_.v.load(std::memory_order_relaxed);
    // const size_t curr_tail = tail_.v.load(std::memory_order_acquire); // 已经在 wait predicate 中检查过

    WriteDataInternal(data, samples, curr_head);
    head_.v.store(curr_head + samples, std::memory_order_release);
- claim: After waking from `cv_not_full_.wait()`, the slow path loads `head_.v` with `memory_order_relaxed` (line 201) then immediately calls `WriteDataInternal` and stores `curr_head + samples` with `memory_order_release` (line 205). The relaxed load means the compiler/CPU is not required to observe the most recent `tail_` store from the consumer thread — the predicate inside `wait()` used `memory_order_acquire` on `tail_` (line 182), but that acquire happened on a prior iteration; by the time execution reaches line 201 the tail may have advanced further (more space freed) which is safe, but more critically the relaxed load of `head_` could observe a stale value if another writer had incremented `head_` in the interim. The SPSC contract prevents concurrent writers, so in practice this is benign — there is only one producer. However, if the ownership invariant ever relaxes (e.g., `AudioSampleCallback` and `AudioSampleBatchCallback` called from different contexts), the relaxed head load before write is a data race on `head_`. The correct ordering for a store-to-be-published is to load the index with at least `memory_order_relaxed` is fine for the writer's own head (SPSC invariant), but the missing `acquire` on `head_` after wakeup is a documentation/future-maintenance hazard.
- suggested_fix: Load `head_.v` with `memory_order_acquire` on the wakeup path to be consistent with the contract that the lock release from `cv_not_full_.notify_one()` synchronizes-with the `wait()` return. Add a comment explicitly noting the SPSC invariant that makes the relaxed load sufficient today, so future maintainers understand the constraint.

---

## F7: `Clear()` resets head/tail to 0 inside the mutex but `Write` fast path reads head with `memory_order_relaxed` — potential stale-index memcpy

- severity: P1
- file: entry/src/main/cpp/platform/audio/ring_buffer.cpp
- line: 106-130 and 357-371
- evidence_excerpt: |
    bool RingBuffer::Write(const int16_t *data, size_t samples) {
      if (!data || samples == 0)
        return false;

      const size_t head = head_.v.load(std::memory_order_relaxed);
      const size_t tail = tail_.v.load(std::memory_order_acquire);

      const size_t size = head - tail;
      const size_t available = capacity_ - size;

      if (samples > available) {
        ...
        return false;
      }

      WriteDataInternal(data, samples, head);

      head_.v.store(head + samples, std::memory_order_release);
- claim: `RingBuffer::Write()` (fast path, non-blocking) loads `head_.v` with `memory_order_relaxed` (line 110). `Clear()` stores 0 into `head_` and `tail_` under `mutex_` with `memory_order_relaxed` (lines 363-364). `Write()` does not hold `mutex_`. Therefore a race exists: `Write()` loads a stale large `head` value (e.g., 90000) while `Clear()` has just zeroed both indices. `WriteDataInternal(data, 960, 90000)` computes `offset = 90000 & mask_` — for a capacity of 96000 (rounded up to 131072), this is `90000 & 131071 = 90000`, well within the allocated array, so no out-of-bounds access occurs. However the consumer (audio callback) now reads from index 0 (post-Clear) while the producer writes to 90000 — the written data is effectively orphaned and the buffer logically contains garbage: the consumer will underrun on the orphaned samples. More critically, after `Write` stores `head + samples = 90960`, and the consumer calls `Clear()` again, then `WriteDataInternal` with the stale `head = 90960` writes to offset `90960 & 131071 = 90960` — still in bounds, but the invariant `head >= tail` (needed for `available = capacity_ - (head-tail)` to be correct) is violated because tail is now 0 and head is about to be set to 90960, making the buffer appear 90960/131072 = ~69% full with stale data. The probability of this specific interleaving is low, but `Clear()` is called by `Pause()`, `Stop()`, `Reset()`, and `AudioPlayer::Stop()` while `ProcessAudio()` may be concurrently running (it releases `mutex_` before writing). The comment in `Clear()` acknowledges the `WriteWait` slow-path issue was fixed, but the `Write` fast path is not protected by `mutex_` and still reads head with relaxed ordering.
- suggested_fix: In `Write()` (fast path), load `head_.v` with `memory_order_acquire` to ensure it observes the reset to 0 performed by `Clear()`. Alternatively, document clearly that `Write()` may only be called while no concurrent `Clear()` can execute (which requires callers to guarantee mutual exclusion at a higher level — currently not the case since `ProcessAudio()` calls `Write()` after releasing `mutex_`).

---

## F8: Resampler `Resample()` uses `in_frames == 1` single-frame path accessing `in[1]` — potential read past single-element array

- severity: P2
- file: entry/src/main/cpp/platform/audio/audio_resampler.cpp
- line: 79-89
- evidence_excerpt: |
    size_t AudioResampler::Resample(const int16_t *in, size_t in_frames,
                                    int16_t *out) {
      if (!in || !out || in_frames == 0 || current_ratio_ <= 0.0)
        return 0;

      if (!history_init_ && in_frames >= 1) {
        int16_t l0 = in[0];
        int16_t r0 = in[1];
        hist_l_[0] = hist_l_[1] = hist_l_[2] = hist_l_[3] = l0;
        hist_r_[0] = hist_r_[1] = hist_r_[2] = hist_r_[3] = r0;
        history_init_ = true;
      }
- claim: `AudioSampleCallback` (single-frame path in `audio_bridge.cpp` line 635-637) creates a 2-element array `int16_t samples[2] = {left, right}` and calls `ProcessAudio(samples, 1)`. `ProcessAudio` calls `resampler_.Resample(data, frames, ...)` where `frames == 1`. Inside `Resample()`, when `!history_init_`, the code reads `in[0]` and `in[1]` — valid for the 2-element array, so no out-of-bounds here. However `in_frames >= 1` is the guard (line 84), not `in_frames >= 2`. If any future caller passes `in_frames == 1` with an `in` array that has only 1 element (e.g., a mono core or a future code path that does not construct a stereo pair), accessing `in[1]` is out-of-bounds. The existing caller happens to be safe, but the function silently assumes stereo layout without asserting `in` has `2 * in_frames` elements. The `fetch_channel` helper correctly bounds-checks via the `in_frames` parameter on per-frame lookups, but the history initialization bypasses that helper.
- suggested_fix: Add a guard `if (in_frames < 1 || in == nullptr) return 0;` (already present) and additionally access `in[1]` only when the stereo layout is guaranteed — replace the direct `in[1]` with a call to `fetch_channel(in, in_frames, hist_r_, 0, false)` which is already bounds-checked. This also makes the history initialization consistent with the main resample loop.

---

## Audit observations

**Lock discipline is the main strength.** The `mutex_` in `AudioBridge` protects all shared state — resampler, ring buffer pointer, player pointer, and DRC skew — during initialization, reset, and the locked portion of `ProcessAudio`. The `Clear()` fix (holding `mutex_` for index reset) and the DRC `resampler_.UpdateRatio()` re-lock both show recent deliberate hardening. The `CallbackGuard` pattern in `AudioPlayer` with a 2-second drain window in `Cleanup()` is a solid shutdown discipline that prevents the common use-after-free where an in-flight callback fires after the renderer is destroyed.

**The residual risk is the lock-release-then-use pattern in `ProcessAudio`.** The function correctly releases `mutex_` before `WriteWait()` to avoid priority inversion (the callback thread would deadlock if it needed the same lock). However, the raw pointer `out_buf_data` captured from `resample_out_buf_.data()` before the unlock and the plain-member writes to `recover_streak_` and `drc_last_update_` after the unlock are the live hazards. The `resample_out_buf_` pointer risk (F1) is the highest-priority fix: a concurrent `Reset()` with a rate change can trigger a reallocation that invalidates the pointer mid-`WriteWait`. The `drc_last_update_` non-atomic access (F2) compounds this by suppressing the first DRC correction after a rate change for up to 50 ms.

**The dual-callback registration (F5) is an architectural fragility** rather than a latent crash: on current HarmonyOS API 12 devices it is harmless (API 12 callback wins), but it violates the principle of having exactly one data consumer per render cycle and will silently corrupt audio if the platform ever changes its precedence rule. The SPSC ring buffer is fundamentally sound; `WriteWait`'s slow-path wakeup ordering (F6) and `Clear()`'s interaction with the `Write` fast path (F7) are ordering discipline issues rather than crashes under the current strictly single-producer regime.
