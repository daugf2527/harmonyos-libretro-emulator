# M5: GLES 渲染器稳定性验证清单

**文档版本**: v1.0
**创建日期**: 2026-05-31
**适用范围**: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
**验证目标**: 确保 GLES 渲染路径在初始化、运行时、错误恢复场景下的稳定性

---

## 0. 清单使用说明

### 验证方法
- **代码审查**: 读取源码确认实现逻辑
- **hilog 验证**: 运行游戏并过滤 `hilog | grep "GLESRenderer\|GLES_DIAG\|EGL"`
- **真机测试**: 在 HarmonyOS 设备/模拟器上实际运行并观察行为

### PASS/FAIL 标准
- ✅ **PASS**: 代码实现正确 + hilog 无错误 + 真机行为符合预期
- ⚠️ **PARTIAL**: 代码实现正确但缺少日志/错误处理
- ❌ **FAIL**: 代码缺失/错误 或 真机出现崩溃/黑屏/花屏

---

## 1. 初始化检查（7 项）

### 1.1 EGL Display 初始化
**检查点**: `eglGetDisplay` + `eglInitialize` 成功，版本号合理

**验证方法**:
- 代码位置: `gles_renderer.cpp:599-613`
- hilog 关键字: `"EGL init: display="`
- 预期输出: `EGL init: display=0x... version=1.4` 或更高版本

**PASS 标准**:
- `egl_display_ != EGL_NO_DISPLAY`
- `major >= 1 && minor >= 4`
- hilog 无 `"Failed to"` 错误

---

### 1.2 EGL Config 选择
**检查点**: `eglChooseConfig` 返回至少 1 个符合要求的配置（GLES 3.0 + RGBA8888）

**验证方法**:
- 代码位置: `gles_renderer.cpp:616-638`
- hilog 关键字: `"EGL config: num="`
- 预期输出: `EGL config: num=1 RGBA=8/8/8/8 DS=...`

**PASS 标准**:
-`numConfigs >= 1`
- `R/G/B/A >= 8/8/8/8`（支持 XRGB8888 格式）
- hilog 无 `"Failed to choose EGL config"`

---

### 1.3 EGL Context 创建
**检查点**: `eglCreateContext` 成功创建 GLES 3.0 上下文

**验证方法**:
- 代码位置: `gles_renderer.cpp:663-673`
- hilog 关键字: `"Failed to create EGL context"` (反向验证)
- 预期行为: 无错误日志

**PASS 标准**:
- `egl_context_ != EGL_NO_CONTEXT`
- `eglBindAPI(EGL_OPENGL_ES_API)` 返回 true
- Context 属性包含 `EGL_CONTEXT_CLIENT_VERSION, 3`

---

### 1.4 EGL Surface 创建
**检查点**: `eglCreateWindowSurface` 成功绑定 NativeWindow

**验证方法**:
- 代码位置: `gles_renderer.cpp:676-686`
- hilog 关键字: `"EGL surface created: window="`
- 预期输出: `EGL surface created: window=0x... surface=0x... context=0x...`

**PASS 标准**:
- `egl_surface_ != EGL_NO_SURFACE`
- `eglMakeCurrent` 返回 true
- hilog 显示有效的 window/surface/context 指针

---

### 1.5 OpenGL ES 版本检查
**检查点**: `glGetString(GL_VERSION)` 返回 GLES 3.0 或更高

**验证方法**:
- 代码位置: `gles_renderer.cpp:292-306`
- hilog 关键字: `"GLES info:"` / `"GLES vendor:"` / `"GLES GLSL:"`
- 预期输出: `GLES info: OpenGL ES 3.0 | Mali-G78` (示例)

**PASS 标准**:
- GL_VERSION 包含 `"OpenGL ES 3."` 或更高
- GL_SHADING_LANGUAGE_VERSION 包含 `"3.00"` 或更高
- hilog 显示 vendor/renderer 信息（非 NULL）

---

### 1.6 着色器编译与链接
**检查点**: 顶点/片段着色器编译成功，程序链接成功

**验证方法**:
- 代码位置: `gles_renderer.cpp:729-800`
- hilog 关键字: `"Shader compile error"` / `"Program link error"` (反向验证)
- 预期行为: 无错误日志

**PASS 标准**:
- `GL_COMPILE_STATUS == GL_TRUE` (vs + fs)
- `GL_LINK_STATUS == GL_TRUE`
- `sampler_loc_ >= 0` 且 `uniform_swizzle_loc_ >= 0`（uniform 位置有效）

---

### 1.7 纹理与缓冲区创建
**检查点**: VAO/VBO/Texture 对象创建成功，纹理参数设置正确

