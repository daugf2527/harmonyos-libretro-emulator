# API 22 三源差异审计 — 音频 + 资源 + 系统服务子系统

> ⚠️ **已废弃**：本文件为早期草稿，主题与他文件重叠且未填充。内容已并入并完成于
> `audio-subsystem.md`（音频 OHAudio 37 符号）+ `resource-system.md`（资源/文件IO/日志 13 符号）。
> 保留占位以免 git 困惑，**勿据本文件**。

> 目标 SDK = HarmonyOS 6.0.2(22) = API 22
> 本机 SDK header version = 6.0.2.130
> 审计日期 = 2026-06-05

## 三源
- **源 A 本地代码**: `entry/src/main/cpp/`(排除 `core/libretro/**`)
- **源 B 本机 SDK header**: `D:\Program Files\DevEco Studio\sdk\default\openharmony\native\sysroot\usr\include\`
- **源 C 官方 API22 文档**: developer.huawei.com(web-search MCP)

---

## 差异表

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|-------------|------|----------|----------|
| _(填充中)_ | | | | | |

---

## 状态计数

_(填充中)_

## 最高优先级差异

_(填充中)_
