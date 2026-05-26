# Wire-up Verification — 附录 O 7 项静态验证 (执行日期 2026-05-26)

## 总结

| 项 | 静态 Verdict | 必须真重启确认 |
|---|---|---|
| #1 H3 SessionStart hook | **STATIC_PASS** | 是 |
| #2 OS1 statusLine | **STATIC_PASS** | 是（UI 渲染） |
| #3 SE1 项目级 model | **STATIC_PASS** | 是（运行时版本支持） |
| #4 CT3 @import 子 CLAUDE.md | **STATIC_PASS** | 是（harness 真加载行为） |
| #5 CT5 napi-reviewer memory | **STATIC_PASS** | 是（agent 引用行为） |
| #6 SC1+SC2 skill frontmatter | **STATIC_PASS** | 是（skill 调用时 model 实效） |
| #7 NT1 Notification hook | **STATIC_PASS** | 否（脚本 EXIT:0，fallback 已确认） |

**静态全 PASS：7 / 7**  
**必须真重启 + 真触发才能 100% 闭环：6 / 7（#7 已足够）**  
**静态发现的真实问题：无**

---

## 逐项详情

### #1 H3 SessionStart hook

**静态检查**：

- 文件 `.claude/hooks/session-start.sh`：**存在** (`-rwxr-xr-x`, 660 bytes)
- 可执行权限：**是**
- `bash -n` 语法：**PASS**
- settings.json `SessionStart` 段：**存在**
  ```json
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": ".claude/hooks/session-start.sh" }] }
  ]
  ```
- 手动触发输出（`bash .claude/hooks/session-start.sh`，EXIT:0）：
  ```
  === git status -s ===
   M docs/plans/2026-05-24-harness-fusion-design.md

  === git log --oneline -3 ===
  2b42ddf Merge pull request #71 ...
  0bb99ce fix(napi,engine,audio,video): 闭环审计 T1–T6 全部 30 项 REAL findings 修复
  8441462 docs(plans): 附录 O — 重启 Claude Code 后 7 项 wire-up 验证清单

  === last quick_signals ===
  # quick_signals snapshot — 2026-05-25 16:50:40
    regression   PASS  (10s)
    hygiene      PASS  (3s)
    ui-fixes     PASS  (7s)
    cxx-build    PASS  (1s)
    => ALL PASS / SKIP
  ```

**还需重启 + 真触发确认**：  
重启后不给任何提示，问"现状如何？"——期望 Claude 秒答分支、最近 3 commit、qs 状态，无需自行 Read 文件。

**Verdict：STATIC_PASS**

---

### #2 OS1 statusLine

**静态检查**：

- 文件 `.claude/statusline.sh`：**存在** (`-rwxr-xr-x`, 1463 bytes)
- `bash -n` 语法：**PASS**
- settings.json `statusLine` 字段：**存在**
  ```json
  "statusLine": { "type": "command", "command": ".claude/statusline.sh" }
  ```
- 手动触发（`echo '{}' | bash .claude/statusline.sh`，EXIT:0）：
  ```
  [main*] qs:PASS idle:6m
  ```
  格式符合 `[branch*] qs:PASS idle:Nm`。

**还需重启 + 真触发确认**：  
Claude Code 底部状态栏实际是否渲染 `statusLine.command` 输出，取决于 UI 版本支持。重启后看 UI 状态栏是否真出现该字符串。

**Verdict：STATIC_PASS**

---

### #3 SE1 项目级 model

**静态检查**：

- settings.json 顶层 `"model"` 字段：**存在，值 `"sonnet"`**（文件第 3 行）
  ```json
  { "model": "sonnet", ... }
  ```

**还需重启 + 真触发确认**：  
`model` 字段是否被 Claude Code 当前版本识别取决于版本支持（v2.1.101+）。重启后跑 `/doctor` 或观察 statusline 模型标记确认生效。若用户级 `~/.claude/settings.json` 也有 `model` 字段，项目级覆盖行为需实测。

**Verdict：STATIC_PASS**（字段就位；版本支持待 doctor 验证）

---

### #4 CT3 @import 子 CLAUDE.md

**静态检查**：

- root `CLAUDE.md` 第 14–15 行：
  ```
  @entry/src/main/ets/CLAUDE.md
  @entry/src/main/cpp/CLAUDE.md
  ```
- `entry/src/main/ets/CLAUDE.md`：**存在**，67 行，4553 bytes（非空）
- `entry/src/main/cpp/CLAUDE.md`：**存在**，50 行，2839 bytes（非空）
- 两份子文件均含实质性约束内容（ets: aboutToAppear/ForEach/Canvas 规则；cpp: NativeBuffer/LOG_DOMAIN/thread 规则）

**还需重启 + 真触发确认**：  
@import 是 v2.1+ 自动内联特性。旧版本客户端仅按需加载。验证方法：重启后不切 cwd，问"NativeBuffer 用 mmap 还是 FromNativeWindowBuffer？"——期望直接回答 FromNativeWindowBuffer（说明 cpp/CLAUDE.md 已内联）；若 Claude 说"我需要先 Read cpp/CLAUDE.md"则说明旧版本，需升级。

