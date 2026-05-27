# T3 Audio Bridge — Fix-Verify Report

**Audit ref**: `docs/audit/audit-20260527-090735/agent-T3-audio.md`
**Scope**: `platform/audio/audio_bridge.cpp`, `audio_player.cpp`, `ring_buffer.cpp`, `audio_resampler.cpp`
**Date**: 2026-05-27

---

## F1: `resample_out_buf_` accessed after lock is released — stale pointer on concurrent Reset

- verdict: N/A_MITIGATED
- file: entry/src/main/cpp/platform/audio/audio_bridge.cpp
- line: 333-355
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
- notes: Code at lines 333-355 is unchanged from the original evidence_excerpt. CORE-REVIEW.md confirmed MITIGATED: both `AudioBridge::Reset` and `ProcessAudio` run on the Engine thread (GameLoop). The assumed two-thread concurrent scenario does not exist under the current threading model — `ProcessAudio` is the synchronous `retro_audio_sample_batch` callback, which cannot race with `Reset` in the same thread. No fix was applied, and no regression was introduced. Verdict: N/A_MITIGATED.

---

## F2: `drc_last_update_` written outside the mutex after the lock is released

- verdict: FIXED
- file: entry/src/main/cpp/platform/audio/audio_bridge.cpp
- line: 601-624
- evidence_excerpt: |
    // Audit T3-F2: clear DRC throttle timestamp so the first post-Reset update is not delayed by stale timing
    drc_last_update_ = std::chrono::steady_clock::time_point{};
    SetRunState(AudioRunState::INIT, "reset_same_rate");
    ...
    // Audit T3-F2: clear DRC throttle timestamp on full reinit path too
    drc_last_update_ = std::chrono::steady_clock::time_point{};
    SetRunState(AudioRunState::INIT, "reset_reinit");
- notes: Both occurrences of the fix are present. Line 602 covers the same-rate Reset path ("reset_same_rate") and line 624 covers the full reinit path ("reset_reinit"). Both assign `std::chrono::steady_clock::time_point{}` (zero epoch), which makes `time_since_epoch().count() == 0` evaluate true on the next call to `ProcessAudio`, immediately triggering the first DRC update after a Reset rather than waiting the full `kDrcUpdateIntervalMs` (50 ms). This directly addresses the functional sub-claim from CORE-REVIEW: "Reset 未清零 `drc_last_update_` 是真 functional bug". The suggested_fix shape (reset the timestamp in `Reset()`) is matched. The non-atomic field change was explicitly out-of-scope per CORE-REVIEW decision (single-thread UB not fixed). Verdict: FIXED.

---

## F3: `recover_streak_` mutated without the mutex after `lock.unlock()`

- verdict: N/A_MITIGATED
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
- notes: Code at lines 375-390 is unchanged from the original evidence_excerpt. CORE-REVIEW.md confirmed MITIGATED: `recover_streak_` is only accessed on the Engine thread — both in `ProcessAudio` (post-unlock) and in `Reset`/`Pause`/`Stop`/`Start` (which are also Engine thread calls). Sequential single-thread access means no data race exists under the current model. No fix was applied, no regression introduced. Verdict: N/A_MITIGATED.

---

## F4: `callback_last_time_` is a non-atomic member written on the audio callback thread without synchronization

- verdict: N/A_MITIGATED
- file: entry/src/main/cpp/platform/audio/audio_player.cpp
- line: 516-524
- evidence_excerpt: |
    // [DEBUG] 记录回调时间间隔（使用成员变量避免多线程数据竞争）
    auto current_time = std::chrono::steady_clock::now();
    long long delta_ms = 0;
    if (player->callback_log_count_ > 0) {
      delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                     current_time - player->callback_last_time_)
                     .count();
    }
    player->callback_last_time_ = current_time;
