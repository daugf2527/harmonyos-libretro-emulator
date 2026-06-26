# XComponent / 输入子系统 — OH_ Native API 三源差异审计 (API 22)

> 目标 SDK = 6.0.2(22) = API 22
> 源 A 本地代码: `entry/src/main/cpp/app/framework/plugin_manager.cpp`（XComponent/输入 callsite 全部集中于此单文件；`core/libretro/**` 已排除）
> 源 B 本机 SDK header (version 6.0.2.130):
>   - `…/native/sysroot/usr/include/ace/xcomponent/native_interface_xcomponent.h`
>   - `…/native/sysroot/usr/include/ace/xcomponent/native_xcomponent_key_event.h`
> 源 C 官方 API22 文档: developer.huawei.com（V14 references + V13 + guides-v5）
>
> 审计日期: 2026-06-05 · 状态: 完成

---

## 结论速览

- **本地用到 30 个 OH_ XComponent/输入符号**（14 函数 + 8 typedef/struct + 8 枚举值/宏）。
- **全部 30 个在 API22 header 中存在**，签名一致，本地全部用符号常量（无硬编码数值），**0 个真实 bug / 0 个缺失**。
- 唯一"差异"是**任务下发清单里的一处事实错误**：清单标 `OH_NATIVEXCOMPONENT_RESULT_SUCCESS(16)`，而 header / 官方文档均为 **0**。本地代码并未硬编码 16，用的是符号 `OH_NATIVEXCOMPONENT_RESULT_SUCCESS`，因此无落地风险——属"审计输入勘误"而非代码缺陷。
- since 维度：本地最高要求 `RegisterKeyEventCallbackWithResult`（since 14），目标 API22 完全覆盖。所有符号均无 `@deprecated`。

---

## 差异表

