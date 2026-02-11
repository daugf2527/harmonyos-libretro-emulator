# Code Quality Debt Backlog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将本次本地质检发现的问题沉淀为可执行的后续修复清单，并同步到 GitHub Issue 跟踪列表。

**Architecture:** 本文档不包含代码修复，只做问题归档与修复设计。每个问题提供严重级别、代码证据、官方依据、修复建议与验收标准，后续按优先级逐项落地。

**Tech Stack:** C++17、HarmonyOS NDK (HiLog / NativeBuffer / NativeWindow)、GitHub Issues

## 背景与范围

- 时间：2026-02-10
- 分支：`feat/switch-game-singleflight`
- 本次动作：仅文档化与挂账，不修改业务代码
- 证据来源：
  - 本地代码静态检查
  - 仓库脚本：`scripts/ci/check_repo_hygiene.sh`、`scripts/ci/check_regression_guards.sh`
  - 官方与权威资料（华为开发者文档、OpenHarmony docs、libretro 官方头文件、cppreference）

## 质检结论（摘要）

- 仓库现有静态门禁通过，但存在 **45 个需后续修复的问题**：
  - 8 个高优先级（并发数据竞争/线程模型违规/生命周期收敛阻断/输入路由死锁/Stop 超时析构崩溃）
  - 26 个中优先级（日志格式规范一致性、敏感文件忽略规则、事件合并丢更新、核心选项并发访问、磁盘控制并发访问、PluginManager 输入状态隔离、StopEngineAsync 生命周期收敛、Stop 超时恢复通道、端口映射一致性、AudioBridge 统计并发访问、Blur 端口错配、Touch 固定端口错配、全局引擎回调指针线程边界、全局输入回调指针线程边界、CoreLoader 测试接口路径校验前读取、CoreLoaderNapi ELF 边界校验缺口、PlatformResourceManager 句柄生命周期收敛、PlatformResourceManager 锁边界一致性、EnvState 目录字符串跨线程同步、SetFilesDir/LoadRom 时序一致性、SwitchGameAsync token 取消窗口、keyboard callback 转发链路缺失、EngineMessage 路径静默截断、Vulkan wait_sync_index 同步语义缺口、Vulkan present 队列选择错误、VulkanPresenter 帧状态并发悬垂指针风险）
  - 11 个低优先级（AV 查询并发可见性、全局静态回调线程边界加固、主回调注册返回值可观测性、Start 异常路径门禁复位、Reset 状态通知一致性、NAPI async work 失败路径收口、StopEngineAsync 异常复位、NAPI async complete 状态分流、NAPI 导出注册返回值可观测性、CoreLoaderNapi 大文件读取上限/异常保护、core options 配置并发读改写覆盖）

## 问题清单

### P0-1 并发数据竞争：锁内写、锁外读 `stats_.audioBatchCalls`

- 严重级别：`High`
- 影响：在多线程音视频回调路径下存在未定义行为（UB）风险，可能导致偶发统计异常或极端情况下不可预期行为。
- 代码证据：
  - 写入（锁内）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1790`
  - 读取（锁外）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1850`
  - 成员定义：`entry/src/main/cpp/core/engine/libretro_engine.h:43`
  - 保护锁：`entry/src/main/cpp/core/engine/libretro_engine.h:360`
- 官方/权威依据：
  - C++ 内存模型：发生 data race 时行为未定义（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 方案 A：该字段所有读写都统一纳入 `statsMutex_` 锁域。
  - 方案 B：将该计数字段改为 `std::atomic<uint64_t>`，并统一内存序语义。
  - 推荐方案：优先 A（保持与现有 `RuntimeStats` 一致），若热路径性能不足再评估 B。
- 验收标准：
  - 读写路径无“锁内写 + 锁外读”混用。
  - clang-tidy/静态检查不再出现并发访问告警（如已启用）。

### P0-2 并发数据竞争：`AudioPlayer` 回调线程与控制线程共享状态无统一同步

- 严重级别：`High`
- 影响：音频回调路径与控制路径并发访问 `is_playing_ / resume_on_interrupt_ / workgroup_ / workgroup_token_`，存在 UB 风险，可能导致状态错乱、偶发崩溃或停播异常。
- 代码证据：
  - 成员定义：`entry/src/main/cpp/platform/audio/audio_player.h:173`、`entry/src/main/cpp/platform/audio/audio_player.h:174`、`entry/src/main/cpp/platform/audio/audio_player.h:167`、`entry/src/main/cpp/platform/audio/audio_player.h:168`
  - 控制路径读写：`entry/src/main/cpp/platform/audio/audio_player.cpp:194`、`entry/src/main/cpp/platform/audio/audio_player.cpp:208`、`entry/src/main/cpp/platform/audio/audio_player.cpp:234`、`entry/src/main/cpp/platform/audio/audio_player.cpp:260`
  - 中断回调读写：`entry/src/main/cpp/platform/audio/audio_player.cpp:686`、`entry/src/main/cpp/platform/audio/audio_player.cpp:687`、`entry/src/main/cpp/platform/audio/audio_player.cpp:688`、`entry/src/main/cpp/platform/audio/audio_player.cpp:705`、`entry/src/main/cpp/platform/audio/audio_player.cpp:706`
  - workgroup 回调/清理并发访问：`entry/src/main/cpp/platform/audio/audio_player.cpp:296`、`entry/src/main/cpp/platform/audio/audio_player.cpp:336`、`entry/src/main/cpp/platform/audio/audio_player.cpp:444`、`entry/src/main/cpp/platform/audio/audio_player.cpp:734`、`entry/src/main/cpp/platform/audio/audio_player.cpp:748`
- 官方/权威依据：
  - C++ 内存模型：发生 data race 时行为未定义（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 为上述共享字段建立统一锁边界（或明确原子化策略），避免“回调线程 + 控制线程”无锁混用。
  - 资源清理前建立回调停机/收敛屏障，避免释放期仍被回调访问。
- 验收标准：
  - 共享状态字段不再出现无锁跨线程读写路径。
  - 音频中断、暂停、停止与销毁流程的状态切换具备一致锁边界。

### P0-3 并发数据竞争：`EnvState` 最小音频时延字段跨线程无锁访问

- 严重级别：`High`
- 影响：NAPI 线程调用 `SetMinimumAudioLatency` 与引擎线程 `ProcessFrame` 共享 `pending_min_audio_latency_ms_ / has_pending_min_audio_latency_`，存在 UB 风险，可能导致延迟设置丢失或异常抖动。
- 代码证据：
  - NAPI 入口：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1356`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1371`
  - 写入路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:774`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:56`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:57`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:58`
  - 消费路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1558`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:60`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:61`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:65`
  - 字段定义：`entry/src/main/cpp/core/libretro/env_dispatcher.h:217`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:218`
- 官方/权威依据：
  - C++ 内存模型：发生 data race 时行为未定义（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 将上述字段改为原子并统一内存序，或以互斥锁包裹 set/consume 整体读写边界。
- 验收标准：
  - 不再存在跨线程无锁读写该字段的路径。
  - 高频调用最小音频时延接口时行为稳定可预测。

### P0-4 线程模型违规：NAPI 直接调用 core API，绕过 Engine 线程串行边界

- 严重级别：`High`
- 影响：`SaveState/LoadState/SRAM/Cheat/ResetCore/GetRegion` 等在 NAPI 线程直调 core API，与引擎线程 `retro_run` 并发执行，存在崩溃、存档损坏、状态错乱风险。
- 代码证据：
  - NAPI 入口：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1117`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1142`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1165`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1189`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1212`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1221`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1228`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1403`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1433`
  - 引擎线程主循环：`entry/src/main/cpp/core/engine/libretro_engine.cpp:791`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1538`
  - 直调实现路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:2202`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2206`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2212`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2216`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2229`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2242`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2248`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2255`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2267`
- 官方/权威依据：
  - Libretro 官方文档 Thread safety：API 不保证线程安全，且不建议在 `retro_run` 主线程外调用。
  - 来源：<https://docs.libretro.com/development/cores/developing-cores/>
- 修复建议（后续实施）：
  - 统一将上述操作消息化投递到 Engine 线程执行。
  - 需要返回值的接口使用请求-响应桥接（future/条件变量）。
  - 在 `LOADING/STOPPING` 等阶段增加状态门禁。
- 验收标准：
  - 相关 core API 不再从 NAPI 线程直接进入核心实现。
  - 并发触发存档/读档/金手指/reset/region 场景下稳定无崩溃。

### P0-5 生命周期收敛缺陷：`Stop` 提前进入 `STOPPING`，导致 Stop 消息清理分支失效

