/*
 * 新架构测试页面 - 使用 refactored* NAPI 接口
 * DEV DIAGNOSTIC ONLY: 不注册到产品 main_pages.json，不作为默认产品路由入口。
 */

import testNapi from 'libentry.so';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import {
  DPadControl,
  ABXYControl,
  StartSelectControl,
  AnalogStickControl
} from '../components/VirtualController';
import {
  createDefaultPortAssignments,
  InputDeviceInfo,
  InputSourceType,
  PortAssignState
} from '../common/InputPortRouting';
import {
  AudioStatusPayload,
  CoreCrashPayload,
  CoreMessagePayload,
  EngineErrorInfo,
  EngineState,
  EventHubScope,
  FpsUpdatePayload,
  GeometryUpdatePayload,
  LibretroEventHub
} from '../common/LibretroEventHub';
import LogHelper from '../common/LogHelper';
import { EmuStateColors, EmuTypography } from '../common/EmuUiTokens';
import { NapiErrorResult } from '../common/ErrorCodes';
import { EmuButton, EmuButtonKind, EmuButtonSize } from '../components/EmuButton';
import { DevDiagnosticsBlock } from '../components/DevDiagnosticsBlock';
import { runtimeCoreDiagnosticController } from '../common/RuntimeCoreDiagnosticController';
import {
  RuntimeSoakState,
  RuntimeSoakTestController
} from '../common/RuntimeSoakTestController';

// NAPI 接口定义 (遵循 AGENTS.md 规范)
interface LibretroNapi {
  refactoredStartEngine(): NapiErrorResult;
  refactoredStopEngine(): boolean;
  refactoredStopEngineAsync(): Promise<boolean>;
  refactoredLoadCore(path: string): NapiErrorResult;
  refactoredLoadRom(
    path: string,
    resMgr?: resourceManager.ResourceManager
  ): NapiErrorResult;
  refactoredSetFilesDir(path: string): boolean;
  refactoredSendInput(port: number, keyId: number, pressed: boolean): boolean;
  refactoredSendAnalog(
    port: number,
    index: number,
    id: number,
    value: number
  ): boolean;
  refactoredAssignPortSource(
    port: number,
    sourceType: number,
    deviceId?: string
  ): boolean;
  refactoredUnassignPort(port: number): boolean;
  refactoredListInputDevices(): InputDeviceInfo[];
  refactoredSetScalingMode(mode: number): boolean;
  refactoredResetStats(): boolean;
  refactoredSetSoftwareMaxResolution(w: number, h: number): boolean;
  refactoredGetCoreOptions(): string;
  refactoredGetCoreOptionsAsync(): Promise<string>;
  refactoredSetCoreOption(key: string, value: string): boolean;
  refactoredSetCoreOptionAsync(key: string, value: string): Promise<boolean>;
  refactoredSetMinimumAudioLatency(ms: number): boolean;
  refactoredSetAIUpscale(enabled: boolean): boolean;
  refactoredPauseEngine(): boolean;
  refactoredResumeEngine(): boolean;
  refactoredGetState(): number;
  refactoredGetStats(): RuntimeStatsDTO;
  refactoredGetInputDebugStats(): InputDebugStats;
  refactoredWaitForStateAsync(
    state: number,
    timeoutMs?: number
  ): Promise<boolean>;
  refactoredGetLastErrorInfo(): EngineErrorInfo;
  refactoredClearLastErrorInfo(): boolean;
}

const nativeApi = testNapi as LibretroNapi;

interface CoreOptionValue {
  value: string;
  label: string;
}

interface CoreOptionItem {
  key: string;
  desc: string;
  value: string;
  values: CoreOptionValue[];
}

interface RuntimeStatsDTO {
  videoRefreshCalls: number;
  videoNullFrames: number;
  videoDupeFrames: number;
  audioBatchCalls: number;
  audioFramesIn: number;
  frameCount: number;
  audioBufferUsage: number;
  audioUnderruns: number;
  audioOverruns: number;
}

interface InputDebugStats {
  touchCount: number;
  mouseCount: number;
  keyCount: number;
  hasFocus: boolean;
  mouseDown: boolean;
  lastTouchType: number;
  lastMouseAction: number;
  lastKeyAction: number;
}

interface ResolutionPreset {
  w: number;
  h: number;
}

// [2026-06-08 D026] V2:改 @ObservedV2 class + @Trace 字段(原裸 interface)。
// build() 读 this.coreCheck.running/.text 传给 DevDiagnosticsBlock 子组件,原 @Local 持
// 裸 interface 时字段就地 mutate(this.coreCheck.running=)不触发 build() 重算→子组件停初值
// (静默不刷新)。@ObservedV2+@Trace 使字段级 mutate 精准触发依赖该字段的节点重渲染。
@ObservedV2
class CoreCheckState {
  @Trace running: boolean = false;
  @Trace text: string = '';
}


// RetroPad Constants removed (imported inputs used dynamically)

@Entry
@ComponentV2
struct LibretroNewArchTestPage {
  @Local status: string = '未启动';
  @Local logs: string[] = [];
  @Local coreOptions: CoreOptionItem[] = [];
  @Local audioStatus: AudioStatusPayload = {
    active: false,
    occupancy: 0,
    underrun: false,
    underruns: 0,
    overruns: 0
  };
  @Local fps: number = 0;
  @Local perfStatsText: string = '';
  @Local geometryText: string = '';
  @Local inputDebugText: string = '';
  @Local inputFocusText: string = '';
  @Local uiInputDebugText: string = '';
  @Local stats: RuntimeStatsDTO = {
    videoRefreshCalls: 0,
    videoNullFrames: 0,
    videoDupeFrames: 0,
    audioBatchCalls: 0,
    audioFramesIn: 0,
    frameCount: 0,
    audioBufferUsage: 0,
    audioUnderruns: 0,
    audioOverruns: 0
  };
  @Local scalingMode: number = 2;
  @Local softwareMaxPresetIndex: number = 1;
  @Local autoAdjust: boolean = true;
  @Local latencyMs: number = 0;
  @Local lastAdjustTs: number = 0;
  @Local lastUnderruns: number = 0;
  @Local selectedPortIndex: number = 0;
  @Local portAssignments: PortAssignState[] = createDefaultPortAssignments();
  @Local inputDevices: InputDeviceInfo[] = [];
  @Local alertMsg: string = '';
  @Local alertVisible: boolean = false;
  @Local drawerVisible: boolean = false;
  @Local logsOverlayVisible: boolean = false;
  @Local useDrawer: boolean = false;
  @Local aiUpscaleEnabled: boolean = false;
  @Local xengineAvailable: boolean = false;
  @Local hideVirtualController: boolean = false;
  @Local coreCheck: CoreCheckState = new CoreCheckState();
  @Local soakState: RuntimeSoakState = { running: false, secondsLeft: 0, summaryText: '' };
  private readonly soakController: RuntimeSoakTestController = new RuntimeSoakTestController();
  private readonly logDate: Date = new Date();