| API | 类型 | 本地用法摘要 | 本机header(API22):存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------|------------------------------------------------|-----------|----------|
| `OH_NativeXComponent_GetXComponentId` | 函数 | L120/L427 取 XComponent ID 进 idStr[OH_XCOMPONENT_ID_LEN_MAX+1] | 存在; `(component, char* id, uint64_t* size)`; since 8; 无 deprecated | 一致 | **一致** |
| `OH_NativeXComponent_GetXComponentSize` | 函数 | L166/L458/L472/L513 取 surface 宽高(uint64_t) 做坐标归一化 | 存在; `(component, const void* window, uint64_t* width, uint64_t* height)`; since 8 | 一致 | **一致** |
| `OH_NativeXComponent_GetTouchEvent` | 函数 | L500 取 TouchEvent 结构填 touchEvent | 存在; `(component, const void* window, OH_NativeXComponent_TouchEvent*)`; since 8 | 一致 | **一致** |
| `OH_NativeXComponent_GetMouseEvent` | 函数 | L570 取 MouseEvent 结构 | 存在; `(component, const void* window, OH_NativeXComponent_MouseEvent*)`; since 9 | 一致 | **一致** |
| `OH_NativeXComponent_GetKeyEvent` | 函数 | L302 取 KeyEvent 指针(二级指针) | 存在; `(component, OH_NativeXComponent_KeyEvent** keyEvent)`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_GetKeyEventAction` | 函数 | L309 取 KeyAction | 存在; `(keyEvent, OH_NativeXComponent_KeyAction*)`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_GetKeyEventCode` | 函数 | L316 取 KeyCode | 存在; `(keyEvent, OH_NativeXComponent_KeyCode*)`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_GetKeyEventDeviceId` | 函数 | L198 取 deviceId 拼 "key:<id>" | 存在; `(keyEvent, int64_t* deviceId)`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_RegisterCallback` | 函数 | L559 注册 Surface 生命周期 + DispatchTouchEvent | 存在; `(component, OH_NativeXComponent_Callback*)`; since 8 | 一致 | **一致** |
| `OH_NativeXComponent_RegisterMouseEventCallback` | 函数 | L619 注册鼠标回调; 检查返回==RESULT_SUCCESS | 存在; `(component, OH_NativeXComponent_MouseEvent_Callback*)`; since 9; **无 deprecated** | 一致(since 10 表述见注1) | **一致** |
| `OH_NativeXComponent_RegisterFocusEventCallback` | 函数 | L627 注册 focus 回调 | 存在; `(component, void(*)(component,window))`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_RegisterBlurEventCallback` | 函数 | L639 注册 blur 回调 | 存在; `(component, void(*)(component,window))`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_RegisterKeyEventCallbackWithResult` | 函数 | L665 **首选**键盘回调(bool 返回); 失败 fallback 到旧版 | 存在; `(component, bool(*)(component,window))`; **since 14**; 无 deprecated | 一致, since 14 (V14 docs) | **一致**（本地最高 since 需求；API22 覆盖） |
| `OH_NativeXComponent_RegisterKeyEventCallback` | 函数 | L676 fallback 键盘回调(void 返回) | 存在; `(component, void(*)(component,window))`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_KeyEvent` | typedef(opaque struct) | L193/L301 不透明句柄, 经 Get* 取字段 | 存在; `typedef struct OH_NativeXComponent_KeyEvent …`; since 10 | 一致 | **一致** |
| `OH_NativeXComponent_KeyCode` | typedef enum | L239/L250/L315 映射到 retro joypad/key | 存在; enum(KEY_*); since 10; key_event.h | 一致 | **一致** |
| `OH_NativeXComponent_KeyAction` | typedef enum | L308 区分 DOWN/UP | 存在; enum; since 10; key_event.h | 一致 | **一致** |
| `OH_NativeXComponent_TouchEvent` | typedef struct | L499 读 .type/.numPoints/.touchPoints[] | 存在; struct(含 touchPoints[10]/numPoints); since 8 | 一致 | **一致** |
| `OH_NativeXComponent_TouchPoint` | typedef struct | L522 读 touchPoints[0].x/.y | 存在; struct(id/x/y/screenX/…/isPressed); since 8 | 一致 | **一致** |
| `OH_NativeXComponent_MouseEvent` | typedef struct | L569 读 .action/.button/.x/.y | 存在; struct(x/y/screenX/screenY/timestamp/action/button); since 9 | 一致 | **一致** |
| `OH_NativeXComponent_MouseEvent_Callback` | typedef struct | L562 设 DispatchMouseEvent + DispatchHoverEvent | 存在; struct{DispatchMouseEvent, DispatchHoverEvent}; since 9 | 一致 | **一致** |
| `OH_NativeXComponent_Callback` | typedef struct | L443 设 OnSurfaceCreated/Changed/Destroyed + DispatchTouchEvent | 存在; struct(4 个回调指针); since 8 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_RESULT_SUCCESS` | 枚举值 | 全文件 ~12 处用作返回值判定 | 存在; **= 0**; since 8 | **= 0** (V14 docs 确认) | ⚠️ **任务清单标 16 错误；真值 0**；本地用符号未硬编码→无 bug |
| `OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN` | 枚举值 | L321 判 isDown | 存在; `= 0`; since 10; key_event.h | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_KEY_ACTION_UP` | 枚举值 | L322 判 isUp | 存在; `= 1`(隐式); since 10 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN` | 枚举值 | L308 初值 | 存在; `= -1`; since 10 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_LEFT_BUTTON` | 枚举值 | L598/L601 按位 & 判左键 | 存在; `= 0x01`; since 9 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_MOVE` | 枚举值(TouchEventType) | L550 判 pressed; L549 配合 DOWN | 存在; TouchEventType `MOVE`(=2); since 8 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_DOWN` | 枚举值(TouchEventType) | L549 判 pressed | 存在; TouchEventType `DOWN`(=0); since 8 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_MOUSE_PRESS` | 枚举值(MouseEventAction) | L597 判按下 | 存在; MouseEventAction(=1); since 9 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_MOUSE_RELEASE` | 枚举值(MouseEventAction) | L600 判释放 | 存在; MouseEventAction(=2); since 9 | 一致 | **一致** |
| `OH_NATIVEXCOMPONENT_MOUSE_CANCEL` | 枚举值(MouseEventAction) | L603 判取消 | 存在; MouseEventAction; **since 18**(注2) | 一致 | **一致**（since 18 ≤ API22，覆盖 OK） |
| `OH_XCOMPONENT_ID_LEN_MAX` | 常量(const uint32_t) | L118/L425 idStr 缓冲尺寸 | 存在; `const uint32_t = 128`; since 8 | 一致 | **一致** |
| `OH_NATIVE_XCOMPONENT_OBJ` | 宏(字符串) | L396 napi_get_named_property 取 XComponent 对象 | 存在; `#define …("__NATIVE_XCOMPONENT_OBJ__")`; since 8 | 一致 | **一致** |

> 注1：官方 V13 文档把 `RegisterMouseEventCallback` 标 "API 10 present"，header 标 `introduced=9.0.0`；属文档 since 起点表述差(min vs 文档版本)，函数本身在 API22 一致可用，**非差异**。
> 注2：`OH_NATIVEXCOMPONENT_MOUSE_CANCEL` header 注释明确 `@since 18`；本地有使用，目标 API22 覆盖，无 minSdk 风险（前提：工程 minCompatibleVersion ≤ 此值才需注意，但本子系统 callsite 全在 API22 编译目标内）。

---

## API22 header 有、本地未用（输入相关新能力，供后续可选增强参考，非缺陷）

