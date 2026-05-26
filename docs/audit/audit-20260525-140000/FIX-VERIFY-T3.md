# Fix-Verify T3 — Audio (commit 0bb99ce)

验证时间：2026-05-26  
Commit：`0bb99cec64c836bc427b02869ef9ddbe4d07991f`  
范围：audio_bridge.cpp / audio_player.cpp / ring_buffer.h / audio_player.h  
T3-F8 跳过（FALSE_POSITIVE）

---

## 总结表

| ID | 期望 fix | 判定 | 备注 |
|---|---|---|---|
| T3-F1 | DRC re-lock 窗口防御性注释/处理 | **VERIFIED** | 加了锁 + 注释说明为何此处需要加锁 |
| T3-F2 | WriteWait predicate / Clear() 同步防御性注释 | **PARTIAL** | 谓词在 wait 内正确重读 tail，但无显式 T3-F2 标注注释；P2 可接受 |
| T3-F3 | unlock 前捕获 resample_out_buf_ 指针 | **VERIFIED** | 完整实现，消除 dangling 窗口 |
| T3-F4 | SetFrameSizeInCallback 失败 → Cleanup()+return false | **VERIFIED** | 完整实现，提前返回 |
| T3-F5 | callback_cond_.wait → wait_for 2s 超时 | **VERIFIED** | 完整实现，有审计注释 |
| T3-F6 | mutable size_t 计数器 → std::atomic<size_t> | **VERIFIED** | 4 个计数器全部改 atomic，有审计注释 |
| T3-F7 | max_out_frames +8 → +16 | **VERIFIED** | 精确匹配，有审计注释 |
| T3-F9 | callback log 计数器 → std::atomic<int> | **VERIFIED** | audio_player.h 9 个计数器全部改 atomic |
| T3-F10 | Initialize() re-entry：sample_rate 不同时 Reset+reinit | **VERIFIED** | 完整实现，有日志输出 |

**VERIFIED 8 / PARTIAL 1 / NOT_APPLIED 0**

---

## 逐项详情

### T3-F1 — DRC unique_lock/lock_guard re-lock 窗口（P2 降级）

**判定：VERIFIED**

CORE-REVIEW 将此项降级为 P2（未来维护 footgun，非当前 bug）。commit 在 DRC block 内改用 `std::lock_guard<std::mutex> drc_guard(mutex_)` 重新加锁，并在注释中明确解释了为何此处需要加锁：

```cpp
// audio_bridge.cpp:453-458
// 更新 Ratio 需要加锁,因为 Reset() 可能在另一线程重置 Resampler。
// 原实现注释承认"风险可控"但实际是数据竞争 UB,这里恢复加锁。
if (skew != drc_skew_.load()) {
    std::lock_guard<std::mutex> drc_guard(mutex_);
    drc_skew_.store(skew);
    resampler_.UpdateRatio(skew);
```

P2 防御性处理完整，超出"加注释"期望。

---

### T3-F2 — ring_buffer WriteWait predicate（P2 降级）

**判定：PARTIAL**

CORE-REVIEW 降级 P2，期望防御性注释或验证 Clear() 同步。

当前 ring_buffer.cpp WriteWait 谓词在 `cv_not_full_.wait` 内正确重读 curr_tail（`tail_.v.load(acquire)`），不存在实际溢出路径：

```cpp
// ring_buffer.cpp:179-184
cv_not_full_.wait(lock, [&]() {
    if (!running.load(std::memory_order_relaxed)) return true;
    const size_t curr_head = head_.v.load(std::memory_order_relaxed);
    const size_t curr_tail = tail_.v.load(std::memory_order_acquire);
    return samples <= capacity_ - (curr_head - curr_tail);
});
```

Clear() 实现（line 357+）在 mutex_ 内归零 head/tail，与 WriteWait 慢路径互斥。代码无问题，但 commit 无专门的 "T3-F2" 注释标注此为已审计。P2 可接受，无安全风险。

---

### T3-F3 — unlock 前捕获 resample_out_buf_ 指针（P1）

**判定：VERIFIED**

```cpp
// audio_bridge.cpp:333-338
// Audit T3-F3: capture buffer pointer and sample count before releasing lock
const int16_t* const out_buf_data = resample_out_buf_.data();
const size_t samples_to_write = out_frames * 2;

// 在调用可能阻塞的 WriteWait 之前解锁
lock.unlock();
```