- 严重级别：`High`
- 影响：`Stop` 路径中“由引擎线程消费 Stop 消息并执行清理”的设计被绕过，`UnloadGameIfNeeded("stop")` 分支难以命中，生命周期语义与实现不一致。
- 代码证据：
  - `Stop` 先置位再发消息：`entry/src/main/cpp/core/engine/libretro_engine.cpp:343`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:344`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:348`
  - GameLoop 顶部提前退出：`entry/src/main/cpp/core/engine/libretro_engine.cpp:797`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:804`
  - Stop 消息分支（含卸载逻辑）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:939`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:942`
- 官方/权威依据：
  - libretro 生命周期约束：`retro_unload_game` 在 `retro_deinit` 之前调用；`retro_deinit` 应显式释放资源。
  - 来源：<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - 收敛到单一路径：Stop 仅投递消息，不在调用线程提前置 `STOPPING`。
  - 由引擎线程消费 Stop 消息后统一执行清理与状态迁移。
- 验收标准：
  - Stop 调用后，`MessageType::Stop` 分支可稳定触发。
  - 清理顺序与状态迁移在日志中可验证、可复现。

### P0-6 生命周期收敛缺陷：`Stop` 超时后 `Reset` 继续执行清理，线程未收敛即重置

- 严重级别：`High`
- 影响：`Stop` 超时路径会提前返回，`running_` 仍可能为真；后续 `Reset` 不校验线程收敛就继续重开队列/卸载核心，可能导致后台 GameLoop 与前台清理并发交错。
- 代码证据：
  - Stop 超时提前返回：`entry/src/main/cpp/core/engine/libretro_engine.cpp:361`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:369`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:370`
  - `running_` 仅成功路径置 false：`entry/src/main/cpp/core/engine/libretro_engine.cpp:377`
  - Reset 未校验 Stop 结果即继续：`entry/src/main/cpp/core/engine/libretro_engine.cpp:390`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:392`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:400`
  - Switch 失败恢复路径直接 `Stop -> Reset`：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:444`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:446`
- 官方/权威依据：
  - libretro 生命周期约束：`retro_unload_game` 在 `retro_deinit` 之前调用；`retro_deinit` 显式释放资源。
  - 来源：<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - `Stop()` 返回显式结果（成功/超时/失败），`Reset()` 仅在线程已收敛时继续。
  - Stop 超时时进入结构化错误态，禁止继续 destructive reset。
  - 失败恢复路径增加 `gameLoopExited_` 门禁。
- 验收标准：
  - Stop 超时后不会继续执行并发重置清理。
  - `SwitchGameAsync` 恢复路径在超时场景行为可预测且无生命周期错序。

### P0-7 死锁风险：`AssignPort(None)` 持锁重入 `UnassignPort`

- 严重级别：`High`
- 影响：`AssignPort` 在持有 `mutex_` 的情况下调用 `UnassignPort`，后者再次锁同一 `std::mutex`，触发未定义行为/死锁风险；输入绑定接口可能直接卡死。
- 代码证据：
  - 首次加锁：`entry/src/main/cpp/core/engine/input_port_router.cpp:40`
  - 持锁调用：`entry/src/main/cpp/core/engine/input_port_router.cpp:42`、`entry/src/main/cpp/core/engine/input_port_router.cpp:43`
  - 二次加锁：`entry/src/main/cpp/core/engine/input_port_router.cpp:95`
- 官方/权威依据：
  - `std::mutex::lock`：同一线程重复上锁会导致未定义行为（常见表现为死锁）。
  - 来源：<https://en.cppreference.com/w/cpp/thread/mutex/lock>
- 修复建议（后续实施）：
  - 将 `sourceType == None` 分支改为调用“无锁内部解绑实现”（例如 `UnassignPortLocked`）。
  - 增加 `AssignPort(None)` 限时返回回归用例。
- 验收标准：
  - `AssignPort(None)` 在压力场景下稳定返回，不出现阻塞。
  - 绑定/解绑接口在高频切换下可持续响应。

### P0-8 生命周期收敛崩溃风险：`Stop` 超时后保留 joinable 线程，析构可触发 `std::terminate`

- 严重级别：`High`
- 影响：`Stop` 超时分支提前返回且不 `join`；若进入 `LibretroEngine` 析构，`std::thread gameThread_` 可能在 joinable 状态析构，触发进程级 `std::terminate`。
- 代码证据：
  - 析构调用 `Stop()`：`entry/src/main/cpp/core/engine/libretro_engine.cpp:221`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:222`
  - 超时提前返回（未 join）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:361`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:369`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:370`
  - `join()` 仅成功路径执行：`entry/src/main/cpp/core/engine/libretro_engine.cpp:373`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:374`
  - 线程成员：`entry/src/main/cpp/core/engine/libretro_engine.h:291`
- 官方/权威依据：
  - `std::thread::~thread`：对象析构时若仍 joinable，将调用 `std::terminate`。
  - 来源：<https://en.cppreference.com/w/cpp/thread/thread/~thread>
- 修复建议（后续实施）：
  - Stop 超时路径建立“线程善后”与“不可安全析构”保护分支，避免直接销毁 joinable 线程对象。
  - 析构前强制验证 `gameThread_` 非 joinable（join 或可控替代策略）。
  - 对 Stop 超时场景输出结构化错误并阻断危险退出路径。
- 验收标准：
  - Stop 超时场景下不会因析构触发 `std::terminate`。
  - 退出路径线程生命周期可观测且可证明收敛完成。

### P1-1 HiLog 格式规范一致性：存在未显式隐私标识的格式串

- 严重级别：`Medium`
- 影响：日志在 release 场景下可能与隐私/可见性策略不一致，降低日志规范一致性。
- 代码证据：
  - `entry/src/main/cpp/core/engine/libretro_engine.cpp:1628`
  - 当前格式：`"[Perf] Auto-skipping frame (audio usage=%.1f%%)"`
- 官方依据：
  - C/C++ HiLog 指南：格式参数应使用 `%{private flag}specifier`。
  - 来源：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hilog-guidelines-ndk>
- 修复建议（后续实施）：
  - 将浮点日志改为带显式可见性标识的写法（例如 `%{public}f`），并统一项目日志模板。
- 验收标准：
  - 业务代码不再出现无隐私标识的格式参数写法。
  - 与项目现有 `%{public}d/%{public}u/%{public}X` 规范不冲突。

### P1-2 安全治理缺口：`.gitignore` 未覆盖证书/密钥衍生文件

- 严重级别：`Medium`
- 影响：后续迭代中存在证书请求/密钥文件误提交风险。
- 代码证据：
  - `.gitignore` 当前内容：`.gitignore:1`
  - 本地存在待忽略样例：`harmony_ci_key.csr`
- 修复建议（后续实施）：
  - 在 `.gitignore` 增加最小必要规则（示例：`*.csr`, `*.pem`, `*.key`, `*.p12`）。
  - 如仓库已有加密流程，改用安全存储方案（Secrets/密钥库）并仅保留模板文件。
- 验收标准：
  - 常见证书/密钥文件默认不进入 `git status` 变更列表。
  - CI 签名材料只从受控密钥源注入，不在仓库存放明文敏感文件。

### P1-3 事件节流逻辑缺陷：`EventBridge` 合并缓存被删除但未发送

- 严重级别：`Medium`
- 影响：在限流/队列拥塞场景下，`pending_payload_` 可能被直接擦除，导致最后一次状态更新丢失（UI 看到旧状态）。
- 代码证据：
  - 限流时缓存 pending：`entry/src/main/cpp/core/engine/event_bridge.cpp:137`、`entry/src/main/cpp/core/engine/event_bridge.cpp:139`
  - 过窗口后仅擦除 pending：`entry/src/main/cpp/core/engine/event_bridge.cpp:146`、`entry/src/main/cpp/core/engine/event_bridge.cpp:148`
  - 队列满时同样缓存 pending：`entry/src/main/cpp/core/engine/event_bridge.cpp:157`、`entry/src/main/cpp/core/engine/event_bridge.cpp:161`
- 修复建议（后续实施）：
  - 命中 pending 时优先发送 pending payload，再清理缓存。
  - 仅在投递成功后删除 pending，避免“删了但没发”。
- 验收标准：
  - 节流场景下最终状态可稳定送达。
  - 不再存在 pending 仅删除不发送路径。

### P1-4 并发访问缺口：`EnvState` 核心选项容器跨线程读写未统一同步

- 严重级别：`Medium`
- 影响：引擎线程更新核心选项 definitions/categories 时，NAPI 线程并发读取（`GetCoreOptions`/`SetCoreOption`）可能访问到重分配中的容器，导致偶发崩溃或结果不一致。
- 代码证据：
  - NAPI 读取：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1061`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2029`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2031`
  - NAPI 写入（读取 definitions 校验）：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1070`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2024`、`entry/src/main/cpp/core/libretro/core_options_registry.cpp:199`
  - 引擎线程更新容器：`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:1288`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:1302`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:126`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:127`
- 修复建议（后续实施）：
  - 为 definitions/categories 增加统一读写锁，或改为不可变快照发布。
  - `GetCoreOptionsJson` 与 `SetCoreOption` 使用同一线程安全访问入口。