| API | since | 说明 |
|-----|-------|------|
| `OH_NativeXComponent_RegisterUIInputEventCallback` | 12 | 统一 UI input 事件回调（当前仅 axis 轴事件）——**手柄摇杆/轴输入**的官方推荐通道，本项目摇杆走 ArkTS→NAPI，未用此 native 轴回调 |
| `OH_NativeXComponent_GetKeyEventSourceType` | 10 | 取按键事件 sourceType（可区分键盘/手柄来源），本地仅取 action/code/deviceId 未取 sourceType |
| `OH_NativeXComponent_GetKeyEventModifierKeyStates` | 20 | 取按键修饰键状态(Ctrl/Shift/Alt 位掩码) |
| `OH_NativeXComponent_GetKeyEventNumLock/CapsLock/ScrollLockState` | 20 | 取锁定键状态 |
| `OH_NativeXComponent_GetMouseEventModifierKeyStates` / `GetExtraMouseEventInfo` | 20 | 鼠标修饰键 / 扩展鼠标信息 |
| `OH_NativeXComponent_GetHistoricalPoints` | 10 | 触控历史点（高频采样轨迹），本项目只取 touchPoints[0] 单点 |
| `OH_NativeXComponent_GetTouchPointToolType` / `TiltX/Y` / `WindowX/Y` / `DisplayX/Y` | 9~12 | 触控笔/窗口/屏幕坐标细分 |
| `OH_NativeXComponent_SetExpectedFrameRateRange` / `RegisterOnFrameCallback` | 11 | 期望帧率范围 / onFrame 回调 |
| `OH_NativeXComponent_SetNeedSoftKeyboard` | 12 | 软键盘需求 |
| `OH_ArkUI_SurfaceHolder_*` 系列 | 19 | 新版 SurfaceHolder/SurfaceCallback 生命周期 API（替代 RegisterCallback 的现代写法） |
| `ArkUI_XComponentSurfaceConfig` + `OH_ArkUI_SurfaceHolder_SetSurfaceConfig` / `SetIsOpaque` | **22** | **API22 新增**：XComponent surface 不透明度配置 |

> 说明：以上均为"本地未用"的 API22 可用能力，**不构成差异/缺陷**，仅作输入子系统未来增强（手柄轴输入、修饰键、触控笔）的官方通道清单。

---

## 最高优先级差异（3 条）

1. **[审计输入勘误 / 高]** 任务下发清单标注 `OH_NATIVEXCOMPONENT_RESULT_SUCCESS(16)` — **错误**。本机 API22 header（`native_interface_xcomponent.h` L72）与官方 V14 文档均明确 **= 0**（`FAILED=-1`/`BAD_PARAMETER=-2`）。
   - **落地影响：无**。本地全部用符号常量 `OH_NATIVEXCOMPONENT_RESULT_SUCCESS`（~12 处），未硬编码 16，编译期取真值 0。
   - **处置**：勿据"16"去改任何 callsite；若别处文档/注释写了 16 需勘误。

2. **[since 边界 / 中]** `OH_NativeXComponent_RegisterKeyEventCallbackWithResult` 是本子系统 **since 要求最高**的符号（since **14**）。本地已做正确兜底：失败时 fallback 到 `RegisterKeyEventCallback`（since 10）。目标 API22 完全覆盖，**但若未来 minCompatibleSdkVersion 下探 < 14，则 WithResult 在低版本设备 dlsym 失败概率上升** —— 当前 fallback 逻辑（L671-686）已正确处理，无需改动，仅作版本依赖记录。

3. **[能力缺口（非缺陷）/ 低]** 输入子系统**未使用 `OH_NativeXComponent_RegisterUIInputEventCallback`（since 12，官方轴/手柄输入通道）**。本项目手柄摇杆经 ArkTS 虚拟手柄→NAPI 路径，native 侧未接 axis 事件。这是**架构选择**而非差异，但若要做物理手柄摇杆/扳机的 native 直采，这是官方推荐入口。

---

## 统计

- **本地用到的 OH_ XComponent/输入符号总数：30**
  - 函数 14 · typedef/struct 8 · 枚举值/宏 8
- **状态计数：**
  - **一致：30 / 30**（全部在 API22 header 存在、签名一致、本地用符号常量、无 deprecated 命中）
  - **有差异：0**（代码层面零差异）
  - **审计输入勘误：1**（任务清单 RESULT_SUCCESS=16 vs 真值 0；不影响代码）
- **deprecated 命中：0**（本子系统所用符号无一标 @deprecated；header 内 `AttachNativeRootNode`/`DetachNativeRootNode` 虽 since12/deprecated20，但**本地未使用**）
- **since 覆盖：** 本地最高 since=14（WithResult），目标 API22 全覆盖，含 fallback 兜底。
- **API22 新增且与 XComponent 相关：** `ArkUI_XComponentSurfaceConfig` 系列（surface 不透明度配置）— 本地未用，非缺陷。

落盘路径：`docs/audit/api22-diff/xcomponent-input.md`