后续 WriteWait/Write 均使用局部变量 `out_buf_data`，消除了 lock.unlock() 后 resample_out_buf_ 被 Reset() 重分配的 dangling 指针窗口。完全满足期望。

---

### T3-F4 — SetFrameSizeInCallback 失败路径（P2）

**判定：VERIFIED**

```cpp
// audio_player.cpp:160-163
    LOGF(LOG_ERROR, ...);
    Cleanup(); // Audit T3-F4: SetFrameSizeInCallback failure is fatal; cleanup before returning
    return false;
}
LOGF(LOG_INFO, ...);  // 成功时才执行
```

失败时立即 Cleanup() + return false，不再落入 GenerateRenderer。与项目其他失败处理模式一致。

---

### T3-F5 — callback_cond_.wait → wait_for 2s 超时（P2）

**判定：VERIFIED**

```cpp
// audio_player.cpp:935-937
callback_cond_.wait_for(lock, std::chrono::seconds(2),
                         [this]() { return active_callbacks_ == 0; }); // Audit T3-F5: bounded wait, avoid indefinite hang
```

有界超时防止析构在 callback 卡死时永久阻塞。

---

### T3-F6 — ring_buffer.h mutable size_t 计数器 → atomic（P2）

**判定：VERIFIED**

```cpp
// ring_buffer.h:129-132（diff）
// 日志节流 — Audit T3-F6: atomic to avoid UB from concurrent producer/consumer access
mutable std::atomic<size_t> write_wait_block_logs_{0};
mutable std::atomic<size_t> write_wait_resume_logs_{0};
mutable std::atomic<size_t> read_wait_block_logs_{0};
mutable std::atomic<size_t> read_wait_resume_logs_{0};
```

4 个计数器全部 atomic，消除 producer/consumer 跨线程 UB。

---

### T3-F7 — max_out_frames +8 → +16（P2）

**判定：VERIFIED**

```cpp
// audio_bridge.cpp:297（diff）
-    size_t max_out_frames = static_cast<size_t>(std::ceil(frames * ratio)) + 8;
+    size_t max_out_frames = static_cast<size_t>(std::ceil(frames * ratio)) + 16; // Audit T3-F7: +16 margin (was +8)
```

精确匹配期望，有审计注释。

---

### T3-F9 — callback log 计数器 → std::atomic<int>（P2）

**判定：VERIFIED**

audio_player.h 内 9 个计数器全部改为 atomic：

```cpp
// audio_player.h:191-199（diff）
mutable std::atomic<int> callback_log_count_{0};        // Audit T3-F9
mutable std::atomic<int> callback_jitter_log_count_{0};
mutable std::atomic<int> callback_diag_log_count_{0};
mutable std::atomic<int> callback_underrun_log_count_{0};
mutable std::atomic<int> callback_cost_log_count_{0};
mutable std::atomic<int> callback_invalid_log_count_{0};
mutable std::atomic<int> legacy_log_count_{0};
mutable std::atomic<int> legacy_cb11_log_count_{0};
mutable std::atomic<int> legacy_diag_log_count_{0};
```

消除 OHAudio callback 线程与主线程之间的日志计数 UB。

---

### T3-F10 — Initialize() re-entry sample_rate 差异重初始化（P2）

**判定：VERIFIED**

```cpp
// audio_bridge.cpp:514-522
// Audit T3-F10: update core_sample_rate_ and reinit resampler if sample rate changed
const int32_t new_rate = (sample_rate > 0 ? sample_rate : 48000);
if (new_rate != core_sample_rate_) {
    LOGF(LOG_INFO, "%{public}s AudioBridge reuse: sample rate changed %{public}d->%{public}d, reinit resampler",
         kAudioChainPrefix, core_sample_rate_, new_rate);
    core_sample_rate_ = new_rate;
    resampler_.Init(core_sample_rate_, output_sample_rate_);
    drc_skew_.store(1.0);
}
```

完整实现：rate 变化检测、更新成员、重初始化 resampler、重置 drc_skew。修复了跨游戏切换时错误音调问题。

---

## 结论

T3 9 项中 8 项 **VERIFIED**，1 项（T3-F2）**PARTIAL**（代码逻辑正确，无专门审计标注，P2 可接受）。
无 NOT_APPLIED 项。