- notes: Code at lines 516-524 is unchanged from the original evidence_excerpt. CORE-REVIEW.md confirmed MITIGATED: with F5 fixed (API 12 callback-only path), there is exactly one callback thread (`OnWriteDataCallback`), and `callback_last_time_` is accessed exclusively on that thread. The dual-callback hazard raised by the original finding is eliminated by the F5 fix. No regression was introduced. Verdict: N/A_MITIGATED.

---

## F5: Both API11 (`OnWriteDataLegacy`) and API12 (`OnWriteDataCallback`) callbacks are registered simultaneously; double-firing risk

- verdict: FIXED
- file: entry/src/main/cpp/platform/audio/audio_player.cpp
- line: 175-202
- evidence_excerpt: |
    // Audit T3-F5: only register the API 12+ write-data callback. Previously the legacy
    // `OH_AudioStreamBuilder_SetRendererCallback` slot was also unconditionally set,
    // which is fragile — on devices where the OS honours both slots, the ring buffer
    // would be drained twice per render cycle (silent half-amplitude artifact).
    OH_AudioRenderer_OnWriteDataCallback writeDataCb = OnWriteDataCallback;
    result = OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder_, writeDataCb, this);
    ...
    // Register interrupt-event callback only (no write-data slot here, see T3-F5).
    OH_AudioRenderer_Callbacks interruptOnly;
    memset(&interruptOnly, 0, sizeof(OH_AudioRenderer_Callbacks));
    interruptOnly.OH_AudioRenderer_OnInterruptEvent = OnInterruptEvent;
    result = OH_AudioStreamBuilder_SetRendererCallback(builder_, interruptOnly, this);
- notes: The legacy `callbacks.OH_AudioRenderer_OnWriteData = OnWriteDataLegacy` slot is no longer set. The fix splits registration into two calls: (1) `SetRendererWriteDataCallback` with `OnWriteDataCallback` only (API 12+ path), and (2) a separate `SetRendererCallback` call using a zeroed `interruptOnly` struct that sets only `OnInterruptEvent` with a null write-data slot. This matches the suggested_fix shape of having exactly one data-consumer callback per render cycle, and eliminates the dual-registration fragility. The strategy is CHANGED_APPROACH relative to the suggested "#if API_VERSION compile guard" — instead the project targets API 12+ uniformly, drops the legacy slot entirely, and separates interrupt registration. This is a valid and arguably cleaner approach. The `// Audit T3-F5:` comment at line 175 is the fix location anchor. Verdict: FIXED (CHANGED_APPROACH variant — compile-time `#if API_VERSION` guard was not used; instead the legacy slot was removed unconditionally since compileSdkVersion targets API 12+).

---

## F6: `WriteWait` slow path loads `curr_head` with `memory_order_relaxed` before writing

- verdict: N/A_MITIGATED
- file: entry/src/main/cpp/platform/audio/ring_buffer.cpp
- line: 200-205
- evidence_excerpt: |
    // 醒来后再次检查并写入
    const size_t curr_head = head_.v.load(std::memory_order_relaxed);
    // const size_t curr_tail = tail_.v.load(std::memory_order_acquire); // 已经在 wait predicate 中检查过

    WriteDataInternal(data, samples, curr_head);
    head_.v.store(curr_head + samples, std::memory_order_release);
- notes: Code at lines 200-205 is unchanged from the original evidence_excerpt. CORE-REVIEW.md confirmed MITIGATED: the SPSC single-producer contract ensures no concurrent writer can update `head_` between the wakeup and the `WriteDataInternal` call. The relaxed load is safe under this invariant. No fix was applied, no regression introduced. Verdict: N/A_MITIGATED.

---

## F7: `Clear()` resets head/tail to 0 inside the mutex but `Write` fast path reads head with `memory_order_relaxed` — potential stale-index memcpy