- 验收标准：
  - definitions/categories 不再出现并发无锁读写。
  - 核心加载期间并发调用选项接口行为稳定。

### P1-5 并发数据竞争：`DiskController` 回调表与弹仓状态跨线程访问无同步

- 严重级别：`Medium`
- 影响：引擎线程更新磁盘回调时，NAPI 线程可并发读/调 `callbacks_`，存在 UB 风险；`ejected_` 状态可见性可能漂移。
- 代码证据：
  - 字段定义：`entry/src/main/cpp/core/libretro/disk_controller.h:44`、`entry/src/main/cpp/core/libretro/disk_controller.h:46`
  - 引擎线程写回调：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1967`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1976`
  - NAPI 直调磁盘接口：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1587`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1610`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1619`
  - 读/写实现：`entry/src/main/cpp/core/libretro/disk_controller.cpp:12`、`entry/src/main/cpp/core/libretro/disk_controller.cpp:20`、`entry/src/main/cpp/core/libretro/disk_controller.cpp:34`、`entry/src/main/cpp/core/libretro/disk_controller.cpp:48`、`entry/src/main/cpp/core/libretro/disk_controller.cpp:53`
- 官方/权威依据：
  - C++ 内存模型：发生 data race 时行为未定义（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 为 `DiskController` 引入互斥锁，统一保护 `callbacks_ / ejected_`。
  - 或统一切换到 Engine 线程串行执行磁盘控制请求。
- 验收标准：
  - 并发“回调注册 + 磁盘控制调用”场景下无崩溃、无异常返回。

### P1-6 输入状态隔离缺口：`PluginManager` 使用全局静态输入状态，未按 `XComponent` 分桶

- 严重级别：`Medium`
- 影响：多实例/切页场景下，`mouseDown/hasFocus/last*` 在组件间共享，可能导致跨组件输入串扰与调试可观测性失真。
- 代码证据：
  - 全局静态状态定义：`entry/src/main/cpp/app/framework/plugin_manager.cpp:37`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:42`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:60`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:75`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:80`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:85`
  - 回调读写路径：`entry/src/main/cpp/app/framework/plugin_manager.cpp:533`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:541`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:565`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:577`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:639`
- 修复建议（后续实施）：
  - 以 `xcomponentId` 为键维护输入状态（`unordered_map<xId, InputState>`）。
  - 与 `NewArchWindowById` 对齐统一锁边界，避免状态/窗口映射锁语义漂移。
- 验收标准：
  - 并行 `XComponent` 场景下输入状态互不污染。
  - `GetNewArchInputStats` 可按组件维度定位问题。

### P1-7 生命周期收敛缺口：`StopEngineAsync` 使用 detached 线程且无完成态句柄

- 严重级别：`Medium`
- 影响：接口仅表示“已发起停止”，不表示“已完成停止”；Stop/Unload 与后续异步调用存在收敛窗口，生命周期可观测性不足。
- 代码证据：
  - detached 调用：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:684`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:692`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:698`
  - 停止收敛路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:325`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:358`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:377`
- 官方/权威依据：
  - OpenHarmony N-API 异步工作模型（`napi_create_async_work`/`napi_queue_async_work`）：<https://gitee.com/openharmony/arkui_napi/blob/master/interfaces/kits/napi/native_api.h>
  - Node-API 简单异步操作建议使用 `napi_create_async_work`：<https://nodejs.org/api/n-api.html#simple-asynchronous-operations>
- 修复建议（后续实施）：
  - 将 Stop 异步化改为 `napi_async_work` + Promise 完成态，resolve 时机对齐 `EngineState::STOPPED`。
  - 与 `SwitchGameAsync` 建立统一生命周期门禁（token/singleflight + state gate）。
- 验收标准：
  - 调用方可可靠等待 Stop 完成，不再依赖“先发起再轮询”的隐式约定。

### P1-8 可恢复性缺口：`Stop` 超时后 `Start` 被阻断且缺少 NAPI 恢复通道

- 严重级别：`Medium`
- 影响：`Stop` 超时置位 `stopTimedOut_` 后，`Start` 会被直接拒绝；但 JS 层无 `ResetEngine` 类接口，前台恢复路径不足。
- 代码证据：
  - Stop 超时置位并返回：`entry/src/main/cpp/core/engine/libretro_engine.cpp:362`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:369`
  - Start 阻断：`entry/src/main/cpp/core/engine/libretro_engine.cpp:277`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:278`
  - `Reset()` 可清标记但未导出：`entry/src/main/cpp/core/engine/libretro_engine.cpp:396`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1675`、`entry/src/main/cpp/types/libentry/index.d.ts:24`
- 官方/权威依据：
  - Node-API / OpenHarmony N-API 异步工作模型强调可管理的异步完成态与可观测错误反馈。
  - 来源：<https://nodejs.org/api/n-api.html#simple-asynchronous-operations>、<https://gitee.com/openharmony/arkui_napi/blob/master/interfaces/kits/napi/native_api.h>
- 修复建议（后续实施）：
  - 暴露 `refactoredResetEngine` 等恢复接口。
  - `StopEngine/StopEngineAsync` 返回值区分“成功停止”与“超时失败”。
  - 在 `GetLastErrorInfo` 增加 stop timeout 结构化错误码。
- 验收标准：
  - stop timeout 后可通过公开 API 恢复到可启动状态。
  - 前台可感知失败原因并执行恢复策略。

### P1-9 输入路由一致性缺陷：端口重绑定后旧 `deviceId` 映射未清理

- 严重级别：`Medium`
- 影响：`AssignPort` 重绑定端口时仅写入新映射，不删除旧 `deviceId -> port` 条目；`ResolvePortForDevice` 快路径缺少一致性校验，导致旧设备可能继续命中新端口（输入串线）。
- 代码证据：
  - 重绑定只增不删：`entry/src/main/cpp/core/engine/input_port_router.cpp:77`、`entry/src/main/cpp/core/engine/input_port_router.cpp:78`、`entry/src/main/cpp/core/engine/input_port_router.cpp:80`、`entry/src/main/cpp/core/engine/input_port_router.cpp:81`
  - 快路径缺少 `deviceId/sourceType` 校验：`entry/src/main/cpp/core/engine/input_port_router.cpp:148`、`entry/src/main/cpp/core/engine/input_port_router.cpp:149`、`entry/src/main/cpp/core/engine/input_port_router.cpp:151`、`entry/src/main/cpp/core/engine/input_port_router.cpp:152`
- 修复建议（后续实施）：
  - 端口重绑定前先移除旧设备映射。
  - `ResolvePortForDevice` 快路径增加映射一致性校验。
  - 增加“`A->0` 后 `B->0`，A 不再命中 0”回归用例。
- 验收标准：
  - 不再出现陈旧 `deviceToPort_` 映射。
  - 多设备重绑定/热插拔下输入路由稳定正确。

### P1-10 并发访问缺口：`AudioBridge` 统计读取与 `Reset/Stop` 共享状态无统一锁边界

- 严重级别：`Medium`
- 影响：`GetBufferUsage/GetBufferStats/IsPlaying` 无锁读取 `ring_buffer_ / audio_player_`，而 `Reset/Stop` 在另一线程重置同一成员，存在 data race 风险。
- 代码证据：
  - 无锁读取：`entry/src/main/cpp/platform/audio/audio_bridge.cpp:626`、`entry/src/main/cpp/platform/audio/audio_bridge.cpp:634`、`entry/src/main/cpp/platform/audio/audio_bridge.cpp:642`
  - 锁内重置/释放：`entry/src/main/cpp/platform/audio/audio_bridge.cpp:508`、`entry/src/main/cpp/platform/audio/audio_bridge.cpp:534`、`entry/src/main/cpp/platform/audio/audio_bridge.cpp:539`、`entry/src/main/cpp/platform/audio/audio_bridge.cpp:541`
  - 读取入口（NAPI）：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1291`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1293`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1297`
- 官方/权威依据：
  - `std::shared_ptr` 线程安全说明：同一 `shared_ptr` 对象被并发读写需要同步。
  - 来源：<https://en.cppreference.com/w/cpp/memory/shared_ptr>
  - C++ data race/UB：<https://en.cppreference.com/w/cpp/language/multithread>
- 修复建议（后续实施）：
  - 为统计读取接口补齐与 `Reset/Stop` 一致的锁边界。
  - 或改为统一快照发布，避免“原子标志 + 非原子指针”混合判定。
- 验收标准：
  - 指针成员不再出现无锁跨线程读写。
  - 并发 `GetStats + Stop/Reset` 场景下稳定无崩溃、无异常值。

### P1-11 输入路由一致性缺陷：`Blur` 回调固定向 `port=0` 发送 Pointer 抬起

