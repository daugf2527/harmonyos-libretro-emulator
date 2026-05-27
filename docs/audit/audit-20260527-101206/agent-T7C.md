# T7-C Audit: ArkTS Layer (Input / EventBridge)

Auditor: agent-T7C
Scope: common/LibretroEventHub.ets, common/RuntimeInputCommandBridge.ets,
       common/RuntimeInputPortController.ets, common/InputPortRouting.ts,
       pages/InputLayoutPage.ets (InputManager parts),
       pages/MultiplayerInputPage.ets (InputManager parts)

---

## F1: sendRuntimeAnalog X 轴调用返回值被丢弃——X 轴静默失败时调用者无感知

- severity: P1
- file: entry/src/main/ets/common/RuntimeInputCommandBridge.ets
- line: 36-37
- evidence_excerpt: |
    nativeApi.refactoredSendAnalog(port, index, 0, normalizeAnalogValue(x))
    return nativeApi.refactoredSendAnalog(port, index, 1, normalizeAnalogValue(y))
- claim: X 轴（id=0）的 `refactoredSendAnalog` 调用结果被完全丢弃，函数整体只 `return` Y 轴（id=1）的结果。若 C++ 侧 X 轴调用失败（返回 false），调用者拿到的 boolean 仍是 true（Y 轴成功），导致 analog stick X 方向输入无响应时无任何可观察信号，极难排查。
- suggested_fix: 将 X 轴结果存入局部变量，两次调用结果做 AND 后作为函数返回值；或改为独立调用并记录失败日志。

---

## F2: LibretroEventHub 单例无销毁路径——Ability 重启后旧 NAPI 回调悬空

