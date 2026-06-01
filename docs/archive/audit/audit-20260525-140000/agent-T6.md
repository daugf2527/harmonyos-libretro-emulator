# 资源生命周期审计报告 — agent-T6

审计范围：
- `entry/src/main/cpp/platform/`
- `entry/src/main/cpp/core/engine/`（SaveState / SRAM）
- `entry/src/main/cpp/app/`（fd 使用）
- `entry/src/main/ets/common/SaveStateRepository.ets`（SaveState 持久化）

审计日期：2026-05-25

---

## F1: GraphicsContext::Initialize 在 CreateSurface 失败时未清理已创建的 EGL context/display

- severity: P1
- file: `entry/src/main/cpp/platform/graphics/graphics_context.cpp`
- line: 47-57
- evidence_excerpt: |
    ```
      // 2. Create Context (if not exists)
      if (egl_context_ == EGL_NO_CONTEXT) {
        if (!CreateContext(config)) {
          return false;
        }
      }

      // 3. Create Surface
      if (!CreateSurface(window)) {
        return false;
      }
    ```
- claim: 当 `CreateContext` 成功（egl_context_ 和 egl_display_ 均已分配），随后 `CreateSurface` 失败时，函数直接 `return false`，没有调用 `Destroy()` 清理已分配的 `egl_context_` 和 `egl_display_`。调用者（如 `VideoPipeline::InitializeHardwareRendererImpl`，见 video_pipeline.cpp line ~1589）在此路径收到失败后不一定会调用 `Destroy()`，导致 EGL context 和 display 泄漏。同样地，若 `CreateContext` 成功但 `eglInitialize`（line 36）之后、`CreateContext` 之前出现第二次重入，display 也可能双重分配。对比 `GLESRenderer::Init` 和 `VulkanContext::Initialize` 在每个失败路径都调 `Deinit()`/`Destroy()`。
- suggested_fix: 在 `CreateSurface` 失败的 `return false` 前调用 `Destroy()` 清理已创建的 context/display，或重构为 RAII 风格确保失败路径清理。同时检查 `InitializeHardwareRendererImpl` 中 `graphics_context_->Initialize` 失败后是否需要补一次 `DestroyHardwareRendererImpl`。

---

## F2: GLESRenderer::Deinit 在销毁 EGL 资源之前将 healthy_ 置为 true

- severity: P2
- file: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- line: 495-501（0-based line 494-500）
- evidence_excerpt: |
    ```
    void GLESRenderer::Deinit() {
      std::lock_guard<std::recursive_mutex> lock(mutex_);
      healthy_ = true;
      last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                            std::memory_order_release);
      last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                    std::memory_order_release);
    ```
- claim: `Deinit()` 在函数开头将 `healthy_` 设为 `true`、错误码重置为 `EGL_SUCCESS`，但 EGL context/surface/display 的实际销毁在函数后半段（约 line 555+ 之后）。如果有其他线程在 `Deinit` 持锁期间轮询 `healthy_`（例如通过原子访问），会在资源已开始销毁时读到"健康"状态，造成误判。另外 `healthy_ = true` 语义上意味"可用"，而 `Deinit` 的语义是"销毁"，二者矛盾——`Deinit` 完成后调用方用 `healthy_` 判断 renderer 是否可用时会得到错误结论。正确做法应在 Deinit 开始时将 `healthy_` 置 `false`，而不是 `true`。
- suggested_fix: 将 `Deinit` 开头的 `healthy_ = true` 改为 `healthy_ = false`，与"正在销毁"的语义一致。

---

## F3: SaveState 写入非原子——进程崩溃会产生损坏存档且清空 manifest

- severity: P1
- file: `entry/src/main/ets/common/SaveStateRepository.ets`
- line: 194-212（writeArrayBufferToFile）和 173-192（saveManifest）
- evidence_excerpt: |
    ```
    function writeArrayBufferToFile(path: string, data: ArrayBuffer): void {
      let file: fs.File | undefined = undefined
      try {
        file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        ...
        fs.writeSync(file.fd, data, writeOptions)
      ...
    async function saveManifest(...): Promise<void> {
      ...
      file = await fs.open(buildManifestPath(context.filesDir), fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      await fs.write(file.fd, JSON.stringify(document, null, 2))
    ```
- claim: 存档数据（`.state` 文件）和清单（`manifest.json`）均以 `TRUNC` 模式直接打开目标路径写入，不使用临时文件+rename 的原子写入模式。若进程在写入过程中崩溃（OOM、系统杀死、断电等）：(1) `.state` 文件被截断为已写入的部分字节，读取时会得到损坏的存档数据；(2) `manifest.json` 被截断为空或部分 JSON，导致 `loadManifest` 的 `JSON.parse` 抛异常，进而触发 `buildManifestFromDirectory` 重建——但重建后所有 `romFile` 字段丢失（硬编码为空字符串，见 line 158），导致存档无法与 ROM 关联。对比同项目 C++ 侧的 `file_configuration.cpp`（line 94-116）已实现 tmp+fsync+rename 的原子写模式，ArkTS 侧缺少同等保护。
- suggested_fix: 对 `writeArrayBufferToFile` 和 `saveManifest` 均改用临时文件写入模式：先写入 `path + ".tmp"` 临时文件，写完后调用 `fs.rename(tmpPath, path)` 原子替换。HarmonyOS `fileIo` 支持 `fs.rename()`，写法与 Node.js fs 类似。对于 `.state` 数据文件可额外在写入完成后调用 `fs.fsync(file.fd)` 确保落盘。

---

## F4: saveStateData 先写存档数据再读 manifest，两步之间不原子，可能产生孤儿存档文件

- severity: P2
- file: `entry/src/main/ets/common/SaveStateRepository.ets`
- line: 37-61
- evidence_excerpt: |
    ```
    export async function saveStateData(...): Promise<SaveStateManifestItem> {
      await ensureDirExists(buildSaveDirPath(context.filesDir))
      ...
      const targetPath = buildSaveFilePath(context.filesDir, fileName)
      writeArrayBufferToFile(targetPath, data)       // 第一步：写数据文件
      ...
      const document = await loadManifest(context)   // 第二步：读 manifest
      ...
      await saveManifest(context, { ... })           // 第三步：写 manifest
      return item
    ```
- claim: 若进程在第一步（写 `.state` 文件）成功后、第三步（更新 manifest）之前崩溃，`.state` 文件已存在于磁盘，但 manifest 中没有对应条目。重启后 `buildManifestFromDirectory` 能扫描到该文件但 `romFile` 字段为空字符串，用户看到一个无法识别来源 ROM 的孤儿存档。此问题在 F3 修复（临时文件+rename）后依然存在，需额外处理。
- suggested_fix: 将写顺序改为先更新 manifest（在 manifest 中预登记 item），再写数据文件。若数据文件写入失败则回滚 manifest；或者接受孤儿文件风险，在 `buildManifestFromDirectory` 重建时通过文件名时间戳注入合理 `romFile`（已知同一 ROM 启动时有上下文），这属于业务容错设计选择。

---

## DONE