- 严重级别：`Medium`
- 影响：鼠标事件路径按 `deviceId` 解析目标端口发送 Pointer；但 `Blur` 回调固定发送到 `port=0`，在鼠标映射到非 0 端口时可能导致真实端口按下态残留。
- 代码证据：
  - 鼠标事件按设备解析端口：`entry/src/main/cpp/app/framework/plugin_manager.cpp:526`
  - 鼠标事件按解析端口发送：`entry/src/main/cpp/app/framework/plugin_manager.cpp:542`
  - Blur 回调固定发到 `port=0`：`entry/src/main/cpp/app/framework/plugin_manager.cpp:573`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:579`
- 官方/权威依据：
  - libretro 输入查询以玩家端口 `port` 为维度（`Which player 'port' to query`）。
  - 来源：<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - Blur 回调按当前鼠标设备映射端口发送 release。
  - 无法解析端口时兜底清理所有鼠标绑定端口。
- 验收标准：
  - Blur 后 release 与当前鼠标映射端口一致。
  - 非 0 端口映射场景无 stuck pressed。

### P1-12 输入路由一致性缺陷：触摸事件固定发送到 `port=0`，绕过端口解析

- 严重级别：`Medium`
- 影响：触摸路径直接 `SendPointer(0, ...)`，未按设备映射解析端口；在多端口映射场景下会把触摸输入错误路由到 `port0`。
- 代码证据：
  - 触摸路径固定 `port=0`：`entry/src/main/cpp/app/framework/plugin_manager.cpp:489`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:490`
  - 键盘路径先解析端口再发送：`entry/src/main/cpp/app/framework/plugin_manager.cpp:232`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:238`
  - 鼠标路径先解析端口再发送：`entry/src/main/cpp/app/framework/plugin_manager.cpp:526`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:542`
- 官方/权威依据：
  - libretro 输入查询接口按 `port` 维度定义玩家输入语义（`retro_input_state_t(unsigned port, ...)`）。
  - 来源：<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - 为触摸路径补齐与键盘/鼠标一致的端口解析流程。
  - 无法解析端口时使用显式降级策略，避免隐式硬编码 `0`。
- 验收标准：
  - 触摸输入在多端口映射场景可按配置路由。
  - 触摸/键盘/鼠标三条路径端口语义一致。

### P1-13 线程边界缺口：`g_engineInstance` 全局裸指针跨线程读写无同步

- 严重级别：`Medium`
- 影响：全局桥接指针在构造/析构写入、回调线程读取均无同步；在 Stop 超时与析构交错窗口可引发 data race（UB）与悬空访问风险。
- 代码证据：
  - 全局静态指针定义：`entry/src/main/cpp/core/engine/libretro_engine.cpp:30`
  - 写入点（构造/析构）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:186`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:223`
  - 回调读取点：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1584`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1776`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1860`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:203`
- 官方/权威依据：
  - C++ 内存模型：缺少同步的并发读写属于 data race，行为未定义。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread>
- 修复建议（后续实施）：
  - 将桥接实例句柄改为线程安全发布/读取模型（原子指针或统一锁边界）。
  - 在 Stop/析构阶段增加回调不可见屏障，确保对象销毁前后可见性一致。
- 验收标准：
  - 回调桥接实例不存在无同步并发读写路径。
  - Stop/析构交错场景无 UB 或悬空访问。

### P1-14 线程边界缺口：`InputManager::g_instance` 全局裸指针跨线程读写无同步

- 严重级别：`Medium`
- 影响：输入回调桥 `g_instance` 在构造/析构写入、在 `OnInputState/OnRumble/OnSensor*` 回调读取均缺少同步；生命周期交错时存在 data race（UB）风险。
- 代码证据：
  - 指针定义与写入：`entry/src/main/cpp/core/engine/input_manager.cpp:77`、`entry/src/main/cpp/core/engine/input_manager.cpp:81`、`entry/src/main/cpp/core/engine/input_manager.cpp:87`
  - 回调读取：`entry/src/main/cpp/core/engine/input_manager.cpp:203`、`entry/src/main/cpp/core/engine/input_manager.cpp:252`、`entry/src/main/cpp/core/engine/input_manager.cpp:267`、`entry/src/main/cpp/core/engine/input_manager.cpp:280`
  - 上层线程/成员顺序（异常收敛时放大风险）：`entry/src/main/cpp/core/engine/libretro_engine.h:291`、`entry/src/main/cpp/core/engine/libretro_engine.h:307`
- 官方/权威依据：
  - C++ 内存模型：缺少同步的并发读写属于 data race，行为未定义。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread>
- 修复建议（后续实施）：
  - 将输入回调桥接指针改为线程安全发布/读取模型（原子指针或统一锁边界）。
  - 在 Stop/析构阶段增加输入回调不可见屏障，保证销毁前后可见性一致。
- 验收标准：
  - 输入回调桥不存在无同步并发读写路径。
  - Stop/析构交错场景下输入回调行为稳定，无 UB。

### P1-15 安全边界缺口：`testCoreLoader` 在 `corePath` allowlist 校验前直接读文件

- 严重级别：`Medium`
- 影响：`testCoreLoader` 先执行 `ReadNeededLibrariesFromElf(corePath)` 直接 `open/read`，后续才进入 `CoreLoader::LoadCore` 的 `ValidateCorePath` 校验；测试路径与正式加载路径安全边界不一致。
- 代码证据：
  - 预读取入口（校验前）：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:291`
  - 预读取直接文件访问：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:33`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:35`
  - 正式加载路径校验（对照）：`entry/src/main/cpp/core/libretro/core_loader.cpp:85`
- 官方/权威依据：
  - CWE-22（路径遍历/受限目录边界问题）：<https://cwe.mitre.org/data/definitions/22.html>
- 修复建议（后续实施）：
  - 在 `testCoreLoader` 入口先复用 `security::ValidateCorePath`，未通过则立即返回。
  - 仅在校验通过后执行 NEEDED 预解析。
  - 避免同一路径出现“测试入口绕过、正式入口校验”的双重安全语义。
- 验收标准：
  - 所有 `corePath` 文件访问都经过统一 allowlist 校验。
  - 测试入口与正式加载入口的路径安全边界一致。

### P1-16 解析健壮性缺口：`CoreLoaderNapi` ELF 解析缺少边界与字符串终止校验

- 严重级别：`Medium`
- 影响：异常/损坏 ELF 输入下，`ReadNeededLibrariesFromElf` 可能越界读取程序头/动态段，且 `DT_NEEDED` 读取默认假设 NUL 终止，存在崩溃/DoS 风险。
- 代码证据：
  - 程序头边界未校验直接访问：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:140`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:141`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:198`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:199`
  - 动态段边界未校验直接访问：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:155`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:157`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:213`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:215`
  - `DT_NEEDED` 名称构造缺少边界终止校验：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:183`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:241`
- 官方/权威依据：
  - ELF 结构偏移/表项语义：<https://man7.org/linux/man-pages/man5/elf.5.html>
  - `std::basic_string(const CharT*)` 对无效范围行为未定义：<https://en.cppreference.com/w/cpp/string/basic_string/basic_string>
- 修复建议（后续实施）：
  - 为 `e_phoff/e_phnum/e_phentsize`、`dyn_offset/dyn_size` 增加溢出与范围校验。
  - 读取 `DT_NEEDED` 时使用显式边界扫描后再构造字符串。
  - 异常 ELF 直接返回结构化错误，不进入后续解析循环。
- 验收标准：
  - 损坏/截断 ELF 输入不会触发越界访问或崩溃。
  - `DT_NEEDED` 读取严格受文件边界约束。

### P1-17 生命周期缺口：`PlatformResourceManager` 持久缓存 `NativeResourceManager*`，Release 后存在悬空访问窗口

- 严重级别：`Medium`
- 影响：`NativeResourceManager*` 在短流程中初始化并释放后，仍被单例成员持有；后续路径可能继续使用已释放句柄，存在崩溃/未定义行为风险。
- 代码证据：
  - 初始化与释放：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:62`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:88`
  - 写入单例成员：`entry/src/main/cpp/platform/resource/rom_loader.cpp:58`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:56`
  - 后续读取使用：`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:94`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:147`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:198`
  - 后续仍可能走该单例路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1147`
- 官方/权威依据：
  - `OH_ResourceManager_InitNativeResourceManager` / `OH_ResourceManager_ReleaseNativeResourceManager`（Release 释放 native ResourceManager）。
  - 来源：<https://developer.huawei.com/consumer/en/doc/harmonyos-references/capi-raw-file-manager-h>
  - OpenHarmony Rawfile API 参考（同组 API 生命周期语义）。
  - 来源：<https://gitee.com/openharmony/docs/raw/6504327caf2e1fbd10998a3994c717b6ea3efe33/en/application-dev/reference/apis-localization-kit/rawfile.md>
- 修复建议（后续实施）：
  - 禁止在单例中持久缓存借用态 `NativeResourceManager*`，改为调用链显式传递或 RAII 封装。
  - 若保留成员缓存，明确所有权并在 Release 后立即置空，禁止后续复用。
- 验收标准：
  - 不再存在 Release 后继续访问该句柄的路径。
  - `NativeResourceManager` 生命周期与调用链一致、可证明收敛。

### P1-18 并发访问缺口：`PlatformResourceManager` 对 `native_resource_manager_` 存在“锁内写 + 锁外读”

- 严重级别：`Medium`
- 影响：`Initialize` 锁内写成员，而 `GetRawFileList/ListDir` 锁外读成员并进入 rawfile API，存在 data race 风险与并发行为不确定性。
- 代码证据：
  - 写入（加锁）：`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:55`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:56`
  - 读取（无锁）：`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:142`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:147`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:198`
  - 互斥体定义：`entry/src/main/cpp/platform/resource/platform_resource_manager.h:54`
