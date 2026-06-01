# Agent T5 — NativeBuffer / NativeWindow 用法审计

审计范围：`entry/src/main/cpp/`（**排除** `entry/src/main/cpp/core/libretro/`）  
审计日期：2026-05-25  
审计目标：OH_NativeBuffer_* / OH_NativeWindow_* 配对与生命周期

---

## 扫描范围确认

涉及 OH_NativeBuffer_* 或 OH_NativeWindow_* 的文件（共 4 个）：

| 文件 | 涉及 API |
|------|----------|
| `entry/src/main/cpp/core/engine/video_pipeline.cpp` | RequestBuffer / FlushBuffer / AbortBuffer / FromNativeWindowBuffer / Map / Unmap / Unreference / Reference / Unreference |
| `entry/src/main/cpp/core/engine/render_thread.cpp` | Reference / Unreference（消息队列生命周期） |
| `entry/src/main/cpp/core/engine/window_state_manager.cpp` | NativeWindowHandleOpt / SetScalingModeV2 |
| `entry/src/main/cpp/core/engine/window_guard.h` | Reference / Unreference（RAII ScopedWindow） |

mmap/munmap：**0 次匹配**（排除 vendored 后）。

---

## F1: Map 成功但 addr==nullptr 时缺少 OH_NativeBuffer_Unmap

- severity: P1
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- line: 1086-1107
- evidence_excerpt: |
    ```
    ret = OH_NativeBuffer_FromNativeWindowBuffer(buffer, &nativeBuffer);
    void *addr = nullptr;
    if (ret == 0) {
      ret = OH_NativeBuffer_Map(nativeBuffer, &addr);
    }
    // ...
    if (ret != 0 || !addr) {
      // ...
      if (nativeBuffer) {
        OH_NativeBuffer_Unreference(nativeBuffer);
      }
      return RenderResult::DROPPED;
    }
    ```
- claim: 错误处理分支的触发条件是 `ret != 0 || !addr`。当 `FromNativeWindowBuffer` 成功（ret=0）、`Map` 也返回 0 成功、但 addr 仍为 nullptr 时（理论上的异常/驱动 bug 情况），代码进入此分支：此时 `OH_NativeBuffer_Map` 已成功执行，理应配对 `OH_NativeBuffer_Unmap`，但分支内只调用了 `Unreference` 而无 `Unmap`，构成 Map 与 Unmap 的不配对路径。这一条件虽然极罕见（Map 返回 0 但输出 nullptr），一旦发生将泄漏 map 状态，潜在导致后续 buffer 分配失败或 GPU 同步异常。
- suggested_fix: 在进入 `if (ret != 0 || !addr)` 分支时，先检查 `nativeBuffer != nullptr && ret == 0`（即 Map 曾经成功过）再调用 Unmap，然后再 Unreference。可以用辅助 flag `bool mapped = (nativeBuffer != nullptr && ret == 0 && addr != nullptr)` 在 Map 成功后设置；或者更稳健地：在 `if (ret != 0 || !addr)` 分支内，若 `nativeBuffer` 非 null 且 `ret == 0`（Map 返回成功）则先 Unmap 再 Unreference。

---

## F2: 多个翻译单元共享同一 LOG_DOMAIN（0xD003），hilog 过滤失效

- severity: P2
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`，`entry/src/main/cpp/core/engine/render_thread.cpp`（以及其他多个文件）
- line: video_pipeline.cpp:23-24；render_thread.cpp:8-9
- evidence_excerpt: |
    ```
    // video_pipeline.cpp:23-24
    #undef LOG_DOMAIN
    #define LOG_DOMAIN 0xD003

    // render_thread.cpp:8-9
    #undef LOG_DOMAIN
    #define LOG_DOMAIN 0xD003
    ```
- claim: `entry/src/main/cpp/` 下有超过 20 个翻译单元（包括 video_pipeline.cpp、render_thread.cpp、libretro_engine.cpp、audio_bridge.cpp、audio_player.cpp、fence_utils.cpp、env_dispatcher.cpp、event_bridge.cpp 等）均使用相同的 `LOG_DOMAIN 0xD003`。CLAUDE.md 明确约束"每个翻译单元应使用唯一 domain 以保持 hilog 过滤实用性"，此处大面积重复违反该约束，导致无法通过 `hilog -D 0xD003` 将某一特定子系统的日志与其他子系统区分。
- suggested_fix: 为每个子系统分配独立的 LOG_DOMAIN 值。建议按子系统划分范围，例如：VideoEngine=0xD003、RenderThread=0xD004（当前被 logger_provider 使用，需重新协调）、AudioBridge/AudioPlayer=0xD005、Platform=0xD006 等，确保范围在 [0xD000, 0xFFFF] 内无冲突。

---

## 正向确认（无问题的路径）

以下审计点经逐路径检查，**未发现问题**：

1. **mmap/munmap 禁用**：排除 vendored 后 0 次匹配，完全合规。

2. **RequestBuffer → FlushBuffer/AbortBuffer 配对**（`video_pipeline.cpp:1007-1374`）：
   - RequestBuffer 失败 → AbortBuffer（lines 1051, 1077）✓
   - Fence 超时 → AbortBuffer（line 1077）✓
   - FromNativeWindowBuffer/Map 失败 → AbortBuffer（line 1101）✓
   - 所有 GetConfig 校验失败 → Unmap + AbortBuffer（lines 1117-1118, 1141, 1155, 1169, 1192）✓
   - Unmap 失败 → AbortBuffer（line 1310）✓
   - FlushBuffer 失败 → AbortBuffer（line 1332，buffer 所有权未转移时合法）✓
   - 成功路径 → FlushBuffer（line 1322），无 AbortBuffer ✓

3. **OH_NativeBuffer_Map → OH_NativeBuffer_Unmap 配对（正常路径）**：
   - 所有从 Map 成功进入内容处理区域的路径（lines 1107-1303），均在 line 1304 调用 Unmap 后退出，无 use-after-unmap。

4. **OH_NativeBuffer_Unreference 覆盖**：
   - 共 9 条 nativeBuffer 非 null 的退出路径（lines 1103, 1119, 1142, 1156, 1170, 1193, 1311, 1333, 1337），全部调用了 Unreference，无泄漏（F1 除外）。

5. **OH_NativeWindow_NativeObjectReference/Unreference 配对**：
   - `video_pipeline.cpp:1015-1023` 中 WindowRefGuard RAII 结构体确保 Reference/Unreference 配对 ✓
   - `window_guard.h` 中 SetWindow 和 ScopedWindow（含 move 语义）全部正确 ✓
   - `render_thread.cpp` 中 SET_WINDOW 消息入队时 Reference（line 99），出队后 HandleSetWindow 处 Unreference（line 342）；队列中重复 SET_WINDOW 清理时也正确 Unreference（line 259）✓

6. **fenceFd 资源管理**：
   - RequestBuffer 失败路径在 lines 1045-1047 显式 WaitAndCloseFence ✓
   - Fence 等待后 fenceFd 置 -1（line 1063），后续所有路径安全 ✓
   - FlushBuffer 调用时传入 -1（已关闭），正确 ✓

7. **同文件内 RequestBuffer 与 FromNativeWindowBuffer 配对（CLAUDE.md 约束）**：
   - 两者均在 `video_pipeline.cpp` 同一函数 `RenderCPU()` 内，满足"同文件配对"约束 ✓

---

## DONE