- verdict: N/A_MITIGATED
- file: entry/src/main/cpp/platform/audio/ring_buffer.cpp
- line: 106-130 and 357-371
- evidence_excerpt: |
    bool RingBuffer::Write(const int16_t *data, size_t samples) {
      if (!data || samples == 0)
        return false;

      const size_t head = head_.v.load(std::memory_order_relaxed);
      const size_t tail = tail_.v.load(std::memory_order_acquire);
    ...
    void RingBuffer::Clear() {
      {
          std::lock_guard<std::mutex> lock(mutex_);
          head_.v.store(0, std::memory_order_relaxed);
          tail_.v.store(0, std::memory_order_relaxed);
          cv_not_empty_.notify_all();
          cv_not_full_.notify_all();
      }
- notes: Code at lines 106-130 (`Write`) and 357-371 (`Clear`) is unchanged from the original evidence_excerpt. CORE-REVIEW.md confirmed MITIGATED: `Write` and `Clear` are both called on the Engine thread sequentially (`ProcessAudio` must return before any message containing `Stop`/`Pause`/`Reset` is processed by GameLoop). The SPSC contract plus single-thread sequential access means no race between `Write` fast-path and `Clear` can occur. No fix was applied, no regression introduced. Verdict: N/A_MITIGATED.

---

## F8: Resampler `Resample()` uses `in_frames == 1` single-frame path accessing `in[1]` — potential read past single-element array

- verdict: FIXED
- file: entry/src/main/cpp/platform/audio/audio_resampler.cpp
- line: 84-95
- evidence_excerpt: |
    // Audit T3-F8: history init assumes interleaved stereo (`in` size must be >= in_frames * 2).
    // All current callers (AudioBridge::ProcessAudio -> retro_audio_sample_batch, and
    // AudioBridge::AudioSampleCallback which builds an explicit 2-element array)
    // satisfy this. If a future mono caller appears, gate this block on a stereo flag
    // or route the per-channel reads through fetch_channel (which has bounds via in_frames).
    if (!history_init_ && in_frames >= 1) {
      const int16_t l0 = in[0];
      const int16_t r0 = in[1];
      hist_l_[0] = hist_l_[1] = hist_l_[2] = hist_l_[3] = l0;
      hist_r_[0] = hist_r_[1] = hist_r_[2] = hist_r_[3] = r0;
      history_init_ = true;
    }
- notes: The `in[0]` / `in[1]` direct accesses are still present (unchanged logic), but a new comment block at lines 84-88 explicitly states the stereo-interleaved precondition and lists the current callers that satisfy it, plus the mitigation path for future mono callers. The original suggested_fix proposed replacing `in[1]` with `fetch_channel(in, in_frames, hist_r_, 0, false)`, but CORE-REVIEW classified this as a documentation/contract fix rather than a code logic change, and the fix chosen is a detailed comment explaining the precondition — a CHANGED_APPROACH. The `// Audit T3-F8:` comment at line 84 is the fix location anchor. The existing `const` qualifiers were also added to `l0`/`r0` declarations (lines 90-91 show `const int16_t l0` vs original `int16_t l0`), which is a minor hardening. Verdict: FIXED (CHANGED_APPROACH — documentation/contract comment rather than `fetch_channel` substitution, per CORE-REVIEW decision that current callers are safe and this is a forward-contract clarification).

---

## Summary

Fix-verify completed for all 8 T3 findings. Totals: **FIXED: 3** (F2, F5, F8) | **PARTIAL: 0** | **UNFIXED: 0** | **CHANGED_APPROACH: 0** (F5 and F8 have approach variants but are counted as FIXED per the CORE-REVIEW decision scope) | **N/A_MITIGATED: 5** (F1, F3, F4, F6, F7). All three fixed findings have their `// Audit T3-F<N>:` anchor comments present in the code. For F2, both Reset paths (same-rate and reinit) have the `drc_last_update_ = std::chrono::steady_clock::time_point{}` zero-assignment, satisfying the two-occurrence requirement. For F5, the write-data slot is cleanly separated from the interrupt-only callback registration with no legacy `OnWriteDataLegacy` slot set. For F8, the stereo precondition is documented inline. No regressions were detected at the five MITIGATED locations (F1, F3, F4, F6, F7 — all original code is intact and unchanged).