- 官方/权威依据：
  - OpenHarmony Rawfile 文档：rawfile APIs 非线程安全（仅 open/close 线程安全）。
  - 来源：<https://gitee.com/openharmony/docs/raw/6504327caf2e1fbd10998a3994c717b6ea3efe33/en/application-dev/reference/apis-localization-kit/rawfile.md>
  - C++ 内存模型：data race 属于未定义行为（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 统一 `native_resource_manager_` 读写锁边界。
  - 对 rawfile 非线程安全路径建立串行访问策略。
- 验收标准：
  - 消除 `native_resource_manager_` 的“锁内写 + 锁外读”混用。
  - 并发目录枚举/读取场景稳定无竞态告警。

### P1-19 并发访问缺口：`EnvState` 目录字符串在 `SetFilesDir` 与 `GetFilesDir` 间无统一同步

- 严重级别：`Medium`
- 影响：运行态下 `SetFilesDir` 通过消息队列在引擎线程异步写入 `EnvState` 目录字符串，NAPI 线程可并发读取 `GetFilesDir`，存在 data race（UB）与路径读取不一致风险。
- 代码证据：
  - 目录字段与无锁 getter/setter：`entry/src/main/cpp/core/libretro/env_dispatcher.h:22`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:26`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:32`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:202`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:208`
  - 引擎线程写入：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1262`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:620`
  - NAPI 线程读取：`entry/src/main/cpp/core/engine/libretro_engine.cpp:761`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:68`
  - 运行态异步入队入口：`entry/src/main/cpp/core/engine/libretro_engine.cpp:741`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:746`
- 官方/权威依据：
  - C++ 内存模型：data race 属于未定义行为（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
  - Libretro 线程安全声明：API 不保证线程安全。
  - 来源：<https://docs.libretro.com/development/cores/developing-cores/>
- 修复建议（后续实施）：
  - 为目录字符串建立统一读写锁边界，或改为不可变快照 + 原子发布。
  - `GetFilesDir` 返回受保护快照，避免直接读取可变内部字符串。
  - 明确 `SetFilesDir` 与 rawfile 路径访问的线程边界。
- 验收标准：
  - 并发调用 `SetFilesDir`/rawfile 装载时无 data race 告警。
  - `filesDir` 读取结果稳定一致。

### P1-20 时序一致性缺口：`SetFilesDir` 异步生效与 `LoadRom` 预处理读取旧目录存在竞态

- 严重级别：`Medium`
- 影响：运行态 `SetFilesDir` 仅表示“消息已入队”，目录实际生效滞后于引擎线程处理；若随即调用 `LoadRom`（rawfile 路径），NAPI 预处理可能读取旧 `filesDir`，导致 ROM 解包目录与会话目录不一致。
- 代码证据：
  - 运行态 `SetFilesDir` 入队后即返回：`entry/src/main/cpp/core/engine/libretro_engine.cpp:741`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:746`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:751`
  - 实际生效点（引擎线程消息处理）：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1262`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1270`
  - `LoadRom` NAPI 预处理读取当前目录：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:348`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:366`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:68`
- 官方/权威依据：
  - Libretro 线程模型强调前端应保持调用顺序与生命周期一致性，避免并发无序调用引入不确定行为。
  - 来源：<https://docs.libretro.com/development/cores/developing-cores/>
- 修复建议（后续实施）：
  - 为 `SetFilesDir` 增加“生效确认”语义（ack/等待处理完成）后再返回成功。
  - 或要求 `LoadRom` 传入显式 `filesDirOverride`，避免依赖异步可变全局目录。
  - 对 `SetFilesDir -> LoadRom` 连续调用增加顺序屏障。
- 验收标准：
  - 连续调用 `SetFilesDir` 后立即 `LoadRom`，解包目录始终与最新配置一致。
  - 链路行为不再依赖线程调度时序。

### P1-21 生命周期收敛缺口：`SwitchGameAsync` 预处理失败仍推进 `switch_token`，可误取消在途切换

- 严重级别：`Medium`
- 影响：`SwitchGameAsync` 在预处理前更新全局 token；若预处理失败直接返回，已在执行中的旧 token 会被判定过期并提前退出，可能留下半状态。
- 代码证据：
  - 预处理前推进 token：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:621`
  - 预处理失败直接返回：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:625`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:628`
  - 过期 token 早退（无恢复）路径：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:464`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:483`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:500`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:517`
- 官方/权威依据：
  - libretro 生命周期要求前端保持可预期状态收敛与资源释放顺序。
  - 来源：<https://docs.libretro.com/development/cores/developing-cores/>、<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - 将 `switch_token.store(token)` 延后到预处理成功后。
  - 为 token 过期分支补齐统一恢复/收敛策略，避免半状态退出。
- 验收标准：
  - 无效后续请求不会取消有效在途切换。
  - token 过期退出后引擎状态可预测且可恢复。

### P1-22 功能兼容性缺口：已接收 `RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK` 但未向 core 转发键盘事件

- 严重级别：`Medium`
- 影响：依赖 keyboard callback 的 core（家用电脑/文本输入类）无法收到标准键盘事件，兼容性下降。
- 代码证据：
  - 回调注册保存：`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:831`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:839`
  - 保存结构与 getter：`entry/src/main/cpp/core/libretro/env_dispatcher.h:138`、`entry/src/main/cpp/core/libretro/env_dispatcher.h:143`
  - 键盘事件当前仅映射 Joypad：`entry/src/main/cpp/app/framework/plugin_manager.cpp:185`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:238`
- 官方/权威依据：
  - libretro 标准说明 keyboard callback 由 frontend 在键盘事件时调用。
  - 来源：<https://raw.githubusercontent.com/libretro/libretro-common/master/include/libretro.h>
- 修复建议（后续实施）：
  - 在键盘事件入口补齐到 `retro_keyboard_callback` 的转发桥接（down/up、keycode、character、modifiers）。
  - Joypad 映射保留为兼容路径，但不替代标准 keyboard callback。
- 验收标准：
  - core 注册 keyboard callback 后可收到成对键盘事件。
  - 相关核心文本输入/按键功能可用。

### P1-23 数据一致性缺口：`EngineMessage` 固定 512 字节路径导致 `LoadCore/LoadRom/SetFilesDir` 静默截断

