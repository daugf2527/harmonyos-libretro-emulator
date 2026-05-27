# T7-A Audit: C++ Engine Layer (Input / EventBridge)

审计范围：
- `entry/src/main/cpp/core/engine/input_manager.cpp`
- `entry/src/main/cpp/core/engine/input_manager.h`
- `entry/src/main/cpp/core/engine/input_port_router.cpp`
- `entry/src/main/cpp/core/engine/input_port_router.h`
- `entry/src/main/cpp/core/engine/event_bridge.cpp`
- `entry/src/main/cpp/core/engine/event_bridge.h`
- `entry/src/main/cpp/core/engine/input_snapshot.h`
- `entry/src/main/cpp/interfaces/input/i_input_manager.h`

---

## F1: InputManager::portRouter_ 和 controller_port_device_callback_ 无 mutex 保护，跨线程 data race

- severity: P0
- file: entry/src/main/cpp/core/engine/input_manager.cpp
- line: 186-192
- evidence_excerpt: |
    void InputManager::SetPortRouter(InputPortRouter *router) {
      portRouter_ = router;
    }

    void InputManager::SetControllerPortDeviceCallback(
        std::function<void(unsigned, unsigned)> callback) {
      controller_port_device_callback_ = std::move(callback);
    }
- claim: `portRouter_` 和 `controller_port_device_callback_` 均为普通非原子成员字段，写入在 NAPI/JS 线程（SetPortRouter/SetControllerPortDeviceCallback），读取在 Engine 线程（AssignPortSource、UnassignPort、ListInputDevices、CanSendVirtual、ResolvePortForDevice、RecordInputDevice、SetControllerPortDevice 等，共 7 处调用）。两侧之间没有任何 mutex 或 atomic 保护，是经典 data race。在 NAPI 线程设置 portRouter_=router 的同时 Engine 线程正在读取并解引用 portRouter_，可能导致 use-after-free 或空指针崩溃。
- suggested_fix: 为 InputManager 增加一个 `std::mutex members_mutex_`，在所有读写 `portRouter_` 和 `controller_port_device_callback_` 的路径上加 `lock_guard`；或将 `portRouter_` 改为 `std::atomic<InputPortRouter*>`（需评估 ABA 问题）。生命周期上须确保 portRouter_ 指向对象在 InputManager 析构之前保持有效。

---

## F2: OnInputState 接受 unsigned port 但 InputSnapshot::GetButton/GetAnalog/GetPointer 接受 int port，隐式截断后越界

