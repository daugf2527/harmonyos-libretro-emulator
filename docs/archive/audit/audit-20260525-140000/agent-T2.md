# Engine 状态机审计报告 — agent-T2

审计文件：
- `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- `entry/src/main/cpp/core/engine/libretro_engine.h`

---

## F1: STOPPED 态允许 LoadCore 但状态转换表禁止 STOPPED→LOADING，导致状态机不一致

- severity: P1
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 1315-1324
- evidence_excerpt: |
    ```
    case MessageType::LoadCore:
      if (!(state_.load() == EngineState::INIT ||
            state_.load() == EngineState::STARTING ||
            state_.load() == EngineState::STOPPED ||
            state_.load() == EngineState::ERROR)) {
        ...
        break;
      }
      TransitionTo(EngineState::LOADING);
    ```
- claim: HandleMessage 的 LoadCore 分支明确允许从 STOPPED 态进入（第 1318 行），随即调用 `TransitionTo(EngineState::LOADING)`。但 IsValidTransition 的 STOPPED 分支（第 256-257 行）仅允许 STOPPED→STARTING 和 STOPPED→INIT，**不包含** STOPPED→LOADING。TransitionTo 遇到非法转换只打 WARN 日志并 return，不修改状态——状态仍留在 STOPPED，但 HandleMessage 继续向下执行 `LoadCore()` 调用，造成引擎状态与实际执行路径脱节（引擎在 STOPPED 态跑了 LoadCore 逻辑，随后 TransitionTo(CORE_LOADED) 也会因同样规则被拦截而无声失败）。
- suggested_fix: 在 IsValidTransition 的 STOPPED 分支补上 `to == EngineState::LOADING`；或者将 HandleMessage LoadCore 分支对 STOPPED 态的预先检查与实际允许的转换保持一致（先要求 caller 调 Start() 回到 STARTING 再发 LoadCore）。两者取其一，关键是消除"gate 检查放行但 TransitionTo 拦截"的静默错误。

---

## F2: TransitionTo 在 CAS 成功后不持 stateMutex_ 直接 notify_all，与 WaitForState 的 cv wait 存在通知丢失窗口

- severity: P1
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 2476-2481
- evidence_excerpt: |
    ```
    if (state_.compare_exchange_strong(oldState, newState)) {
      break;
    }
    // CAS 失败:oldState 已被更新为当前实际值,重试。
    }
    stateCond_.notify_all();
    ```
- claim: TransitionTo 成功完成 CAS 写入（第 2476 行）后，在不持 stateMutex_ 的情况下调用 `stateCond_.notify_all()`（第 2481 行）。而 WaitForState 中的 `stateCond_.wait_for`（第 2530-2532 行）持有 stateMutex_。C++ 标准不禁止这种用法（notify_all 无需持锁），但有一个经典的通知丢失窗口：WaitForState 在 lock 加锁之前（第 2526 行之后、第 2530 行之前）调用 state_.load() 还是旧值，随后切换到 TransitionTo 完成 CAS + notify_all，再切回 WaitForState 进入 wait_for——这个 notify_all 就丢掉了。wait_for 仍有超时保底，但若 caller 用短超时（如 timeoutMs 很小）则会误报 false。结合 WaitForState 第 2523-2524 行的无锁快路径检查，共有两处 TOCTOU 窗口。
- suggested_fix: 在 TransitionTo 的 notify_all 前加锁 stateMutex_，或在 WaitForState 取消无锁快路径，统一在持锁后再检查并 wait，消除通知丢失窗口。

---

## F3: WaitForState(target, 0) 语义歧义——应该是"不等、立查"还是"无限等待"，当前实现是前者但文档为空

- severity: P2
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 2527-2528
- evidence_excerpt: |
    ```
    if (timeoutMs == 0) {
      return state_.load() == target;
    }
    ```
- claim: 当 timeoutMs 为 0 时，WaitForState 持有 stateMutex_ 锁后立即对 `state_` 做一次 load 然后返回，既不等待也不调用 cv。这个行为（timeout=0 → 不等）对 caller 而言难以预测——更常见的 convention 是 timeout=0 表示"非阻塞立查"（可以），或者表示"永久等待"（0 作无穷大）。实现本身无明显 bug，但接口语义未文档化，且持 stateMutex_ 加锁只是为了做一次 atomic load 是不必要的开销，还可能与其他锁路径产生争用。
- suggested_fix: 在函数头注释清楚 "timeoutMs=0 表示非阻塞立查"；并将该路径的 stateMutex_ 加锁去掉（直接 `return state_.load() == target`，与第 2523 行快路径行为一致）。

---

## F4: Stop() 在持有 controlMutex_ 的情况下阻塞等待 gameLoopExited_（最长 5000ms），导致外部 API 全面锁死

- severity: P1
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 442-475
- evidence_excerpt: |
    ```
    bool LibretroEngine::Stop() {
      std::lock_guard<std::recursive_mutex> lock(controlMutex_);
      ...
      constexpr uint32_t STOP_TIMEOUT_MS = 5000;
      bool exited = false;
      {
        std::unique_lock<std::mutex> lock(stopMutex_);
        exited =
            stopCond_.wait_for(lock, std::chrono::milliseconds(STOP_TIMEOUT_MS),
                               [this]() { return gameLoopExited_.load(); });
      }
    ```
- claim: Stop() 用 `lock_guard<recursive_mutex>` 锁住 controlMutex_（第 443 行），然后在同一栈帧内阻塞等待 GameLoop 退出（最多 5000ms，第 469-475 行）。在此期间任何外部线程调用 Start()、Reset()、LoadCore()、LoadGame()、SetFilesDir() 等方法（均在开头拿 controlMutex_）都会阻塞至多 5000ms。若 Stop() 超时（第 481 行 stopTimedOut_），controlMutex_ 才释放，但此时 GameLoop 可能仍在运行，外部方法在获得锁后操作已损坏的状态。这不是纯粹死锁（GameLoop 不拿 controlMutex_），但仍是高并发下的严重响应问题。
- suggested_fix: 将 Stop() 的 controlMutex_ 锁范围拆分：前段（发 Stop 消息、关闭队列）持锁，wait_for 等待阶段释放锁，join 和状态清理再按需持锁。或者将 Stop() 改为异步信号 + 调用者自行 join，避免在持锁情况下做长时间等待。

---

## F5: 注释（第 38 行）声称"析构函数不写回 nullptr"，实际代码（第 324 行）写了 nullptr，形成误导性文档

- severity: P2
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 36-44 及 324
- evidence_excerpt: |
    ```
    //   - g_engineInstance 由构造函数写入,析构函数不写回 nullptr
    // 当前默认只创建一个实例,无冲突;...
    static std::atomic<LibretroEngine *> g_engineInstance{nullptr};
    ...
    g_engineInstance.store(nullptr, std::memory_order_release);  // line 324
    ```
- claim: 第 38 行注释明确写"析构函数不写回 nullptr"，但 ~LibretroEngine 第 324 行确实执行了 `g_engineInstance.store(nullptr, std::memory_order_release)`。这段注释可能来自早期版本，与当前实现相悖。任何读到这段注释的开发者可能误以为析构后 g_engineInstance 仍非 null，从而绕过 null 检查直接使用悬空指针。
- suggested_fix: 将第 38 行注释改为"析构函数会将 g_engineInstance 写回 nullptr（见 ~LibretroEngine）"，并确认注释与当前代码保持同步。

---

## F6: OnVideoRefresh / OnAudioSampleBatch / OnEnvironment 中局部变量名 `g_engineInstance` 遮蔽了匿名命名空间中的静态全局同名变量

- severity: P2
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 2001, 2118, 2206
- evidence_excerpt: |
    ```
    void LibretroEngine::OnVideoRefresh(...) {
      LibretroEngine *g_engineInstance = GetEngineInstanceSnapshot();
    ...
    size_t LibretroEngine::OnAudioSampleBatch(...) {
      LibretroEngine *g_engineInstance = GetEngineInstanceSnapshot();
    ...
    bool LibretroEngine::OnEnvironment(...) {
      LibretroEngine *g_engineInstance = GetEngineInstanceSnapshot();
    ```
- claim: 匿名命名空间的静态全局变量 `static std::atomic<LibretroEngine *> g_engineInstance{nullptr}`（第 44 行）与这三个方法内声明的局部变量同名。虽然编译器会选取局部变量，逻辑上也通过 GetEngineInstanceSnapshot() 做了正确访问，但名称遮蔽会混淆代码审查者，且若未来有人在这些方法中不小心引用无本地赋值情况下的 g_engineInstance，可能意外访问全局指针（无 null 检查）。
- suggested_fix: 将三处局部变量改名为 `engine`、`eng` 或 `self` 等无歧义名称，消除与全局同名遮蔽。

---

## F7: `g_engineInstance` 双轨设计——Meyer's singleton 与手动全局指针并存，生命周期注释已过时但设计风险仍在

- severity: P2
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 33-44 及 305-309
- evidence_excerpt: |
    ```
    // 设计警告:本项目同时存在 GetInstance() 的 Meyer's singleton (line ~282) 和
    // 此处的 g_engineInstance 全局指针,后者由构造函数 store(this)。两套生命周期:
    //   - GetInstance() 的静态局部 `instance` 在程序退出最末才析构
    //   - g_engineInstance 由构造函数写入,析构函数不写回 nullptr
    static std::atomic<LibretroEngine *> g_engineInstance{nullptr};
    ...
    LibretroEngine *LibretroEngine::GetInstance() {
      static LibretroEngine instance;
      return &instance;
    }
    ```
- claim: 代码本身已在注释中记录了这一设计风险（第 39-42 行），并指出了两个修复方向，但至今未收敛。该双轨设计的实际危害：任何在 GetInstance() 单例之外另建 LibretroEngine 实例的代码（如测试 stub、多引擎场景）都会覆写 g_engineInstance，导致静态回调（OnVideoRefresh 等）指向不正确的实例，且无任何报错。
- suggested_fix: 按注释中建议的修复方向二选一：要么删除 g_engineInstance、所有静态回调改走 GetInstance()；要么将 g_engineInstance 的写入只在 GetInstance() 首次调用时执行一次（不在构造函数中设置）。

---

## DONE