- 严重级别：`Medium`
- 影响：NAPI 层接受的路径（最多 1023 字节）进入消息队列后会被静默截断为 511 字节，造成“调用方输入路径”与“引擎执行路径”不一致，长路径场景下易出现隐蔽加载失败/目录错配。
- 代码证据：
  - NAPI 入口 1024 缓冲：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:337`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:356`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1096`
  - 消息载荷固定 512 与截断复制：`entry/src/main/cpp/core/engine/engine_messages.h:41`、`entry/src/main/cpp/core/engine/engine_messages.h:90`、`entry/src/main/cpp/core/engine/engine_messages.h:92`
  - 引擎消费截断路径：`entry/src/main/cpp/core/engine/libretro_engine.cpp:955`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1039`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1270`
- 官方/权威依据：
  - Node-API `napi_get_value_string_utf8`：缓冲不足时会发生截断；当前入口上限与消息层上限不一致会引入中间层数据丢失。
  - 来源：<https://r2.nodejs.org/docs/latest-v10.x/api/all.html#napi_get_value_string_utf8>
  - POSIX 路径长度并非固定 512，硬编码 512 作为消息层上限缺乏依据。
  - 来源：<https://man7.org/linux/man-pages/man3/realpath.3.html>
- 修复建议（后续实施）：
  - 优先将消息路径字段改为 `std::string`（或等效堆对象）避免静默截断。
  - 若保留定长数组，需与入口上限统一并在超限时显式报错（禁止静默截断）。
- 验收标准：
  - 任意被 NAPI 接受的路径在引擎消费侧保持字节级一致。
  - 超限输入返回明确错误，不再出现静默截断。

### P1-24 同步语义缺口：`VulkanPresenter::WaitSyncIndex` 使用 1 秒超时返回，可能在前端未完成时允许 core 复用图像

- 严重级别：`Medium`
- 影响：`wait_sync_index` 在 `VK_TIMEOUT` 时仅记录日志并返回；core 侧会把“回调返回”视为可继续复用图像/资源，可能在前端 GPU 工作未完成时触发并发访问，导致画面损坏或不稳定。
- 代码证据：
  - 1 秒超时等待并在超时后继续返回：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:342`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:353`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:355`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:360`
- 官方/权威依据：
  - libretro Vulkan 接口语义：图像在 `wait_sync_index` 完成前不得被 core 触碰。
  - 来源：`entry/src/main/cpp/core/libretro/libretro_vulkan.h:353`、`entry/src/main/cpp/core/libretro/libretro_vulkan.h:374`
  - Vulkan 规范：`vkWaitForFences` 返回 `VK_TIMEOUT` 表示等待条件未满足。
  - 来源：<https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/vkWaitForFences.html>
- 修复建议（后续实施）：
  - `wait_sync_index` 必须“完成再返回”：使用无穷等待或循环等待到成功；`VK_ERROR_DEVICE_LOST` 进入结构化错误态。
  - 保留超时日志可作为诊断，但不应提前放行 core 复用。
- 验收标准：
  - `WaitSyncIndex()` 仅在 fence 完成后返回（或进入明确错误态）。
  - 压力场景下不再出现“超时后继续复用”的同步违约行为。

### P1-25 队列语义缺口：`VulkanPresenter` 固定使用 graphics queue 调用 `present`，忽略 negotiation 提供的 `presentation_queue`

- 严重级别：`Medium`
- 影响：当 core 通过 Vulkan negotiation 提供独立 `presentation_queue` 时，前端仍在 graphics queue 上执行 `vkQueuePresentKHR`，可能导致 present 失败或渲染链路不稳定。
- 代码证据：
  - `VulkanContext` 已维护并暴露 `present_queue`：`entry/src/main/cpp/platform/graphics/vulkan_context.h:30`、`entry/src/main/cpp/platform/graphics/vulkan_context.cpp:271`、`entry/src/main/cpp/platform/graphics/vulkan_context.cpp:315`
  - `VulkanPresenter` 初始化仅取 `GetQueue()`：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:54`
  - `vkQueuePresentKHR` 固定使用 `queue_`：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:490`
- 官方/权威依据：
  - Vulkan 规范：`vkQueuePresentKHR` 传入队列必须支持向目标 surface presentation。
  - 来源：<https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/vkQueuePresentKHR.html>
  - libretro Vulkan negotiation 语义：当主队列不支持 presentation 时，core 可提供单独 `presentation_queue`。
  - 来源：<https://github.com/libretro/libretro-common/blob/master/include/libretro_vulkan.h>
- 修复建议（后续实施）：
  - `VulkanPresenter` 增加 `present_queue_` 并从 `VulkanContext::GetPresentQueue()` 初始化。
  - `queue_submit` 保持 graphics queue，`queue_present_khr` 改用 present queue。
- 验收标准：
  - 独立 present queue 场景下 `vkQueuePresentKHR` 稳定成功，不再因队列选择错误失败。

### P1-26 并发边界缺口：`Present()` 解锁后继续使用 `FrameState*`，与 `frames_` 并发改写/resize 存在 UB 风险

- 严重级别：`Medium`
- 影响：`Present()` 在锁内获取 `FrameState*` 后解锁继续访问；并发路径可在锁内重写或 `resize(frames_)`，可能触发悬垂指针、数据竞争与偶发崩溃。
- 代码证据：
  - `Present()` 取指针后解锁并继续访问：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:147`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:154`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:162`
  - `SetSyncIndexMask -> EnsureFrameSlots` 可 `resize(frames_)`：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:173`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:378`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:392`
  - 并发重写帧状态：`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:301`、`entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp:325`
- 官方/权威依据：
  - libretro Vulkan 接口强调线程友好，core 可在任意线程构建/提交命令。
  - 来源：<https://github.com/libretro/libretro-common/blob/master/include/libretro_vulkan.h>
  - `std::vector` 重分配会使元素引用/指针失效。
  - 来源：<https://en.cppreference.com/w/cpp/container/vector>
  - C++ data race 属于未定义行为（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread>
- 修复建议（后续实施）：
  - 为 `Present/SetSyncIndexMask/SetImage/SetCommandBuffers` 建立统一并发协议；禁止“解锁后持有 `frames_` 元素裸指针”。
  - 优先采用锁内快照+锁外只读副本，或稳定地址容器+细粒度锁。
- 验收标准：
  - 不再存在解锁后访问 `frames_` 元素裸指针路径。
  - 并发 Vulkan 压力场景下无随机崩溃/同步状态错乱。

### P2-1 并发可见性问题：`GetAVInfo` 读取 AV 字段与引擎线程写入未同步

- 严重级别：`Low`
- 影响：`GetAVInfo` 可能读取到不一致快照（宽高/FPS/采样率组合异常），在部分平台存在 `double` 读撕裂风险。
- 代码证据：
  - 字段与 getter：`entry/src/main/cpp/core/engine/libretro_engine.h:191`、`entry/src/main/cpp/core/engine/libretro_engine.h:193`、`entry/src/main/cpp/core/engine/libretro_engine.h:351`、`entry/src/main/cpp/core/engine/libretro_engine.h:355`
  - 引擎线程写入：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1195`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1199`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1201`
  - NAPI 读取：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1462`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1470`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1476`
- 官方/权威依据：
  - C++ 内存模型：发生 data race 时行为未定义（UB）。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 使用原子字段或互斥锁返回一致性 AV 快照。
- 验收标准：
  - 高频并发查询 AV 信息时，结果稳定且字段间一致。

### P2-2 线程边界硬化：`env_dispatcher` 全局静态回调状态缺少显式同步与归属约束

- 严重级别：`Low`
- 影响：`g_rumble_cb/g_sensor_*/g_hw_framebuffer_cb` 依赖隐式线程模型；当前可工作但边界未代码化，后续并发模型演进时有引入 UB 风险。
- 代码证据：
  - 全局静态状态与访问：`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:501`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:502`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:503`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:504`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:519`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:536`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:543`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:558`
  - 注册写入：`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:507`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:508`、`entry/src/main/cpp/core/libretro/env_dispatcher.cpp:513`
  - 上层绑定点：`entry/src/main/cpp/core/engine/libretro_engine.cpp:1400`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:1403`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:202`
- 官方/权威依据：
  - Libretro 线程安全声明：<https://docs.libretro.com/development/cores/developing-cores/>
  - C++ data race/UB：<https://en.cppreference.com/w/cpp/language/multithread>
- 修复建议（后续实施）：
  - 显式声明并断言“Engine 线程归属”；如需跨线程访问则改为原子句柄或互斥保护。
  - 在 Stop/Unload 增加回调可见性收敛屏障。
- 验收标准：
  - 回调状态线程边界清晰且可验证，不依赖隐式约定。

### P2-3 可观测性缺口：主 `XComponent` 回调注册未检查返回值

- 严重级别：`Low`
- 影响：主回调注册失败时仍可能继续流程并输出“已注册”日志，导致 Surface/Touch 生命周期链路异常时缺少即时错误信号。
- 代码证据：
  - 未检查返回值：`entry/src/main/cpp/app/framework/plugin_manager.cpp:495`
  - 紧随其后的成功日志：`entry/src/main/cpp/app/framework/plugin_manager.cpp:496`
  - 对比：鼠标/焦点/键盘注册均有返回值检查：`entry/src/main/cpp/app/framework/plugin_manager.cpp:553`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:561`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:573`、`entry/src/main/cpp/app/framework/plugin_manager.cpp:588`
- 官方/权威依据：
  - `OH_NativeXComponent_RegisterCallback` 返回 `int32_t` 状态码（`SUCCESS/FAILED/BAD_PARAMETER`）。
  - 来源：<https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/native__interface__xcomponent_8h-V13>
- 修复建议（后续实施）：
  - 主回调注册结果与鼠标/焦点/键盘保持一致的错误处理策略。
- 验收标准：
  - 主回调注册失败时可观测、可定位，不再误报成功。

### P2-4 异常安全缺口：`Start` 中 `startInProgress_` 缺少异常路径兜底复位

- 严重级别：`Low`
- 影响：`Start` 通过 `startInProgress_.exchange(true)` 建立并发门禁，但主要依赖手工 `store(false)` 复位；若中途抛异常（如线程创建失败），门禁可能粘死，后续启动持续被拒绝。
- 代码证据：
  - 置位：`entry/src/main/cpp/core/engine/libretro_engine.cpp:268`
  - 线程创建：`entry/src/main/cpp/core/engine/libretro_engine.cpp:295`
  - 正常复位：`entry/src/main/cpp/core/engine/libretro_engine.cpp:297`
  - 仅部分显式分支复位：`entry/src/main/cpp/core/engine/libretro_engine.cpp:274`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:279`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:284`
- 官方/权威依据：
  - `std::thread` 构造失败会抛 `std::system_error`。
  - 来源：<https://en.cppreference.com/w/cpp/thread/thread/thread>
  - `std::system_error` 定义：<https://en.cppreference.com/w/cpp/error/system_error>
- 修复建议（后续实施）：
  - 用 RAII 守卫统一管理 `startInProgress_` 复位，覆盖异常/早退路径。
- 验收标准：
  - 线程创建失败后 `startInProgress_` 能自动复位，启动可重试。

### P2-5 状态通知一致性缺口：`Reset` 直接写 `INIT` 绕过 `TransitionTo`

- 严重级别：`Low`
- 影响：`Reset` 直接 `state_.store(INIT)`，不会触发 `stateCond_.notify_all()` 与 `engine_state` 事件，导致等待/订阅链路与其他状态迁移不一致。
- 代码证据：
  - 直接写状态：`entry/src/main/cpp/core/engine/libretro_engine.cpp:424`
  - 等待依赖条件变量：`entry/src/main/cpp/core/engine/libretro_engine.cpp:2164`
  - `TransitionTo` 负责 notify + event：`entry/src/main/cpp/core/engine/libretro_engine.cpp:2115`、`entry/src/main/cpp/core/engine/libretro_engine.cpp:2123`
- 官方/权威依据：
  - `condition_variable::wait_for` 依赖 notify/超时/伪唤醒唤起等待方。
  - 来源：<https://en.cppreference.com/w/cpp/thread/condition_variable/wait_for>
- 修复建议（后续实施）：
  - Reset 场景统一走 `TransitionTo(EngineState::INIT)`，或补齐同等通知与事件语义。
- 验收标准：
  - Reset 后等待 `INIT` 的调用可及时返回。
  - Reset 场景 `engine_state` 事件流保持一致。

### P2-6 异常路径收口缺口：`SwitchGameAsync/WaitForStateAsync` 未检查 async work 创建/入队返回值

- 严重级别：`Low`
- 影响：`napi_create_async_work` / `napi_queue_async_work` 失败时可能导致 Promise 悬挂、上下文对象泄漏，调用侧缺少明确失败信号。
- 代码证据：
  - `SwitchGameAsync` 未检查返回值：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:646`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:648`
  - `WaitForEngineStateAsync` 未检查返回值：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1024`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1026`
  - Promise 创建同样未做失败收口：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:641`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1019`
- 官方/权威依据：
  - OpenHarmony `native_api.h` 以 `napi_status` 返回 N-API 调用结果，并包含 `node_api.h`。
  - 来源：<https://gitee.com/openharmony/arkui_napi/raw/master/interfaces/kits/napi/native_api.h>
  - Node-API 头文件中 `napi_create_async_work` / `napi_queue_async_work` 均返回 `napi_status`。
  - 来源：<https://raw.githubusercontent.com/nodejs/node/v22.13.1/src/node_api.h>
  - Node-API 文档（simple asynchronous operations）：<https://nodejs.org/api/n-api.html#simple-asynchronous-operations>
- 修复建议（后续实施）：
  - 对 `napi_create_promise` / `napi_create_async_work` / `napi_queue_async_work` 全量校验返回值。
  - 失败时统一释放上下文并返回可观测失败结果（resolve/reject）。
- 验收标准：
  - 异步任务创建/入队失败时 Promise 不会悬挂。
  - 无上下文泄漏路径。

### P2-7 异常安全缺口：`StopEngineAsync` 线程创建失败时 `stop_in_progress` 可能粘死

- 严重级别：`Low`
- 影响：`StopEngineAsync` 先置位 `stop_in_progress=true` 再创建线程；若线程创建抛异常，门禁位可能无法复位，后续停止请求被持续忽略。
- 代码证据：
  - 门禁位定义：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:35`
  - 先置位再建线程：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:687`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:692`
  - 正常复位仅在线程函数尾部：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:697`
  - 异常路径宏未复位门禁：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:93`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:103`
- 官方/权威依据：
  - `std::thread` 构造失败会抛 `std::system_error`。
  - 来源：<https://en.cppreference.com/w/cpp/thread/thread/thread>
  - `std::system_error` 定义：<https://en.cppreference.com/w/cpp/error/system_error>
- 修复建议（后续实施）：
  - 以 RAII 守卫统一管理 `stop_in_progress`，覆盖异常/早退路径。
  - 或显式 catch 线程创建异常并立即复位门禁。
- 验收标准：
  - 线程创建失败后 `stop_in_progress` 一定复位。
  - `StopEngineAsync` 失败后可继续重试。

### P2-8 状态分流缺口：NAPI async complete 回调忽略 `napi_status`

- 严重级别：`Low`
- 影响：`SwitchGameAsync/WaitForEngineStateAsync` 的 complete 回调忽略 `status` 并统一 `resolve`，会把“任务取消/宿主失败”混同为业务 `false`，调用侧无法区分失败类型。
- 代码证据：
  - complete 回调参数未使用：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:537`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:963`
  - 无条件 resolve：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:545`、`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:971`
