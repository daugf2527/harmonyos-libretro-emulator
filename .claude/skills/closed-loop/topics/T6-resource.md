# T6 — 资源生命周期

## Scope
XComponent / NativeWindow / EGL surface / file descriptors / SRAM/SaveState 文件句柄。

**Files**: 跨层(`cpp/platform/`, `cpp/app/`, ets 调用 NAPI 文件 I/O 的路径)

## Hazards
- surface recreation under config change — 设备旋转 / 后台切换时旧 NativeWindow 残留引用
- fd leaks — open / close 在异常路径下不配对
- atomic save guarantees — SRAM/SaveState 写入需 tmp + rename,否则崩溃留半截文件
- EGL surface lost — 设备休眠后 EGL surface 失效,renderer 必须重建
- 跨进程文件竞争 — 多实例 / debugger attach 时写同一 SRAM 文件

## Done criteria 模板(场景驱动)
- [ ] XComponent surface 重建路径下 NativeWindow / EGL surface / GLES context 全部释放并重建
- [ ] 所有 file descriptor 走 RAII(`std::unique_ptr<FILE, …>` 或 finally block)
- [ ] SaveState / SRAM 写入路径全部 tmp + rename 原子
- [ ] 设备旋转 / 后台切回 / 锁屏的渲染路径无 crash 无黑屏