**验证方法**:
- 代码位置: `gles_renderer.cpp:802-842`
- 验证方式: 代码审查（无专用日志）
- 关键参数: `GL_TEXTURE_MIN_FILTER = GL_NEAREST`（锐利像素）

**PASS 标准**:
- `vao_ != 0` 且 `vbo_ != 0` 且 `texture_ != 0`
- 纹理过滤使用 `GL_NEAREST`（避免模糊）
- 纹理环绕使用 `GL_CLAMP_TO_EDGE`（避免边缘伪影）

---

## 2. 渲染检查（6 项）

### 2.1 纹理上传（格式支持）
**检查点**: 支持 XRGB8888/RGB565/0RGB1555 三种像素格式

**验证方法**:
- 代码位置: `gles_renderer.cpp:917-940`
- hilog 关键字: `"GLES direct render: size="`（前 3 帧）
- 预期输出: `GLES direct render: size=... row=... fmt=0/1/2 align=2/4`

**PASS 标准**:
- XRGB8888: `internalFormat=GL_RGBA8, pixelFormat=GL_RGBA, swizzleRB=true`
- RGB565: `internalFormat=GL_RGB565, pixelFormat=GL_RGB, pixelType=GL_UNSIGNED_SHORT_5_6_5`
- 0RGB1555: `internalFormat=GL_RGB5_A1, pixelFormat=GL_RGBA, pixelType=GL_UNSIGNED_SHORT_5_5_5_1`
- 格式切换时触发 `glTexImage2D`（非 `glTexSubImage2D`）

---

### 2.2 纹理上传（Pitch 处理）
**检查点**: 正确处理非对齐 pitch（`GL_UNPACK_ROW_LENGTH` + `GL_UNPACK_ALIGNMENT`）

**验证方法**:
- 代码位置: `gles_renderer.cpp:1059-1090`
- hilog 关键字: `"[GLES_DIAG] upload unpack: align="`（需开启诊断模式）
- 预期行为: `rowLength = pitch / bpp`，`alignment = 1/2/4`（根据 pitch 对齐）

**PASS 标准**:
- `GL_UNPACK_ROW_LENGTH` 设置为 `pitch / bpp`
- `GL_UNPACK_ALIGNMENT` 根据 pitch 对齐（4 优先，其次 2，最后 1）
- **关键修复（T4-F6）**: 渲染前查询并保存 `prevUnpackAlignment/prevUnpackRowLength`，渲染后恢复（避免污染 HW core 状态）

---

### 2.3 视口与宽高比
**检查点**: 根据内容宽高比正确计算 letterbox/pillarbox

**验证方法**:
- 代码位置: `gles_renderer.cpp:878-904`
- 验证方式: 代码审查 + 真机观察（画面不应拉伸变形）
- 关键逻辑: `scaleX/scaleY` 根据 `srcAspect` vs `dstAspect` 计算

**PASS 标准**:
- `dstAspect > srcAspect` → `scaleX = srcAspect / dstAspect`（左右黑边）
- `dstAspect < srcAspect` → `scaleY = dstAspect / srcAspect`（上下黑边）
- 真机画面无拉伸变形（圆形物体保持圆形）

---

### 2.4 着色器 Swizzle（RB 通道交换）
**检查点**: XRGB8888 格式时正确交换 R/B 通道（shader swizzle）

**验证方法**:
- 代码位置: `gles_renderer.cpp:936-945`
- hilog 关键字: 无专用日志（代码审查）
- 真机验证: XRGB8888 游戏画面颜色正确（红色不应显示为蓝色）

**PASS 标准**:
- `format == RETRO_PIXEL_FORMAT_XRGB8888` → `swizzleRB = true`
- `glUniform1i(uniform_swizzle_loc_, 1)` 被调用
- 片段着色器输出 `vec4(texColor.b, texColor.g, texColor.r, 1.0)`

---

### 2.5 eglSwapBuffers 成功率
**检查点**: `eglSwapBuffers` 正常返回，无频繁失败

**验证方法**:
- 代码位置: `gles_renderer.cpp:1159-1210`
- hilog 关键字: `"[GLES_DIAG] eglSwapBuffers ok:"` / `"eglSwapBuffers failed:"`
- 预期行为: 正常游戏时 99%+ 帧 swap 成功

**PASS 标准**:
- `eglSwapBuffers` 返回 `EGL_TRUE`
- `last_egl_error_ == EGL_SUCCESS`
- `last_swap_failure_kind_ == SwapFailureKind::NONE`
- hilog 无连续 `"eglSwapBuffers failed"` 错误（偶发 1-2 次可接受）

---

### 2.6 帧率稳定性
**检查点**: 60fps 游戏稳定输出 60fps（VSync 生效）