- 官方/权威依据：
  - Node-API async complete 回调接收 `napi_status`，取消路径会以 `napi_cancelled` 进入 complete 回调。
  - 来源：<https://nodejs.org/api/n-api.html#simple-asynchronous-operations>
  - 来源：<https://nodejs.org/api/n-api.html#napi_cancel_async_work>
- 修复建议（后续实施）：
  - 按 `status` 分支处理：`napi_ok` 走业务结果；非 `napi_ok`（尤其 `napi_cancelled`）走 reject/结构化错误。
  - 补充取消与宿主异常日志，避免被业务返回值吞没。
- 验收标准：
  - JS 侧可区分“业务失败”与“异步取消/宿主失败”。
  - complete 回调不再无条件 resolve。

### P2-9 可观测性缺口：`napi_define_properties` 返回值未检查

- 严重级别：`Low`
- 影响：NAPI 导出注册失败时仍可能打印“注册成功”日志，导致导出缺失与日志状态不一致，排障成本上升。
- 代码证据：
  - 未检查返回值：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1794`
  - 无条件成功日志：`entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:1795`
- 官方/权威依据：
  - `napi_define_properties` 函数签名返回 `napi_status`，调用方应基于返回值处理错误。
  - 来源：<https://raw.githubusercontent.com/nodejs/node/v22.13.1/src/node_api.h>
- 修复建议（后续实施）：
  - 检查 `napi_define_properties` 返回状态并记录结构化错误。
  - 成功日志仅在 `napi_ok` 时输出。
- 验收标准：
  - 导出注册失败可被初始化阶段及时观测与定位。
  - 不再出现“失败仍打印成功”的假阳性日志。

### P2-10 资源治理缺口：`CoreLoaderNapi::ReadFile` 无容量上限且缺异常保护

- 严重级别：`Low`
- 影响：`ReadFile` 直接按 `st_size` 扩容 `std::vector`，未设置上限；异常大输入下可能抛分配异常，且 NAPI 入口缺少异常保护，存在进程 `terminate` 风险。
- 代码证据：
  - 无上限读取与扩容：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:41`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:46`
  - NAPI 入口缺少异常保护：`entry/src/main/cpp/app/napi/core_loader_napi.cpp:264`、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:291`
  - 对照（已有 512MB 上限）：`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:72`、`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:103`
- 官方/权威依据：
  - `std::vector::resize` 可能抛出分配异常：<https://en.cppreference.com/w/cpp/container/vector/resize>
  - 未捕获异常会触发 `std::terminate`：<https://en.cppreference.com/w/cpp/error/terminate>
- 修复建议（后续实施）：
  - 为 `ReadFile` 增加统一最大读取上限（与项目其它路径一致）。
  - NAPI 入口补充异常保护并返回结构化错误。
- 验收标准：
  - 超大输入不会触发崩溃。
  - 超限时返回明确错误并可观测。

### P2-11 并发一致性缺口：core options 配置“读-改-写”无串行化，跨线程更新会互相覆盖

- 严重级别：`Low`
- 影响：`SetCoreOptionValue` 每次写入都执行“加载整份配置 -> 更新单键 -> 覆盖保存”；多个线程/请求并发写不同 key 时可能发生丢更新（last-writer-wins），导致配置回退。
- 代码证据：
  - 读改写流程：`entry/src/main/cpp/core/libretro/core_options_registry.cpp:200`、`entry/src/main/cpp/core/libretro/core_options_registry.cpp:201`、`entry/src/main/cpp/core/libretro/core_options_registry.cpp:202`
  - 无进程内串行化：`entry/src/main/cpp/core/libretro/core_options_registry.cpp:183`
  - 底层配置读写接口无锁：`entry/src/main/cpp/common/config/file_configuration.cpp:56`、`entry/src/main/cpp/common/config/file_configuration.cpp:89`
- 官方/权威依据：
  - C++ 内存模型/并发访问基本原则：跨线程共享可变状态需同步，避免竞争与丢更新。
  - 来源：<https://en.cppreference.com/w/cpp/language/multithread.html>
- 修复建议（后续实施）：
  - 在 core options 配置层增加进程内串行化（互斥锁/专用串行队列）。
  - 将读改写收敛为原子事务（单入口）并统一错误处理。
