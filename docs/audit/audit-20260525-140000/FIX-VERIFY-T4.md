# Fix-Verify T4 — commit 0bb99ce

**验证时间**: 2026-05-26  
**验证范围**: T4-F2 / T4-F3 / T4-F4 / T4-F5（T4-F1 FALSE_POSITIVE 跳过）  
**方法**: `git show 0bb99ce -- <file>` diff + HEAD 当前行读取

---

## 总结表

| ID | 文件 | 判定 | 说明 |
|---|---|---|---|
| T4-F2 | gles_renderer.cpp + 9 其他 TU | **PARTIAL** | 10 个 video/graphics TU 已分配唯一域（0xD006-0xD00F），但 gles_renderer.cpp 原属的 0xD003 族（19 个 TU）**仍全部共用 0xD003** |
| T4-F3 | gles_renderer.cpp:Deinit() | **VERIFIED** | `healthy_=true` → `false`，位于 Deinit() 开头锁内 |
| T4-F4 | window_state_manager.cpp:Apply() | **VERIFIED** | 5 个 opt 各自独立 if 块更新 last_state_ 对应字段 |
| T4-F5 | video_pipeline.h:pixel_format_ | **VERIFIED** | 加了 thread ownership 注释 |

---

## LOG_DOMAIN 完整分配表（现 HEAD，排 core/libretro vendored）

| 值 | TU（≥1 则列全） |
|---|---|
| 0xD000 | tests/unit/core_loader_test.cpp |
| 0xD001 | app/framework/plugin_manager.cpp, app/napi/core_loader_napi.cpp, app/napi/module_init.cpp, platform/resource/rom_loader.cpp |
| **0xD003** | **app/napi/engine_napi_common.h, common/fence_utils.cpp, common/file_security.cpp, core/engine/core_quirks_manager.cpp, core/engine/core_state_manager.cpp, core/engine/event_bridge.cpp, core/engine/input_manager.cpp, core/engine/libretro_engine.cpp, platform/audio/audio_bridge.cpp, platform/audio/audio_player.cpp, platform/audio/ring_buffer.cpp, platform/resource/platform_resource_manager.cpp, platform/resource/rawfile_rom_processor.cpp, platform/resource/temp_file_manager.cpp, platform/sync/native_vsync_driver.cpp, tests/integration/test_gambatte_load.cpp, tests/integration/test_gambatte_rom.cpp（共 17 TU）** |
| 0xD004 | common/diagnostics/logger_provider.cpp |
| 0xD005 | core/engine/input_port_router.cpp |
| 0xD006 | platform/graphics/graphics_context.cpp |
| 0xD007 | platform/graphics/gles_renderer.cpp |
| 0xD008 | core/engine/render_thread.cpp |
| 0xD009 | core/engine/video_pipeline.cpp |
| 0xD00A | platform/graphics/hw_render_presenter.cpp |
| 0xD00B | platform/graphics/vulkan_presenter.cpp |
| 0xD00C | platform/graphics/vulkan_context.cpp |
| 0xD00D | platform/graphics/vulkan_loader.cpp |
| 0xD00E | platform/graphics/pixel_converter_neon.cpp |
| 0xD00F | platform/graphics/pixel_converter_scalar.cpp |

**重复统计**: 0xD003 被 17 个 TU 共用（hilog 无法区分），0xD001 被 4 个 TU 共用。

---

## 逐项详情

### T4-F2 — LOG_DOMAIN 唯一分配 · PARTIAL

**期望**: gles_renderer.cpp 及 7 个 platform/graphics TU 分配唯一 LOG_DOMAIN，不再共用 0xD003。

**Commit diff 摘要**（`git show 0bb99ce`）：

```
-#define LOG_DOMAIN 0xD003   → +#define LOG_DOMAIN 0xD008  (render_thread.cpp)
-#define LOG_DOMAIN 0xD003   → +#define LOG_DOMAIN 0xD009  (video_pipeline.cpp)
-#define LOG_DOMAIN 0xD003   → +#define LOG_DOMAIN 0xD006  (graphics_context.cpp)
-#define LOG_DOMAIN 0xD003   → +#define LOG_DOMAIN 0xD00C  (vulkan_context.cpp)
```

（commit 称修改了 10 个 platform/graphics TU，0xD006-0xD00F 全部唯一——经 grep 确认这 10 个 TU 确实各有独立值）

**现状**:
- ✅ platform/graphics 全 8 个 TU：0xD006~0xD00F，唯一，无重复
- ✅ render_thread.cpp：0xD008，唯一
- ✅ video_pipeline.cpp：0xD009，唯一
- ❌ libretro_engine.cpp / audio_bridge.cpp / audio_player.cpp / 其余 core+platform TU：**仍用 0xD003**（17 个 TU 共用）

**判定 PARTIAL 原因**: T4-F2 原文只点名 "gles_renderer.cpp + 7 other platform/graphics TUs"——这 10 个文件已全部修好。但 FIX-PLAN.md 同行写的是 "Assign unique LOG_DOMAIN to **each file**"，CORE-REVIEW 原文也说 "gles_renderer.cpp shares 0xD003 with video_pipeline.cpp **and 7+ other files**"，隐含期望覆盖范围更大。0xD003 在整个 first-party 代码库仍被 17 TU 共用，hilog -D 0xD003 仍无法做有效子系统过滤。

**建议**: 如要完整修复，需给 audio/core/resource/sync 各子系统独立分配域，但超出本次 audit 范围，应作为新 finding 立项。

---