  private xComponentId: string = 'new_arch_xcomponent';
  private eventScope: EventHubScope | undefined = undefined;
  private inputDebugTimer: number = -1;
  private pageActive: boolean = false;
  private uiTouchCount: number = 0;
  private uiMouseCount: number = 0;
  private uiKeyCount: number = 0;
  private uiLastTouchType: number = -1;
  private uiLastMouseAction: number = -1;
  private uiLastKeyType: number = -1;
  private inputSourceOptions: SelectOption[] = [
    { value: '未分配' },
    { value: '虚拟手柄' },
    { value: '键盘' },
    { value: '鼠标' },
    { value: '手柄' },
    { value: '蓝牙手柄' }
  ];
  private inputSourceTypes: InputSourceType[] = [
    InputSourceType.None,
    InputSourceType.Virtual,
    InputSourceType.Keyboard,
    InputSourceType.Mouse,
    InputSourceType.Gamepad,
    InputSourceType.BluetoothGamepad
  ];

  // === 内联回调提取（类属性箭头函数，避免每次 build() 创建新函数对象） ===
  private onOpenDrawer = (): void => {
    this.log('UI: 点击打开抽屉 -> true');
    this.drawerVisible = true;
    this.logsOverlayVisible = false;
  };
  private onToggleLogs = (): void => {
    this.logsOverlayVisible = !this.logsOverlayVisible;
    if (this.logsOverlayVisible) {
      this.drawerVisible = false;
    }
  };
  private onHideVirtualCtrlChange = (v: boolean): void => {
    this.hideVirtualController = v;
    this.log(`UI: 隐藏虚拟手柄 = ${v}`);
  };
  private onSelectPort0 = (): void => { this.selectedPortIndex = 0; };
  private onSelectPort1 = (): void => { this.selectedPortIndex = 1; };
  private onSelectPort2 = (): void => { this.selectedPortIndex = 2; };
  private onSelectPort3 = (): void => { this.selectedPortIndex = 3; };
  private onInputSourceSelect = (index: number): void => {
    const sourceType = this.inputSourceTypes[index] ?? InputSourceType.None;
    this.applyPortAssignment(this.selectedPortIndex, sourceType, true, this.currentPortAssignment.deviceId);
  };
  private onStartEngine = async (): Promise<void> => {
    this.log('调用 refactoredStartEngine');
    nativeApi.refactoredClearLastErrorInfo();
    const startResult = nativeApi.refactoredStartEngine();
    this.log(`refactoredStartEngine 返回: ${startResult.success}`);
    if (!startResult.success) { this.status = '启动失败'; return; }
    const started = await nativeApi.refactoredWaitForStateAsync(EngineState.STARTING, 5000);
    if (!this.pageActive) {
      return;
    }
    this.status = started ? '引擎已启动' : '启动超时';
  };
  private onSetFilesDir = (): void => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const filesDir = context.filesDir;
    this.log(`调用 refactoredSetFilesDir: ${LogHelper.describePathForLog(filesDir)}`);
    const ok: boolean = nativeApi.refactoredSetFilesDir(filesDir);
    this.log(`refactoredSetFilesDir 返回: ${ok}`);
  };
  private onLoadCore = async (): Promise<void> => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const abiPath = this.resolveAbiPath();
    const corePath = `${context.bundleCodeDir}/libs/${abiPath}/libgambatte_libretro.so`;
    this.log(`调用 refactoredLoadCore: ${LogHelper.describePathForLog(corePath)}`);
    const coreResult = nativeApi.refactoredLoadCore(corePath);
    this.log(`refactoredLoadCore 返回: ${coreResult.success}`);
    if (!coreResult.success) { this.status = '核心加载失败'; return; }
    const loaded = await nativeApi.refactoredWaitForStateAsync(EngineState.CORE_LOADED, 5000);
    if (!this.pageActive) {
      return;
    }
    if (!loaded) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const detail = err && err.reason ? `原因: ${err.reason}` : '原因未知';
      this.log(`LoadCore 超时: ${detail}`);
    }
    this.status = loaded ? '核心已加载' : '核心加载超时';
  };
  private onInitOptions = (): void => { void this.refreshCoreOptions(); };
  private onLoadRom = async (): Promise<void> => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const resMgr = context.resourceManager;
    this.log('调用 refactoredLoadRom: roms/snake_v0.1.gb');
    const romResult = nativeApi.refactoredLoadRom('roms/snake_v0.1.gb', resMgr);
    this.log(`refactoredLoadRom 返回: ${romResult.success}`);
    if (!romResult.success) { this.status = 'ROM加载失败'; return; }
    const running = await nativeApi.refactoredWaitForStateAsync(EngineState.RUNNING, 5000);
    if (!this.pageActive) {
      return;
    }
    if (!running) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const detail = err && err.reason ? `原因: ${err.reason}` : '原因未知';
      this.log(`LoadRom 超时: ${detail}`);
    }
    this.status = running ? 'ROM已加载，运行中' : 'ROM加载超时';
    if (romResult.success) { void this.refreshCoreOptions(); }
  };
  private onPauseEngine = (): void => {
    this.log('调用 refactoredPauseEngine');
    const ok: boolean = nativeApi.refactoredPauseEngine();
    this.log(`refactoredPauseEngine 返回: ${ok}`);
    this.status = '已暂停';
  };
  private onResumeEngine = (): void => {
    this.log('调用 refactoredResumeEngine');
    const ok: boolean = nativeApi.refactoredResumeEngine();
    this.log(`refactoredResumeEngine 返回: ${ok}`);
    this.status = '运行中';
  };
  private onStopEngine = async (): Promise<void> => {
    this.log('调用 refactoredStopEngine');
    const ok: boolean = await nativeApi.refactoredStopEngineAsync();
    if (!this.pageActive) {
      return;
    }
    this.log(`refactoredStopEngine 返回: ${ok}`);
    if (!ok) { this.status = '停止失败'; return; }
    const stopped = await nativeApi.refactoredWaitForStateAsync(EngineState.STOPPED, 5000);
    if (!this.pageActive) {
      return;
    }
    this.status = stopped ? '已停止' : '停止超时';
  };
  private onQueryState = (): void => {
    const state: number = nativeApi.refactoredGetState();
    const stateNames: string[] = ['INIT', 'CORE_LOADED', 'GAME_LOADED', 'RUNNING', 'PAUSED', 'STOPPING', 'STOPPED', 'STARTING', 'LOADING', 'ERROR'];
    this.log(`当前状态: ${stateNames[state] || state}`);
  };

  private readRuntimeStats(): RuntimeStatsDTO {
    const s = nativeApi.refactoredGetStats() as RuntimeStatsDTO;
    return {
      videoRefreshCalls: Number(s.videoRefreshCalls) || 0,
      videoNullFrames: Number(s.videoNullFrames) || 0,
      videoDupeFrames: Number(s.videoDupeFrames) || 0,
      audioBatchCalls: Number(s.audioBatchCalls) || 0,
      audioFramesIn: Number(s.audioFramesIn) || 0,
      frameCount: Number(s.frameCount) || 0,
      audioBufferUsage: Number(s.audioBufferUsage) || 0,
      audioUnderruns: Number(s.audioUnderruns) || 0,
      audioOverruns: Number(s.audioOverruns) || 0
    };
  }

  private applyRuntimeStats(stats: RuntimeStatsDTO): void {
    this.stats = stats;
  }

  private syncAudioStatusFromStats(stats: RuntimeStatsDTO): void {
    const occupancyPercent = Math.max(0, Math.min(100, Math.round((Number(stats.audioBufferUsage) || 0) * 100)));
    const underruns = Number(stats.audioUnderruns) || 0;
    const overruns = Number(stats.audioOverruns) || 0;
    const active = this.audioStatus.active || Number(stats.audioBatchCalls) > 0 || Number(stats.frameCount) > 0;

    this.audioStatus = {
      active: active,
      occupancy: occupancyPercent,
      underrun: underruns > this.lastUnderruns || (active && occupancyPercent <= 10),
      underruns: underruns,
      overruns: overruns
    };
  }

  private syncAudioAlert(): void {
    const occupancy = Number(this.audioStatus.occupancy) || 0;
    const underruns = Number(this.audioStatus.underruns) || 0;
    const overruns = Number(this.audioStatus.overruns) || 0;

    if (this.audioStatus.underrun) {
      this.alertVisible = true;
      this.alertMsg = `音频欠载：Buf ${occupancy}% · U/O ${underruns}/${overruns}`;
      return;
    }

    if (this.audioStatus.active && occupancy >= 85) {
      this.alertVisible = true;
      this.alertMsg = `缓冲高占用：Buf ${occupancy}% · U/O ${underruns}/${overruns}`;
      return;
    }

    this.alertVisible = false;
    this.alertMsg = '';
  }

  private refreshRuntimeStats(logMessage: string): void {
    try {
      const stats = this.readRuntimeStats();
      this.applyRuntimeStats(stats);
      this.syncAudioStatusFromStats(stats);
      this.handleAudioStatus();
      this.log(logMessage);
    } catch (_) {
      this.log(`${logMessage}失败`);
    }
  }

  private onQueryStats = (): void => {
    this.refreshRuntimeStats('已刷新统计');
  };
  private onResetStats = (): void => {
    const ok = nativeApi.refactoredResetStats();
    this.log(`重置统计: ${ok}`);
    if (ok) {
      this.lastUnderruns = 0;
      this.alertVisible = false;
      this.alertMsg = '';
      this.refreshRuntimeStats('统计已清零');
    }
  };
  private onAiUpscaleChange = (v: boolean): void => {
    if (!this.xengineAvailable) {
      this.aiUpscaleEnabled = false;
      this.log('XEngine 不可用：当前设备不支持 SystemCapability.Graphic.XEngine');
      return;
    }
    this.aiUpscaleEnabled = v;
    const ok = nativeApi.refactoredSetAIUpscale(v);
    this.log(`设置 AI 超分: ${v} => ${ok}`);
  };
  private onAutoAdjustChange = (v: boolean): void => { this.autoAdjust = v; };
  private onLatencyChange = (v: number): void => {
    this.latencyMs = Math.max(0, Math.min(200, Math.round(v)));
    const ok: boolean = nativeApi.refactoredSetMinimumAudioLatency(this.latencyMs);
    this.log(`设置最小延迟: ${this.latencyMs}ms => ${ok}`);
  };
  private onRefreshAudioStatus = (): void => {
    this.refreshRuntimeStats('已刷新音频状态');
  };
  private onRefreshPerformanceSnapshot = (): void => {
    this.refreshRuntimeStats('已刷新性能快照');
  };
  private onClearAlert = (): void => { this.alertVisible = false; this.alertMsg = ''; };
  private onCloseDrawer = (): void => { this.drawerVisible = false; };
  private onCloseLogs = (): void => { this.logsOverlayVisible = false; };
  private onScalingModeHW = (): void => {
    const okMode = nativeApi.refactoredSetScalingMode(0);
    const okStats = nativeApi.refactoredResetStats();
    this.scalingMode = 0; this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`切换画质模式: 0(HW), okMode=${okMode}, okStats=${okStats}`);
  };
  private onScalingModeSW = (): void => {
    const presets: ResolutionPreset[] = [{ w: 640, h: 480 }, { w: 1280, h: 720 }, { w: 1920, h: 1080 }];
    const preset = presets[this.softwareMaxPresetIndex] || presets[1];
    const okMode = nativeApi.refactoredSetScalingMode(1);
    const okMax = nativeApi.refactoredSetSoftwareMaxResolution(preset.w, preset.h);
    const okStats = nativeApi.refactoredResetStats();
    this.scalingMode = 1; this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`切换画质模式: 1(SW) ${preset.w}x${preset.h}, okMode=${okMode}, okMax=${okMax}, okStats=${okStats}`);
  };
  private onScalingModeGLES = (): void => {
    const okMode = nativeApi.refactoredSetScalingMode(2);
    const okStats = nativeApi.refactoredResetStats();
    this.scalingMode = 2; this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`切换画质模式: 2(GLES), okMode=${okMode}, okStats=${okStats}`);
  };
  private onSWPreset480p = (): void => {
    this.softwareMaxPresetIndex = 0; const okMax = nativeApi.refactoredSetSoftwareMaxResolution(640, 480);
    const okStats = nativeApi.refactoredResetStats(); this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`设置软件最大分辨率: 640x480, okMax=${okMax}, okStats=${okStats}`);
  };
  private onSWPreset720p = (): void => {
    this.softwareMaxPresetIndex = 1; const okMax = nativeApi.refactoredSetSoftwareMaxResolution(1280, 720);
    const okStats = nativeApi.refactoredResetStats(); this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`设置软件最大分辨率: 1280x720, okMax=${okMax}, okStats=${okStats}`);
  };
  private onSWPreset1080p = (): void => {
    this.softwareMaxPresetIndex = 2; const okMax = nativeApi.refactoredSetSoftwareMaxResolution(1920, 1080);
    const okStats = nativeApi.refactoredResetStats(); this.fps = 0; this.perfStatsText = ''; this.geometryText = '';
    this.log(`设置软件最大分辨率: 1920x1080, okMax=${okMax}, okStats=${okStats}`);
  };

  aboutToAppear() {
    this.pageActive = true;
    this.log('页面加载');

    try {
      this.xengineAvailable = canIUse('SystemCapability.Graphic.XEngine');
    } catch (_) {
      this.xengineAvailable = false;
    }
    this.eventScope = LibretroEventHub.getInstance().createScope();
    this.eventScope.onOptionsUpdate((_payload) => {
      void this.refreshCoreOptions();
    });
    this.eventScope.onAudioStatus((payload) => {
      this.audioStatus = {
        active: payload.active,
        occupancy: Number(payload.occupancy) || 0,
        underrun: payload.underrun,
        underruns: Number(payload.underruns) || 0,
        overruns: Number(payload.overruns) || 0
      };
      this.handleAudioStatus();
    });
    this.eventScope.onFpsUpdate((payload) => {
      this.handleFpsUpdate(payload);
    });
    this.eventScope.onGeometryUpdate((payload) => {
      this.handleGeometryUpdate(payload);
    });
    this.eventScope.onCoreMessage((payload) => {
      this.handleCoreMessage(payload);
    });
    this.eventScope.onCoreCrash((payload) => {
      this.handleCoreCrash(payload);
    });
    this.startInputDebug();
    this.refreshInputDevices();
    this.syncPortAssignments();
  }

  aboutToDisappear() {
    this.pageActive = false;
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
    this.log('页面销毁，停止引擎');
    void nativeApi.refactoredStopEngineAsync();
    this.stopInputDebug();
  }

  log(msg: string) {
    this.logDate.setTime(Date.now());
    const time = this.logDate.toLocaleTimeString();
    this.logs = [`[${time}] ${msg}`, ...this.logs.slice(0, 19)];
    LogHelper.info('NewArchTest', 'Test', msg);
  }

  private refreshInputDevices() {
    try {
      this.inputDevices = nativeApi.refactoredListInputDevices() || [];
    } catch (e) {
      this.inputDevices = [];
      this.log(`获取设备列表失败: ${(e as Error).message}`);
    }
  }

  private syncPortAssignments() {
    this.portAssignments.forEach((assignment) => {
      this.applyPortAssignment(assignment.portId, assignment.sourceType, false, assignment.deviceId);
    });
  }

  private getPortAssignment(portId: number): PortAssignState {
    const assignments = this.portAssignments ?? [];
    const found = assignments.find((item) => item.portId === portId);
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

  private getInputSourceIndex(sourceType: InputSourceType): number {
    const index = this.inputSourceTypes.indexOf(sourceType);
    return index >= 0 ? index : 0;
  }

  private createSelectOption(value: ResourceStr): SelectOption {
    return { value: value };
  }

  private get currentPortAssignment(): PortAssignState {
    return this.getPortAssignment(this.selectedPortIndex);
  }

  private get currentInputSourceIndex(): number {
    return this.getInputSourceIndex(this.currentPortAssignment.sourceType);
  }

  private get inputSourceOptionsSafe(): SelectOption[] {
    const options = this.inputSourceOptions ?? [];
    return options.length > 0
      ? options
      : [this.createSelectOption('未分配')];
  }

  private get safeInputSourceIndex(): number {
    const options = this.inputSourceOptionsSafe;
    const index = this.currentInputSourceIndex;
    if (index < 0) {
      return 0;
    }
    if (index >= options.length) {
      return options.length - 1;
    }
    return index;
  }

  private get currentInputSourceLabel(): ResourceStr {
    const options = this.inputSourceOptions ?? [];
    if (options.length === 0) {
      return '未分配';
    }
    const index = this.safeInputSourceIndex;
    const option = options[index];
    if (!option || option.value === undefined || option.value === null) {
      return '未分配';
    }
    return option.value;
  }

  private updatePortAssignment(portId: number, sourceType: InputSourceType, deviceId: string) {
    this.portAssignments = this.portAssignments.map((item) => {
      if (item.portId !== portId) {
        return item;
      }
      return {
        portId: portId,
        sourceType: sourceType,
        deviceId: deviceId,
        isActive: sourceType !== InputSourceType.None
      };
    });
  }

  private applyPortAssignment(
    portId: number,
    sourceType: InputSourceType,
    updateState: boolean,
    deviceId: string = ''
  ) {
    let ok = false;
    if (sourceType === InputSourceType.None) {
      ok = nativeApi.refactoredUnassignPort(portId);
    } else {
      ok = nativeApi.refactoredAssignPortSource(portId, sourceType, deviceId || undefined);
    }
    if (updateState) {
      this.updatePortAssignment(portId, sourceType, deviceId);
    }
    if (!ok) {
      this.log(`端口映射失败: port=${portId} source=${sourceType}`);
    }
  }

  private isVirtualPortActive(portId: number): boolean {
    const assignment = this.getPortAssignment(portId);
    return assignment.sourceType === InputSourceType.Virtual;
  }

  private sendAnalog(index: number, x: number, y: number) {
    if (!this.isVirtualPortActive(this.selectedPortIndex)) {
      return;
    }
    const xVal = this.normalizeAnalogValue(x);
    const yVal = this.normalizeAnalogValue(y);
    nativeApi.refactoredSendAnalog(this.selectedPortIndex, index, 0, xVal);
    nativeApi.refactoredSendAnalog(this.selectedPortIndex, index, 1, yVal);
  }

  private sendButton(keyId: number, pressed: boolean) {
    if (!this.isVirtualPortActive(this.selectedPortIndex)) {
      return;
    }
    nativeApi.refactoredSendInput(this.selectedPortIndex, keyId, pressed);
  }

  private normalizeAnalogValue(value: number): number {
    let v = value;
    if (v > 1) {
      v = 1;
    } else if (v < -1) {
      v = -1;
    }
    if (v >= 0) {
      return Math.round(v * 32767);
    }
    return Math.round(v * 32768);
  }

  async refreshCoreOptions(): Promise<void> {
    const nextOptions = await this.getCoreOptions();
    if (!this.pageActive) {
      return;
    }
    this.coreOptions = nextOptions;
    this.log('刷新选项完成');
  }

  handleAudioStatus() {
    const underruns = Number(this.audioStatus.underruns) || 0;
    if (underruns > this.lastUnderruns) {
      this.lastUnderruns = underruns;
    }
    this.syncAudioAlert();

    if (this.autoAdjust && this.audioStatus.underrun) {
      const now = Date.now();
      if (now - this.lastAdjustTs > 2000) {
        this.latencyMs = Math.min(200, this.latencyMs + 20);
        nativeApi.refactoredSetMinimumAudioLatency(this.latencyMs);
        this.lastAdjustTs = now;
        this.log(`自动调节: 检测到欠载，增加延迟至 ${this.latencyMs}ms`);
      }
    }
  }

  handleFpsUpdate(payload: FpsUpdatePayload) {
    const v = Number(payload.fps);
    if (!Number.isNaN(v)) this.fps = v;

    const drops = Number(payload.drops ?? 0);
    const dupes = Number(payload.dupes ?? 0);
    const nulls = Number(payload.nulls ?? 0);
    const underruns = Number(payload.underruns ?? 0);
    const overruns = Number(payload.overruns ?? 0);
    const buf = Number(payload.audioBufferUsage ?? 0);
    this.perfStatsText = `D:${drops} Du:${dupes} N:${nulls} U/O:${underruns}/${overruns} Buf:${buf.toFixed(0)}%`;
  }

  handleGeometryUpdate(payload: GeometryUpdatePayload) {
    const w = Number(payload.base_width);
    const h = Number(payload.base_height);
    const a = Number(payload.aspect_ratio ?? 0);
    if (w > 0 && h > 0) {
      const aspectText = (a > 0) ? a.toFixed(3) : (w / h).toFixed(3);
      this.geometryText = `Base:${w}x${h} AR:${aspectText}`;
    }
  }

  handleCoreMessage(payload: CoreMessagePayload) {
    this.log(`核心消息: ${payload.msg}`);
  }

  handleCoreCrash(payload: CoreCrashPayload) {
    this.log(`核心异常: ${payload.reason}`);
  }

  private updateInputDebugStats() {
    try {
      const stats = nativeApi.refactoredGetInputDebugStats() as InputDebugStats;
      const touchCount = Number(stats.touchCount);
      const mouseCount = Number(stats.mouseCount);
      const keyCount = Number(stats.keyCount);
      const lastTouch = Number(stats.lastTouchType);
      const lastMouse = Number(stats.lastMouseAction);
      const lastKey = Number(stats.lastKeyAction);
      const hasFocus = Boolean(stats.hasFocus);
      const mouseDown = Boolean(stats.mouseDown);

      const touchText = Number.isFinite(touchCount) ? touchCount : 0;
      const mouseText = Number.isFinite(mouseCount) ? mouseCount : 0;
      const keyText = Number.isFinite(keyCount) ? keyCount : 0;
      const lastTouchText = Number.isFinite(lastTouch) ? lastTouch : -1;
      const lastMouseText = Number.isFinite(lastMouse) ? lastMouse : -1;
      const lastKeyText = Number.isFinite(lastKey) ? lastKey : -1;

      this.inputDebugText =
        `Touch:${touchText}(${lastTouchText}) Mouse:${mouseText}(${lastMouseText}) Key:${keyText}(${lastKeyText})`;
      this.inputFocusText = `Focus:${hasFocus ? 'Y' : 'N'} MouseDown:${mouseDown ? 'Y' : 'N'}`;
      this.uiInputDebugText =
        `UI Touch:${this.uiTouchCount}(${this.uiLastTouchType}) ` +
        `Mouse:${this.uiMouseCount}(${this.uiLastMouseAction}) ` +
        `Key:${this.uiKeyCount}(${this.uiLastKeyType})`;
    } catch (_) {
      this.inputDebugText = '';
      this.inputFocusText = '';
      this.uiInputDebugText = '';
    }
  }

  private startInputDebug() {
    if (this.inputDebugTimer !== -1) {
      clearInterval(this.inputDebugTimer);
    }
    this.updateInputDebugStats();
    this.inputDebugTimer = setInterval(() => {
      this.updateInputDebugStats();
    }, 500);
  }

  private stopInputDebug() {
    if (this.inputDebugTimer !== -1) {
      clearInterval(this.inputDebugTimer);
      this.inputDebugTimer = -1;
    }
  }

  private resolveAbiPath(): string {
    const rawAbiList = String(deviceInfo.abiList ?? '').toLowerCase();
    return rawAbiList.indexOf('x86_64') >= 0 ? 'x86_64' : 'arm64';
  }

  // 复用 onLoadCore 同款 corePath（gambatte），保持 dev 页只验证当前正在用的核心。
  private resolveDiagnosticCorePath(): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return '';
    }
    const abiPath = this.resolveAbiPath();
    return `${context.bundleCodeDir}/libs/${abiPath}/libgambatte_libretro.so`;
  }

  async runCoreCheck(): Promise<void> {
    if (this.coreCheck.running) {
      return;
    }
    this.coreCheck.running = true;
    this.coreCheck.text = '正在验证核心符号...';
    try {
      const corePath = this.resolveDiagnosticCorePath();
      if (!corePath) {
        this.coreCheck.text = '获取 Context 失败';
        return;
      }
      const result = await runtimeCoreDiagnosticController.testCoreLoader(corePath);
      if (!this.pageActive) {
        return;
      }
      this.coreCheck.text = result;
    } catch (e) {
      if (!this.pageActive) {
        return;
      }
      const msg = (e as Error)?.message || String(e);
      this.coreCheck.text = `Failed: ${msg}`;
      LogHelper.error('NewArchTest', 'Core', `符号验证异常: ${msg}`);
    } finally {
      if (this.pageActive) {
        this.coreCheck.running = false;
      }
    }
  }

  startSoak(durationSeconds: number): void {
    const running = nativeApi.refactoredGetState() === EngineState.RUNNING;
    this.soakController.start(durationSeconds, running, (state: RuntimeSoakState) => {
      this.applySoakState(state);
    });
  }

  stopSoak(): void {
    this.soakController.stop((state: RuntimeSoakState) => {
      this.applySoakState(state);
    });
  }

  private applySoakState(state: RuntimeSoakState): void {
    // [D026] 整体替换而非字段就地 mutate:RuntimeSoakState 是 controller 共享 DTO
    // (不宜改 @ObservedV2 class),故 @Local 整体赋值触发引用变化→build() 重渲染。
    this.soakState = {
      running: state.running,
      secondsLeft: state.secondsLeft,
      summaryText: state.summaryText
    };
  }

  private onCoreCheckClick = (): void => {
    void this.runCoreCheck();
  };

  private onSoakToggleClick = (): void => {
    if (this.soakState.running) {
      this.stopSoak();
    } else {
      this.startSoak(600);
    }
  };


  parseOptionsJson(s: string): CoreOptionItem[] {
  try {
    const arr = JSON.parse(s) as Partial<CoreOptionItem>[] | null;
    if (!Array.isArray(arr)) return [];
    return arr.map((item: Partial<CoreOptionItem>): CoreOptionItem => {
      return {
        key: String(item.key ?? ''),
        desc: String(item.desc ?? ''),
        value: String(item.value ?? ''),
        values: Array.isArray(item.values) ? item.values.map((value: Partial<CoreOptionValue>): CoreOptionValue => {
          return {
            value: String(value.value ?? ''),
            label: String(value.label ?? '')
          };
        }) : []
      };
    }).filter((item: CoreOptionItem) => item.key.length > 0);
  } catch (_) {
    return [];
  }
}
  async getCoreOptions(): Promise<CoreOptionItem[]> {
    try {
      const s: string = await nativeApi.refactoredGetCoreOptionsAsync();
      return this.parseOptionsJson(s);
    } catch (_) {
      return [];
    }
  }

  // === 共享 @Builder：控制面板内容（主区域 + drawer 复用） ===

  @Builder
  EngineControlButtons() {
    Row() {
      Button('1. 启动引擎')
        .fontSize(EmuTypography.sm)
        .onClick(this.onStartEngine)
      Button('2. 设置目录')
        .fontSize(EmuTypography.sm)
        .margin({ left: 5 })
        .onClick(this.onSetFilesDir)
      Button('3. 加载核心')
        .fontSize(EmuTypography.sm)
        .margin({ left: 5 })
        .onClick(this.onLoadCore)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  InitOptionsButton() {
    Row() {
      Button('初始化事件/读取选项')
        .fontSize(EmuTypography.sm)
        .onClick(this.onInitOptions)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  RomControlButtons() {
    // 示范替换：4 个 inline Button → EmuButton（统一 kind/size/Curve.EaseInOut 动效）。
    // 本测试页其余 ~30 个 Button 暂保留 inline 写法，留待产品视觉确认 EmuButton 配色与
    // 现有 toggle/Material 蓝紫风格的取舍后再批量替换。
    Row({ space: 5 }) {
      EmuButton({
        label: '4. 加载ROM',
        kind: EmuButtonKind.SECONDARY,
        buttonSize: EmuButtonSize.SM,
        onTap: () => { void this.onLoadRom() }
      })
      EmuButton({
        label: '暂停',
        kind: EmuButtonKind.WARNING,
        buttonSize: EmuButtonSize.SM,
        onTap: () => { this.onPauseEngine() }
      })
      EmuButton({
        label: '继续',
        kind: EmuButtonKind.SUCCESS,
        buttonSize: EmuButtonSize.SM,
        onTap: () => { this.onResumeEngine() }
      })
      EmuButton({
        label: '停止',
        kind: EmuButtonKind.DANGER,
        buttonSize: EmuButtonSize.SM,
        onTap: () => { void this.onStopEngine() }
      })
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  QueryButtons() {
    Row() {
      Button('查询状态')
        .fontSize(EmuTypography.sm)
        .onClick(this.onQueryState)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)

    Row() {
      Button('查询统计')
        .fontSize(EmuTypography.sm)
        .onClick(this.onQueryStats)
      Button('重置统计')
        .fontSize(EmuTypography.sm)
        .margin({ left: 5 })
        .onClick(this.onResetStats)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  StatsDisplay() {
    Column() {
      Text('统计')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Text(`视频刷新: ${this.stats.videoRefreshCalls}  空帧: ${this.stats.videoNullFrames}  dupe: ${this.stats.videoDupeFrames}`)
        .fontSize(EmuTypography.sm)
        .fontColor('#CCC')
      Text(`音频批量: ${this.stats.audioBatchCalls}  帧入: ${this.stats.audioFramesIn}  缓冲占用: ${(this.stats.audioBufferUsage * 100).toFixed(0)}%`)
        .fontSize(EmuTypography.sm)
        .fontColor('#CCC')
      Text(`欠载: ${this.stats.audioUnderruns}  过载: ${this.stats.audioOverruns}  帧计数: ${this.stats.frameCount}`)
        .fontSize(EmuTypography.sm)
        .fontColor('#CCC')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  @Builder
  CoreOptionsDisplay() {
    Column() {
      Text('Core Options')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      ForEach(this.coreOptions, (opt: CoreOptionItem) => {
        Row() {
          Text(`${opt.desc}: ${opt.value}`)
            .fontSize(EmuTypography.sm)
            .fontColor('#CCC')
          Blank()
          Button('切换')
            .fontSize(EmuTypography.sm)
            .onClick(async () => {
              const values: CoreOptionValue[] = Array.isArray(opt.values) ? opt.values : [];
              const idx = Math.max(0, values.findIndex((v: CoreOptionValue) => v.value === opt.value));
              const next = values.length > 0 ? values[(idx + 1) % values.length] : undefined;
              if (next && next.value) {
                const ok = await nativeApi.refactoredSetCoreOptionAsync(opt.key, next.value);
                if (ok) {
                  void this.refreshCoreOptions();
                }
              }
            })
        }
        .width('100%')
        .padding(4)
      }, (opt: CoreOptionItem) => opt.key)
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  @Builder
  VideoControlSection() {
    Column() {
      Text('视频控制')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Row() {
        Text('AI 画质增强 (XEngine)')
          .fontSize(EmuTypography.sm)
          .fontColor('#CCC')
        Toggle({ type: ToggleType.Switch, isOn: this.aiUpscaleEnabled })
          .enabled(this.xengineAvailable)
          .onChange(this.onAiUpscaleChange)
      }
      .width('100%')
      .padding(4)
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  @Builder
  AudioControlSection() {
    Column() {
      Text('音频控制')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Row() {
        Text('自动调节')
          .fontSize(EmuTypography.sm)
          .fontColor('#CCC')
        Toggle({ type: ToggleType.Switch, isOn: this.autoAdjust })
          .onChange(this.onAutoAdjustChange)
      }
      .width('100%')
      .padding(4)
      Row() {
        Text(`最小延迟: ${this.latencyMs}ms`)
          .fontSize(EmuTypography.sm)
          .fontColor('#CCC')
        Slider({
          value: this.latencyMs,
          min: 0,
          max: 200,
          step: 10
        })
          .onChange(this.onLatencyChange)
      }
      .width('100%')
      .padding(4)
      Row() {
        Button('刷新音频状态')
          .fontSize(EmuTypography.sm)
          .onClick(this.onRefreshAudioStatus)
        Button('刷新性能快照')
          .fontSize(EmuTypography.sm)
          .margin({ left: 5 })
          .onClick(this.onRefreshPerformanceSnapshot)
      }
      .width('100%')
      .padding(4)
      if (this.alertVisible) {
        Row() {
          Text(this.alertMsg)
            .fontSize(EmuTypography.sm)
            .fontColor(EmuStateColors.dangerDefault)
          Blank()
          Button('清除告警')
            .fontSize(EmuTypography.sm)
            .onClick(this.onClearAlert)
        }
        .width('100%')
        .padding(4)
        .backgroundColor('#2A0000')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  @Builder
  AudioStatusDisplay() {
    Column() {
      Text('音频状态')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Text(`运行: ${this.audioStatus.active ? '是' : '否'}  占用: ${this.audioStatus.occupancy}%  欠载: ${this.audioStatus.underrun ? '是' : '否'}`)
        .fontSize(EmuTypography.sm)
        .fontColor('#CCC')
      Text(`欠载次数: ${this.audioStatus.underruns}  过载次数: ${this.audioStatus.overruns}`)
        .fontSize(EmuTypography.sm)
        .fontColor('#CCC')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  @Builder
  HeaderSection() {
    Column() {
      Row() {
        Text('新架构测试')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)

        Blank()

        Text(this.status)
          .fontSize(EmuTypography.md)
          .fontColor('#4CAF50')
        Text(`FPS: ${this.fps.toFixed(2)}`)
          .fontSize(EmuTypography.md)
          .fontColor('#4CAF50')

        Text(this.perfStatsText)
          .fontSize(EmuTypography.xs)
          .fontColor('#CCCCCC')

        if (this.geometryText.length > 0) {
          Text(this.geometryText)
            .fontSize(EmuTypography.xs)
            .fontColor('#CCCCCC')
        }
      }
      .width('100%')
      .padding(15)

      Row() {
        Text(`XComponentId: ${this.xComponentId}`)
          .fontSize(EmuTypography.sm)
          .fontColor('#CCCCCC')
      }
      .width('100%')
      .padding({ left: 15, right: 15, bottom: 10 })

      Column() {
        if (this.inputDebugText.length > 0) {
          Text(this.inputDebugText)
            .fontSize(EmuTypography.sm)
            .fontColor('#CCCCCC')
        }
        if (this.inputFocusText.length > 0) {
          Text(this.inputFocusText)
            .fontSize(EmuTypography.sm)
            .fontColor('#CCCCCC')
        }
        if (this.uiInputDebugText.length > 0) {
          Text(this.uiInputDebugText)
            .fontSize(EmuTypography.sm)
            .fontColor('#CCCCCC')
        }
      }
      .width('100%')
      .padding({ left: 15, right: 15, bottom: 10 })
    }
    .width('100%')
    .backgroundColor('#333')
  }

  @Builder
  SurfaceSection() {
    XComponent({
      id: this.xComponentId,
      type: XComponentType.SURFACE,
      libraryname: 'entry'
    })
      .width('100%')
      .height('40%')
      .backgroundColor(Color.Black)
      .focusable(true)
      .focusOnTouch(true)
      .onTouch((event) => {
        this.uiTouchCount += 1;
        this.uiLastTouchType = Number(event.type);
      })
      .onMouse((event) => {
        this.uiMouseCount += 1;
        this.uiLastMouseAction = Number(event.action);
      })
      .onKeyEvent((event) => {
        if (!event) {
          return;
        }
        this.uiKeyCount += 1;
        this.uiLastKeyType = Number(event.type);
      })
      .onLoad(() => {
        this.log(`XComponent onLoad id=${this.xComponentId}`);
      })
      .onDestroy(() => {
        this.log(`XComponent onDestroy id=${this.xComponentId}`);
      })
  }

  @Builder
  TopActionBar() {
    Row() {
      Blank()
      Button('打开抽屉')
        .fontSize(EmuTypography.sm)
        .onClick(this.onOpenDrawer)
      Button(this.logsOverlayVisible ? '隐藏日志' : '显示日志')
        .fontSize(EmuTypography.sm)
        .margin({ left: 5 })
        .onClick(this.onToggleLogs)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.End)
  }

  @Builder
  PortSelectionSection() {
    Row() {
      Text('端口')
        .fontSize(EmuTypography.sm)
        .fontColor(Color.White)
        .margin({ right: 8 })

      Button('P1')
        .fontSize(EmuTypography.sm)
        .backgroundColor(this.selectedPortIndex === 0 ? '#1976D2' : '#455A64')
        .onClick(this.onSelectPort0)

      Button('P2')
        .fontSize(EmuTypography.sm)
        .margin({ left: 6 })
        .backgroundColor(this.selectedPortIndex === 1 ? '#1976D2' : '#455A64')
        .onClick(this.onSelectPort1)

      Button('P3')
        .fontSize(EmuTypography.sm)
        .margin({ left: 6 })
        .backgroundColor(this.selectedPortIndex === 2 ? '#1976D2' : '#455A64')
        .onClick(this.onSelectPort2)

      Button('P4')
        .fontSize(EmuTypography.sm)
        .margin({ left: 6 })
        .backgroundColor(this.selectedPortIndex === 3 ? '#1976D2' : '#455A64')
        .onClick(this.onSelectPort3)
    }
    .width('100%')
    .padding({ left: 10, right: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  InputSourceSection() {
    Row() {
      Text('输入来源')
        .fontSize(EmuTypography.sm)
        .fontColor(Color.White)
        .margin({ right: 8 })

      Select(this.inputSourceOptionsSafe)
        .selected(this.safeInputSourceIndex)
        .value(this.currentInputSourceLabel)
        .font({ size: 12 })
        .fontColor(Color.White)
        .selectedOptionFont({ size: 12, weight: FontWeight.Regular })
        .optionFont({ size: 12 })
        .width('70%')
        .onSelect(this.onInputSourceSelect)
    }
    .width('100%')
    .padding({ left: 10, right: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  VirtualControllerToggleSection() {
    Row() {
      Text('调试')
        .fontSize(EmuTypography.sm)
        .fontColor(Color.White)
        .margin({ right: 8 })
      Toggle({ type: ToggleType.Switch, isOn: this.hideVirtualController })
        .onChange(this.onHideVirtualCtrlChange)
      Text(this.hideVirtualController ? '手柄隐藏中' : '手柄显示中')
        .fontSize(EmuTypography.sm)
        .fontColor('#CCCCCC')
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  VirtualControllerSection() {
    if (!this.hideVirtualController) {
      Column() {
        Row() {
          Column() {
            DPadControl({
              buttonSize: 60,
              onKeyPress: (keyId: number, pressed: boolean) => {
                if (pressed) {
                  this.log(`UI: DPad Key ${keyId} Down`);
                }
                this.sendButton(keyId, pressed);
              }
            })

            AnalogStickControl({
              index: 0,
              baseSize: 120,
              knobSize: 50,
              onAnalogChange: (index: number, x: number, y: number) => {
                this.sendAnalog(index, x, y);
              }
            })
            .margin({ top: 10 })

            AnalogStickControl({
              index: 1,
              baseSize: 110,
              knobSize: 45,
              onAnalogChange: (index: number, x: number, y: number) => {
                this.sendAnalog(index, x, y);
              }
            })
            .margin({ top: 12 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          StartSelectControl({
            buttonWidth: 60,
            buttonHeight: 30,
            isVertical: true,
            onKeyPress: (keyId: number, pressed: boolean) => {
              if (pressed) {
                this.log(`UI: Func Key ${keyId} Down`);
              }
              this.sendButton(keyId, pressed);
            }
          })
          .padding({ left: 10, right: 10 })

          Column() {
            ABXYControl({
              buttonSize: 55,
              onKeyPress: (keyId: number, pressed: boolean) => {
                if (pressed) {
                  this.log(`UI: Action Key ${keyId} Down`);
                }
                this.sendButton(keyId, pressed);
              }
            })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#222')
        .borderRadius(10)
        .margin({ bottom: 10 })
      }
      .width('100%')
      .padding(5)
    }
  }

  @Builder
  ScalingModeSection() {
    Column() {
      Text('画质模式 (切换将清零统计)')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })

      Row() {
        Button('硬件')
          .fontSize(EmuTypography.sm)
          .backgroundColor(this.scalingMode === 0 ? '#1976D2' : '#455A64')
          .onClick(this.onScalingModeHW)

        Button('软件')
          .fontSize(EmuTypography.sm)
          .margin({ left: 6 })
          .backgroundColor(this.scalingMode === 1 ? '#1976D2' : '#455A64')
          .onClick(this.onScalingModeSW)

        Button('GLES')
          .fontSize(EmuTypography.sm)
          .margin({ left: 6 })
          .backgroundColor(this.scalingMode === 2 ? '#1976D2' : '#455A64')
          .onClick(this.onScalingModeGLES)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (this.scalingMode === 1) {
        Text('软件最大分辨率 (切换将清零统计)')
          .fontSize(EmuTypography.sm)
          .fontColor('#CCCCCC')
          .margin({ top: 8, bottom: 5 })

        Row() {
          Button('480p')
            .fontSize(EmuTypography.sm)
            .backgroundColor(this.softwareMaxPresetIndex === 0 ? '#6A1B9A' : '#455A64')
            .onClick(this.onSWPreset480p)

          Button('720p')
            .fontSize(EmuTypography.sm)
            .margin({ left: 6 })
            .backgroundColor(this.softwareMaxPresetIndex === 1 ? '#6A1B9A' : '#455A64')
            .onClick(this.onSWPreset720p)

          Button('1080p')
            .fontSize(EmuTypography.sm)
            .margin({ left: 6 })
            .backgroundColor(this.softwareMaxPresetIndex === 2 ? '#6A1B9A' : '#455A64')
            .onClick(this.onSWPreset1080p)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
    .borderRadius(10)
    .margin({ bottom: 10 })
  }

  @Builder
  LogEntries() {
    ForEach(this.logs, (log: string) => {
      Text(log)
        .fontSize(EmuTypography.xs)
        .fontColor('#CCC')
        .width('100%')
        .textAlign(TextAlign.Start)
    }, (log: string, index: number) => 'log-' + index)
  }

  @Builder
  LogsSection() {
    Column() {
      Text('日志:')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })

      Column() {
        this.LogEntries()
      }
      .width('100%')
      .height('30%')
      .padding(10)
      .backgroundColor('#222')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  MainPanelContent() {
    Column() {
      this.ScalingModeSection()
      this.EngineControlButtons()
      this.InitOptionsButton()
      this.RomControlButtons()
      this.QueryButtons()
      this.StatsDisplay()
      this.CoreOptionsDisplay()
      this.VideoControlSection()
      this.AudioControlSection()
      this.AudioStatusDisplay()
      this.LogsSection()
    }
    .width('100%')
  }

  @Builder
  LogsOverlay() {
    Row() {
      Blank()
      Scroll() {
        Column() {
          Row() {
            Text('日志')
              .fontSize(EmuTypography.md)
              .fontColor(Color.White)
            Blank()
            Button('关闭')
              .fontSize(EmuTypography.sm)
              .onClick(this.onCloseLogs)
          }
          .width('100%')
          .padding(8)

          Scroll() {
            Column() {
              this.LogEntries()
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
        }
        .width('60%')
        .height('30%')
        .backgroundColor('#222')
        .borderRadius(8)
        .padding(8)
        .margin({ top: 70, right: 10 })
      }
      .scrollable(ScrollDirection.Vertical)
    }
    .width('100%')
  }

  @Builder
  DrawerOverlay() {
    Row() {
      Blank()
        .onClick(this.onCloseDrawer)
      Scroll() {
        Column() {
          Row() {
            Text('功能抽屉')
              .fontSize(EmuTypography.lg)
              .fontColor(Color.White)
            Blank()
            Button('收起')
              .fontSize(EmuTypography.sm)
              .onClick(this.onCloseDrawer)
          }
          .width('100%')
          .padding(10)

          this.EngineControlButtons()
          this.InitOptionsButton()
          this.RomControlButtons()
          this.QueryButtons()
          this.StatsDisplay()
          this.CoreOptionsDisplay()
          this.VideoControlSection()
          this.AudioControlSection()
          this.AudioStatusDisplay()
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#1E1E1E')
      }
      .scrollable(ScrollDirection.Vertical)
      .width('70%')
      .height('100%')
      .padding(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00000066')
    .zIndex(999)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.HeaderSection()
          this.SurfaceSection()
          this.TopActionBar()
          this.PortSelectionSection()
          this.InputSourceSection()
          this.VirtualControllerToggleSection()
          this.VirtualControllerSection()

          if (!this.useDrawer) {
            this.MainPanelContent()
          }

          DevDiagnosticsBlock({
            coreCheckRunning: this.coreCheck.running,
            coreCheckText: this.coreCheck.text,
            soakRunning: this.soakState.running,
            soakSecondsLeft: this.soakState.secondsLeft,
            soakSummaryText: this.soakState.summaryText,
            switching: false,
            onCoreCheck: this.onCoreCheckClick,
            onSoakToggle: this.onSoakToggleClick
          })
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .width('100%')
      .height('100%')
      .backgroundColor('#111')

      if (this.logsOverlayVisible) {
        this.LogsOverlay()
      }

      if (this.drawerVisible) {
        this.DrawerOverlay()
      }
    }
  }
}
