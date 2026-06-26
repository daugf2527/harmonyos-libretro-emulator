# 最近 5 天开发 多方位质检报告（2026-06-03 → 06-08）

> 方法：**对抗式复核**，不重跑项目已做的 grep 自检，而是攻击其验证不到的地方。
> 4 个独立角度（V2 迁移 / NAPI 边界 / 音视频并发 / tracker 诚实性）+ 主 AI 交叉复核头条 finding 防自评漂移。
> 全部为**静态分析，未编译/未真机/未模拟器**。

## 窗口规模
~50 commits / 110 文件 / +5821 −1256。主题：API22 适配、NAPI 类型谎言整治(D003/D012/D013/D014)、ArkTS async-@State 守卫(D016-D018)、音频 underrun 双 profile(D019/D020)、**ArkTS V1→V2 全量迁移(ddb9ad7，单提交 91 文件)**、视频帧率 30↔60fps 反复、死代码清理(D021/D022)、线程 QoS。

## ⚠️ 最高杠杆的系统性发现（贯穿全窗口）
**验证盲区**：这 5 天几乎每条 fix 都标注"未编译/未真机"。唯一自动验证是 `quick_signals.sh`（grep 守卫 + C++ ninja 增量编译），**它不编译 .ets**（memory `feedback_quick_signals_not_arkts_compile` 已记录）。窗口内**真发生过 2 次编译断裂**：`bf52592`（Edit 漏函数签名致 `} {` 破坏）、`ea149c3`（MemoryLevel 真机编译 ERROR）——都是事后才发现。
→ **91 文件 V2 迁移 + 全部 .ets fix 从未走过 hvigor 编译**。本报告能静态查到的 bug 只是下限；建议**首要动作是 DevEco 全量复编一次** + 真机/模拟器冒烟，而非继续静态加固。

## Findings 汇总（按严重度）

| ID | 级 | 角度 | file:line | 一句话 | 交叉复核 |
|---|---|---|---|---|---|
| **C-F1** | **P1** | 音频 | `audio_bridge.cpp:77-103` + `:108` | D019 音频延迟可调设置（UI 上限 200ms）全部 < D020 缓冲地板（模拟器 250ms=12000帧），`max(target,floor)` 只升不降 → 模拟器上**恒钳死 no-op**，但 SettingsPage 仍向用户承诺"调大抗 underrun" = placebo dead config | ✅ 主 AI 实物证实（地板 48000×250/1000=12000 > 200ms 9600） |
| **A-Q1-1** | **P1** | V2 | `LibretroNewArchTestPage.ets:186,739-754` | `@Local coreCheck: CoreCheckState`（裸 interface，非 @ObservedV2）字段就地 mutate `this.coreCheck.running=` → V2 不刷新 → "验证核心符号"按钮结果静默不更新 | ✅ 主 AI 实物证实（interface@131，无整体替换） |
| **A-Q1-2** | **P1** | V2 | `LibretroNewArchTestPage.ets:187,771-774` | `@Local soakState: RuntimeSoakState` 同根因 → 压力测试倒计时/状态静默不刷新 | ✅ 同上 |
| **B-Q3** | **P2** | NAPI | `engine_lifecycle_napi.cpp:845`(+ query:60 / core_loader:587) | `CompleteSwitchGame`（生产切游戏路径）`status!=napi_ok` 时不 early-return，落到 L880 `MakeErrorResult`+`ResolveDeferredChecked` → env teardown(napi_cancelled) 时仍调 napi_* = **正是 D003 要消除的 UB**；D003"已对齐正范式"声明**夸大**（漏 3 函数） | ✅ 主 AI 实物证实 |
| **C-F2** | **P2** | 并发 | `audio_player.cpp:506-538,637-650` | 音频实时回调持 `state_mutex_` 时调 `OH_AudioWorkgroup_Start/Stop`(HAL)；真机 workgroup 正常 → 每帧持锁跨 HAL 与 rebuffer 争锁 = 优先级反转。**模拟器因 workgroup_disabled_ 短路反而免疫** → D024 defer 埋的是真机隐患，"平台非代码"叙事在此**掩盖了真机代码问题** | C 报告（前 audit 已识别 F1，C 补"跨 HAL 持锁"加重项） |
| **C-F3** | **P2** | 并发 | `frame_pacer.h:82-88` | `SetTargetFps`（Engine 线程）写非原子 `deadline_initialized_`/`frame_started_`，`BeginFrame/EndFrame`（RenderThread）读写同成员 → 跨线程非原子 bool race（`target_frame_time_us_` 已原子化但漏了同函数顺带写的两个 bool） | C 报告，预存 bug，撤销链正好改紧邻代码没碰它 |
| **F-1** | **P2** | 工具 | `check_async_state_guard.pl:28,31` + `scan_code_drift.sh:100-109` | gc Pattern 7（D018 防回归守卫）key 在 `@State` 上，V2 迁移把全仓 @State→@Local → `next unless %state_fields` 恒跳过 → **静默死亡 `methods=0 NO_GUARD=0`**（实跑证实），它要守的 await-写@Local-漏守卫竞态如今无人检测，报表假绿 | ✅ 主 AI 实跑证实 |
| F-2 | P3 | 工具 | `scan_code_drift.sh:16-20` | Pattern 1（@State complex types）同样 key @State，迁移后恒 0、moot（target 已不存在，无害但占位假绿） | ✅ 实跑 |
| C-F4 | P3 | 并发 | `libretro_engine.h:201,381` | `targetFps_`(plain double) Engine 写 / NAPI 线程 `GetFps()` 读，formally UB（aarch64 实际原子，低危） | C 报告 |
| A-Q3-1 | P3 | V2 | `LibretroGamePage.ets:12,66` | 2 个未使用 import（疑 B 档删码残留），仅 warning 级 | A 报告 |
| C-F5 | P3 | 音频 | `audio_bridge.cpp:478-495` | 真机 rebuffer 理论 Pause/Start 振荡（HAL 廉价，非死循环） | C 报告 |