**验证方法**:
- 代码位置: `gles_renderer.cpp:706-708` (`eglSwapInterval`)
- hilog 关键字: `"Swap interval initialized:"` / `"VSync set to:"`
- 真机验证: ArkTS 侧 `fps_update` 事件显示稳定 60fps

**PASS 标准**:
- `swap_interval_ == 1`（默认开启 VSync）
- `eglSwapInterval(egl_display_, 1)` 被调用
- 真机 FPS 稳定在 59-61 范围（允许 ±1 波动）

---

## 3. 错误恢复检查（5 项）

### 3.1 GL 错误检测
**检查点**: 关键操作后检查 `glGetError()`，记录异常

**验证方法**:
- 代码位置: `gles_renderer.cpp:949-969` (`LogGlError` lambda)
- hilog 关键字: `"GL error after"` / `"[GLES_DIAG] GL ok after"`
- 触发条件: 开启诊断模式（`SetDiagnosticsEnabled(true)`）

**PASS 标准**:
- `pixel_store` / `tex_upload` / `draw` 阶段都有 `LogGlError` 调用
- 正常运行时 hilog 显示 `"GL ok after ..."`（前 3 帧 + 每 600 帧采样）
- 出现 GL 错误时日志包含错误码（如 `0x0502 = GL_INVALID_OPERATION`）

---

### 3.2 EGL Surface 丢失恢复
**检查点**: `eglSwapBuffers` 返回 `EGL_BAD_SURFACE` 时触发 surface 重建

**验证方法**:
- 代码位置: `gles_renderer.cpp:1172-1182`
- hilog 关键字: `"eglSwapBuffers recoverable failure"` / `"mark surface lost"`
- 触发场景: 应用切后台再切回前台（Surface 生命周期变化）

**PASS 标准**:
- `IsRecoverableSwapError(err)` 返回 true（`EGL_BAD_SURFACE` / `EGL_BAD_NATIVE_WINDOW` / `EGL_BAD_MATCH`）
- `healthy_ = false` 被设置（标记需要恢复）
- `last_swap_failure_kind_ == SwapFailureKind::RECOVERABLE_SURFACE`
- 后续帧调用 `RecreateSurface()` 成功恢复（hilog 显示 `"EGL surface recreated"`）

---

### 3.3 EGL Context Lost 检测
**检查点**: `eglSwapBuffers` 返回 `EGL_CONTEXT_LOST` 时标记致命错误

**验证方法**:
- 代码位置: `gles_renderer.cpp:1164-1171`
- hilog 关键字: `"EGL Context Lost: 0x"`
- 触发场景: GPU 驱动崩溃 / 设备休眠唤醒（罕见）

**PASS 标准**:
- `err == EGL_CONTEXT_LOST` → `healthy_ = false`
- `last_swap_failure_kind_ == SwapFailureKind::CONTEXT_LOST`
- 日志包含错误码与错误名（如 `0x300E (EGL_CONTEXT_LOST)`）
- 引擎层检测到 `healthy_ == false` 后停止渲染或重新初始化

---

### 3.4 资源泄漏防护（Deinit）
**检查点**: `Deinit()` 正确释放所有 GL/EGL 资源

**验证方法**:
- 代码位置: `gles_renderer.cpp:495-596`
- hilog 关键字: `"EGL context not current during Deinit"` (异常路径)
- 验证方式: 代码审查 + 多次启动/停止游戏无内存泄漏

**PASS 标准**:
- Context 有效时: `glDeleteSync/glDeleteBuffers/glDeleteTextures/glDeleteProgram` 被调用
- Context 无效时: 调用 `release()` 丢弃句柄（避免 UB），依赖 `eglTerminate` 回收
- `upload_scratch_ring_` 调用 `shrink_to_fit()`（释放内存）
- `eglDestroySurface` / `eglDestroyContext` / `eglTerminate` 按顺序执行

---

### 3.5 线程安全（recursive_mutex）
**检查点**: 所有公开接口使用 `std::lock_guard<std::recursive_mutex>` 保护

**验证方法**:
- 代码位置: 所有 public 方法（`Init/Deinit/Render/Resize/SetSwapInterval` 等）
- 验证方式: 代码审查（每个方法首行是否有 `std::lock_guard<std::recursive_mutex> lock(mutex_);`）
- 关键场景: `Deinit()` 内部调用 `DestroySurfaceOnly()`（递归锁允许重入）

**PASS 标准**:
- 所有 public 方法都有 `lock(mutex_)`
- `Deinit()` 可以安全调用 `DestroySurfaceOnly()`（递归锁不死锁）
- 多线程场景（Engine 线程 + XComponent 回调线程）无数据竞争

