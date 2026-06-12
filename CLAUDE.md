# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@C:/Users/newwo/.cc-switch/agent-policy/COMMON.md

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
- **ArkTS 性能/规范按需检查** (codelinter; ~34s 全 ets / ~20s 每文件; **非编译验证**):
  ```bash
  bash scripts/ci/check_arkts_codelinter.sh            # 全 ets 目录
  bash scripts/ci/check_arkts_codelinter.sh <f.ets>…   # 指定文件(增量)
  ```
  补 quick_signals 对 .ets 的性能/AST 规范盲区(cxx-build 只覆盖 C++)。**能力边界**: codelinter 默认仅 `@performance` 规则集，**不抓** ArkTS 语法/类型 error(no-any / V1V2 误用)；correctness 需项目根 `code-linter.json5` 加 `@typescript-eslint` 且本地 CLI 激活不了 → **编译/类型盲区仍只能靠 hvigor/DevEco 复编**。Git Bash 调 codelinter 须 `cmd //c`(双斜杠)。详见 tech-debt-tracker D030 + memory `feedback_codelinter_capability_boundary`。
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
| **codegraph** | **C/C++ 为主**（`.codegraph/` 索引 + daemon watcher 自动同步） | codegraph_explore / codegraph_search / codegraph_callers / codegraph_impact — 跨文件调用图 / 影响面。**不索引 `.ets`**（0.9.9 `EXTENSION_MAP` 无此扩展）→ ArkTS 符号 / UI 组件查询一律走 serena；**codegraph 空结果 ≠ 无此符号** |
| **ast-grep** | 任意语言（AST pattern） | find_code / find_code_by_rule — **配对检查**（acquire/release、map/unmap）、threading violation 跨文件扫 |
| **web-search** | Web | `mcp__web-search__web_fetch`（单 URL）/ `mcp__web-search__web_search`（关键词）— HarmonyOS 官方文档抓取；本机 SDK header 优先（`feedback_websearch_fail_fallback_to_sdk_header`）。**firecrawl 已弃用**（见 memory `feedback_firecrawl_deprecated`） |
| **sequential-thinking** | — | 罕见 finding 拿不准时多角度推理（不滥用） |

### 何时**必须**用 MCP（按代码位置 / 操作类型）

| 改动位置 / 操作 | 必用工具 | 为什么 |
|---|---|---|
| `entry/src/main/cpp/app/napi/**` 改动 | `cclsp__find_references` + `cclsp__get_incoming_calls` | 纯 Grep 会漏 ArkTS 侧 EventBridge / TSFN 引用 |
| `core/engine/libretro_engine.cpp` 状态机 | `cclsp__find_workspace_symbols` | 跨文件 enum / struct 引用 |
| NativeBuffer / Resource lifecycle 配对 | `ast-grep__find_code` | `OH_NativeBuffer_*` / `OH_NativeWindow_*` callsite 配对扫描 |
| C++ 类型 / 接口改动 | `cclsp__find_references` + cxx-build 复编 | 下游 type warning（注：cclsp **无** diagnostics 工具；C++ 诊断靠编译，见下方实证边界） |
| ets 文件符号总览 / 找符号 | `serena__get_symbols_overview` + `serena__find_symbol` | cclsp 不覆盖 ets;ets LSP 走 serena |
| 多文件 audit / cross-cutting review | `serena__find_referencing_symbols` | 跨文件批量查引用 |

### 何时**可以/应该**退回 Read/Grep（分语言实证版，2026-06-08 5天质检实测校准）

> 旧版写"MCP 能给更精确答案处用 Grep = 选型错误"是一刀切。实测此 **ArkTS+C++ 混合仓**该按语言分层，Grep 在 .ets 与文本场景往往是**正确**选择，不是 fallback。详见 memory `feedback_mcp_tools_fail_on_ets`。