- severity: P1
- file: entry/src/main/ets/common/LibretroEventHub.ets
- line: 256-277
- evidence_excerpt: |
    export class LibretroEventHub {
      private static instance: LibretroEventHub | undefined = undefined;
      private initialized: boolean = false;
      ...
      static getInstance(): LibretroEventHub {
        if (!LibretroEventHub.instance) {
          LibretroEventHub.instance = new LibretroEventHub();
        }
        return LibretroEventHub.instance;
      }
- claim: `LibretroEventHub.instance` 是进程级静态单例，没有 `destroy()` 或 `reset()` 方法。当 HarmonyOS Ability 被系统回收再重启时，C++ 侧的 native EventBridge 会重新初始化，但 ArkTS 侧旧的单例实例及其内部 NAPI 回调闭包（在 `initializeIfNeeded` 中注册）仍然指向上一次 Ability 的上下文。由于 `initialized` 为 true，`start()` 调用会直接 return，不会重新注册 NAPI callback，导致 C++ 事件推不到新的 ArkTS 侧监听器。若 Ability 生命周期与 Application 生命周期不同步，此路径必然触发。
- suggested_fix: 提供 `destroy()` 方法，将 `instance` 和 `initialized` 重置为初始状态；在 Ability 的 `onDestroy` 钩子中调用该方法。

---

## F3: InputLayoutPage.showSavedToast() 在页面销毁后仍可能写回 @State

- severity: P1
- file: entry/src/main/ets/pages/InputLayoutPage.ets
- line: 351-363
- evidence_excerpt: |
    private showSavedToast(): void {
      this.savedToastVisible = true
      if (this.savedToastTimer !== -1) {
        clearTimeout(this.savedToastTimer)
      }
      this.savedToastTimer = setTimeout(() => {
        if (!this.pageActive) {
          return
        }
        this.savedToastVisible = false
        this.savedToastTimer = -1
      }, 1800)
    }
- claim: `setTimeout` 回调在 1800ms 后执行。若用户在此窗口内离开页面，`aboutToDisappear()` 会将 `pageActive = false`，但 `savedToastTimer` 的 `clearTimeout` 在 `aboutToDisappear` 中确实执行了（line 106-108），这是正确的。然而，根项目级 CLAUDE.md 明确禁止在 `aboutToAppear` 系列生命周期中使用 `setTimeout`，理由是"setTimeout 不与页面生命周期绑定"。此处改 `savedToastVisible = false` 虽有 `!pageActive` 保护，但仍是文档约定的反模式，且清理逻辑依赖两处同步（`aboutToDisappear` 的 clearTimeout + 回调内部的 pageActive 检查），维护脆弱。若 `aboutToDisappear` 在某种调度时序下先于 `clearTimeout` 被跳过（如系统强杀），回调仍会写回已销毁组件。
- suggested_fix: 将 savedToast 逻辑改为 `onPageShow/onPageHide` 控制，或将 `savedToastVisible` 改为受页面 token 保护的 async 方式，而不是 setTimeout。至少确保 `aboutToDisappear` 的 `clearTimeout` 在任何代码路径下都可达。

---

## F4: runtimeInputPortController 模块单例在 engine 未初始化时被多页面调用——无 ready 检查

- severity: P1
- file: entry/src/main/ets/common/RuntimeInputPortController.ets
- line: 27-38, 41
- evidence_excerpt: |
    applyPortAssignment(portId: number, sourceType: InputSourceType, deviceId: string = ''): boolean {
      try {
        if (sourceType === InputSourceType.None) {
          return nativeApi.refactoredUnassignPort(portId)
        }
        return nativeApi.refactoredAssignPortSource(portId, sourceType, deviceId ?? '')
      } catch (err) {
        ...
      }
    }
    export const runtimeInputPortController: RuntimeInputPortController = new RuntimeInputPortController()
- claim: `runtimeInputPortController` 是模块级单例，被 LibretroGamePage、MultiplayerInputPage、SettingsPage 在任意时机调用（包括 `aboutToAppear`、按钮点击等）。`applyPortAssignment` 和 `listInputDevices` 直接调用 NAPI 函数，但没有检查 native engine 是否已初始化（`refactoredInitEventBridge` 是否成功、C++ 端 LibretroEngine 是否处于合法状态）。在 engine 未加载时调用，C++ 侧 NAPI 函数可能访问未初始化的 InputManager，导致 crash 或返回垃圾数据。
- suggested_fix: 在 `RuntimeInputPortController` 的 NAPI 调用前增加 engine ready 状态检查（可通过 `LibretroEventHub` 监听的最新 `engine_state` 判断，或增加独立的 `isEngineReady()` NAPI query）；或在 C++ 侧对 NAPI 函数加 early-return guard（若 engine 未初始化则返回 false 并 log warning）。

---

## F5: MultiplayerInputPage.aboutToAppear() 同步调用 NAPI——不符合 aboutToAppear 轻量化规范

- severity: P2
- file: entry/src/main/ets/pages/MultiplayerInputPage.ets
- line: 100-102
- evidence_excerpt: |
    aboutToAppear(): void {
      this.refreshDevices()
    }
- claim: `refreshDevices()` 在内部同步调用 `runtimeInputPortController.listInputDevices()`（line 135），后者是 NAPI 跨语言调用。项目级 CLAUDE.md（`entry/src/main/ets/CLAUDE.md`）规定：`aboutToAppear()` 中的轻量同步调用可保留，但 NAPI 跨进程调用并不能保证是微秒级完成，且不与页面生命周期绑定（若 native 端阻塞，会卡住页面转场动画）。此外与 F4 同理，此时 engine 可能未初始化。
- suggested_fix: 将 `refreshDevices()` 改为 `void this.refreshDevices()` fire-and-forget 异步调用，并在内部调用 NAPI 前检查 engine ready 状态；参考 LibraryPage 的 `void this.refreshLibraryGames()` 模式。

---

## F6: isVirtualPortActive 在找不到 portId 时静默返回 false——无任何日志或错误信号

- severity: P2
- file: entry/src/main/ets/common/InputPortRouting.ts
- line: 80-91, 129-131
- evidence_excerpt: |
    export function findPortAssignment(assignments: PortAssignState[], portId: number): PortAssignState {
      const found = assignments.find((item: PortAssignState) => item.portId === portId);
      if (found) {
        return found;
      }
      return {
        portId: portId,
        sourceType: InputSourceType.None,
        deviceId: '',
        isActive: false
      };
    }
- claim: `isVirtualPortActive` 内部调用 `findPortAssignment`，若 `portId` 在 assignments 中不存在，返回一个 `sourceType: None` 的哨兵对象，导致 `isVirtualPortActive` 返回 false，`sendRuntimeButton`/`sendRuntimeAnalog` 静默放弃本次 input 事件。从运行时角度，portId 传入非法值（如 selectedPortIndex 超出 assignments 数组范围）会造成输入被整批丢弃，调试者无法区分"port 未激活"和"port id 越界"两种原因。
- suggested_fix: 在 `findPortAssignment` 返回哨兵对象前增加 LogHelper.warn 日志，明确说明是"portId not found"而非"port inactive"；或在 `isVirtualPortActive` 中区分两种返回情况并分别记录。

---

## F7: sendRuntimeAnalog 函数签名将 analog id 硬编码为 0/1，无法支持其他 analog 轴组合

- severity: P2
- file: entry/src/main/ets/common/RuntimeInputCommandBridge.ets
- line: 26-38
- evidence_excerpt: |
    export function sendRuntimeAnalog(
      assignments: PortAssignState[],
      port: number,
      index: number,
      x: number,
      y: number
    ): boolean {
      if (!isVirtualPortActive(assignments, port)) {
        return false
      }
      nativeApi.refactoredSendAnalog(port, index, 0, normalizeAnalogValue(x))
      return nativeApi.refactoredSendAnalog(port, index, 1, normalizeAnalogValue(y))
    }
- claim: `refactoredSendAnalog(port, index, id, value)` 的第三个参数 `id` 表示 analog 轴方向（libretro 定义：0=X轴，1=Y轴）。函数将 `id` 硬编码为 0 和 1，意味着每次调用固定发两个轴。若调用者只想发 X 轴（如 joystick 水平灵敏度单独调整）或未来支持 R3/L3 analog 扩展，必须绕过这个封装直接调 NAPI，破坏封装层价值。与 F1 的"丢弃 X 轴结果"合并后，整个 analog 路径的设计一致性存疑。
- suggested_fix: 将 `sendRuntimeAnalog` 分解为 `sendRuntimeAnalogAxis(assignments, port, index, axisId, value)` 单轴版本，调用者按需组合；或保留双轴版但明确注释限制，并补充返回值语义。

---

## F8: LibretroEventHub.subscribe 的 replayLatest 回调在异常时从监听列表移除自身——可能造成意外取消订阅

- severity: P2
- file: entry/src/main/ets/common/LibretroEventHub.ets
- line: 301-312
- evidence_excerpt: |
    const replay = options?.replayLatest ?? this.statefulEvents.has(event);
    if (replay) {
      const last = this.lastPayloads.get(event);
      if (last) {
        try {
          listener.callback(last);
        } catch (err) {
          this.removeListener(event, listener.id);
          this.logCallbackError(event, err);
        }
      }
    }
- claim: 当 `replayLatest` 触发重播时，若回调抛出异常，`removeListener` 被调用——此时 listener 在订阅后立即被移除，后续的 live 事件将永远收不到。这是 subscribe 调用时的"副作用自删除"：调用者以为订阅成功（拿到了 `EventSubscription`），但实际上已经被静默取消注册。特别是 statefulEvents（engine_state、core_crash 等）默认启用 replayLatest，任何 UI 初始化时的一次性异常（例如 State 尚未就绪）都会导致关键事件监听永久丢失。
- suggested_fix: replay 阶段的回调异常只应记录日志，不应 removeListener。仅 live dispatch 时的持续性异常才考虑移除监听器（当前 handleEvent 的逻辑）。或者将 replay 和 live dispatch 的错误处理策略统一为"记录日志但不移除"。
