# T7-B Audit: NAPI Layer (engine_input_napi.cpp)

Auditor: NAPI Boundary Reviewer  
Date: 2026-05-27  
Files examined:
- `entry/src/main/cpp/app/napi/engine_input_napi.cpp`
- `entry/src/main/cpp/app/napi/engine_napi_common.h`
- `entry/src/main/cpp/core/engine/input_manager.h`
- `entry/src/main/cpp/interfaces/input/i_input_manager.h`
- `entry/src/main/ets/common/RuntimeInputCommandBridge.ets`
- `entry/src/main/ets/common/RuntimeInputPortController.ets`

---

## F1: GetStringArgAllowEmpty "string too long" 路径不抛异常，静默返回 false

- severity: P1
- file: `entry/src/main/cpp/app/napi/engine_napi_common.h`
- line: 133-136
- evidence_excerpt: |
    if (size >= outSize) {
        LOGF(LOG_ERROR,
             "[NEW] %s string arg too long: %{public}s", func, argName);
        return false;
    }
- claim: `GetStringArgAllowEmpty` 在字符串超过缓冲区上限（本文件中是 256 字节）时只打 log、返回 false，没有调用 `napi_throw_type_error`。调用方 `AssignPortSource`（engine_input_napi.cpp:93-95）收到 false 后会通过 `MakeBool(env, false)` 返回 JS 侧 `false`，而不抛出异常。ArkTS 侧无法区分"参数合法但操作失败"与"参数非法被截断"，会误认为调用成功（返回 false 是业务逻辑失败，不是类型违规）。形成与 `GetStringArg`（line 102-105）相同的 no-throw 对称漏洞。注意：`GetStringArg` 的同等路径同样未 throw（line 102-106）。
- suggested_fix: 在 `GetStringArgAllowEmpty`（及 `GetStringArg`）的 `size >= outSize` 分支中调用 `napi_throw_range_error(env, nullptr, "String argument exceeds maximum length")`，与其他类型违规（`napi_throw_type_error`）保持风格一致，然后再 `return false`。

---

## F2: ListInputDevices 中所有 napi_create_* 调用均未检查返回值，OOM/GC压力下可写入 null 指针

