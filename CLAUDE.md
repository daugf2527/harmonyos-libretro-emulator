# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Layered context

- **This file (root)**: cross-layer architecture, build/release commands, environment notes.
- **`entry/src/main/ets/CLAUDE.md`**: ArkTS/ArkUI patterns and anti-patterns.
- **`entry/src/main/cpp/CLAUDE.md`**: C++ engine threading, NativeBuffer, LOG_DOMAIN constraints.

v2.1+ auto-inlines the sub-directory CLAUDE.md files via the @imports below;
older clients pull them in on demand when Claude works under those paths.

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
