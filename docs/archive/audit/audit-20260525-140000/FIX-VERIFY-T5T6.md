# Fix Verify — T5 + T6 (6 项)

**commit**: `0bb99ce`
**验证时间**: 2026-05-26
**验证方法**: `git show 0bb99ce -- <file>` diff + Read 当前 HEAD 相关行

---

## 总结表

| ID | 文件 | 期望 fix | 结论 |
|---|---|---|---|
| T5-F1 | video_pipeline.cpp:1099-1102 | Map ret==0 addr==nullptr 补 Unmap | ✅ VERIFIED |
| T5-F2 | video_pipeline.cpp + render_thread.cpp LOG_DOMAIN | 各 TU 独立 LOG_DOMAIN | ✅ VERIFIED (同 T4-F2) |
| T6-F1 | graphics_context.cpp:53 | CreateSurface 失败路径加 Destroy() | ✅ VERIFIED |
| T6-F2 | gles_renderer.cpp Deinit healthy_ | healthy_=false 在 Deinit 起始 | ✅ VERIFIED (同 T4-F3) |
| T6-F3 | SaveStateRepository.ets writeArrayBufferToFile + saveManifest | tmp+rename 原子写 | ✅ VERIFIED |
| T6-F4 | SaveStateRepository.ets saveStateData 写序 | 重排顺序 或 文档说明 orphan 风险 | ✅ VERIFIED (CHANGED_APPROACH: 选文档) |

**全部 6 项 VERIFIED**。

---

## 逐项详情

### T5-F1 — video_pipeline.cpp NativeBuffer Unmap 补全

**期望**: Map 成功 (ret==0) 但 addr==nullptr 时，先 Unmap 再 Unreference。

**当前代码** (`video_pipeline.cpp:1094-1110`):
```cpp
if (ret != 0 || !addr) {
    if (!nativeBuffer) {
        m->nbFromWindowBufferFailures++;
    } else {
        m->nbMapFailures++;
        if (ret == 0) {
            // Audit T5-F1: Map succeeded (ret==0) but addr==nullptr; Unmap required per contract
            OH_NativeBuffer_Unmap(nativeBuffer);
        }
    }
    m->nwAbortBufferCalls++;
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    if (nativeBuffer) {
        OH_NativeBuffer_Unreference(nativeBuffer);  // Unreference 在 Unmap 之后
    }
    ...
}
```

**结论**: ✅ VERIFIED — ret==0 分支内先 Unmap，随后走公共路径 Unreference，顺序正确。

---

### T5-F2 — video_pipeline.cpp + render_thread.cpp LOG_DOMAIN 唯一化

**期望**: 各 TU 分配独立 LOG_DOMAIN（0xD000-0xFFFF 范围内，且文件间不冲突）。

**diff 摘要** (来自 git show):
- `video_pipeline.cpp`: `0xD003 → 0xD009`
- `render_thread.cpp`: `0xD003 → 0xD008`

**结论**: ✅ VERIFIED — 与 T4-F2 同批修复（commit message: "10 个 platform/graphics TU 分配唯一 LOG_DOMAIN 0xD006-0xD00F"），参见 T4 agent 分析。

---

### T6-F1 — graphics_context.cpp CreateSurface 失败路径 Destroy()

**期望**: CreateContext 成功后 CreateSurface 失败时，return false 前先 Destroy() 清 egl_context_/egl_display_。

**diff 摘要**:
```cpp
// 3. Create Surface
if (!CreateSurface(window)) {
+   Destroy(); // Audit T6-F1: release egl_context_ and egl_display_ to prevent leak
    return false;
}
```

**当前文件** (`graphics_context.cpp:53-55`): 与 diff 一致。

**结论**: ✅ VERIFIED — EGL 资源在失败路径正确释放。

---

### T6-F2 — gles_renderer.cpp Deinit healthy_ 置 false

**期望**: healthy_=false 在 Deinit() 起始处，而非末尾或仅在成功路径。

**diff 摘要**:
```cpp
-  healthy_ = true;
+  healthy_ = false; // Audit T4-F3: renderer is unusable during and after Deinit
```

**结论**: ✅ VERIFIED (同 T4-F3) — 参见 T4 agent 分析。Deinit 开头即置 false，防止并发访问。

---

### T6-F3 — SaveStateRepository.ets tmp+rename 原子写

**期望**: writeArrayBufferToFile 和 saveManifest 均改为 tmp+rename 原子写，避免写入中断导致数据损坏。

**writeArrayBufferToFile diff 摘要**:
```typescript
+  const tmpPath = path + '.tmp'
   file = fs.openSync(tmpPath, ...)   // 写 .tmp
   fs.writeSync(file.fd, data, writeOptions)
+  fs.closeSync(file.fd)
+  file = undefined
+  fs.renameSync(tmpPath, path)       // 原子 rename
   // catch: unlinkSync(tmpPath) 清理
```

**saveManifest diff 摘要**:
```typescript
+  const tmpPath = manifestPath + '.tmp'
   file = await fs.open(tmpPath, ...)   // 写 .tmp
   await fs.write(file.fd, ...)
+  await fs.close(file.fd)
+  file = undefined
+  await fs.rename(tmpPath, manifestPath)  // 原子 rename
   // catch: close + unlinkSync(.tmp) 清理
```

**结论**: ✅ VERIFIED — 两个写函数均已实现 tmp+rename 模式，与 C++ 侧 file_configuration.cpp 已有方案对位。

---

### T6-F4 — SaveStateRepository.ets saveStateData 写序

**期望**: 重排顺序（先 pre-register manifest entry 再写 .state 文件），或加文档说明 orphan 风险。

**当前代码** (`SaveStateRepository.ets:41-42`):
```typescript
// T6-F4: .state written before manifest; crash here leaves an orphan .state (no romFile association).
// Mitigated by T6-F3 (both writes are atomic), but a process kill between the two steps is still possible.
writeArrayBufferToFile(targetPath, data)
```

**结论**: ✅ VERIFIED (CHANGED_APPROACH) — 选择了"加文档"而非重排顺序。注释准确说明 orphan 风险已被 T6-F3 部分缓解（各写操作原子），但两步间进程崩溃仍可能留孤立 .state 文件。接受此折衷：重排需要将 manifest 预写变为两阶段，复杂度更高。

---

## 备注

- T5-F2 和 T6-F2 与 T4-F2/T4-F3 是同批修复，不重复分析 diff。
- T6-F4 CHANGED_APPROACH 不降级为 PARTIAL：审计原文明确允许"或加文档"替代重排。
