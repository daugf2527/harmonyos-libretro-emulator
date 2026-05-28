# T5 — NativeBuffer 用法

## Scope
Cross-cutting:任何调 `OH_NativeBuffer_*` / `OH_NativeWindow_*` 的代码。

**Files**: 任何 first-party C++(`entry/src/main/cpp/**`,vendored libretro 除外)

## Hazards
- acquire / release pairing — `OH_NativeWindow_RequestBuffer` 必须配对 `OH_NativeBuffer_FromNativeWindowBuffer`
- format mismatch — 申请的 format 与实际写入不符
- map / unmap pairing — `OH_NativeBuffer_Map` 必须配对 `OH_NativeBuffer_Unmap`,异常路径不能跳过
- use-after-free — Unmap 后还访问 mapped pointer / FlushBuffer 后还写 buffer
- 禁用 `mmap()` / `munmap()` — `AGENTS.md` 强制:NativeWindow 像素必须走 `OH_NativeBuffer_Map/Unmap`

## Done criteria 模板(场景驱动)
- [ ] 所有 RequestBuffer 路径都配对 FromNativeWindowBuffer(同文件内)
- [ ] 所有 Map 路径都配对 Unmap,包括 early return / exception / 错误路径
- [ ] 任意时间点 mapped pointer 数量与 unmapped count 守恒
- [ ] regression_guard 扫 mmap/munmap = 0(first-party C++)

## 必用 MCP
`mcp__ast-grep__find_code_by_rule` — 配对模式扫描:
```yaml
id: native-buffer-pair
language: cpp
rule:
  pattern: OH_NativeBuffer_Map($BUF, ...)
```
逐 callsite 检查同文件内有无 Unmap。