- severity: P1
- file: `entry/src/main/cpp/app/napi/engine_input_napi.cpp`
- line: 138-160
- evidence_excerpt: |
    napi_create_array_with_length(env, devices.size(), &array);
    for (size_t i = 0; i < devices.size(); ++i) {
        napi_value obj = nullptr;
        napi_create_object(env, &obj);
        napi_value val = nullptr;
        napi_create_string_utf8(env, devices[i].deviceId.c_str(),
                                NAPI_AUTO_LENGTH, &val);
        napi_set_named_property(env, obj, "deviceId", val);
- claim: `napi_create_array_with_length`、`napi_create_object`、`napi_create_string_utf8`、`napi_create_int32` 的返回值均未检查。若任何一步因内存不足返回非 `napi_ok`，后续变量（`array`、`obj`、`val`）仍为 `nullptr`，接下来的 `napi_set_named_property` / `napi_set_element` 会对 null 指针解引用，导致崩溃。同时，`NAPI_TRY_CATCH_END` 只能捕获 C++ 异常，无法捕获 NAPI API 内部的 C++ 崩溃。相比之下，`BuildStringArray`（engine_napi_common.h:199-208）存在相同模式——无状态检查——但 `ListInputDevices` 的影响面更大（每个对象 3 个字段，N 个设备）。
- suggested_fix: 对循环内每次 `napi_create_*` 调用检查返回值；若失败则调用 `napi_throw_error` 并提前返回 `nullptr`。考虑将对象构建逻辑提取成独立 helper 函数以复用错误处理逻辑。

---

## F3: RegisterInputNapi 不检查 napi_define_properties 返回值

- severity: P2
- file: `entry/src/main/cpp/app/napi/engine_input_napi.cpp`
- line: 232
- evidence_excerpt: |
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
- claim: `RegisterInputNapi` 的 `napi_define_properties` 调用忽略返回值。若注册失败（如内存不足、exports 对象非法），7 个函数均无声注册失败，ArkTS 侧调用时会得到 `undefined is not a function` 运行时崩溃，且没有任何 C++ 侧的日志或抛出。对比 `core_loader_napi.cpp:655-659` 已正确检查并 log。`engine_lifecycle_napi.cpp:933`、`engine_state_napi.cpp:385`、`engine_query_napi.cpp:378`、`engine_video_napi.cpp:178`、`engine_disk_napi.cpp:101` 均存在相同问题，但本审计范围仅限 engine_input_napi.cpp。
- suggested_fix: 参照 `core_loader_napi.cpp:655-659` 的模式，检查返回值并在失败时 log + 调用 `napi_throw_error`。

---

## F4: SendAnalog 的 double→int 精度截断不对 ArkTS 侧透明

- severity: P2
- file: `entry/src/main/cpp/app/napi/engine_input_napi.cpp`
- line: 57-68
- evidence_excerpt: |
    if (value > 32767.0) {
        value = 32767.0;
    } else if (value < -32768.0) {
        value = -32768.0;
    }
    const bool ok =
        input->SendAnalog(port, index, id, static_cast<int>(value));
- claim: `value` 经 `GetDoubleArg` 读入为 `double`，截断 clamp 后做 `static_cast<int>(value)` 传给 `SendAnalog`，该函数签名为 `int value`（IInputManager 第 42 行）。ArkTS 侧 `normalizeAnalogValue` 已将值规范化到 `[-32768, 32767]` 整数范围（RuntimeInputCommandBridge.ets:40-51），故正常路径不受影响。但如果调用方传入非整数 double（如 `0.5`，即未经 normalizeAnalogValue 处理的原始触摸比例），`static_cast<int>` 截断将导致精度丢失（`0.5 → 0`），且无任何 log 或告警。这不是崩溃风险，但是无声的数据丢失。
- suggested_fix: 考虑改用 `static_cast<int>(std::round(value))` 减少截断误差，或在注释/文档中明确本函数只接受已规范化为整数的值。

---

## F5: AssignPortSource 的 deviceId 缓冲区硬编码 256 字节，无法安全处理 UUID 类设备 ID

- severity: P2
- file: `entry/src/main/cpp/app/napi/engine_input_napi.cpp`
- line: 92
- evidence_excerpt: |
    char idBuf[256] = {0};
    if (!GetStringArgAllowEmpty(env, args[2], idBuf, sizeof(idBuf),
                                "AssignPortSource", "deviceId")) {
        return MakeBool(env, false);
    }
    deviceId = idBuf;
- claim: 栈上 256 字节缓冲区对标准 UUID（36 字符）足够，但 HarmonyOS 设备 ID 的长度规格未在接口文档中固定。如果系统返回更长的设备 ID（如 base64/hash 格式，可能 64-128 字节），超出 255 字节后 `GetStringArgAllowEmpty` 静默失败（结合 F1 中无 throw），`AssignPortSource` 返回 `false`，ArkTS 无法区分是设备不存在还是参数过长。建议改用 `std::string` 直接读取，避免硬编码缓冲区。
- suggested_fix: 使用两步 `napi_get_value_string_utf8` 动态分配（先 `nullptr` 获取长度，再分配 `std::string` 或 `std::vector<char>`），或将 256 提取为常量 `kMaxDeviceIdLen` 并在运行时检测截断时抛出异常（结合 F1 修复）。

---

## 总结（VERDICT）

**VERDICT**: concerns

本文件不存在 HARD invariant 违规（无 `napi_env` 跨线程存储、无 TSFN 缺失、无 `napi_call_function` 在非 NAPI 线程调用）。所有 7 个 NAPI 函数均运行在 NAPI 线程且不阻塞（调用 InputManager 是 mutex 保护的快速操作，无消息队列等待）。`MakeBool` 已有 pending-exception 守卫（T1-F5 已修复）。`NAPI_TRY_CATCH_BEGIN/END` 覆盖所有函数体。

主要关切：
- F1（P1）：string-too-long 路径静默失败，无 throw
- F2（P1）：`ListInputDevices` 对象构建无 napi_create_* 状态检查，OOM 下可崩溃
- F3（P2）：`napi_define_properties` 返回值未检查
- F4/F5（P2）：数值截断和缓冲区硬编码的低风险但值得跟踪的设计问题

无需 block，但 F1 和 F2 应在下一个 fix 窗口处理。
