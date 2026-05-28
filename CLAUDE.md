# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Layered context

- **This file (root)**: cross-layer architecture, build/release commands, environment notes.
- **`entry/src/main/ets/CLAUDE.md`**: ArkTS/ArkUI patterns and anti-patterns.
- **`entry/src/main/cpp/CLAUDE.md`**: C++ engine threading, NativeBuffer, LOG_DOMAIN constraints.

v2.1+ auto-inlines the sub-directory CLAUDE.md files via the @imports below;
older clients pull them in on demand when Claude works under those paths.

`AGENTS.md` 是 Codex Bot 风格的项目级规范（强制规则 + ArkTS 编程规范 + ArkUI/ArkTS UI 开发指南），
内容通用，本 CLAUDE.md 也 `@import` 引入避免分裂双轨。

@AGENTS.md
@entry/src/main/ets/CLAUDE.md
@entry/src/main/cpp/CLAUDE.md

## Common Development Commands

- **Open & build/run**: DevEco Studio → select `entry` module → Build / Run.
- **Test pages**: `pages/LibretroGamePage` or `pages/LibretroNewArchTestPage`. Monitor via `hilog`.
- **Build HAP**: `hvigorw assembleHap` (also used in PR CI).
- **AI quick feedback** (regression + hygiene + incremental C++ build, ~10s; designed for use after edits to get a quick PASS/FAIL signal without a full hvigor sync):
  ```bash
  bash scripts/check/quick_signals.sh
  ```
  Requires DevEco Sync to have run at least once (for `entry/.cxx/.../build.ninja`). cmake auto-discovered from DevEco SDK; falls back to SKIP if not found. To verify failure detection: briefly add `mmap(` to any `entry/src/main/cpp/**/*.cpp` (non-vendored), rerun, then revert.
- **CI hygiene checks** (also wired as Stop hook in `.claude/settings.json`):
  ```bash
  bash scripts/ci/check_repo_hygiene.sh
  bash scripts/ci/check_regression_guards.sh
  ```
- **PR validation**: `.github/workflows/harmonyos-pr-ci.yml` (HarmonyOS CLI tools, `codelinter`, HAP smoke).
- **Release**: push `v*` tag → `.github/workflows/harmonyos-release.yml` builds + signs + publishes GitHub Release.

## High-Level Architecture (new_arch)

- **ArkTS/ArkUI layer** (`entry/src/main/ets/`): UI, page state, interaction (`pages/`, `components/`, `common/`, `config/`).
- **C++ native layer** (`entry/src/main/cpp/`): `libentry.so` provides the engine.
  - `app/`: NAPI exports + XComponent bridging (`refactored*` interfaces).
  - `core/`: `LibretroEngine` (state machine, message queue, `retro_run`), `VideoPipeline`, core loader.
  - `platform/`: `AudioBridge`, graphics, resources, sync, XComponent.
- **Bridges & threads**:
  - XComponent + NativeWindow → video surface.
  - NAPI → ArkTS ↔ C++ engine.
  - Engine thread → GameLoop + `VideoPipeline` (Hardware/Software/GLES/Vulkan, dynamic pixel/geometry negotiation).
  - Audio thread → `AudioBridge` (resampling, DRC, RingBuffer, underrun stats).
  - EventBridge → input (keys, joysticks, sensors), SaveState/SRAM/Core Options/Cheat/DiskControl.

**Primary documentation** (read before structural changes):
- `docs/plans/2026-02-06-new-arch-technical-whitepaper.md` — LibretroEngine, AudioBridge, VideoPipeline deep dives.

**Key source files**:
- `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`

## Global Constraints

- Prioritize official HarmonyOS docs + `libretro.h`.
- Deprecated code lives only in `deprecated/legacy/` (excluded from mainline, also in `.claudeignore`).
- All changes must pass regression guards (`scripts/ci/check_regression_guards.sh`).

## MCP / Skill 工具决策树

**按语言 + 用途分工**（消除 "cclsp 优先 / serena 备选" 二选一歧义）：

| 工具 | 覆盖语言 | 主要用途 |
|---|---|---|
| **cclsp** | **C/C++ 只**（本地 `.claude/cclsp.json` 配的 clangd） | find_definition / find_references / get_incoming_calls / get_outgoing_calls / find_workspace_symbols / get_hover / get_diagnostics_for_file / prepare_call_hierarchy |
| **serena** | 全仓库（C++/ets/md）+ project memory | get_symbols_overview / find_symbol / find_referencing_symbols / list_memories / write_memory / 跨语言文件级符号操作 |
| **ast-grep** | 任意语言（AST pattern） | find_code / find_code_by_rule — **配对检查**（acquire/release、map/unmap）、threading violation 跨文件扫 |
| **firecrawl** | Web | scrape / search — HarmonyOS 官方文档抓取；本机 SDK header 优先（`feedback_websearch_fail_fallback_to_sdk_header`） |
| **sequential-thinking** | — | 罕见 finding 拿不准时多角度推理（不滥用） |

### 何时**必须**用 MCP（按代码位置 / 操作类型）