---

## 4. 可选特性检查（2 项）

### 4.1 XEngine AI 超分支持
**检查点**: 华为设备上检测并启用 XEngine Spatial Upscale

**验证方法**:
- 代码位置: `gles_renderer.cpp:413-463`
- hilog 关键字: `"XEngine Spatial Upscale Supported"` / `"NOT Supported"`
- 触发条件: 华为旗舰设备（Mate/P 系列）

**PASS 标准**:
- `dlopen("libxengine.so")` 成功 → `xengine_supported_ = true`
- `HMS_XEG_GetString(XEG_EXTENSIONS)` 包含 `"XEG_spatial_upscale"`
- 启用后 hilog 显示 `"XEngine AI Upscale: ON"`
- 渲染时调用 `hms_xeg_renderSpatialUpscale_(texture_)` 替代 `glDrawArrays`

---

### 4.2 诊断模式日志
**检查点**: `SetDiagnosticsEnabled(true)` 后输出详细诊断日志

**验证方法**:
- 代码位置: `gles_renderer.cpp:489-493` + 各处 `if (diagEnabled)` 分支
- hilog 关键字: `"[GLES_DIAG]"`
- 触发条件: ArkTS 调用 `refactoredSetGlesDiagnostics(true)`

**PASS 标准**:
- 前 3 帧输出完整日志（frame begin/end, params, context, unpack, tex upload, swap）
- 第 4 帧起每 600 帧采样一次（避免日志洪水）
- 日志包含关键参数: `data/size/pitch/row/bpp/fmt/dupe/viewport/window/tid`
- 日志包含 EGL 上下文状态: `cur_display/cur_context/cur_draw/cur_read`

---

## 5. 回归防护（已修复问题）

以下问题已在历史审计中修复，验证时确认不再出现：

### 5.1 T4-F6: GL_UNPACK_* 状态污染
**问题**: 未保存/恢复 `GL_UNPACK_ALIGNMENT` / `GL_UNPACK_ROW_LENGTH`，污染 HW core 状态

**修复**: `gles_renderer.cpp:1072-1073` 渲染前查询并保存，`1142-1143` 渲染后恢复

**验证**: HW render core（如 Beetle PSX HW）运行正常，无花屏/错位

---

### 5.2 内存泄漏: upload_scratch_ring_
**问题**: `Deinit()` 后 `upload_scratch_ring_` 未释放内存

**修复**: `gles_renderer.cpp:585-588` 调用 `shrink_to_fit()`

**验证**: 多次启动/停止游戏，内存占用稳定（无持续增长）

---

## 6. 验证流程建议

### 6.1 基础验证（必做）
1. **冷启动**: 启动游戏，检查 hilog 初始化日志（1.1-1.7）
2. **运行 5 分钟**: 观察 FPS 稳定性（2.6）+ swap 成功率（2.5）
3. **切后台/前台**: 验证 Surface 恢复（3.2）
4. **停止游戏**: 检查 Deinit 日志（3.4）

### 6.2 格式兼容性验证
测试不同像素格式的核心：
- **XRGB8888**: Snes9x, Genesis Plus GX
- **RGB565**: Gambatte (GB/GBC)
- **0RGB1555**: Beetle PSX (software mode)

### 6.3 压力测试
- **快速切换游戏**: 连续 10 次 SwitchGameAsync，检查无内存泄漏
- **长时间运行**: 运行 1 小时，检查无 swap 失败累积
- **诊断模式**: 开启诊断模式运行 10 分钟，检查无异常 GL 错误

---

## 7. 已知限制

1. **PBO 上传路径已禁用**: 当前使用直接纹理上传（`glTexSubImage2D` from client memory），PBO 路径因驱动兼容性问题暂时禁用（`gles_renderer.cpp:1044`）
2. **XEngine 仅华为设备**: 非华为设备 `dlopen("libxengine.so")` 失败，自动回退到标准 GLES 路径
3. **VSync 强制开启**: `swap_interval_` 被 `ClampSwapInterval` 限制为 0/1（不支持 adaptive sync）

---

## 8. 参考文档

- **架构白皮书**: `docs/plans/2026-02-06-new-arch-technical-whitepaper.md` (VideoPipeline 章节)
- **M4 视频审计**: `docs/audit/m4-t46-video-callback-audit.md` (像素格式/几何处理)
- **源码**: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp` (1221 行)
- **回归守卫**: `scripts/ci/check_regression_guards.sh` (自动检查 mmap/LOG_DOMAIN 等)

---

**清单状态**: ✅ 初稿完成
**下一步**: 在真机/模拟器上执行验证，记录 PASS/FAIL 结果