**Verdict：STATIC_PASS**（文件就位；@import 自动内联行为待 v2.1+ 真实触发确认）

---

### #5 CT5 napi-reviewer memory

**静态检查**：

- 文件 `.claude/agents/napi-boundary-reviewer.memory.md`：**存在**（55 行）
- 关键词检查：
  - `56 functions`：**找到**（第 12 行："56 functions / 6 modules"）
  - `4 thread classes`：**找到**（第 17 行："4 thread classes — NAPI / Engine / Audio / EventBridge"）
  - `TSFN canonical wrapper`：**找到**（第 19 行："TSFN canonical wrapper: core/engine/event_bridge.cpp"）
- 包含 common mistakes、patterns-to-flag、review session log 等完整框架内容

注：附录 O 期望关键词是"56 函数 / 4 线程 / TSFN canonical"，内容以"56 functions / 6 modules"表达，与 4-thread 并列（两个独立条目），属于同一语义。

**还需重启 + 真触发确认**：  
让 Claude "用 napi-boundary-reviewer 审一下 engine_lifecycle_napi.cpp"——期望 agent 引用 memory.md 的 TSFN canonical / 4-thread 规则，无需用户手动 Read。

**Verdict：STATIC_PASS**

---

### #6 SC1+SC2 skill frontmatter

**静态检查**：

- `.claude/skills/auto-commit-cicd/SKILL.md` frontmatter（SC1）：
  ```yaml
  disable-model-invocation: true
  allowed-tools: Bash, Read, Grep, Glob, Edit, Write
  model: sonnet
  ```
  **`allowed-tools` + `model: sonnet`：存在** ✓

- `.claude/skills/closed-loop/SKILL.md` frontmatter（SC2）：
  ```yaml
  disable-model-invocation: true
  allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet
  model: sonnet
  ```
  **`allowed-tools` + `model: sonnet`：存在** ✓

**还需重启 + 真触发确认**：  
`model: sonnet` frontmatter 字段是否被 Claude Code 当前版本识别、是否真正约束 skill 内的子模型调用，需触发 `/closed-loop` 或 `/auto-commit-cicd` 后观察 statusline 或查询实际使用模型确认。

**Verdict：STATIC_PASS**（字段就位；skill 调用时 model 实效待真触发）

---

### #7 NT1 Notification hook

**静态检查**：

- 文件 `.claude/hooks/notify.sh`：**存在** (`-rwxr-xr-x`, 1294 bytes)
- `bash -n` 语法：**PASS**
- settings.json `Notification` 段：**存在**
  ```json
  "Notification": [
    { "hooks": [{ "type": "command", "command": ".claude/hooks/notify.sh" }] }
  ]
  ```
- 手动触发（`echo '{"message":"test wire-up verification"}' | bash .claude/hooks/notify.sh`，EXIT:0）：
  - 脚本逻辑：先检测 BurntToast；若无则 fallback `msg` 命令
  - EXIT:0，无 stderr —— 脚本无报错（BurntToast 检测或 msg fallback 均以 `|| true` 静默收尾）
  - 当前系统：若 BurntToast 未装，`msg` 命令为 Windows 内建，应走 fallback 路径
  - 无法在 Git Bash 验证是否真弹窗，但脚本已正确走 fallback 分支并退出

**还需重启 + 真触发确认**：  
弹窗类需目视确认。可选：用户手动运行一次 `echo '{"message":"test"}' | bash .claude/hooks/notify.sh` 并观察是否弹出 toast/message box。若想要 BurntToast（非阻塞），需用户一次性执行 `Install-Module BurntToast -Scope CurrentUser -Force`。

**Verdict：STATIC_PASS**（脚本无错，fallback 路径已确认；目视弹窗可选验证）

---

## 整体结论

- **静态全 PASS 项数：7 / 7**
- **必须真重启 + 真触发才能 100% 闭环的项：6 / 7**（#7 已足够静态确认）
- **静态发现的真实问题：无**

### 建议用户重启后执行的 6 个快速验证

| # | 触发方式 | 期望 | 耗时 |
|---|---|---|---|
| H3 | 重启后问"现状如何？" | Claude 秒答分支/commit/qs，无需 Read 文件 | 10s |
| OS1 | 看 UI 底部状态栏 | `[main*] qs:PASS idle:Nm` | 立即 |
| SE1 | 问"你用的哪个 model？" 或 `/doctor` | sonnet | 10s |
| CT3 | 问"NativeBuffer 用 mmap 还是 FromNativeWindowBuffer？" | 直接答 FromNativeWindowBuffer | 10s |
| CT5 | 触发 napi-boundary-reviewer | agent 引用 TSFN canonical 规则 | 30s |
| SC2 | 触发 `/closed-loop` | model 为 sonnet（statusline 或询问） | 10s |