- 验收标准：
  - 并发更新不同 key 后，最终配置不丢键值更新。
  - 高频并发设置 core option 时结果稳定可预测。

## 官方对照（已确认通过项）

- NativeBuffer 路径使用 `FromNativeWindowBuffer -> Map -> Unmap -> Unreference`，符合当前项目约束方向：
  - `entry/src/main/cpp/core/engine/video_pipeline.cpp:659`
  - `entry/src/main/cpp/core/engine/video_pipeline.cpp:662`
  - `entry/src/main/cpp/core/engine/video_pipeline.cpp:840`
  - `entry/src/main/cpp/core/engine/video_pipeline.cpp:852`
- 参考：
  - OpenHarmony NativeBuffer API：<https://gitee.com/openharmony/docs/raw/ac028985bc5cc01527e31478995d1748bcde7432/en/application-dev/reference/apis-arkgraphics2d/_o_h___native_buffer.md>
  - OpenHarmony NativeWindow 指南：<https://gitee.com/openharmony/docs/raw/master/en/application-dev/graphics/native-window-guidelines.md>

## 修复优先级与顺序

1. `P0-1` 并发数据竞争（先消除 UB 风险）
2. `P0-2` `AudioPlayer` 并发数据竞争
3. `P0-3` `EnvState` 最小音频时延并发数据竞争
4. `P0-4` core API 线程模型违规
5. `P0-5` `Stop` 状态机清理路径失效
6. `P0-6` Stop 超时后 Reset 继续清理
7. `P0-7` `AssignPort(None)` 持锁重入死锁风险
8. `P0-8` Stop 超时后析构路径 `std::terminate` 风险
9. `P1-1` HiLog 格式规范一致性
10. `P1-2` `.gitignore` 安全规则补齐
11. `P1-3` `EventBridge` 合并丢更新
12. `P1-4` `EnvState` 核心选项并发访问缺口
13. `P1-5` `DiskController` 并发访问缺口
14. `P1-6` `PluginManager` 输入状态按组件隔离
15. `P1-7` `StopEngineAsync` 生命周期收敛
16. `P1-8` `Stop` 超时恢复通道
17. `P1-9` 输入路由映射一致性缺陷
18. `P1-10` `AudioBridge` 统计并发访问缺口
19. `P1-11` `Blur` 固定 `port=0` 的端口错配
20. `P1-12` Touch 固定 `port=0` 的端口错配
21. `P1-13` `g_engineInstance` 全局回调指针线程边界
22. `P1-14` `InputManager::g_instance` 全局回调指针线程边界
23. `P1-15` `testCoreLoader` 路径校验前读取缺口
24. `P1-16` `CoreLoaderNapi` ELF 边界/终止校验缺口
25. `P1-17` `PlatformResourceManager` 句柄生命周期收敛
26. `P1-18` `PlatformResourceManager` 锁边界一致性
27. `P1-19` `EnvState` 目录字符串跨线程同步
28. `P1-20` `SetFilesDir/LoadRom` 时序一致性
29. `P1-21` `SwitchGameAsync` token 取消窗口
30. `P1-22` keyboard callback 转发链路缺失
31. `P1-23` `EngineMessage` 路径静默截断
32. `P1-24` Vulkan `wait_sync_index` 同步语义缺口
33. `P1-25` Vulkan `present` 队列选择语义缺口
34. `P1-26` `Present` 解锁后 `FrameState*` 并发悬垂风险
35. `P2-1` `GetAVInfo` 并发可见性问题
36. `P2-2` `env_dispatcher` 全局静态回调线程边界加固
37. `P2-3` 主回调注册返回值可观测性
38. `P2-4` `Start` 异常路径门禁复位
39. `P2-5` `Reset` 状态通知一致性
40. `P2-6` async work 创建/入队失败路径收口
41. `P2-7` `StopEngineAsync` 异常路径门禁复位
42. `P2-8` async complete 状态分流
43. `P2-9` NAPI 导出注册返回值可观测性
44. `P2-10` `CoreLoaderNapi` 大文件读取上限/异常保护
45. `P2-11` core options 配置并发读改写覆盖

## GitHub Issue 映射

- 跟踪总 issue：`#6`
  - <https://github.com/daugf2527/hongmeng/issues/6>
- 子 issue：
  - `P0-1`：`#3`
    - <https://github.com/daugf2527/hongmeng/issues/3>
  - `P0-2`：`#7`
    - <https://github.com/daugf2527/hongmeng/issues/7>
  - `P0-3`：`#9`
    - <https://github.com/daugf2527/hongmeng/issues/9>
  - `P0-4`：`#11`
    - <https://github.com/daugf2527/hongmeng/issues/11>
  - `P0-5`：`#17`
    - <https://github.com/daugf2527/hongmeng/issues/17>
  - `P0-6`：`#21`
    - <https://github.com/daugf2527/hongmeng/issues/21>
  - `P0-7`：`#19`
    - <https://github.com/daugf2527/hongmeng/issues/19>
  - `P0-8`：`#30`
    - <https://github.com/daugf2527/hongmeng/issues/30>
  - `P1-1`：`#4`
    - <https://github.com/daugf2527/hongmeng/issues/4>
  - `P1-2`：`#5`
    - <https://github.com/daugf2527/hongmeng/issues/5>
  - `P1-3`：`#8`
    - <https://github.com/daugf2527/hongmeng/issues/8>
  - `P1-4`：`#10`
    - <https://github.com/daugf2527/hongmeng/issues/10>
  - `P1-5`：`#12`
    - <https://github.com/daugf2527/hongmeng/issues/12>
  - `P1-6`：`#14`
    - <https://github.com/daugf2527/hongmeng/issues/14>
  - `P1-7`：`#15`
    - <https://github.com/daugf2527/hongmeng/issues/15>
  - `P1-8`：`#18`
    - <https://github.com/daugf2527/hongmeng/issues/18>
  - `P1-9`：`#20`
    - <https://github.com/daugf2527/hongmeng/issues/20>
  - `P1-10`：`#22`
    - <https://github.com/daugf2527/hongmeng/issues/22>
  - `P1-11`：`#23`
    - <https://github.com/daugf2527/hongmeng/issues/23>
  - `P1-12`：`#27`
    - <https://github.com/daugf2527/hongmeng/issues/27>
  - `P1-13`：`#31`
    - <https://github.com/daugf2527/hongmeng/issues/31>
  - `P1-14`：`#32`
    - <https://github.com/daugf2527/hongmeng/issues/32>
  - `P1-15`：`#35`
    - <https://github.com/daugf2527/hongmeng/issues/35>
  - `P1-16`：`#36`
    - <https://github.com/daugf2527/hongmeng/issues/36>
  - `P1-17`：`#38`
    - <https://github.com/daugf2527/hongmeng/issues/38>
  - `P1-18`：`#39`
    - <https://github.com/daugf2527/hongmeng/issues/39>
  - `P1-19`：`#40`
    - <https://github.com/daugf2527/hongmeng/issues/40>
  - `P1-20`：`#41`
    - <https://github.com/daugf2527/hongmeng/issues/41>
  - `P1-21`：`#42`
    - <https://github.com/daugf2527/hongmeng/issues/42>
  - `P1-22`：`#43`
    - <https://github.com/daugf2527/hongmeng/issues/43>
  - `P1-23`：`#45`
    - <https://github.com/daugf2527/hongmeng/issues/45>
  - `P1-24`：`#46`
    - <https://github.com/daugf2527/hongmeng/issues/46>
  - `P1-25`：`#47`
    - <https://github.com/daugf2527/hongmeng/issues/47>
  - `P1-26`：`#48`
    - <https://github.com/daugf2527/hongmeng/issues/48>
  - `P2-1`：`#13`
    - <https://github.com/daugf2527/hongmeng/issues/13>
  - `P2-2`：`#16`
    - <https://github.com/daugf2527/hongmeng/issues/16>
  - `P2-3`：`#24`
    - <https://github.com/daugf2527/hongmeng/issues/24>
  - `P2-4`：`#25`
    - <https://github.com/daugf2527/hongmeng/issues/25>
  - `P2-5`：`#26`
    - <https://github.com/daugf2527/hongmeng/issues/26>
  - `P2-6`：`#28`
    - <https://github.com/daugf2527/hongmeng/issues/28>
  - `P2-7`：`#29`
    - <https://github.com/daugf2527/hongmeng/issues/29>
  - `P2-8`：`#33`
    - <https://github.com/daugf2527/hongmeng/issues/33>
  - `P2-9`：`#34`
    - <https://github.com/daugf2527/hongmeng/issues/34>
  - `P2-10`：`#37`
    - <https://github.com/daugf2527/hongmeng/issues/37>
  - `P2-11`：`#44`
    - <https://github.com/daugf2527/hongmeng/issues/44>

## 执行备注

- 本文档为“待修复清单”，不宣称问题已修复。
- 后续每个子项修复完成后，需补充：
  - 修复 PR 链接
  - 变更文件清单
  - 验证命令与输出摘要
