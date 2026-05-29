/*
 * 通用 Libretro 游戏页面 (New Architecture)
 * 基于 LibretroEngine 新架构重构
 */

import LogHelper from '../common/LogHelper';
import { common } from '@kit.AbilityKit';
import { EmuColors, EmuTypography } from '../common/EmuUiTokens';
import { RuntimeControlPanel } from '../components/RuntimeControlPanel';
import { RuntimeHudMetric } from '../components/RuntimeTopHudBar';
import { RuntimePauseOverlay } from '../components/RuntimePauseOverlay';
import { RuntimeVirtualControllerLayer } from '../components/RuntimeVirtualControllerLayer';
import {
  buildInputSourceItems,
  createDefaultPortAssignments,
  findPortAssignment,
  getInputSourceItemIndex,
  InputDeviceInfo,
  InputSourceItem,
  InputSourceType,
  PortAssignState,
  updatePortAssignments
} from '../common/InputPortRouting';
import {
  AudioStatusPayload,
  CoreCrashPayload,
  EngineState,
  EngineStatePayload,
  EventHubScope,
  FpsUpdatePayload,
  GeometryUpdatePayload,
  LibretroEventHub
} from '../common/LibretroEventHub';
import { consumePendingLibraryLaunchRequest, PendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import {
  markLibraryRecordPlayed,
} from '../common/LibraryRepository'
import {
  CoreConfig,
  LIBRETRO_CORE_CATALOG,
} from '../common/LibretroCoreCatalog'
import {
  createDefaultInputLayoutProfile,
  InputLayoutButton,
  loadInputLayoutProfile
} from '../common/InputLayoutRepository'
import {
  RuntimeInputDebugTextState,
  RuntimeInputDebugTracker
} from '../common/RuntimeInputDebugTracker'
import {
  getRuntimeInputDescriptorMask,
  sendRuntimeAnalog,
  sendRuntimeButton
} from '../common/RuntimeInputCommandBridge'
import {
  buildRuntimeRomConfigs,
  getFileNameFromPath,
  RuntimeRomConfig
} from '../common/RuntimeRomCatalog'
import {
  resolveRuntimeCorePath,
  resolveRuntimeRomPathForSwitch
} from '../common/RuntimePathResolver'
import { RuntimeLibrarySessionTracker } from '../common/RuntimeLibrarySessionTracker'
import { RuntimeSaveStateController } from '../common/RuntimeSaveStateController'
import { runtimeSessionController } from '../common/RuntimeSessionController'
import {
  createDefaultRuntimeRenderSettingsProfile,
  loadRuntimeRenderSettingsProfile,
  RuntimeRenderSettingsProfile,
  saveRuntimeRenderSettingsProfile
} from '../common/RuntimeRenderSettingsRepository'
import { runtimeRenderSettingsController } from '../common/RuntimeRenderSettingsController'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'
import { scanRuntimeRomSources } from '../common/RuntimeRomSourceScanner'

interface LibraryLaunchRouteParams {
  coreId?: string
  romFile?: string
  autoStart?: boolean
}

interface ResolutionPreset {
  w: number;
  h: number;
}

interface PendingSwitch {
  coreIndex: number;
  romIndex: number;
}

interface PerfDisplayState {
  realtimeFps: number;
  coreFps: number;
  audioStatusText: string;
  perfStatsText: string;
  geometryText: string;
}

@Entry
@Component
struct LibretroGamePage {
  @State currentCore: string = '';
  @State currentRom: string = '';
  @State gameRunning: boolean = false;
  @State gamePaused: boolean = false;
  @State switching: boolean = false;
  @State switchError: string = '';
  @State selectedCoreIndex: number = 0;
  @State selectedRomIndex: number = 0;
  @State selectedPortIndex: number = 0;
  @State portAssignmentVersion: number = 0;
  private portAssignments: PortAssignState[] = createDefaultPortAssignments();
  private coreOptions: SelectOption[] = [];
  private romOptions: SelectOption[] = [];
  @State showControls: boolean = false;
  @State perfDisplay: PerfDisplayState = { realtimeFps: 0, coreFps: 0, audioStatusText: '', perfStatsText: '', geometryText: '' };
  @State inputDebugText: string = '';
  @State inputFocusText: string = '';
  @State uiInputDebugText: string = '';
  @State scalingMode: number = 2; // 默认 GLES (2)
  @State softwareMaxPresetIndex: number = 1;
  @State hwRenderAllowed: boolean = true;
  @State hideVirtualController: boolean = false;
  // 游戏画面 aspect ratio：0 表示尚未收到 geometry_update（用 fallback 4/3）。
  // handleGeometryUpdate 会写入真实值（如 2048 ≈ 0.81 竖屏、GBA 1.5 横屏）。
  @State private gameAspectRatio: number = 0;
  @State runtimeSaveStatusText: string = '存档就绪';
  private runtimeInputLayoutButtons: InputLayoutButton[] = createDefaultInputLayoutProfile().buttons;
  // RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS mask:bit N = RETRO_DEVICE_ID_JOYPAD_N 被
  // 当前 core 声明使用,0 = core 未上报(用 fallback 全键集)。@State 触发子组件 re-render。
  @State private runtimeInputDescriptorMask: number = 0;
  
  // 使用包含 "new_arch" 的 ID 以触发 C++ 侧的新引擎逻辑
  private xComponentId: string = 'new_arch_game_xcomponent';
  private eventScope: EventHubScope | undefined = undefined;
  private pendingStart: boolean = false;
  private switchToken: number = 0;
  private pendingSwitch: PendingSwitch | undefined = undefined;
  private pageActive: boolean = false;
  private romListRefreshToken: number = 0;
  private lastStartOrSwitchAtMs: number = 0;
  private readonly librarySessionTracker: RuntimeLibrarySessionTracker = new RuntimeLibrarySessionTracker();
  private readonly inputDebugTracker: RuntimeInputDebugTracker = new RuntimeInputDebugTracker();
  private readonly runtimeSaveStateController: RuntimeSaveStateController = new RuntimeSaveStateController();
  private renderSettingsProfile: RuntimeRenderSettingsProfile = createDefaultRuntimeRenderSettingsProfile();
  private readonly startOrSwitchDebounceMs: number = 600;
  private readonly runtimeInputLayoutWidth: number = 440;
  private readonly runtimeInputLayoutHeight: number = 340;
  // Assigned in refreshInputDevices() alongside inputSourceOptions
  private inputSourceItems: InputSourceItem[] = [];
  
  private roms: RuntimeRomConfig[] = [];
  private readonly cores: CoreConfig[] = LIBRETRO_CORE_CATALOG;
  // CRITICAL fix: cache getAvailableRoms() .filter() result (reference-equality on roms + coreIndex)
  private availableRomsCache: RuntimeRomConfig[] = [];
  private availableRomsCacheRef: RuntimeRomConfig[] | null = null;
  private availableRomsCacheCoreIndex: number = -1;
  // HIGH fix: reuse HUD metrics array instead of allocating in build() every render
  private hudMetricsCache: RuntimeHudMetric[] = [
    { label: 'FPS', value: '--.-' },
    { label: 'LAT', value: '--' },
    { label: 'CORE', value: '--' }
  ];
  
  aboutToAppear() {
    this.pageActive = true;
    this.eventScope = LibretroEventHub.getInstance().createScope();
    this.eventScope.onEngineState((payload) => {
      this.handleEngineState(payload);
    });
    this.eventScope.onCoreCrash((payload) => {
      this.handleCoreCrash(payload);
    });
    this.eventScope.onFpsUpdate((payload) => {
      this.handleFpsUpdate(payload);
    });
    this.eventScope.onAudioStatus((payload) => {
      this.handleAudioStatus(payload);
    });
    this.eventScope.onGeometryUpdate((payload) => {
      this.handleGeometryUpdate(payload);
    });

    // 初始化核心选项
    let coreOpts = this.cores.map((core): SelectOption => {
      return { value: core.name };
    });
    if (coreOpts.length === 0) {
      coreOpts = [this.createSelectOption('无')];
    }
    this.coreOptions = coreOpts;

    void this.refreshRomList();
    this.startInputDebug();
    this.refreshInputDevices();
    this.syncPortAssignments();
    void this.loadRuntimeInputLayout();
    void this.loadRuntimeRenderSettings();
    this.refreshHudMetricsCache();
  }
  
  aboutToDisappear() {
    this.romListRefreshToken += 1;
    this.pageActive = false;
    this.switchToken += 1;
    this.pendingSwitch = undefined;
    if (this.switching) {
      void runtimeSessionController.stopAsync();
      this.switching = false;
    }
    void this.finalizeActiveLibrarySession();
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
    this.stopGame();
    this.stopInputDebug();
  }

  onBackPress(): boolean {
    if (this.gameRunning && this.gamePaused) {
      this.resumeGame();
      return true;
    }
    if (this.gameRunning && !this.gamePaused) {
      this.pauseGame();
      return true;
    }
    return false;
  }

  private isCurrentSwitchTask(token: number): boolean {
    return this.pageActive && token === this.switchToken;
  }

  private async loadRuntimeInputLayout(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    try {
      const profile = await loadInputLayoutProfile(context);
      this.runtimeInputLayoutButtons = profile.buttons;
      LogHelper.info('LibretroGame', 'Input', `已加载本地输入布局: ${profile.buttons.length} buttons`);
    } catch (err) {
      const message = (err as Error).message || String(err);
      LogHelper.warn('LibretroGame', 'Input', `读取本地输入布局失败: ${message}`);
      this.runtimeInputLayoutButtons = createDefaultInputLayoutProfile().buttons;
    }
  }

  private async loadRuntimeRenderSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    const profile = await loadRuntimeRenderSettingsProfile(context);
    this.renderSettingsProfile = profile;
    this.scalingMode = profile.scalingMode;
    this.softwareMaxPresetIndex = profile.softwareMaxPresetIndex;
    this.hwRenderAllowed = profile.hwRenderAllowed;
  }

  private async persistRuntimeRenderSettingsProfile(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    this.renderSettingsProfile = {
      version: this.renderSettingsProfile.version,
      scalingMode: this.scalingMode,
      softwareMaxPresetIndex: this.softwareMaxPresetIndex,
      hwRenderAllowed: this.hwRenderAllowed,
      updatedAt: this.renderSettingsProfile.updatedAt
    };
    this.renderSettingsProfile = await saveRuntimeRenderSettingsProfile(context, this.renderSettingsProfile);
  }

  private getCurrentRuntimeRomFile(): string {
    if (this.librarySessionTracker.activeRomFile.length > 0) {
      return this.librarySessionTracker.activeRomFile;
    }
    const roms = this.getAvailableRoms();
    const rom = roms[this.selectedRomIndex];
    return rom ? rom.file : '';
  }

  private async quickSaveRuntimeState(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await this.runtimeSaveStateController.quickSave(
      context,
      this.gameRunning,
      this.getCurrentRuntimeRomFile()
    );
    // T8-C-F5: await 后必须检查 pageActive,否则离页后仍向已销毁页面写 @State。
    if (!this.pageActive) {
      return;
    }
    this.runtimeSaveStatusText = result;
  }

  private async quickLoadRuntimeState(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await this.runtimeSaveStateController.quickLoad(
      context,
      this.gameRunning,
      this.getCurrentRuntimeRomFile()
    );
    // T8-C-F5: 同 quickSaveRuntimeState。
    if (!this.pageActive) {
      return;
    }
    this.runtimeSaveStatusText = result;
  }

  private handlePauseTileAction(actionCode: string): void {
    if (actionCode === 'quick_save') {
      void this.quickSaveRuntimeState();
      return;
    }
    if (actionCode === 'quick_load') {
      void this.quickLoadRuntimeState();
      return;
    }
    if (actionCode === 'input_mapping') {
      this.resumeGame();
      this.getUIContext().getRouter().pushUrl({ url: 'pages/InputLayoutPage' }).catch((err: Error) => {
        LogHelper.error('LibretroGame', 'Route', `跳转按键映射页失败: ${err.message}`);
        this.runtimeSaveStatusText = '按键映射页面打开失败';
      });
      return;
    }
    if (actionCode === 'visual_filters') {
      this.resumeGame();
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ShaderPreviewPage' }).catch((err: Error) => {
        LogHelper.error('LibretroGame', 'Route', `跳转画面风格页失败: ${err.message}`);
        this.runtimeSaveStatusText = '画面风格页面打开失败';
      });
      return;
    }
    this.runtimeSaveStatusText = `该操作暂未配置 (${actionCode})`;
  }

  handleEngineState(payload: EngineStatePayload) {
    const stateValue = Number(payload.state);
    if (!Number.isFinite(stateValue)) {
      return;
    }
    const running = stateValue === EngineState.GAME_LOADED ||
      stateValue === EngineState.RUNNING ||
      stateValue === EngineState.PAUSED;
    const paused = stateValue === EngineState.PAUSED;
    this.gameRunning = running;
    this.gamePaused = paused;
    this.refreshHudMetricsCache();
    if (stateValue === EngineState.RUNNING && this.pendingStart) {
      this.pendingStart = false;
      LogHelper.info('LibretroGame', 'Engine', '游戏启动成功');
    }
  }

  private inputSourceOptions: SelectOption[] = [];

  private refreshInputDevices() {
    const devices: InputDeviceInfo[] = runtimeInputPortController.listInputDevices();
    const items: InputSourceItem[] = buildInputSourceItems(devices);
    this.inputSourceItems = items;
    this.inputSourceOptions = items.map((item): SelectOption => {
      return { value: item.label };
    });
  }

  private syncPortAssignments() {
    this.portAssignments.forEach((assignment) => {
      this.applyPortAssignment(assignment.portId, assignment.sourceType, false, assignment.deviceId);
    });
  }

  private getPortAssignment(portId: number): PortAssignState {
    return findPortAssignment(this.portAssignments ?? [], portId);
  }

  private getInputSourceIndex(sourceType: InputSourceType, deviceId: string): number {
    return getInputSourceItemIndex(this.inputSourceItems, sourceType, deviceId);
  }

  private createSelectOption(value: ResourceStr): SelectOption {
    return { value: value };
  }

  private clampIndex(index: number, length: number): number {
    const safeIndex = index ?? 0;
    if (length <= 0) {
      return 0;
    }
    if (safeIndex < 0) {
      return 0;
    }
    if (safeIndex >= length) {
      return length - 1;
    }
    return safeIndex;
  }

  private get currentPortAssignment(): PortAssignState {
    return this.getPortAssignment(this.selectedPortIndex);
  }

  private get currentInputSourceIndex(): number {
    const assignment = this.currentPortAssignment;
    return this.getInputSourceIndex(assignment.sourceType, assignment.deviceId);
  }

  private get safeInputSourceIndex(): number {
    return this.clampIndex(this.currentInputSourceIndex, this.inputSourceItems.length);
  }

  private get currentInputSourceLabel(): ResourceStr {
    const item = this.inputSourceItems[this.safeInputSourceIndex];
    return item ? item.label : '未分配';
  }

  private readonly portOptions: SelectOption[] = [
    { value: 'P1' },
    { value: 'P2' },
    { value: 'P3' },
    { value: 'P4' }
  ];

  private get safePortIndex(): number {
    return this.clampIndex(this.selectedPortIndex, this.portOptions.length);
  }

  private get currentPortLabel(): ResourceStr {
    const option = this.portOptions[this.safePortIndex];
    return option?.value ?? 'P1';
  }

  private get safeCoreIndex(): number {
    return this.clampIndex(this.selectedCoreIndex, this.cores.length);
  }

  private get currentCoreLabel(): ResourceStr {
    const core = this.cores[this.safeCoreIndex];
    return core ? core.name : '无';
  }

  private get safeRomIndex(): number {
    return this.clampIndex(this.selectedRomIndex, this.romOptions.length);
  }

  private get currentRomLabel(): ResourceStr {
    const option = this.romOptions[this.safeRomIndex];
    return option?.value ?? '无';
  }

  private get hasRomOptions(): boolean {
    const options = this.romOptions ?? [];
    if (options.length === 0) {
      return false;
    }
    // 如果只有一个选项且是占位符“无”，也视为没有有效选项
    if (options.length === 1 && options[0].value === '无') {
      return false;
    }
    return true;
  }

  private updatePortAssignment(portId: number, sourceType: InputSourceType, deviceId: string) {
    this.portAssignments = updatePortAssignments(this.portAssignments, portId, sourceType, deviceId);
    this.portAssignmentVersion++;
  }

  private applyPortAssignment(
    portId: number,
    sourceType: InputSourceType,
    updateState: boolean,
    deviceId: string = ''
  ) {
    const ok = runtimeInputPortController.applyPortAssignment(portId, sourceType, deviceId);
    if (updateState) {
      this.updatePortAssignment(portId, sourceType, deviceId);
    }
    if (!ok) {
      LogHelper.warn('LibretroGame', 'Input', `端口映射失败: port=${portId} source=${sourceType}`);
    }
  }

  private beginActiveLibrarySession(romFile: string): void {
    this.librarySessionTracker.begin(romFile);
  }

  private async finalizeActiveLibrarySession(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.librarySessionTracker.finalize(context);
  }

  handleCoreCrash(payload: CoreCrashPayload) {
    let message = payload.reason;
    if (payload.step) {
      message += ` (${payload.step})`;
    }
    if (payload.message) {
      message += `: ${payload.message}`;
    }
    this.pendingStart = false;
    this.switchError = message;
    this.switching = false;
    this.gameRunning = false;
    this.gamePaused = false;
    void this.finalizeActiveLibrarySession();
    LogHelper.error('LibretroGame', 'Event', `core_crash: ${message}`);
  }

  handleFpsUpdate(payload: FpsUpdatePayload) {
    const fps = Number(payload.fps);
    if (!Number.isNaN(fps)) {
      const displayFps = this.normalizeFpsForDisplay(fps);
      this.perfDisplay.coreFps = displayFps;
      this.refreshHudMetricsCache();
    }

    const drops = Number(payload.drops ?? 0);
    const dupes = Number(payload.dupes ?? 0);
    const nulls = Number(payload.nulls ?? 0);
    const underruns = Number(payload.underruns ?? 0);
    const overruns = Number(payload.overruns ?? 0);
    const buf = Number(payload.audioBufferUsage ?? 0);
    this.librarySessionTracker.updateFrameStats(fps, drops, dupes, nulls, underruns, overruns, buf);

    this.perfDisplay.perfStatsText = `D:${drops} Du:${dupes} N:${nulls} U/O:${underruns}/${overruns} Buf:${buf.toFixed(0)}%`;
  }

  // 限制 FPS 显示范围：> 240 视为没有 v-sync 限速的瞬时跑分值，
  // 钳到目标帧率（通常 60），避免 UI 显示 "1000 FPS" 这种欺骗性数字。
  private normalizeFpsForDisplay(rawFps: number): number {
    if (!Number.isFinite(rawFps) || rawFps <= 0) {
      return 0;
    }
    const ceiling = 240;
    if (rawFps > ceiling) {
      return 60;
    }
    return Math.round(rawFps);
  }

  handleAudioStatus(payload: AudioStatusPayload) {
    const occupancy = Number(payload.occupancy);
    const underruns = Number(payload.underruns);
    if (Number.isNaN(occupancy) || Number.isNaN(underruns)) {
      return;
    }
    this.librarySessionTracker.updateAudioStatus(occupancy, underruns, Number(payload.overruns));
    this.perfDisplay.audioStatusText = `Buf:${occupancy.toFixed(0)}% U:${underruns}`;
  }

  handleGeometryUpdate(payload: GeometryUpdatePayload) {
    const w = Number(payload.base_width);
    const h = Number(payload.base_height);
    const a = Number(payload.aspect_ratio ?? 0);
    if (w > 0 && h > 0) {
      const aspectText = (a > 0) ? a.toFixed(3) : (w / h).toFixed(3);
      this.perfDisplay.geometryText = `Base:${w}x${h} AR:${aspectText}`;
      // 让 ArkUI 容器按真实游戏画面比例渲染 XComponent，避免拉伸。
      // 例如 2048 是 376×464（竖屏 ≈ 0.81），GBA 是 240×160（横屏 1.5）。
      const ratio = (a > 0) ? a : (w / h);
      if (Number.isFinite(ratio) && ratio > 0 && Math.abs(ratio - this.gameAspectRatio) > 0.005) {
        this.gameAspectRatio = ratio;
      }
    }
    // GeometryUpdate 是 core 完成 av_info 后下发,SET_INPUT_DESCRIPTORS 通常在
    // 此前已被 core 上报。switchGame 返回时窗口太早,这里再拉一次兜底。
    const mask = getRuntimeInputDescriptorMask();
    if (mask !== this.runtimeInputDescriptorMask) {
      this.runtimeInputDescriptorMask = mask;
    }
  }

  private startInputDebug() {
    this.inputDebugTracker.start((state: RuntimeInputDebugTextState) => {
      this.applyInputDebugTextState(state);
    });
  }

  private stopInputDebug() {
    this.inputDebugTracker.stop();
  }

  private applyInputDebugTextState(state: RuntimeInputDebugTextState): void {
    this.inputDebugText = state.inputDebugText;
    this.inputFocusText = state.inputFocusText;
    this.uiInputDebugText = state.uiInputDebugText;
  }
  
  // 更新 ROM 选项
  updateRomOptions() {
    const availableRoms = this.getAvailableRoms();
    let options = availableRoms.map((rom): SelectOption => {
      return { value: rom.name };
    });
    
    // 确保列表不为空，保证 Select 组件正常渲染
    if (options.length === 0) {
      options = [this.createSelectOption('无')];
    }
    
    this.romOptions = options;
    this.selectedRomIndex = 0;
  }
  
  // 获取当前核心可用的 ROM（缓存结果，避免重复 filter）
  getAvailableRoms(): RuntimeRomConfig[] {
    if (this.selectedCoreIndex === this.availableRomsCacheCoreIndex && this.roms === this.availableRomsCacheRef) {
      return this.availableRomsCache;
    }
    this.availableRomsCacheCoreIndex = this.selectedCoreIndex;
    this.availableRomsCacheRef = this.roms;
    const currentCore = this.cores[this.selectedCoreIndex];
    this.availableRomsCache = this.roms.filter(rom => rom.coreId === currentCore.id);
    return this.availableRomsCache;
  }

  private async refreshRomList() {
    const refreshToken = this.romListRefreshToken + 1;
    this.romListRefreshToken = refreshToken;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.roms = buildRuntimeRomConfigs([]);
      this.updateRomOptions();
      return;
    }

    let nextRoms: RuntimeRomConfig[] = buildRuntimeRomConfigs([]);
    try {
      const sources = await scanRuntimeRomSources(context, () => refreshToken === this.romListRefreshToken);
      if (!sources) {
        return;
      }
      nextRoms = buildRuntimeRomConfigs(sources);
    } catch (err) {
      const msg = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'ROM', `扫描 ROM 列表失败: ${msg}`);
    }

    if (refreshToken !== this.romListRefreshToken) {
      return;
    }

    this.roms = nextRoms;
    this.updateRomOptions();
    this.applyPendingLibraryLaunchRequest()
  }

  private applyPendingLibraryLaunchRequest(): void {
    const request = this.resolveInitialLibraryLaunchRequest()
    if (!request) {
      return
    }
    const coreIndex = this.cores.findIndex((core: CoreConfig) => core.id === request.coreId)
    if (coreIndex < 0) {
      LogHelper.warn('LibretroGame', 'Library', `未找到目标核心: ${request.coreId}`)
      return
    }

    this.selectedCoreIndex = coreIndex
    this.updateRomOptions()
    const availableRoms = this.getAvailableRoms()
    const romIndex = availableRoms.findIndex((rom: RuntimeRomConfig) => rom.file === request.romFile)
    if (romIndex < 0) {
      LogHelper.warn('LibretroGame', 'Library', `未找到目标 ROM: ${request.romFile}`)
      return
    }

    this.selectedRomIndex = romIndex
    if (request.autoStart) {
      void this.startOrSwitchGame()
    }
  }

  private resolveInitialLibraryLaunchRequest(): PendingLibraryLaunchRequest | undefined {
    const params = this.getUIContext().getRouter().getParams() as LibraryLaunchRouteParams
    if (typeof params?.coreId === 'string' && params.coreId.length > 0 &&
      typeof params?.romFile === 'string' && params.romFile.length > 0) {
      const request: PendingLibraryLaunchRequest = {
        coreId: params.coreId,
        romFile: params.romFile,
        autoStart: params.autoStart === true
      }
      return request
    }
    return consumePendingLibraryLaunchRequest()
  }

  private getRuntimeFpsText(): string {
    const fps = this.perfDisplay.coreFps > 0 ? this.perfDisplay.coreFps : this.perfDisplay.realtimeFps;
    return fps > 0 ? fps.toFixed(1) : '--.-';
  }

  private getRuntimeLatencyText(): string {
    if (this.librarySessionTracker.audioBufferUsage > 0) {
      return `${Math.max(1, Math.round(this.librarySessionTracker.audioBufferUsage * 8))}ms`;
    }
    return '--';
  }

  private getRuntimeCoreText(): string {
    if (this.currentCore.length > 0) {
      return this.currentCore.replace('.so', '').toUpperCase();
    }
    return '--';
  }

  private getRuntimeProcessText(): string {
    if (this.currentRom.length > 0) {
      return getFileNameFromPath(this.currentRom).replace(/\.[^.]+$/, '').toUpperCase();
    }
    return 'IDLE';
  }

  private refreshHudMetricsCache(): void {
    this.hudMetricsCache[0].value = this.getRuntimeFpsText();
    this.hudMetricsCache[1].value = this.getRuntimeLatencyText();
    this.hudMetricsCache[2].value = this.getRuntimeCoreText();
  }

  private getRuntimeHudMetrics(): RuntimeHudMetric[] {
    return this.hudMetricsCache;
  }

  private handleInputSourceSelect(index: number): void {
    const item = this.inputSourceItems[index];
    if (!item) {
      return;
    }
    LogHelper.info('LibretroGame', 'Input', `选择输入源: ${item.label} (type=${item.type}, id=${item.deviceId})`);
    this.applyPortAssignment(this.selectedPortIndex, item.type, true, item.deviceId);
  }

  private handleCoreSelect(index: number): void {
    this.selectedCoreIndex = this.clampIndex(index, this.cores.length);
    this.updateRomOptions();
    const core = this.cores[this.selectedCoreIndex];
    LogHelper.info('LibretroGame', 'UI', `选择核心: ${core ? core.name : '未知'}`);
  }

  private handleRomSelect(index: number): void {
    this.selectedRomIndex = this.clampIndex(index, this.romOptions.length);
    const roms = this.getAvailableRoms();
    const rom = roms.length > 0 ? roms[this.selectedRomIndex] : null;
    LogHelper.info('LibretroGame', 'UI', `选择 ROM: ${rom ? rom.name : '未知'}`);
  }

  private clearRuntimeStatsForConfigChange(): void {
    const okStats = runtimeRenderSettingsController.resetStats();
    this.perfDisplay.realtimeFps = 0;
    this.perfDisplay.coreFps = 0;
    this.perfDisplay.audioStatusText = '';
    this.perfDisplay.perfStatsText = '';
    this.perfDisplay.geometryText = '';
    LogHelper.info('LibretroGame', 'Config', `重置性能统计: okStats=${okStats}`);
  }

  private applySoftwareResolutionPreset(index: number): void {
    this.softwareMaxPresetIndex = index;
    const presets: ResolutionPreset[] = [
      { w: 640, h: 480 },
      { w: 1280, h: 720 },
      { w: 1920, h: 1080 }
    ];
    const preset = presets[index] || presets[1];
    const okMax = runtimeRenderSettingsController.setSoftwareMaxResolution(preset.w, preset.h);
    this.clearRuntimeStatsForConfigChange();
    void this.persistRuntimeRenderSettingsProfile();
    LogHelper.info('LibretroGame', 'Config', `设置软件最大分辨率: ${preset.w}x${preset.h}, okMax=${okMax}`);
  }

  private applyRenderMode(index: number): void {
    this.scalingMode = index;
    const okMode = runtimeRenderSettingsController.setScalingMode(index);
    if (index === 1) {
      const presets: ResolutionPreset[] = [
        { w: 640, h: 480 },
        { w: 1280, h: 720 },
        { w: 1920, h: 1080 }
      ];
      const preset = presets[this.softwareMaxPresetIndex] || presets[1];
      runtimeRenderSettingsController.setSoftwareMaxResolution(preset.w, preset.h);
    }
    this.clearRuntimeStatsForConfigChange();
    void this.persistRuntimeRenderSettingsProfile();
    LogHelper.info('LibretroGame', 'Config', `设置缩放模式: ${index}, okMode=${okMode}`);
  }

  private openRuntimeControlPanel(): void {
    this.refreshInputDevices();
    this.selectedPortIndex = 0;
    this.showControls = true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主体：上下分屏。游戏区在顶部，虚拟手柄在底部。
      // 用 Column + layoutWeight 物理切分，避免虚拟手柄叠在游戏画面上造成
      // 灰蒙感，也让 XComponent surface 高度直接对应游戏可视区，避免下半
      // 被按键 shroud 浪费像素。
      Column() {
        // 游戏画面舞台 — 顶部 62%。Stack 提供黑边背景，XComponent 按
        // gameAspectRatio 居中显示（2048 竖屏 ~0.81、GBA 横屏 1.5 等），
        // 不再被强行拉成全屏比例。
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: this.xComponentId,
            type: XComponentType.SURFACE,
            libraryname: 'entry'
          })
            .aspectRatio(this.gameAspectRatio > 0 ? this.gameAspectRatio : 4 / 3)
            .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
            .focusable(true)
            .focusOnTouch(true)
            .onTouch((event) => {
              this.inputDebugTracker.recordTouch(Number(event.type));
            })
            .onMouse((event) => {
              this.inputDebugTracker.recordMouse(Number(event.action));
            })
            .onKeyEvent((event) => {
              if (!event) {
                return;
              }
              this.inputDebugTracker.recordKey(Number(event.type));
            })
            .onLoad(() => {
              LogHelper.info(
                'LibretroGame',
                'UI',
                `XComponent 加载完成 (New Arch) id=${this.xComponentId}`
              );
            })
            .onDestroy(() => {
              LogHelper.info(
                'LibretroGame',
                'UI',
                `XComponent 销毁 (New Arch) id=${this.xComponentId}`
              );
            })
        }
        .width('100%')
        .layoutWeight(this.gameRunning && !this.gamePaused && !this.hideVirtualController ? 65 : 100)
        .backgroundColor(Color.Black)

        // 虚拟按键区 — 底部 35%(仅运行时显示)
        if (this.gameRunning && !this.gamePaused && !this.hideVirtualController) {
          Column() {
            RuntimeVirtualControllerLayer({
              buttons: this.runtimeInputLayoutButtons,
              layoutWidth: this.runtimeInputLayoutWidth,
              layoutHeight: this.runtimeInputLayoutHeight,
              inputDescriptorMask: this.runtimeInputDescriptorMask,
              onButtonChange: (keyId: number, pressed: boolean) => {
                this.setButton(keyId, pressed);
              },
              onAnalogChange: (index: number, x: number, y: number) => {
                this.setAnalog(index, x, y);
              }
            })
          }
          .width('100%')
          .layoutWeight(35)
        }
      }
      .width('100%')
      .height('100%')

      // 左上角系统菜单按钮：未运行时唤出 RuntimeControlPanel；运行中显示暂停图标，点击触发 PauseOverlay。
      Button(this.gameRunning ? '⏸' : 'MENU')
        .width(46)
        .height(40)
        .fontSize(this.gameRunning ? 20 : EmuTypography.xl)
        .fontColor(EmuColors.primary)
        .backgroundColor('#CC000000')
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
        .borderRadius(4)
        .margin({ left: 18, top: 48 })
        .enabled(!this.switching && (!this.gameRunning || !this.gamePaused))
        .onClick(() => {
          if (this.gameRunning) {
            this.pauseGame();
          } else {
            this.openRuntimeControlPanel();
          }
        })

      if (this.showControls) {
        this.ControlPanelOverlay()
      }

      if (this.gamePaused) {
        RuntimePauseOverlay({
          processText: this.getRuntimeProcessText(),
          saveStatusText: this.runtimeSaveStatusText,
          fpsText: this.getRuntimeFpsText(),
          onResume: () => {
            this.resumeGame();
          },
          onTerminate: () => {
            this.stopGame();
          },
          onAction: (actionCode: string) => {
            this.handlePauseTileAction(actionCode);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
  
  @Builder
  ControlPanelOverlay() {
    // 弹出层：遮罩 + 菜单面板
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Blank()
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.showControls = false;
      })

      RuntimeControlPanel({
        portOptions: this.portOptions,
        selectedPortIndex: this.safePortIndex,
        currentPortLabel: this.currentPortLabel,
        inputSourceOptions: this.inputSourceOptions,
        selectedInputSourceIndex: this.safeInputSourceIndex,
        currentInputSourceLabel: this.currentInputSourceLabel,
        coreOptions: this.coreOptions,
        selectedCoreIndex: this.safeCoreIndex,
        currentCoreLabel: this.currentCoreLabel,
        romOptions: this.romOptions,
        selectedRomIndex: this.safeRomIndex,
        currentRomLabel: this.currentRomLabel,
        hasRomOptions: this.hasRomOptions,
        switching: this.switching,
        scalingMode: this.scalingMode,
        softwareMaxPresetIndex: this.softwareMaxPresetIndex,
        hwRenderAllowed: this.hwRenderAllowed,
        hideVirtualController: this.hideVirtualController,
        gameRunning: this.gameRunning,
        gamePaused: this.gamePaused,
        runtimeSaveStatusText: this.runtimeSaveStatusText,
        switchError: this.switchError,
        onClose: () => {
          this.showControls = false;
        },
        onPortSelect: (index: number) => {
          this.selectedPortIndex = this.clampIndex(index, this.portOptions.length);
        },
        onInputSourceSelect: (index: number) => {
          this.handleInputSourceSelect(index);
        },
        onCoreSelect: (index: number) => {
          this.handleCoreSelect(index);
        },
        onRomSelect: (index: number) => {
          this.handleRomSelect(index);
        },
        onRenderModeSelect: (index: number) => {
          this.applyRenderMode(index);
        },
        onSoftwareResolutionSelect: (index: number) => {
          this.applySoftwareResolutionPreset(index);
        },
        onHwRenderChange: (value: boolean) => {
          this.hwRenderAllowed = value;
          const ok = runtimeRenderSettingsController.setHwRenderAllowed(value);
          void this.persistRuntimeRenderSettingsProfile();
          LogHelper.info('LibretroGame', 'Config', `设置 HW_RENDER 允许: ${value}, ok=${ok}`);
        },
        onHideVirtualControllerChange: (value: boolean) => {
          this.hideVirtualController = value;
          LogHelper.info('LibretroGame', 'Input', `隐藏虚拟手柄: ${value}`);
        },
        onStartGame: () => {
          void this.startOrSwitchGame();
        },
        onResumeGame: () => {
          this.resumeGame();
        },
        onPauseGame: () => {
          this.pauseGame();
        },
        onRestartGame: () => {
          void this.startOrSwitchGame();
        },
        onStopGame: () => {
          this.stopGame();
        },
        onQuickSave: () => {
          void this.quickSaveRuntimeState();
        },
        onQuickLoad: () => {
          void this.quickLoadRuntimeState();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#55000000')
  }

  // 设置按键状态 (新架构)
  setButton(buttonId: number, pressed: boolean) {
    sendRuntimeButton(this.portAssignments, this.selectedPortIndex, buttonId, pressed);
  }

  setAnalog(index: number, x: number, y: number) {
    sendRuntimeAnalog(this.portAssignments, this.selectedPortIndex, index, x, y);
  }
  
  // 开始/切换游戏 (新架构流程)
  async startOrSwitchGame(forceImmediate: boolean = false) {
    if (this.switching) {
      this.pendingSwitch = {
        coreIndex: this.selectedCoreIndex,
        romIndex: this.selectedRomIndex
      };
      LogHelper.warn('LibretroGame', 'Engine', '切换中，记录待切换请求');
      return;
    }
    this.switching = true;
    const core = this.cores[this.selectedCoreIndex];
    const availableRoms = this.getAvailableRoms();
    const rom = availableRoms[this.selectedRomIndex];
    
    if (!core || !rom) {
      LogHelper.error('LibretroGame', 'Core', '核心或 ROM 无效');
      this.switching = false;
      return;
    }

    // 防止重复点击导致同一游戏反复 stop/start 抖动。
    if (this.gameRunning &&
      !this.gamePaused &&
      this.currentCore === core.name &&
      this.currentRom === rom.name) {
      LogHelper.warn('LibretroGame', 'Engine', '当前游戏已运行，忽略重复启动请求');
      this.switching = false;
      return;
    }

    if (!forceImmediate) {
      const nowMs = Date.now();
      if (nowMs - this.lastStartOrSwitchAtMs < this.startOrSwitchDebounceMs) {
        LogHelper.warn('LibretroGame', 'Engine', '启动请求过于频繁，已防抖忽略');
        this.switching = false;
        return;
      }
      this.lastStartOrSwitchAtMs = nowMs;
    }
    const token = this.switchToken + 1;
    this.switchToken = token;
    await this.finalizeActiveLibrarySession();
    if (!this.isCurrentSwitchTask(token)) {
      return;
    }
    
    LogHelper.info(
      'LibretroGame',
      'Engine',
      `[NewArch] 开始游戏: ${core.name} - ${rom.name}`
    );
    this.switchError = '';
    let success = false;

    try {
      // 1. 获取上下文
      const context = this.getUIContext().getHostContext() as
        common.UIAbilityContext;
      if (!context) throw new Error('获取 Context 失败');
      
      const filesDir = context.filesDir;
      const bundleCodeDir = context.bundleCodeDir;
      const resMgr = context.resourceManager;
      const timeoutMs = 5000;

      runtimeSessionController.clearLastError();
      
      const corePath = await resolveRuntimeCorePath(bundleCodeDir, core.soFile);
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      LogHelper.info('LibretroGame', 'Engine', `加载 Core: ${corePath}`);
      LogHelper.info('LibretroGame', 'Engine', `加载 ROM: ${rom.file}`);
      const resolved = resolveRuntimeRomPathForSwitch(
        rom.file,
        resMgr,
        filesDir
      );
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      LogHelper.info(
        'LibretroGame',
        'Engine',
        `Resolved ROM path: ${resolved.romPath}, useResMgr=${resolved.useResMgr}`
      );
      const ok = await runtimeSessionController.switchGame({
        corePath,
        romPath: resolved.romPath,
        filesDir,
        timeoutMs,
        token,
        resourceManager: resolved.useResMgr ? resMgr : undefined
      });
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      if (!ok) {
        throw new Error(runtimeSessionController.formatLastError('SwitchGame'));
      }
      
      this.currentCore = core.name;
      this.currentRom = rom.name;
      this.gameRunning = true;
      this.gamePaused = false;
      this.pendingStart = false;
      // core 在 retro_load_game / retro_run 早期 frame 通过 SET_INPUT_DESCRIPTORS
      // 声明使用的按键,这里在 switchGame 成功后立刻拉一次。
      this.runtimeInputDescriptorMask = getRuntimeInputDescriptorMask();
      this.refreshHudMetricsCache();
      await markLibraryRecordPlayed(context, rom.file);
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      this.beginActiveLibrarySession(rom.file);
      LogHelper.info('LibretroGame', 'Engine', '游戏启动成功');
      success = true;

    } catch (e) {
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      this.switchError = e.message || String(e);
      LogHelper.error(
        'LibretroGame',
        'Engine',
        `启动异常: ${this.switchError}`
      );
    } finally {
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      if (!success) {
        void runtimeSessionController.stopAsync();
      }
      this.switching = false;
      if (this.pendingSwitch) {
        const pending = this.pendingSwitch;
        this.pendingSwitch = undefined;
        this.selectedCoreIndex = pending.coreIndex;
        this.updateRomOptions();
        const availableRoms = this.getAvailableRoms();
        this.selectedRomIndex =
          pending.romIndex < availableRoms.length ? pending.romIndex : 0;
        this.startOrSwitchGame(true);
      }
    }
  }

  // 暂停游戏
  pauseGame() {
    if (this.gameRunning && !this.gamePaused) {
      runtimeSessionController.pause();
      this.gamePaused = true;
      LogHelper.info('LibretroGame', 'Engine', '游戏已暂停');
    }
  }
  
  // 继续游戏
  resumeGame() {
    if (this.gameRunning && this.gamePaused) {
      runtimeSessionController.resume();
      this.gamePaused = false;
      LogHelper.info('LibretroGame', 'Engine', '游戏已继续');
    }
  }
  
  // 停止游戏
  stopGame() {
    if (this.gameRunning || this.gamePaused) {
      void this.finalizeActiveLibrarySession();
      // stopAsync uses napi_async_work — returns immediately, real stop on worker
      void runtimeSessionController.stopAsync();
      this.gameRunning = false;
      this.gamePaused = false;
      this.runtimeInputDescriptorMask = 0;
      LogHelper.info('LibretroGame', 'Engine', '游戏已停止');
    }
  }
}