- severity: P1
- file: entry/src/main/cpp/core/engine/input_manager.cpp
- line: 229-277
- evidence_excerpt: |
    int16_t InputManager::OnInputState(unsigned port, unsigned device,
                                       unsigned index, unsigned id) {
      ...
      return instance->inputSnapshot_.GetButton(port, id) ? 1 : 0;
      ...
      return instance->inputSnapshot_.GetAnalog(port, index, id);
      ...
      instance->inputSnapshot_.GetPointer(port, x, y, pressed);
- claim: libretro 回调传入的 `port`/`index`/`id` 均为 `unsigned`，直接隐式转换传入 `InputSnapshot` 的 `int` 形参。虽然 `InputSnapshot` 内部有范围检查，但 `index` 最大可为 `UINT_MAX`；在 `GetAnalog` 中 `axis_idx = (index * 2) + id`，若 `index` 为大整数则整数溢出变负数，绕过 `axis_idx >= 0` 检查（因为溢出后回绕到负数，但 `int` 类型范围内一旦 `index` 超过 `INT_MAX/2` 即溢出 UB）。此外 `OnInputState` 本身对 `port` 无 `>= kMaxPorts` 前置检查，依赖下游 `GetButton/GetAnalog/GetPointer` 内的检查，防御层次单一。
- suggested_fix: 在 `OnInputState` 函数入口处统一做 `if (port >= InputSnapshot::kMaxPorts) return 0;` 检查；`GetAnalog` 中在执行乘法前先独立校验 `index < 16 && id < 2`（或等价上界），避免整数溢出 UB。

---

## F3: OnSensorGetInput 对 unsigned port/id 直接传入 GetSensor(int)，同 F2 越界隐患

- severity: P1
- file: entry/src/main/cpp/core/engine/input_manager.cpp
- line: 310-316
- evidence_excerpt: |
    float InputManager::OnSensorGetInput(unsigned port, unsigned id) {
      InputManager *instance = g_instance.load(std::memory_order_acquire);
      if (!instance) {
        return 0.0f;
      }
      return instance->inputSnapshot_.GetSensor(port, id);
    }
- claim: `unsigned port` 和 `unsigned id` 直接隐式转为 `int` 传入 `GetSensor`。当 libretro core 传入 `id >= kMaxSensors`（例如 `RETRO_SENSOR_ACCELEROMETER_X` 等值可能超过 16）时，`GetSensor` 内 `id < kMaxSensors` 检查能拦截；但若 `id` 值本身合法但恶意 core 或内存损坏传入极大 `unsigned`，隐式截断到 `int` 后可能通过检查进而访问越界下标。更根本的问题是没有在 callback 入口做 `assert` 或 early-return。
- suggested_fix: 在 `OnSensorGetInput` 入口增加 `if (port >= InputSnapshot::kMaxPorts || id >= InputSnapshot::kMaxSensors) return 0.0f;` 明确早退，不依赖内部 cast 后的范围检查。

---

## F4: EventBridge::Initialize 重新创建 TSFN 时用 napi_tsfn_release 而非 napi_tsfn_abort，可能导致已入队 EventData 被泄漏

- severity: P1
- file: entry/src/main/cpp/core/engine/event_bridge.cpp
- line: 75-105
- evidence_excerpt: |
    bool EventBridge::Initialize(napi_env env, napi_value callback) {
      std::lock_guard<std::mutex> lock(mutex_);
      if (tsfn_) {
        LOGF(LOG_WARN, "EventBridge already initialized. Releasing old TSFN and re-creating.");
        napi_release_threadsafe_function(tsfn_, napi_tsfn_release);
        tsfn_ = nullptr;
      }
- claim: 当 `Initialize` 被重复调用时（例如重载 core 场景），旧 `tsfn_` 通过 `napi_tsfn_release` 释放。`napi_tsfn_release` 只减少线程引用计数（initial_thread_count=1），令 TSFN 变为"无线程持有"状态，Node.js 会在队列排空后自然调用 finalize_cb 并执行剩余回调。问题是此时 `tsfn_` 已被置 `nullptr`，若队列中仍有 `EventData *` 等待执行，且 `CallJsHandler` 被回调时已重建了新的 TSFN，旧 EventData 可能触发崩溃（env 已失效或新旧回调交叉）。正确做法应先 `napi_abort_threadsafe_function` 排空旧队列并释放所有 data，再 create 新 TSFN。
- suggested_fix: 将重建逻辑改为：先调用 `napi_abort_threadsafe_function(old_tsfn)` 使剩余 item 以 `env=nullptr` 触发 `CallJsHandler`（其中已处理 env==nullptr 时 delete data 的逻辑），再调 `napi_release_threadsafe_function(old_tsfn, napi_tsfn_release)`；此后再创建新 TSFN。

---

## F5: EventBridge::CallJsHandler 调用 napi_call_function 后未检查 pending exception，可能静默吞异常

- severity: P2
- file: entry/src/main/cpp/core/engine/event_bridge.cpp
- line: 217-221
- evidence_excerpt: |
    napi_call_function(env, undefined, js_cb, 1, &result, nullptr);

    delete eventData;
- claim: `napi_call_function` 返回值被丢弃。若 JS 回调函数抛出异常（例如 ArkTS 侧 EventHub 回调内的错误），`napi_call_function` 返回 `napi_pending_exception`，此时继续执行其他 NAPI 操作会触发未定义行为（Node-API 规范要求在 pending exception 状态下不能调用大多数 NAPI 函数）。虽然本函数后面只有 `delete eventData`（纯 C++，不涉及 NAPI），但若未来此处扩展新的 NAPI 调用，将直接踩此坑。同时异常被静默丢弃，ArkTS 侧错误不会被感知。
- suggested_fix: 检查 `napi_call_function` 返回值；若为 `napi_pending_exception`，调用 `napi_get_and_clear_last_exception` 清理异常并记录到 hilog，防止 pending exception 污染后续 NAPI 调用。

---

## F6: InputPortRouter::ClearPortStateLocked 在持有 mutex_ 时回调 inputManager_->ClearPort，若 ClearPort 内部尝试获取同一锁则死锁

- severity: P1
- file: entry/src/main/cpp/core/engine/input_port_router.cpp
- line: 27-32
- evidence_excerpt: |
    void InputPortRouter::ClearPortStateLocked(int port) {
      if (!inputManager_) {
        return;
      }
      inputManager_->ClearPort(port);
    }
- claim: `ClearPortStateLocked` 在 `mutex_` 已持有的情况下（从 `AssignPort`/`UnassignPortLocked` 内调用）调用 `inputManager_->ClearPort(port)`。`InputManager::ClearPort` 本身是直接调 `inputSnapshot_.ClearPort(port)`，不加锁（InputManager 没有自己的 mutex），当前不会死锁。但 `InputManager` 的 public 方法里有若干对 `portRouter_->` 的调用（如 `AssignPortSource` 调 `portRouter_->AssignPort` 进而持有 `mutex_`）；若将来 `ClearPort` 路径被扩展为回调 InputPortRouter 的某个方法，则形成互持死锁。此外，`ClearPortStateLocked` 命名为 "Locked" 暗示持锁状态，但其内部调用外部对象方法属于"持锁回调外部代码"反模式，需要文档说明或重构。
- suggested_fix: 将 `ClearPortStateLocked` 中需要调用 `inputManager_` 的逻辑改为"在锁外执行"的延迟操作（例如收集需要清除的端口号列表，释放锁后再批量清除），或至少在注释中明确声明"ClearPort 不能持有 mutex_ 的相关代码"以防止将来扩展引入死锁。

---

## F7: InputPortRouter::ResolvePortForDevice 在锁内对 portSources_[port].deviceId 静默赋值，与 AssignPort 语义重叠，可能绕过 AssignPort 的冲突检查

- severity: P2
- file: entry/src/main/cpp/core/engine/input_port_router.cpp
- line: 180-197
- evidence_excerpt: |
    for (int port = 0; port < InputSnapshot::kMaxPorts; ++port) {
      const PortSource &source = portSources_[port];
      if (!MatchSourceType(source.sourceType, sourceType)) {
        continue;
      }
      if (!source.deviceId.empty() && source.deviceId != deviceId) {
        continue;
      }
      if (source.deviceId.empty()) {
        portSources_[port].deviceId = deviceId;
        deviceToPort_[deviceId] = port;
- claim: `ResolvePortForDevice` 内含隐式的"自动绑定"逻辑：若找到 `sourceType` 匹配且 `deviceId` 为空的端口，则直接写 `portSources_[port].deviceId = deviceId` 并更新 `deviceToPort_`。这条路径完全绕过了 `AssignPort` 中的冲突检查（"device 已绑定到另一个 port 则拒绝"）。如果同一 deviceId 并发地被两个调用路径分别触发一次 `ResolvePortForDevice`，两次都可能通过"deviceId 为空"检查（race 窗口），最终同一 deviceId 被绑定到两个不同 port，`deviceToPort_` 只保留后者，导致前者 port 的 deviceId 与 deviceToPort_ 不一致（悬挂映射）。
- suggested_fix: 将 `ResolvePortForDevice` 内的隐式自动绑定改为仅"查找"语义（返回已明确绑定的端口），去掉自动写 `portSources_[port].deviceId` 的逻辑；或改为调用 `AssignPort` 走统一绑定路径，保证冲突检查覆盖所有绑定入口。

---

## F8: InputSnapshot 中 std::atomic<float> 和 std::atomic<int16_t> 在 ARM 上不保证 lock-free，若非 lock-free 则在 Engine 线程持有内部锁期间不能被中断

- severity: P2
- file: entry/src/main/cpp/core/engine/input_snapshot.h
- line: 196, 203
- evidence_excerpt: |
    // 使用原子数组存储模拟量（支持 32 个轴）
    std::atomic<int16_t> analog_axes_[kMaxPorts][kMaxAnalogAxes];
    ...
    // 传感器数据 (支持 16 个通道)
    std::atomic<float> sensor_values_[kMaxPorts][kMaxSensors];
- claim: C++ 标准不保证 `std::atomic<float>` 和 `std::atomic<int16_t>` 在所有平台上为 lock-free（标准只保证 `std::atomic<int32_t>`/`uint32_t` 等特定宽度通常 lock-free；`int16_t` 在部分 ARM ABI 下可能走 libatomic 互斥体；`float` 几乎不保证 lock-free）。若实现退化为内部 mutex，则 UI/NAPI 线程写 `SetSensor`/`SetAnalog` 与 Engine 线程（在 `retro_run` 内 60fps 高频）读 `GetAnalog`/`GetSensor` 之间仍有锁争用，且该锁对用户不可见，违背注释所声称的"避免消息队列延迟"初衷。应在编译期通过 `static_assert(std::atomic<float>::is_always_lock_free)` 做显式断言，否则无法保证性能假设成立。
- suggested_fix: 在 `input_snapshot.h` 中加入编译期断言 `static_assert(std::atomic<float>::is_always_lock_free, "atomic<float> must be lock-free on this platform");` 和 `static_assert(std::atomic<int16_t>::is_always_lock_free, ...);`。若断言失败，将 `float` sensor 值用 `std::atomic<uint32_t>` + `bit_cast` 替代，`int16_t` 升宽为 `int32_t`，确保 lock-free 实现。

---

## 无 finding

以下文件经过全文阅读和模式搜索，未发现独立的额外 bug（问题已合并至上述 finding）：
- `entry/src/main/cpp/interfaces/input/i_input_manager.h` — 纯接口定义，无实现代码，无 finding