## 各角度结论

### A — ArkTS V2 迁移（agent + 主 AI 交叉）
- **"零 V1 残留"属实**：实际 V1 装饰器=0（8 个 @State 命中全是注释）。@ComponentV2=65 / @Local=248 / @Param=181 / @Monitor=5；全仓**仅 1 个真 @ObservedV2**（PerfDisplayState，生产 perfDisplay 用对了）。
- **Q1 → 2×P1**：唯二静默反应性 bug，均在 dev 诊断页（爆炸半径低）；同页 audioStatus/stats 走整体替换故安全。**反应性模型整体正确**，只有"裸 interface + 字段就地 mutate"这一模式漏网。
- **Q2 @Param 只读 / @Monitor → 0 finding**：181 个 @Param 无自赋值；5 个 @Monitor 全收 IMonitor 且在 aboutToAppear 显式初始化（没踩"初始化不触发"坑）。
- **Q3 结构完整性 → 无编译失败级残缺**：`} {`=0、@ComponentV2 缺 build()=0、孤儿语句=0。bf52592 破坏未复现。死代码清理(D021/D022)真干净（8 删除符号 0 孤儿引用，3 文件确删）。

### B — NAPI 边界（agent 两次 launch 失败 → 主 AI 接手 inline）
- **Q1 残留类型谎言 → 干净**：disk/input/video/audio napi 的 `return Make(ErrorResult|ResolvedPromise)` = 0 命中，无结构对象返回；index.d.ts 全 63 export 逐核，已修文件外无新类型谎言。**"100% 对齐"对 sync 返回类型属实**。
- **Q2 helper deferred 生命周期**：`MakeResolvedErrorPromise:495-497` 确有 deferred 泄漏（MakeErrorResult 返 nullptr 时 promise 永 pending），但仅 OOM 极端态；D013(a) wontfix **合理**（与既有模板一致）。
- **Q3 → P2 FINDING**：napi_cancelled 处理仓内分裂两套——5 函数严格 early-return（D003+state 正范式）vs 3 函数弱范式（WaitForState/TestCoreLoader/**SwitchGame** 仍在非 ok 路径调 napi_*）。生产路径 `CompleteSwitchGame` 最暴露。

### C — 音视频叙事 + 并发（agent + 主 AI 交叉）
- **对"平台非代码"叙事裁决：部分自洽，掩盖了一个真机问题**。
  - 平台诊断成立（QoS/workgroup 被拒是日志实证，API17→22 跳版引入，非甩锅）。
  - 但 **D019"加缓冲设置根治 underrun"自相矛盾**：纯平台 RT 问题下深缓冲只治标，且实现为 dead code(C-F1)；真正起作用的是 D020 hardcoded profile，与用户可调档无关。"根治"夸大且被自己后续 commit 架空。
  - 叙事归"平台"后，D024 真机优先级反转(C-F2) 以"模拟器非症状"为由 defer——但 F2 是真机专属隐患。
- **Q2(b) 纠正**：`busy_wait_allowed_` 写读**同为 RenderThread**（render_thread.cpp:188 写、EndFrame 读），relaxed 充分——**纠正了我和旧 audit 的"跨线程 race"前提**。
- **Q3 帧率撤销链 → 0 finding**：`60e3538` 外科级移除 30fps cap，`EffectivePeriodUs()` 只剩 `target_frame_time_us_.load()`；busy_wait 与帧率正确解耦；全仓无残留 30fps 硬编码。**撤销干净。**

### D — tracker 诚实性（agent 失败 → 主 AI 接手 inline，抽查）
- **对"改了什么"实质诚实**：D010（P0 黑屏 `if(!result.success)`@1000 + SwitchGameError）、D002（reconcileManifestItems@174/189）抽查均**真 fixed**，fix 代码确在。
- **但有夸大/漂移**：① D003"已对齐正范式"夸大（见 B-Q3）；② 自报数字 drift（D007 称 @ComponentV2=44，实 65）；③ D001/D003/D005 自承"录入即已修、状态误标"。
- **未独立深核**：D-Q2(api22 README 状态) / D-Q3(doc file:line drift) 因 agent 失败仅轻触，建议后续单独跑 `/gc scan_doc_drift`。

### F — 新增防回归工具是否真有效（换角度，主 AI inline + 实跑）
**核心问题**：5 天新增的验证工具会不会"静默 0 命中"给假信心？（memory `feedback_string_match_trace_inputs`）
- **F-1 → P2 确认**：`check_async_state_guard.pl`（gc Pattern 7，D018 的防回归机制）key 在 `@State` 上（L28 收集 + L31 `next unless %state_fields`）。但 V2 迁移把全仓 `@State`→`@Local`（实际 @State=0）→ 工具跳过每个文件，**实跑 `methods=0 NO_GUARD=0`**。它要守的"await 后写 @Local 漏 pageActive 守卫"竞态在 V2 代码里仍在却无人检测，scan_code_drift 报表 Pattern 7 假绿。**V2 迁移静默废掉了 D018 守卫。**
- **F-2 → P3**：Pattern 1（@State complex types）同样 key @State，迁移后恒 0、moot。
- **对照健康项**：`check_foreach_keygen.pl`（Pattern 3，装饰器无关）实跑 `total ForEach=51 NO_KEY=0` ✓；`check_core_compatibility.sh`（M3/D009）实跑 30cores/35roms/65entries ✓。两者非静默死。

> **本轮新 finding 已回写 `docs/tech-debt-tracker.md`**：D025(C-F1)/D026(A-Q1)/D027(B-Q3)/D028(F-1)/D029(C-F3,含C-F4)，并在 D024 备注补 C-F2 真机定性纠正。

## 建议动作（优先级）
1. **[最高] DevEco 全量复编 + 真机/模拟器冒烟** — 解 91 文件 V2 迁移"从未编译"的根本风险，远比静态加固重要。
2. **C-F1（P1）** — 要么把 SettingsPage 音频延迟设置的承诺文案改诚实（标注"模拟器上受 profile 地板限制"），要么让 UI 上限能真正抬高 emulator 地板（当前 200ms<250ms 永远无效）。**这是面向用户的误导**。
3. **A 的 2×P1** — dev 诊断页 coreCheck/soakState 改 @ObservedV2 类 或整体替换 `this.x={...}`；真机点按钮即可复现（spinner 不出）。
4. **B-Q3（P2）** — CompleteSwitchGame 补 D003 严格 napi_cancelled early-return，与 state 正范式对齐；或统一三函数范式。改 app/napi 须 dispatch napi-boundary-reviewer。
5. **C-F2/F3（P2）** — 真机调试条件具备后处理（F2 已是 D024 defer，但需重新评估"真机专属"定性；F3 把两个 bool 原子化，低成本）。

6. **F-1（P2，低成本）** — `check_async_state_guard.pl:28` 正则 `@State`→`@(?:State|Local)`，重跑 human-review（D018 的 7 候选会以 @Local 重现）。**否则 D018 的"防回归"在 V2 代码上一直是假绿。**

## H — MCP 重武器新维度（用户追加指令：动用前两轮未用的 MCP）
目标：用 codegraph 调用图/影响、serena/cclsp LSP 诊断、ast-grep 结构匹配、web-search 上游真值开新角度。**最大产出是钉死了这些工具对本「ArkTS+C++ 混合仓」的真实能力边界**（跨会话沉淀价值 > 单个 finding）。

| MCP 工具 | 对本仓结论 | 证据 |
|---|---|---|
| **serena LSP 诊断** | **对 .ets 不可用** | `get_diagnostics_for_file` 对 LibretroGamePage/NewArchTestPage 报 `invalid AST -32001`——通用 TS server 不认 ArkUI `struct`/`@ComponentV2`。**"用 LSP 诊断绕过未编译盲区"这条路对 ArkTS 不通** |
| **ast-grep（.ets）** | **对 ArkTS 结构性失效** | `dump_syntax_tree` 对含 `struct` 的 ArkTS 片段返回**空**；`this.$OBJ.$FIELD=$VAL` / 已知存在的 `this.coreCheck.running=true` 均假阴性 No matches。tsx/typescript parser 都不解析 ArkUI 扩展语法 → **H3"ast-grep 全仓扫 V2 mutation"对 .ets 整条作废**，A 的 grep 结果仍是权威 |
| **codegraph（C++）** | 可用但**索引不全，空≠不存在** | `SetTargetFps` impact=63 符号（证 D029 race 在 video_pipeline→render_thread→frame_pacer 热路径，非孤立角落）；`ExecuteSyncTask` 17 callers（证 D023 的 14 同步 NAPI 实存）。**但 `GetEventName`/`Emit(EventType)` codegraph+cclsp 都查不到，实物 Grep 证实它们活着** → 印证 CLAUDE.md"codegraph 空结果≠无此符号"，cclsp 同病 |
| **cclsp find_references** | C++ nav 可用但**同样空结果不可信** | `Emit` 只回 2 个声明点、0 callsite；实物 Grep 兜底才拿到真实 21 callsite 分布 |
| **web-search 上游真值** | ✅ 有效，复核了关键断言 | 官方确证 **@Monitor 初始化不触发**（OpenHarmony spec），workaround="抽方法+aboutToAppear 手调"——与项目 5 处 @Monitor 实现完全吻合 → **A-Q2"@Monitor 全对"经上游复核成立** |

**H 维度新增/印证的 finding**：
- **D015(b) 经独立实物验证为 TRUE 但表述精化**：21 emit callsite（input_manager 2 + libretro_engine 19）**全走字符串版 `Emit("...")`**，枚举版 `Emit(EventType)` 外部 callsite=0 属实；但 `GetEventName` 非独立死代码——它被枚举版 `Emit(EventType):168` 内部调用，准确说是"`Emit(EventType)`+`GetEventName` 构成一条 0 外部调用的死链"。D015(b) open 状态合理，链条描述可更精确。
- **D029 race 在热路径**（codegraph impact 佐证，非孤立角落）。
- **A-Q2/D007 上游复核通过**（@Monitor 不触发 + V2 兼容层 API12+ → 迁移合法）。

**方法论沉淀**：本仓是 ArkTS(.ets) + C++ 混合。**LSP 诊断 / ast-grep 结构匹配对 .ets 一律失效**（ArkUI 扩展语法），ArkTS 侧只能 serena 符号级 + Grep 文本级 + 真机编译；C++ 侧 cclsp/codegraph 可用但**空结果必须实物 Grep 兜底**。这条直接影响未来所有"换 MCP 工具"的预期。

## ② 后续：关闭 ArkTS 编译盲区调研（2026-06-08 续，回应"未编译"系统性发现）

针对本报告最高杠杆发现（91 文件 V2 迁移 + 全部 .ets fix 从未 hvigor 编译），调研"能否像 C++ cxx-build 一样把 .ets 落地前接进本地反馈回路"。**结论：现有工具不可达成轻量编译验证，但澄清了 CI gate 一个真盲区。**

- **codelinter ≠ 编译器**：DevEco codelinter（本机 v6.0.240）默认规则集仅 `@performance/recommended` + `@cross-device-app-dev/recommended`，**不含 `@typescript-eslint`** → no-any/no-var/V1V2 误用等 ArkTS 语法/类型 correctness 规则全不跑（实测注入 `function f(x:any):any` 探针 0 命中）。真编译/类型错误由 hvigor ArkTS 编译器在 Build HAP 阶段抓，**无轻量 CLI 替代**。
- **CI gate 名实不符（新 finding D030）**：CI 三条 workflow 的 "Code Linter Gate" 同样 `codelinter -e error … .` 无 `-c`、仓库无 `code-linter.json5` → 对 .ets correctness **零覆盖**，靠后续 Build HAP 兜编译。启用 correctness 需建项目根配置加 `@typescript-eslint`，但 ① 本地 CLI 实测激活不了（单文件扫缺 hvigor 类型上下文）② CI 启用会对存量 91 .ets 爆批量违规变红 → **需用户决策,未自主开启**。
- **全 ets 扫实证（本轮 3 个 .ets fix 的迟到验证）**：codelinter 全扫 **0 error / 38 warn**（36 custom-component 滥用 + 1 reusable + 1 date）→ A-Q1/C-F1/A-Q3-1 改动**性能/AST 规范层零违规**（语法过关；运行时反应性行为仍需真机验）。
- **交付物**：按需工具 `scripts/ci/check_arkts_codelinter.sh`（performance 维度，诚实定位非编译验证，解析 JSON severity 不裸信 exit code，Git Bash 须 `cmd //c`）+ CLAUDE.md 文档 + memory `feedback_codelinter_capability_boundary`。**不接 quick_signals 常驻**（performance warn 非 gate、+30s、会永绿 = 负价值）。
- **建议#1 细化**：原"DevEco 全量复编"仍是**唯一**能验证 .ets 编译/类型/V1V2-OOM 的途径——codelinter 调研证明无 CLI 捷径，hvigor/DevEco 复编不可绕过。

### tracker 后续关单（④）
- **D015(b) closed**：实物追链推翻"枚举版 Emit+GetEventName 是死代码"——字符串版 `Emit(string):122` 内部转发到枚举版 `Emit(EventType):126`→`GetEventName:168`，每次 Emit 都执行，"0 使用"实为"0 外部直接 callsite"误读。无"哪版为正"决策,误判关单。
- **D018 系统性面 closed**：D028 修复 perl 工具后全仓 55 个 async-await 方法**全扫**（非抽样）仅 7 候选且全为测试页/设计性/microtask，原担心"剩余页面零散遗漏"经全扫证伪。
- **D023/D024 维持 defer**（用户既定决策,真机条件未具备）。


- 全静态，0 编译/0 运行验证。
- D-Q2/Q3 未深核（agent 两次失败）。
- 过程踩自身工具坑：bash `cd` 跨调用持久 + 本机 Git Bash 路径解析怪象，导致首轮 `$ETS` 路径翻倍出假 0；已切 Grep/Glob/Read 工具 + 绝对路径重做并自我纠错（教训：本机文件操作禁用 bash find/ls/grep -r）。
- 子代理产出：`agent-A-arkts-v2.md`、`agent-C-audio-video-concurrency.md` 为 agent 落盘；B/D 因 agent 两次 "empty/malformed HTTP 200" 失败转主 AI inline，findings 收于本文。