### T4-F3 — GLESRenderer::Deinit() healthy_=false · VERIFIED

**Diff**:

```cpp
 void GLESRenderer::Deinit() {
   std::lock_guard<std::recursive_mutex> lock(mutex_);
-  healthy_ = true;
+  healthy_ = false; // Audit T4-F3: renderer is unusable during and after Deinit
```

**HEAD 当前代码**（gles_renderer.cpp:495-502）:

```cpp
void GLESRenderer::Deinit() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  healthy_ = false; // Audit T4-F3: renderer is unusable during and after Deinit
  last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                        std::memory_order_release);
  last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                std::memory_order_release);
```

改动位置正确：持锁、Deinit() 开头、赋 false。✅

---

### T4-F4 — WindowStateManager::Apply() 独立更新 last_state_ · VERIFIED

**Diff**:

```cpp
-  if (result.geometry_ok && result.usage_ok && result.swap_ok &&
-      result.source_ok && result.scaling_ok) {
-    last_state_ = state;
+  // Audit T4-F4: update each field independently so partial successes are persisted
+  if (result.geometry_ok) {
+    last_state_.width = state.width;
+    last_state_.height = state.height;
     has_state_ = true;
   }
+  if (result.usage_ok) {
+    last_state_.usage = state.usage;
+  }
+  if (result.swap_ok) {
+    last_state_.swap_interval = state.swap_interval;
+  }
+  if (result.source_ok) {
+    last_state_.source_type = state.source_type;
+  }
+  if (result.scaling_ok) {
+    last_state_.scaling_mode = state.scaling_mode;
+  }
```

5 个 opt 字段各自独立 if 更新，不再 all-or-nothing。has_state_ 随 geometry_ok 一起设置（geometry 是最核心的尺寸状态，其他字段有独立默认值，此选择合理）。✅

---

### T4-F5 — video_pipeline.h pixel_format_ thread ownership 注释 · VERIFIED

**Diff**:

```cpp
+  // Audit T4-F5: Engine thread only — SetPixelFormat and Render() must both be called on Engine thread
   retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;
```

**HEAD 当前**（video_pipeline.h:381-382）:

```cpp
  // Audit T4-F5: Engine thread only — SetPixelFormat and Render() must both be called on Engine thread
  retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;
```

注释明确标注 Engine thread only，防御性要求满足。✅

---

## 遗留问题

- **T4-F2 PARTIAL 遗留**: 0xD003 仍被 17 个非 graphics TU 共用。建议新立 finding，分轮次给 audio / core / resource 子系统各分配唯一域。

---

## 2026-05-27 update — T4-F2-RESIDUAL CLOSED

按子系统分块给 17 个 TU 分配独占 `[0xD000, 0xFFFF]` domain，0xD003 释放给 `core/libretro/*` vendored 桥接专用。`quick_signals.sh` 全 PASS (regression / hygiene / ui-fixes / cxx-build 21 TU 重编 + link)。

### 新分配表（first-party 全部唯一，按值排序）

| 值 | 子系统 | TU |
|---|---|---|
| 0xD000 | tests/unit | core_loader_test.cpp |
| 0xD001 | NAPI loader / framework | plugin_manager / core_loader_napi / module_init / rom_loader（4 TU，沿用） |
| **0xD002** | **NAPI engine bridge (新)** | **engine_napi_common.h** (→ 7 engine_*_napi.cpp 跟着) |
| 0xD003 | vendored libretro 桥 | core/libretro/* (first-party 不再使用) |
| 0xD004 | diagnostics | logger_provider.cpp |
| 0xD005 | core/engine input | input_port_router.cpp |
| 0xD006-0xD00F | platform/graphics + render/video | graphics_context / gles_renderer / render_thread / video_pipeline / hw_render_presenter / vulkan_presenter / vulkan_context / vulkan_loader / pixel_converter_neon / pixel_converter_scalar |
| **0xD010-0xD014** | **core/engine 子系统 (新)** | libretro_engine / core_state_manager / core_quirks_manager / event_bridge / input_manager |
| **0xD020-0xD022** | **platform/audio 子系统 (新)** | audio_bridge / audio_player / ring_buffer |
| **0xD030-0xD032** | **platform/resource 子系统 (新)** | platform_resource_manager / rawfile_rom_processor / temp_file_manager |
| **0xD040** | **platform/sync (新)** | native_vsync_driver |
| **0xD050-0xD051** | **common util (新)** | fence_utils / file_security |
| **0xD060-0xD061** | **tests/integration (新)** | test_gambatte_load / test_gambatte_rom |

### 验收

- 17/17 TU `^#define LOG_DOMAIN 0xD003$` → 各自唯一新值（grep 结果一一对应）
- first-party 仍用 0xD003 的：**0 条**（仅 vendored 保留）
- 唯一性自检：仅 0xD001 napi 一族 4 TU 共用 —— 不在本次 scope，留作 follow-up（详见下方）
- quick_signals: regression / hygiene / ui-fixes / cxx-build (22/22 ninja step) 全 PASS

### 未做（follow-up，超出本 scope）

- **0xD001 4 TU 共用**: plugin_manager / core_loader_napi / module_init / rom_loader 共用 0xD001。这 4 个原本就共用（不是本轮新引入），且都是 NAPI 一族启动期/资源 loader 子系统，hilog 过滤角度可接受。若需进一步唯一化，可按 `0xD002` 段落模式拆开。
- **T1-F4 / T3-F2 防御性注释**: 上轮 fix-verify 已建议，与本 LOG_DOMAIN 任务无关。