- **ArkTS `.ets` 的结构/诊断查询**：serena LSP 诊断（`get_diagnostics_for_file`）+ ast-grep 结构匹配（`find_code`/`dump_syntax_tree`）对 `.ets` **一律失效**——不认 ArkUI `struct`/`@ComponentV2`，serena 报 `invalid AST -32001`、ast-grep 返回空（**假阴性**，连已知存在的 `this.x.f=v` 都查不到）。`.ets` 只能：serena **符号级**（`find_symbol`/`get_symbols_overview`，这层 OK）+ **Grep/Read** + 真机/DevEco 编译。
- **C++ 符号查询的空结果**：cclsp/codegraph **空 callers/references ≠ 不存在**（实测连活着的 `GetEventName`/`Emit` 都查不到）。**绝不据 MCP 空结果下"死代码/无引用"结论**——必须 Grep 实物兜底。
- **citation 验证**（"这几行字节真的在那位置吗"——pure text 对比，LSP 杀鸡用牛刀）/ 单文件一次性 lookup / 文档注释类 / 配对·banned-pattern·文本匹配
- LSP 索引未跑 / MCP 暂时不可用（fallback）

### 工具协同准则

- **先 LSP 看影响面 → 再 Read 那几个 callsite 确认行为** — 别上来直接 Read 全文件
- **配对检查类问题**（acquire/release / ref create/delete / map/unmap）— 用 `ast-grep find_code_by_rule` 扫配对模式比逐文件 Read 快 10×
- **跨线程 / threading violation 检测** — `ast-grep` 跨文件扫 pattern（譬如 `GameLoop` 里直接 `napi_call_function`）

### 工具瘦身记录（外网 ETH arXiv:2602.11988 实证 14-22% token 浪费）

| 检查项 | 现状 | 决策 |
|---|---|---|
| cclsp ↔ serena 重叠 | 描述层重叠（"优先/备选"），实际**按语言分工**不重叠（cclsp=C++ only, serena=全仓库 + memory） | 保留双方，决策树改成按语言分工（本次提交） |
| firecrawl 24 工具 | 2026-05-28 用户决定整体弃用（GitHub 超 token / 中文短文 LLM 不可靠 / web-search 直接覆盖） | **已弃用**（见 memory `feedback_firecrawl_deprecated`），改用 `mcp__web-search__*` |
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

1. First try: `mcp__web-search__web_search` 英文 query + `site:developer.huawei.com`。
2. 单 URL 深读：`mcp__web-search__web_fetch` 传 url + prompt。
3. 本机 SDK header 优先（OH_* API 契约直接读 `D:\Program Files\DevEco Studio\sdk\...\external_window.h` 等）—— 见 memory `feedback_websearch_fail_fallback_to_sdk_header`。

> firecrawl 工具组（scrape / search / parse 等 24 个）已于 2026-05-28 整体弃用，见 memory `feedback_firecrawl_deprecated`。

## 代码搜索工具策略

**直接用 Grep + Glob，跳过 fast-context**——本仓三轮实测 fast-context 三连败：

| 查询 | fast-context | Grep |
|---|---|---|
| Q1 音频核心初始化 | 命中 2 个 `docs/audit/*.md` 复盘文档（**0 源码**） | `audio_driver_init\|retro_audio_callback` 直接命中 `audio_player.cpp` / `audio_resampler.cpp` / `i_audio_sink.h` 等 |
| Q2 NAPI 桥 | 返回 `entry/src/main/app/napi/**.*`（**目录通配符无效**） | `napi_module\|NAPI_MODULE` 直接命中 `entry/src/main/cpp/app/napi/module_init.cpp` |
| Q3 输入事件流 ArkTS→native | `No files found` | 直接命中 `LibretroGamePage.ets` + `VirtualController.ets` + `libretro_engine.cpp` + `core_loader_napi.cpp` 整条链路 |

原因：
1. **Devstral 训练语料对 libretro + 鸿蒙 NAPI 覆盖低**（垂直领域语料稀缺）
2. **C++ 文件深嵌套 5 层** `entry/src/main/cpp/core/libretro/`，fast-context 默认 `tree_depth=1` 看不到深层

**关键命名提醒**（避免再像测试时一样翻车）：
- 项目 NAPI 入口实际用 `napi_module` 类型 + `napi_module_register` 函数（**全小写**），不是常见的 `NAPI_MODULE` 宏

详见 user memory `[[reference-fast-context-mcp]]`。
