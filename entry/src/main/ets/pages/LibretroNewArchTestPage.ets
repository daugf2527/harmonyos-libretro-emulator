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

// NAPI 接口定义 (遵循 AGENTS.md 规范)
interface LibretroNapi {
  refactoredStartEngine(): boolean;
  refactoredStopEngine(): boolean;
  refactoredStopEngineAsync(): boolean;
  refactoredLoadCore(path: string): boolean;
  refactoredLoadRom(
    path: string,
    resMgr?: resourceManager.ResourceManager
  ): boolean;
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
  refactoredSetCoreOption(key: string, value: string): boolean;
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


// RetroPad Constants removed (imported inputs used dynamically)

@Entry
@Component
struct LibretroNewArchTestPage {
  @State status: string = '未启动';
  @State logs: string[] = [];
  @State coreOptions: CoreOptionItem[] = [];
  @State audioStatus: AudioStatusPayload = {
    active: false,
    occupancy: 0,
    underrun: false,
    underruns: 0,
    overruns: 0
  };
  @State fps: number = 0;
  @State perfStatsText: string = '';
  @State geometryText: string = '';
  @State inputDebugText: string = '';
  @State inputFocusText: string = '';
  @State uiInputDebugText: string = '';
  @State stats: RuntimeStatsDTO = {
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
  @State scalingMode: number = 2;
  @State softwareMaxPresetIndex: number = 1;
  @State autoAdjust: boolean = true;
  @State latencyMs: number = 0;
  @State lastAdjustTs: number = 0;
  @State lastUnderruns: number = 0;
  @State selectedPortIndex: number = 0;
  @State portAssignments: PortAssignState[] = createDefaultPortAssignments();
  @State inputDevices: InputDeviceInfo[] = [];
  @State alertMsg: string = '';
  @State alertVisible: boolean = false;
  @State drawerVisible: boolean = false;
  @State logsOverlayVisible: boolean = false;
  @State useDrawer: boolean = false;
  @State aiUpscaleEnabled: boolean = false;
  @State xengineAvailable: boolean = false;
  @State hideVirtualController: boolean = false;
  
  private xComponentId: string = 'new_arch_xcomponent';
  private eventScope: EventHubScope | undefined = undefined;
  private inputDebugTimer: number = -1;
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
    const ok = nativeApi.refactoredStartEngine();
    this.log(`refactoredStartEngine 返回: ${ok}`);
    if (!ok) { this.status = '启动失败'; return; }
    const started = await nativeApi.refactoredWaitForStateAsync(EngineState.STARTING, 5000);
    this.status = started ? '引擎已启动' : '启动超时';
  };
  private onSetFilesDir = (): void => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const filesDir = context.filesDir;
    this.log(`调用 refactoredSetFilesDir: ${filesDir}`);
    const ok: boolean = nativeApi.refactoredSetFilesDir(filesDir);
    this.log(`refactoredSetFilesDir 返回: ${ok}`);
  };
  private onLoadCore = async (): Promise<void> => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const abiPath = this.resolveAbiPath();
    const corePath = `${context.bundleCodeDir}/libs/${abiPath}/libgambatte_libretro.so`;
    this.log(`调用 refactoredLoadCore: ${corePath}`);
    const ok: boolean = nativeApi.refactoredLoadCore(corePath);
    this.log(`refactoredLoadCore 返回: ${ok}`);
    if (!ok) { this.status = '核心加载失败'; return; }
    const loaded = await nativeApi.refactoredWaitForStateAsync(EngineState.CORE_LOADED, 5000);
    if (!loaded) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const detail = err && err.reason ? `原因: ${err.reason}` : '原因未知';
      this.log(`LoadCore 超时: ${detail}`);
    }
    this.status = loaded ? '核心已加载' : '核心加载超时';
  };
  private onInitOptions = (): void => { this.refreshCoreOptions(); };
  private onLoadRom = async (): Promise<void> => {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) { this.log('获取上下文失败'); return; }
    const resMgr = context.resourceManager;
    this.log('调用 refactoredLoadRom: roms/snake_v0.1.gb');
    const ok: boolean = nativeApi.refactoredLoadRom('roms/snake_v0.1.gb', resMgr);
    this.log(`refactoredLoadRom 返回: ${ok}`);
    if (!ok) { this.status = 'ROM加载失败'; return; }
    const running = await nativeApi.refactoredWaitForStateAsync(EngineState.RUNNING, 5000);
    if (!running) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const detail = err && err.reason ? `原因: ${err.reason}` : '原因未知';
      this.log(`LoadRom 超时: ${detail}`);
    }
    this.status = running ? 'ROM已加载，运行中' : 'ROM加载超时';
    if (ok) { this.refreshCoreOptions(); }
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
    const ok: boolean = nativeApi.refactoredStopEngineAsync();
    this.log(`refactoredStopEngine 返回: ${ok}`);
    if (!ok) { this.status = '停止失败'; return; }
    const stopped = await nativeApi.refactoredWaitForStateAsync(EngineState.STOPPED, 5000);
    this.status = stopped ? '已停止' : '停止超时';
  };
  private onQueryState = (): void => {
    const state: number = nativeApi.refactoredGetState();
    const stateNames: string[] = ['INIT', 'CORE_LOADED', 'GAME_LOADED', 'RUNNING', 'PAUSED', 'STOPPING', 'STOPPED', 'STARTING', 'LOADING', 'ERROR'];
    this.log(`当前状态: ${stateNames[state] || state}`);
  };
  private onQueryStats = (): void => {
    try {
      const s = nativeApi.refactoredGetStats() as RuntimeStatsDTO;
      this.stats = {
        videoRefreshCalls: Number(s.videoRefreshCalls) || 0,
        videoNullFrames: Number(s.videoNullFrames) || 0,
        videoDupeFrames: Number(s.videoDupeFrames) || 0,
        audioBatchCalls: Number(s.audioBatchCalls) || 0,
        audioFramesIn: Number(s.audioFramesIn) || 0,
        frameCount: Number(s.frameCount) || 0,
        audioBufferUsage: Number(s.audioBufferUsage) || 0,
        audioUnderruns: Number(s.audioUnderruns) || 0,
        audioOverruns: Number(s.audioOverruns) || 0,
      };
      this.log('已刷新统计');
    } catch (e) { this.log('查询统计失败'); }
  };
  private onResetStats = (): void => {
    const ok = nativeApi.refactoredResetStats();
    this.log(`重置统计: ${ok}`);
    if (ok) {
      try {
        const s = nativeApi.refactoredGetStats() as RuntimeStatsDTO;
        this.stats = {
          videoRefreshCalls: Number(s.videoRefreshCalls) || 0,
          videoNullFrames: Number(s.videoNullFrames) || 0,
          videoDupeFrames: Number(s.videoDupeFrames) || 0,
          audioBatchCalls: Number(s.audioBatchCalls) || 0,
          audioFramesIn: Number(s.audioFramesIn) || 0,
          frameCount: Number(s.frameCount) || 0,
          audioBufferUsage: Number(s.audioBufferUsage) || 0,
          audioUnderruns: Number(s.audioUnderruns) || 0,
          audioOverruns: Number(s.audioOverruns) || 0,
        };
      } catch (_) {}
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
  private onSimulateUnderrun = (): void => {
    this.audioStatus = { active: true, occupancy: 0, underrun: true, underruns: this.audioStatus.underruns + 1, overruns: this.audioStatus.overruns };
    this.handleAudioStatus();
    this.log('触发模拟欠载事件');
  };
  private onSimulateHighOccupancy = (): void => {
    this.audioStatus = { active: true, occupancy: 90, underrun: false, underruns: this.audioStatus.underruns, overruns: this.audioStatus.overruns };
    this.handleAudioStatus();
    this.log('触发模拟高占用事件');
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
    this.log('页面加载');

    try {
      this.xengineAvailable = canIUse('SystemCapability.Graphic.XEngine');
    } catch (_) {
      this.xengineAvailable = false;
    }
    this.eventScope = LibretroEventHub.getInstance().createScope();
    this.eventScope.onOptionsUpdate((_payload) => {
      this.refreshCoreOptions();
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
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
    this.log('页面销毁，停止引擎');
    nativeApi.refactoredStopEngineAsync();
    this.stopInputDebug();
  }

  log(msg: string) {
    const time = new Date().toLocaleTimeString();
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

  refreshCoreOptions() {
    this.coreOptions = this.getCoreOptions();
    this.log('刷新选项完成');
  }

  handleAudioStatus() {
    if (this.autoAdjust && this.audioStatus.underrun) {
      const now = new Date().getTime();
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


  parseOptionsJson(s: string): CoreOptionItem[] {
  try {
    const arr: CoreOptionItem[] = JSON.parse(s) as CoreOptionItem[];
    if (Array.isArray(arr)) return arr;
    return [];
  } catch (_) {
    return [];
  }
}
  getCoreOptions(): CoreOptionItem[] {
    try {
      const s: string = nativeApi.refactoredGetCoreOptions();
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
        .fontSize(12)
        .onClick(this.onStartEngine)
      Button('2. 设置目录')
        .fontSize(12)
        .margin({ left: 5 })
        .onClick(this.onSetFilesDir)
      Button('3. 加载核心')
        .fontSize(12)
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
        .fontSize(12)
        .onClick(this.onInitOptions)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  RomControlButtons() {
    Row() {
      Button('4. 加载ROM')
        .fontSize(12)
        .onClick(this.onLoadRom)
      Button('暂停')
        .fontSize(12)
        .margin({ left: 5 })
        .backgroundColor('#FF9800')
        .onClick(this.onPauseEngine)
      Button('继续')
        .fontSize(12)
        .margin({ left: 5 })
        .backgroundColor('#4CAF50')
        .onClick(this.onResumeEngine)
      Button('停止')
        .fontSize(12)
        .margin({ left: 5 })
        .backgroundColor('#F44336')
        .onClick(this.onStopEngine)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  QueryButtons() {
    Row() {
      Button('查询状态')
        .fontSize(12)
        .onClick(this.onQueryState)
    }
    .width('100%')
    .padding(10)
    .justifyContent(FlexAlign.Center)

    Row() {
      Button('查询统计')
        .fontSize(12)
        .onClick(this.onQueryStats)
      Button('重置统计')
        .fontSize(12)
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
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Text(`视频刷新: ${this.stats.videoRefreshCalls}  空帧: ${this.stats.videoNullFrames}  dupe: ${this.stats.videoDupeFrames}`)
        .fontSize(12)
        .fontColor('#CCC')
      Text(`音频批量: ${this.stats.audioBatchCalls}  帧入: ${this.stats.audioFramesIn}  缓冲占用: ${(this.stats.audioBufferUsage * 100).toFixed(0)}%`)
        .fontSize(12)
        .fontColor('#CCC')
      Text(`欠载: ${this.stats.audioUnderruns}  过载: ${this.stats.audioOverruns}  帧计数: ${this.stats.frameCount}`)
        .fontSize(12)
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
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      ForEach(this.coreOptions, (opt: CoreOptionItem) => {
        Row() {
          Text(`${opt.desc}: ${opt.value}`)
            .fontSize(12)
            .fontColor('#CCC')
          Blank()
          Button('切换')
            .fontSize(12)
            .onClick(() => {
              const values: CoreOptionValue[] = Array.isArray(opt.values) ? opt.values : [];
              const idx = Math.max(0, values.findIndex((v: CoreOptionValue) => v.value === opt.value));
              const next = values.length > 0 ? values[(idx + 1) % values.length] : undefined;
              if (next && next.value) {
                const ok = nativeApi.refactoredSetCoreOption(opt.key, next.value);
                if (ok) {
                  this.refreshCoreOptions();
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
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Row() {
        Text('AI 画质增强 (XEngine)')
          .fontSize(12)
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
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Row() {
        Text('自动调节')
          .fontSize(12)
          .fontColor('#CCC')
        Toggle({ type: ToggleType.Switch, isOn: this.autoAdjust })
          .onChange(this.onAutoAdjustChange)
      }
      .width('100%')
      .padding(4)
      Row() {
        Text(`最小延迟: ${this.latencyMs}ms`)
          .fontSize(12)
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
        Button('模拟欠载')
          .fontSize(12)
          .onClick(this.onSimulateUnderrun)
        Button('模拟高占用')
          .fontSize(12)
          .margin({ left: 5 })
          .onClick(this.onSimulateHighOccupancy)
      }
      .width('100%')
      .padding(4)
      if (this.alertVisible) {
        Row() {
          Text(this.alertMsg)
            .fontSize(12)
            .fontColor('#F44336')
          Blank()
          Button('清除告警')
            .fontSize(12)
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
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ bottom: 5 })
      Text(`运行: ${this.audioStatus.active ? '是' : '否'}  占用: ${this.audioStatus.occupancy}%  欠载: ${this.audioStatus.underrun ? '是' : '否'}`)
        .fontSize(12)
        .fontColor('#CCC')
      Text(`欠载次数: ${this.audioStatus.underruns}  过载次数: ${this.audioStatus.overruns}`)
        .fontSize(12)
        .fontColor('#CCC')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#222')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
      // 顶部状态栏
      Row() {
        Text('新架构测试')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)

        Blank()

        Text(this.status)
          .fontSize(14)
          .fontColor('#4CAF50')
        Text(`FPS: ${this.fps.toFixed(2)}`)
          .fontSize(14)
          .fontColor('#4CAF50')

        Text(this.perfStatsText)
          .fontSize(10)
          .fontColor('#CCCCCC')

        if (this.geometryText.length > 0) {
          Text(this.geometryText)
            .fontSize(10)
            .fontColor('#CCCCCC')
        }
      }
      .width('100%')
      .padding(15)
      .backgroundColor('#333')

      Row() {
        Text(`XComponentId: ${this.xComponentId}`)
          .fontSize(12)
          .fontColor('#CCCCCC')
      }
      .width('100%')
      .padding({ left: 15, right: 15, bottom: 10 })
      .backgroundColor('#333')

      Column() {
        if (this.inputDebugText.length > 0) {
          Text(this.inputDebugText)
            .fontSize(12)
            .fontColor('#CCCCCC')
        }
        if (this.inputFocusText.length > 0) {
          Text(this.inputFocusText)
            .fontSize(12)
            .fontColor('#CCCCCC')
        }
        if (this.uiInputDebugText.length > 0) {
          Text(this.uiInputDebugText)
            .fontSize(12)
            .fontColor('#CCCCCC')
        }
      }
      .width('100%')
      .padding({ left: 15, right: 15, bottom: 10 })
      .backgroundColor('#333')

      // XComponent 游戏画面
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
          // 新架构需要手动设置 NativeWindow - 通过 XComponent 回调自动处理
        })
        .onDestroy(() => {
          this.log(`XComponent onDestroy id=${this.xComponentId}`);
        })

      Row() {
        Blank()
        Button('打开抽屉')
          .fontSize(12)
          .onClick(this.onOpenDrawer)
        Button(this.logsOverlayVisible ? '隐藏日志' : '显示日志')
          .fontSize(12)
          .margin({ left: 5 })
          .onClick(this.onToggleLogs)
      }
      .width('100%')
      .padding(10)
      .justifyContent(FlexAlign.End)

      Row() {
        Text('端口')
          .fontSize(12)
          .fontColor(Color.White)
          .margin({ right: 8 })

        Button('P1')
          .fontSize(12)
          .backgroundColor(this.selectedPortIndex === 0 ? '#1976D2' : '#455A64')
          .onClick(this.onSelectPort0)

        Button('P2')
          .fontSize(12)
          .margin({ left: 6 })
          .backgroundColor(this.selectedPortIndex === 1 ? '#1976D2' : '#455A64')
          .onClick(this.onSelectPort1)

        Button('P3')
          .fontSize(12)
          .margin({ left: 6 })
          .backgroundColor(this.selectedPortIndex === 2 ? '#1976D2' : '#455A64')
          .onClick(this.onSelectPort2)

        Button('P4')
          .fontSize(12)
          .margin({ left: 6 })
          .backgroundColor(this.selectedPortIndex === 3 ? '#1976D2' : '#455A64')
          .onClick(this.onSelectPort3)
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('输入来源')
          .fontSize(12)
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
          .onSelect((index: number) => {
            const sourceType = this.inputSourceTypes[index] ?? InputSourceType.None;
            this.applyPortAssignment(this.selectedPortIndex, sourceType, true, this.currentPortAssignment.deviceId);
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('调试')
          .fontSize(12)
          .fontColor(Color.White)
          .margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.hideVirtualController })
          .onChange((v: boolean) => {
            this.hideVirtualController = v;
            this.log(`UI: 隐藏虚拟手柄 = ${v}`);
          })
        Text(this.hideVirtualController ? '手柄隐藏中' : '手柄显示中')
          .fontSize(12)
          .fontColor('#CCCCCC')
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // Virtual Gamepad Area (Using Shared Component)
      if (!this.hideVirtualController) {
        Column() {
          Row() {
            Column() {
              DPadControl({
                buttonSize: 60,
                onKeyPress: (keyId: number, pressed: boolean) => {
                  if (pressed) this.log(`UI: DPad Key ${keyId} Down`);
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

            // Select / Start
            StartSelectControl({
              buttonWidth: 60,
              buttonHeight: 30,
              isVertical: true,
              onKeyPress: (keyId: number, pressed: boolean) => {
                if (pressed) this.log(`UI: Func Key ${keyId} Down`);
                this.sendButton(keyId, pressed);
              }
            })
            .padding({ left: 10, right: 10 })

            // ABXY
            Column() {
              ABXYControl({
                buttonSize: 55,
                onKeyPress: (keyId: number, pressed: boolean) => {
                  if (pressed) this.log(`UI: Action Key ${keyId} Down`);
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


      if (!this.useDrawer) {
            Column() {
              Text('画质模式 (切换将清零统计)')
                .fontSize(14)
                .fontColor(Color.White)
                .margin({ bottom: 5 })

              Row() {
                Button('硬件')
                  .fontSize(12)
                  .backgroundColor(this.scalingMode === 0 ? '#1976D2' : '#455A64')
                  .onClick(() => {
                    const okMode = nativeApi.refactoredSetScalingMode(0);
                    const okStats = nativeApi.refactoredResetStats();
                    this.scalingMode = 0;
                    this.fps = 0;
                    this.perfStatsText = '';
                    this.geometryText = '';
                    this.log(`切换画质模式: 0(HW), okMode=${okMode}, okStats=${okStats}`);
                  })

                Button('软件')
                  .fontSize(12)
                  .margin({ left: 6 })
                  .backgroundColor(this.scalingMode === 1 ? '#1976D2' : '#455A64')
                  .onClick(() => {
                    const presets: ResolutionPreset[] = [
                      { w: 640, h: 480 },
                      { w: 1280, h: 720 },
                      { w: 1920, h: 1080 }
                    ];
                    const preset = presets[this.softwareMaxPresetIndex] || presets[1];
                    const okMode = nativeApi.refactoredSetScalingMode(1);
                    const okMax = nativeApi.refactoredSetSoftwareMaxResolution(preset.w, preset.h);
                    const okStats = nativeApi.refactoredResetStats();
                    this.scalingMode = 1;
                    this.fps = 0;
                    this.perfStatsText = '';
                    this.geometryText = '';
                    this.log(`切换画质模式: 1(SW) ${preset.w}x${preset.h}, okMode=${okMode}, okMax=${okMax}, okStats=${okStats}`);
                  })

                Button('GLES')
                  .fontSize(12)
                  .margin({ left: 6 })
                  .backgroundColor(this.scalingMode === 2 ? '#1976D2' : '#455A64')
                  .onClick(() => {
                    const okMode = nativeApi.refactoredSetScalingMode(2);
                    const okStats = nativeApi.refactoredResetStats();
                    this.scalingMode = 2;
                    this.fps = 0;
                    this.perfStatsText = '';
                    this.geometryText = '';
                    this.log(`切换画质模式: 2(GLES), okMode=${okMode}, okStats=${okStats}`);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)

              if (this.scalingMode === 1) {
                Text('软件最大分辨率 (切换将清零统计)')
                  .fontSize(12)
                  .fontColor('#CCCCCC')
                  .margin({ top: 8, bottom: 5 })

                Row() {
                  Button('480p')
                    .fontSize(12)
                    .backgroundColor(this.softwareMaxPresetIndex === 0 ? '#6A1B9A' : '#455A64')
                    .onClick(() => {
                      this.softwareMaxPresetIndex = 0;
                      const okMax = nativeApi.refactoredSetSoftwareMaxResolution(640, 480);
                      const okStats = nativeApi.refactoredResetStats();
                      this.fps = 0;
                      this.perfStatsText = '';
                      this.geometryText = '';
                      this.log(`设置软件最大分辨率: 640x480, okMax=${okMax}, okStats=${okStats}`);
                    })

                  Button('720p')
                    .fontSize(12)
                    .margin({ left: 6 })
                    .backgroundColor(this.softwareMaxPresetIndex === 1 ? '#6A1B9A' : '#455A64')
                    .onClick(() => {
                      this.softwareMaxPresetIndex = 1;
                      const okMax = nativeApi.refactoredSetSoftwareMaxResolution(1280, 720);
                      const okStats = nativeApi.refactoredResetStats();
                      this.fps = 0;
                      this.perfStatsText = '';
                      this.geometryText = '';
                      this.log(`设置软件最大分辨率: 1280x720, okMax=${okMax}, okStats=${okStats}`);
                    })

                  Button('1080p')
                    .fontSize(12)
                    .margin({ left: 6 })
                    .backgroundColor(this.softwareMaxPresetIndex === 2 ? '#6A1B9A' : '#455A64')
                    .onClick(() => {
                      this.softwareMaxPresetIndex = 2;
                      const okMax = nativeApi.refactoredSetSoftwareMaxResolution(1920, 1080);
                      const okStats = nativeApi.refactoredResetStats();
                      this.fps = 0;
                      this.perfStatsText = '';
                      this.geometryText = '';
                      this.log(`设置软件最大分辨率: 1920x1080, okMax=${okMax}, okStats=${okStats}`);
                    })
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

            // 控制按钮
            this.EngineControlButtons()
      
            this.InitOptionsButton()
      
            this.RomControlButtons()
      
            this.QueryButtons()
      
            this.StatsDisplay()
      
            this.CoreOptionsDisplay()

            this.VideoControlSection()
      
            this.AudioControlSection()
      
            this.AudioStatusDisplay()
      
            // 日志区域
            Column() {
              Text('日志:')
                .fontSize(14)
                .fontColor(Color.White)
                .margin({ bottom: 5 })
      
              ForEach(this.logs, (log: string) => {
                Text(log)
                  .fontSize(10)
                  .fontColor('#CCC')
                  .width('100%')
                  .textAlign(TextAlign.Start)
                }, (log: string, index: number) => 'log-' + index)
              }
              .width('100%')
              .height('30%')
              .padding(10)
              .backgroundColor('#222')
              .alignItems(HorizontalAlign.Start)
      }
      }
      }
      .scrollable(ScrollDirection.Vertical)
      .width('100%')
      .height('100%')
      .backgroundColor('#111')

      if (this.logsOverlayVisible) {
        Row() {
          Blank()
          Scroll() {
          Column() {
            Row() {
              Text('日志')
                .fontSize(14)
                .fontColor(Color.White)
              Blank()
              Button('关闭')
                .fontSize(12)
                .onClick(() => {
                  this.logsOverlayVisible = false;
                })
            }
            .width('100%')
            .padding(8)
            Scroll() {
              Column() {
                ForEach(this.logs, (log: string) => {
                  Text(log)
                    .fontSize(10)
                    .fontColor('#CCC')
                    .width('100%')
                    .textAlign(TextAlign.Start)
                }, (log: string, index: number) => 'log-' + index)
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
        .width('100%')
      }

      if (this.drawerVisible) {
        Row() {
          Blank()
            .onClick(() => {
              this.drawerVisible = false;
            })
          Scroll() {
          Column() {
            Row() {
              Text('功能抽屉')
                .fontSize(16)
                .fontColor(Color.White)
              Blank()
              Button('收起')
                .fontSize(12)
                .onClick(() => {
                  this.drawerVisible = false;
                })
            }
            .width('100%')
            .padding(10)

            Row() {
              Button('1. 启动引擎')
                .fontSize(12)
                .onClick(async () => {
                  this.log('调用 refactoredStartEngine');
                  nativeApi.refactoredClearLastErrorInfo();
                  const ok = nativeApi.refactoredStartEngine();
                  this.log(`refactoredStartEngine 返回: ${ok}`);
                  if (!ok) {
                    this.status = '启动失败';
                    return;
                  }
                  const started = await nativeApi.refactoredWaitForStateAsync(
                    EngineState.STARTING,
                    5000
                  );
                  this.status = started ? '引擎已启动' : '启动超时';
                })
              Button('2. 设置目录')
                .fontSize(12)
                .margin({ left: 5 })
                .onClick(() => {
                  const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  if (!context) {
                    this.log('获取上下文失败');
                    return;
                  }
                  const filesDir = context.filesDir;
                  this.log(`调用 refactoredSetFilesDir: ${filesDir}`);
                  const ok: boolean = nativeApi.refactoredSetFilesDir(filesDir);
                  this.log(`refactoredSetFilesDir 返回: ${ok}`);
                })
              Button('3. 加载核心')
                .fontSize(12)
                .margin({ left: 5 })
                .onClick(async () => {
                  const context = this.getUIContext().getHostContext() as
                    common.UIAbilityContext;
                  if (!context) {
                    this.log('获取上下文失败');
                    return;
                  }
                  const abiPath = this.resolveAbiPath();
                  const corePath = `${context.bundleCodeDir}/libs/${abiPath}/libgambatte_libretro.so`;
                  this.log(`调用 refactoredLoadCore: ${corePath}`);
                  const ok: boolean = nativeApi.refactoredLoadCore(corePath);
                  this.log(`refactoredLoadCore 返回: ${ok}`);
                  if (!ok) {
                    this.status = '核心加载失败';
                    return;
                  }
                  const loaded = await nativeApi.refactoredWaitForStateAsync(
                    EngineState.CORE_LOADED,
                    5000
                  );
                  if (!loaded) {
                    const err = nativeApi.refactoredGetLastErrorInfo();
                    const detail = err && err.reason ?
                      `原因: ${err.reason}` :
                      '原因未知';
                    this.log(`LoadCore 超时: ${detail}`);
                  }
                  this.status = loaded ? '核心已加载' : '核心加载超时';
                })
            }
            .width('100%')
            .padding(10)
            .justifyContent(FlexAlign.Center)

            this.InitOptionsButton()

            Row() {
              Button('4. 加载ROM')
                .fontSize(12)
                .onClick(async () => {
                  const context = this.getUIContext().getHostContext() as
                    common.UIAbilityContext;
                  if (!context) {
                    this.log('获取上下文失败');
                    return;
                  }
                  const resMgr = context.resourceManager;
                  this.log('调用 refactoredLoadRom: roms/snake_v0.1.gb');
                  const ok: boolean = nativeApi.refactoredLoadRom('roms/snake_v0.1.gb', resMgr);
                  this.log(`refactoredLoadRom 返回: ${ok}`);
                  if (!ok) {
                    this.status = 'ROM加载失败';
                    return;
                  }
                  const running = await nativeApi.refactoredWaitForStateAsync(
                    EngineState.RUNNING,
                    5000
                  );
                  if (!running) {
                    const err = nativeApi.refactoredGetLastErrorInfo();
                    const detail = err && err.reason ?
                      `原因: ${err.reason}` :
                      '原因未知';
                    this.log(`LoadRom 超时: ${detail}`);
                  }
                  this.status = running ? 'ROM已加载，运行中' : 'ROM加载超时';
                  if (ok) {
                    this.refreshCoreOptions();
                  }
                })
              Button('暂停')
                .fontSize(12)
                .margin({ left: 5 })
                .backgroundColor('#FF9800')
                .onClick(() => {
                  this.log('调用 refactoredPauseEngine');
                  const ok: boolean = nativeApi.refactoredPauseEngine();
                  this.log(`refactoredPauseEngine 返回: ${ok}`);
                  this.status = '已暂停';
                })
              Button('继续')
                .fontSize(12)
                .margin({ left: 5 })
                .backgroundColor('#4CAF50')
                .onClick(() => {
                  this.log('调用 refactoredResumeEngine');
                  const ok: boolean = nativeApi.refactoredResumeEngine();
                  this.log(`refactoredResumeEngine 返回: ${ok}`);
                  this.status = '运行中';
                })
              Button('停止')
                .fontSize(12)
                .margin({ left: 5 })
                .backgroundColor('#F44336')
                .onClick(async () => {
                  this.log('调用 refactoredStopEngine');
                  const ok: boolean = nativeApi.refactoredStopEngineAsync();
                  this.log(`refactoredStopEngine 返回: ${ok}`);
                  if (!ok) {
                    this.status = '停止失败';
                    return;
                  }
                  const stopped = await nativeApi.refactoredWaitForStateAsync(
                    EngineState.STOPPED,
                    5000
                  );
                  this.status = stopped ? '已停止' : '停止超时';
                })
            }
            .width('100%')
            .padding(10)
            .justifyContent(FlexAlign.Center)

            Row() {
              Button('查询状态')
                .fontSize(12)
                .onClick(() => {
                  const state: number = nativeApi.refactoredGetState();
                  const stateNames: string[] = ['INIT', 'CORE_LOADED', 'GAME_LOADED', 'RUNNING', 'PAUSED', 'STOPPING', 'STOPPED', 'STARTING', 'LOADING', 'ERROR'];
                  this.log(`当前状态: ${stateNames[state] || state}`);
                })
            }
            .width('100%')
            .padding(10)
            .justifyContent(FlexAlign.Center)

            Row() {
              Button('查询统计')
                .fontSize(12)
                .onClick(() => {
                  try {
                    const s = nativeApi.refactoredGetStats() as RuntimeStatsDTO;
                    this.stats = {
                      videoRefreshCalls: Number(s.videoRefreshCalls) || 0,
                      videoNullFrames: Number(s.videoNullFrames) || 0,
                      videoDupeFrames: Number(s.videoDupeFrames) || 0,
                      audioBatchCalls: Number(s.audioBatchCalls) || 0,
                      audioFramesIn: Number(s.audioFramesIn) || 0,
                      frameCount: Number(s.frameCount) || 0,
                      audioBufferUsage: Number(s.audioBufferUsage) || 0,
                      audioUnderruns: Number(s.audioUnderruns) || 0,
                      audioOverruns: Number(s.audioOverruns) || 0,
                    };
                    this.log('已刷新统计');
                  } catch (e) {
                    this.log('查询统计失败');
                  }
                })
              Button('重置统计')
                .fontSize(12)
                .margin({ left: 5 })
                .onClick(() => {
                  const ok = nativeApi.refactoredResetStats();
                  this.log(`重置统计: ${ok}`);
                  if (ok) {
                    try {
                      const s = nativeApi.refactoredGetStats() as RuntimeStatsDTO;
                      this.stats = {
                        videoRefreshCalls: Number(s.videoRefreshCalls) || 0,
                        videoNullFrames: Number(s.videoNullFrames) || 0,
                        videoDupeFrames: Number(s.videoDupeFrames) || 0,
                        audioBatchCalls: Number(s.audioBatchCalls) || 0,
                        audioFramesIn: Number(s.audioFramesIn) || 0,
                        frameCount: Number(s.frameCount) || 0,
                        audioBufferUsage: Number(s.audioBufferUsage) || 0,
                        audioUnderruns: Number(s.audioUnderruns) || 0,
                        audioOverruns: Number(s.audioOverruns) || 0,
                      };
                    } catch (_) {}
                  }
                })
            }
            .width('100%')
            .padding(10)
            .justifyContent(FlexAlign.Center)

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
  }
  }
}}