| 改动位置 / 操作 | 必用工具 | 为什么 |
|---|---|---|
| `entry/src/main/cpp/app/napi/**` 改动 | `cclsp__find_references` + `cclsp__get_incoming_calls` | 纯 Grep 会漏 ArkTS 侧 EventBridge / TSFN 引用 |
| `core/engine/libretro_engine.cpp` 状态机 | `cclsp__find_workspace_symbols` | 跨文件 enum / struct 引用 |
| NativeBuffer / Resource lifecycle 配对 | `ast-grep__find_code` | `OH_NativeBuffer_*` / `OH_NativeWindow_*` callsite 配对扫描 |
| C++ 类型 / 接口改动 | `cclsp__find_references` + `cclsp__get_diagnostics_for_file` | 下游 type warning |
| ets 文件符号总览 / 找符号 | `serena__get_symbols_overview` + `serena__find_symbol` | cclsp 不覆盖 ets;ets LSP 走 serena |
| 多文件 audit / cross-cutting review | `serena__find_referencing_symbols` | 跨文件批量查引用 |

### 何时**可以**退回 Read/Grep

- **citation 验证**（"这 5 行字节真的在那位置吗"——pure text 对比，LSP 杀鸡用牛刀）—— 见 `.claude/skills/closed-loop/SKILL.md` Step 2/7
- 单文件一次性 lookup
- 文档 / 注释类（非代码）
- LSP 索引未跑 / MCP 暂时不可用（fallback）

### 工具协同准则

- **先 LSP 看影响面 → 再 Read 那几个 callsite 确认行为** — 别上来直接 Read 全文件
- **配对检查类问题**（acquire/release / ref create/delete / map/unmap）— 用 `ast-grep find_code_by_rule` 扫配对模式比逐文件 Read 快 10×
- **跨线程 / threading violation 检测** — `ast-grep` 跨文件扫 pattern（譬如 `GameLoop` 里直接 `napi_call_function`）

### 工具瘦身记录（外网 ETH arXiv:2602.11988 实证 14-22% token 浪费）

| 检查项 | 现状 | 决策 |
|---|---|---|
| cclsp ↔ serena 重叠 | 描述层重叠（"优先/备选"），实际**按语言分工**不重叠（cclsp=C++ only, serena=全仓库 + memory） | 保留双方，决策树改成按语言分工（本次提交） |
| firecrawl 24 工具 | 30 天调用主要是 search / scrape；rest 18 个工具 token 占位 | **TODO**：等用户决策是否项目级关闭 / 删除（影响其他个人项目） |
| sequential-thinking 1 工具 | 偶用于 audit 罕见 finding 推理 | 保留 |
| ast-grep 4 工具 | 配对检查不可替代 | 保留 |

## Environment (Windows + Git Bash)

**PATH bug**: Claude Code injects `$PATH` literally, truncating Windows system PATH. Tools and MCP servers spawn through `cmd /c`, so PATH must be **Windows style** (`;` separator, backslashes) — Git Bash style (`/d/nodejs:/c/...`) makes `cmd` treat the whole string as one invalid path. Use `${PATH}` (not `$PATH`) to chain the inherited PATH:
```json
{ "env": { "PATH": "D:\\nodejs;C:\\Windows\\System32\\WindowsPowerShell\\v1.0;${PATH}" } }
```
Restart session and verify with `node --version` plus `/mcp` (all servers should be `✓ connected`).

**Local tool paths**:
- git in PATH (v2.54.0)
- python3 `/c/Users/newwo/bin/python3` (v3.8.1)
- node/npm `D:\nodejs` (v22.22.0 / v10.8.2)
- PowerShell `C:\Windows\System32\WindowsPowerShell\v1.0`
- DevEco Studio `D:\Program Files\DevEco Studio\bin`
- HarmonyOS CLI `D:\hongmeng\command-line-tools\bin`

**statusline**: `~/.claude/statusline.sh` uses pure bash JSON parsing (grep + sed) to avoid node/jq dependency.

**Windows 注意事项速查**（onboard 新机器 / Claude Code 升级 / 加新 MCP 时必撞，全版见 memory `feedback_windows_pitfalls`）：

| # | 坑 | 一句话应对 |
|---|---|---|
| W1 | `cmd /c` 包装 stdio MCP（npx → npx.cmd batch script） | MCP JSON `"command":"cmd","args":["/c","npx","-y","<pkg>"]` |
| W2 | Git Bash 不在 PATH 时 Claude Code 起不来 | 环境变量 `CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe` |
| W3 | PowerShell `claude` not recognized | `SetEnvironmentVariable("PATH","$env:USERPROFILE\.local\bin;...","User")` 后重启 PS |
| W4 | `%USERPROFILE%` vs `~` | PowerShell + Git Bash 用 `~`；CMD 用 `%USERPROFILE%` |
| W5 | PowerShell 中文 / emoji 乱码 | `chcp 65001; [Console]::OutputEncoding=[Text.Encoding]::UTF8` |
| W6 | Plan mode Shift+Tab 某些终端 skip plan mode | 改按 **Alt+M** 进入 plan mode |
| W7 | MCP server OAuth 后启动超时 | 启动前 `$env:MCP_TIMEOUT=10000` |
| W9 | 不知 Claude Code 健康状态 | 会话内 `/doctor`；命令行 `claude doctor` |

## Web research tips (developer.huawei.com)

1. First try: `WebSearch` English query + `site:developer.huawei.com`.
2. If empty: `firecrawl_search` (check credits) — `sources` param must be `[{type: "web"}]` array.
3. For JS-rendered pages: `firecrawl_scrape` with `waitFor: 5000`.
4. Local PDFs/DOCX: `firecrawl_parse`.
