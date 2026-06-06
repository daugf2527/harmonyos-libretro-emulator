/*
 * 通用 Libretro 游戏页面 (New Architecture)
 * 基于 LibretroEngine 新架构重构
 */

import LogHelper from '../common/LogHelper';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { EmuColors, EmuTypography } from '../common/EmuUiTokens';
import { RuntimeHudMetric } from '../components/RuntimeTopHudBar';
import { RuntimePauseOverlay } from '../components/RuntimePauseOverlay';
import { RuntimeVirtualControllerLayer } from '../components/RuntimeVirtualControllerLayer';
import { SingleModeLayout, DualModeLayout, TripleModeLayout } from '../components/FoldableLayouts';
import { ErrorCodeUtils, EngineErrorCodes, FileErrorCodes } from '../common/ErrorCodes';
import {
  createDefaultPortAssignments,
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
import {
  createDefaultRuntimeAudioSettingsProfile,
  loadRuntimeAudioSettingsProfile,
  RuntimeAudioSettingsProfile
} from '../common/RuntimeAudioSettingsRepository'
import { runtimeAudioSettingsController } from '../common/RuntimeAudioSettingsController'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'
import { scanRuntimeRomSources } from '../common/RuntimeRomSourceScanner'

/**
 * 携带 C++ 回传 errorCode 的切换游戏异常。
 * 让 catch 块直接消费结构化错误码，不再依赖 message 字符串嗅探。
 */
class SwitchGameError extends Error {
  errorCode?: number

  constructor(errorCode: number | undefined, message: string) {
    super(message)
    this.errorCode = errorCode
  }
}

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
  retryCount: number;
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
  @State switchProgress: number = 0;
  @State switchProgressText: string = '';
  @State selectedCoreIndex: number = 0;
  @State selectedRomIndex: number = 0;
  @State selectedPortIndex: number = 0;
  private portAssignments: PortAssignState[] = createDefaultPortAssignments();
  @State perfDisplay: PerfDisplayState = { realtimeFps: 0, coreFps: 0, audioStatusText: '', perfStatsText: '', geometryText: '' };
  @State inputDebugText: string = '';
  @State inputFocusText: string = '';
  @State uiInputDebugText: string = '';
  @State scalingMode: number = 2; // 默认 GLES (2)
  @State softwareMaxPresetIndex: number = 1;
  @State hwRenderAllowed: boolean = true;
  @State hideVirtualController: boolean = false;
  @State private idleHintReady: boolean = false;
  // 游戏画面 aspect ratio：0 表示尚未收到 geometry_update（用 fallback 4/3）。
  // handleGeometryUpdate 会写入真实值（如 2048 ≈ 0.81 竖屏、GBA 1.5 横屏）。
  @State private gameAspectRatio: number = 0;
  @State runtimeSaveStatusText: string = '存档就绪';
  // 折叠屏适配状态
  @State currentFoldMode: 'single' | 'dual' | 'triple' = 'single';
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;
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
  private readonly maxSwitchRetries: number = 2;
  private pageActive: boolean = false;
  private romListRefreshToken: number = 0;
  private lastStartOrSwitchAtMs: number = 0;
  private readonly librarySessionTracker: RuntimeLibrarySessionTracker = new RuntimeLibrarySessionTracker();
  private readonly inputDebugTracker: RuntimeInputDebugTracker = new RuntimeInputDebugTracker();
  private readonly runtimeSaveStateController: RuntimeSaveStateController = new RuntimeSaveStateController();
  private renderSettingsProfile: RuntimeRenderSettingsProfile = createDefaultRuntimeRenderSettingsProfile();
  private audioSettingsProfile: RuntimeAudioSettingsProfile = createDefaultRuntimeAudioSettingsProfile();
  private readonly startOrSwitchDebounceMs: number = 600;
  private readonly runtimeInputLayoutWidth: number = 440;
  private readonly runtimeInputLayoutHeight: number = 340;

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
    this.setKeepScreenOn(true);
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

    void this.refreshRomList();
    this.startInputDebug();
    this.syncPortAssignments();
    void this.loadRuntimeInputLayout();
    void this.loadRuntimeRenderSettings();
    void this.loadRuntimeAudioSettings();
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
    this.setKeepScreenOn(false);
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
      // 使用错误码提供更友好的提示
      const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_READ_ERROR.numericCode);
      LogHelper.info('LibretroGame', 'Input', `错误提示: ${userMsg}`);
      this.runtimeInputLayoutButtons = createDefaultInputLayoutProfile().buttons;
    }
  }

  private async loadRuntimeRenderSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    const profile = await loadRuntimeRenderSettingsProfile(context);
    // T8-C-F5 同范式:本方法由 aboutToAppear fire-and-forget 触发,await 配置读取
    // 期间用户可能退出页面(aboutToDisappear 置 pageActive=false 并销毁),写
    // @State(scalingMode/softwareMaxPresetIndex/hwRenderAllowed)前必须检查
    // pageActive,否则向已销毁页面 setState。对照 quickSave/quickLoad 已有此守卫,
    // 本方法此前遗漏(D016)。
    if (!this.pageActive) {
      return;
    }
    this.renderSettingsProfile = profile;
    this.scalingMode = profile.scalingMode;
    this.softwareMaxPresetIndex = profile.softwareMaxPresetIndex;
    this.hwRenderAllowed = profile.hwRenderAllowed;
  }

  private async loadRuntimeAudioSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    const profile = await loadRuntimeAudioSettingsProfile(context);
    // await 后页面可能已销毁(D016 范式);audioSettingsProfile 虽为 private(无
    // re-render),仍守卫保持一致 + 避免向已销毁页面写。
    if (!this.pageActive) {
      return;
    }
    this.audioSettingsProfile = profile;
    // 若游戏已在运行(用户改设置后返回游戏页等场景),立即应用新延迟。
    if (this.gameRunning) {
      runtimeAudioSettingsController.setMinimumAudioLatency(profile.latencyMs);
    }
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
    if (actionCode === 'restart_game') {
      this.resumeGame();
      void this.startOrSwitchGame(true);
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

  private syncPortAssignments() {
    this.portAssignments.forEach((assignment) => {
      this.applyPortAssignment(assignment.portId, assignment.sourceType, false, assignment.deviceId);
    });
  }

  private updatePortAssignment(portId: number, sourceType: InputSourceType, deviceId: string) {
    this.portAssignments = updatePortAssignments(this.portAssignments, portId, sourceType, deviceId);
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
    const displayFps = (!Number.isNaN(fps))
      ? this.normalizeFpsForDisplay(fps)
      : this.perfDisplay.coreFps;

    const drops = Number(payload.drops ?? 0);
    const dupes = Number(payload.dupes ?? 0);
    const nulls = Number(payload.nulls ?? 0);
    const underruns = Number(payload.underruns ?? 0);
    const overruns = Number(payload.overruns ?? 0);
    const buf = Number(payload.audioBufferUsage ?? 0);
    this.librarySessionTracker.updateFrameStats(fps, drops, dupes, nulls, underruns, overruns, buf);

    // 整体替换触发 @State 刷新（V1 不支持字段级 mutate 观测；ArkTS 禁对象 spread，显式列字段）
    this.perfDisplay = {
      realtimeFps: this.perfDisplay.realtimeFps,
      coreFps: displayFps,
      audioStatusText: this.perfDisplay.audioStatusText,
      perfStatsText: `D:${drops} Du:${dupes} N:${nulls} U/O:${underruns}/${overruns} Buf:${buf.toFixed(0)}%`,
      geometryText: this.perfDisplay.geometryText
    };
    if (!Number.isNaN(fps)) {
      this.refreshHudMetricsCache();
    }
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
    // 整体替换触发 @State 刷新（ArkTS 禁对象 spread，显式列字段）
    this.perfDisplay = {
      realtimeFps: this.perfDisplay.realtimeFps,
      coreFps: this.perfDisplay.coreFps,
      audioStatusText: `Buf:${occupancy.toFixed(0)}% U:${underruns}`,
      perfStatsText: this.perfDisplay.perfStatsText,
      geometryText: this.perfDisplay.geometryText
    };
  }

  handleGeometryUpdate(payload: GeometryUpdatePayload) {
    const w = Number(payload.base_width);
    const h = Number(payload.base_height);
    const a = Number(payload.aspect_ratio ?? 0);
    if (w > 0 && h > 0) {
      const aspectText = (a > 0) ? a.toFixed(3) : (w / h).toFixed(3);
      // 整体替换触发 @State 刷新（ArkTS 禁对象 spread，显式列字段）
      this.perfDisplay = {
        realtimeFps: this.perfDisplay.realtimeFps,
        coreFps: this.perfDisplay.coreFps,
        audioStatusText: this.perfDisplay.audioStatusText,
        perfStatsText: this.perfDisplay.perfStatsText,
        geometryText: `Base:${w}x${h} AR:${aspectText}`
      };
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

  updateRomOptions() {
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
      // 使用错误码提供具体错误信息
      const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_LIST_ERROR.numericCode);
      LogHelper.warn('LibretroGame', 'ROM', `用户提示: ${userMsg}`);
    }

    if (refreshToken !== this.romListRefreshToken) {
      return;
    }

    this.roms = nextRoms;
    this.updateRomOptions();
    this.applyPendingLibraryLaunchRequest()
    this.idleHintReady = true
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

  // 折叠态检测：根据屏幕宽高比判断折叠态
  private detectFoldMode(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const aspectRatio = width / height;
    // 折叠态判断阈值（基于华为折叠屏设备实测数据）
    // 单折态（竖屏）：宽高比 < 1.2
    // 双折态（半展开）：1.2 <= 宽高比 < 2.0
    // 三折态（全展开）：宽高比 >= 2.0
    let newMode: 'single' | 'dual' | 'triple' = 'single';
    if (aspectRatio >= 2.0) {
      newMode = 'triple';
    } else if (aspectRatio >= 1.2) {
      newMode = 'dual';
    } else {
      newMode = 'single';
    }
    if (newMode !== this.currentFoldMode) {
      LogHelper.info('LibretroGame', 'Foldable', `折叠态切换: ${this.currentFoldMode} -> ${newMode} (${width}x${height}, AR=${aspectRatio.toFixed(2)})`);
      this.currentFoldMode = newMode;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 根据折叠态选择布局
      if (this.currentFoldMode === 'single') {
        // 单折态：原有布局（上下分屏）
        this.SingleFoldLayout()
      } else if (this.currentFoldMode === 'dual') {
        // 双折态：Digital GameBoy 布局
        DualModeLayout({
          xComponentId: this.xComponentId,
          screenAspectRatio: this.gameAspectRatio > 0 ? this.gameAspectRatio : 4 / 3,
          onKeyPress: (keyId: number, pressed: boolean) => {
            this.setButton(keyId, pressed);
          },
          onReset: () => {
            void this.startOrSwitchGame(true);
          },
          onStop: () => {
            this.stopGame();
          }
        })
      } else {
        // 三折态：Switch Layout 布局
        TripleModeLayout({
          xComponentId: this.xComponentId,
          screenAspectRatio: this.gameAspectRatio > 0 ? this.gameAspectRatio : 4 / 3,
          fps: this.perfDisplay.coreFps,
          cpuUsage: 0,
          onKeyPress: (keyId: number, pressed: boolean) => {
            this.setButton(keyId, pressed);
          },
          onReset: () => {
            void this.startOrSwitchGame(true);
          },
          onStop: () => {
            this.stopGame();
          }
        })
      }

      // 左上角系统菜单按钮：运行中显示暂停图标，点击触发 PauseOverlay；未运行时按 MENU 返回上一页。
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
            this.getUIContext().getRouter().back();
          }
        })

      // 取消按钮：仅在 switching=true 时显示
      if (this.switching) {
        Column({ space: 12 }) {
          // 进度条
          Column({ space: 8 }) {
            Text(this.switchProgressText)
              .fontSize(14)
              .fontColor(EmuColors.onSurface)
              .fontWeight(FontWeight.Medium)

            Progress({ value: this.switchProgress, total: 100, type: ProgressType.Linear })
              .width(200)
              .height(4)
              .color(EmuColors.primary)
              .backgroundColor('#33FFFFFF')

            Text(`${this.switchProgress}%`)
              .fontSize(12)
              .fontColor('#FF9D9E9E')
              .fontFamily('monospace')
          }
          .padding(16)
          .backgroundColor('#CC000000')
          .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
          .borderRadius(8)

          Button('取消')
            .width(60)
            .height(40)
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.error)
            .backgroundColor('#CC000000')
            .border({ width: 0.5, color: '#33FF4444', style: BorderStyle.Solid })
            .borderRadius(4)
            .onClick(() => {
              LogHelper.info('LibretroGame', 'Engine', 'Cancel switch requested');
              runtimeSessionController.cancelSwitch();
              this.switching = false;
              this.switchError = '';
            })
        }
        .margin({ left: 18, top: 100 })
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

      if (this.idleHintReady && !this.gameRunning && !this.switching && !this.pendingStart && !this.gamePaused) {
        this.IdleEmptyState()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 监听屏幕尺寸变化，检测折叠态
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width !== this.screenWidth || height !== this.screenHeight) {
        this.screenWidth = width;
        this.screenHeight = height;
        this.detectFoldMode(width, height);
      }
    })
  }

  @Builder
  private IdleEmptyState() {
    Column({ space: 18 }) {
      Text('▢')
        .fontSize(56)
        .fontColor(EmuColors.primary)
        .opacity(0.6)

      Text('未加载游戏')
        .fontSize(18)
        .fontColor(EmuColors.onSurface)
        .fontWeight(FontWeight.Medium)

      Text('从游戏库选择一个游戏开始')
        .fontSize(13)
        .fontColor('#FF9D9E9E')
        .fontFamily('monospace')
        .letterSpacing(0.6)
        .textAlign(TextAlign.Center)

      Button('返回游戏库')
        .fontSize(14)
        .fontColor(EmuColors.primary)
        .fontWeight(FontWeight.Bold)
        .backgroundColor('#0F1A0F')
        .border({ width: 0.5, color: '#5500FF41', style: BorderStyle.Solid })
        .borderRadius(6)
        .height(40)
        .padding({ left: 20, right: 20 })
        .margin({ top: 12 })
        .onClick(() => {
          this.getUIContext().getRouter().back()
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  @Builder
  private SingleFoldLayout() {
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
        romIndex: this.selectedRomIndex,
        retryCount: 0
      };
      LogHelper.warn('LibretroGame', 'Engine', '切换中，记录待切换请求');
      return;
    }
    this.switching = true;
    this.switchProgress = 0;
    this.switchProgressText = '准备切换...';
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
      const result = await runtimeSessionController.switchGame({
        corePath,
        romPath: resolved.romPath,
        filesDir,
        timeoutMs,
        token,
        resourceManager: resolved.useResMgr ? resMgr : undefined,
        progressCallback: (progress: number, message: string) => {
          this.switchProgress = progress;
          this.switchProgressText = message;
        }
      });
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      if (!result.success) {
        // 直接消费 C++ 回传的结构化 errorCode（接通跨层错误码通道，
        // 不再靠 message 字符串嗅探）。errorCode 缺省时回退到引擎错误信息。
        const failure = new SwitchGameError(
          result.errorCode,
          result.message || runtimeSessionController.formatLastError('SwitchGame')
        );
        throw failure;
      }

      this.currentCore = core.name;
      this.currentRom = rom.name;
      this.gameRunning = true;
      this.gamePaused = false;
      this.pendingStart = false;
      // D019: 游戏启动成功(引擎 RUNNING、AudioBridge 已 Reset(sample_rate))后应用
      // 音频缓冲延迟,加深 RingBuffer 水位抗 callback 抖动(模拟器/低端机 underrun)。
      // 生产路径此前从不调用,沿用默认 latency=0(浅缓冲),故模拟器抖动即 underrun。
      runtimeAudioSettingsController.setMinimumAudioLatency(this.audioSettingsProfile.latencyMs);
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
      const rawMessage = (e as Error).message || String(e);
      let errorCode = EngineErrorCodes.ENGINE_START_FAILED;

      if (e instanceof SwitchGameError && e.errorCode !== undefined) {
        // 首选：C++ 回传的结构化 errorCode（精确，含 STATE_TRANSITION_FAILED 等
        // 字符串嗅探拿不到的码）。
        const definition = ErrorCodeUtils.findByNumericCode(e.errorCode);
        if (definition) {
          errorCode = definition;
        }
      } else if (rawMessage.includes('Core') || rawMessage.includes('核心')) {
        // 兜底：非结构化异常（如中间层 reject）退回消息推断。
        errorCode = EngineErrorCodes.CORE_LOAD_FAILED;
      } else if (rawMessage.includes('ROM') || rawMessage.includes('游戏')) {
        errorCode = EngineErrorCodes.ROM_LOAD_FAILED;
      }

      const userMsg = ErrorCodeUtils.getUserMessage(errorCode.numericCode);
      this.switchError = userMsg;

      LogHelper.error(
        'LibretroGame',
        'Engine',
        `启动异常 [${errorCode.code}]: ${rawMessage}`
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

        // 如果当前切换失败且 pending 是同一个请求的重试，检查重试次数
        if (!success &&
            pending.coreIndex === this.selectedCoreIndex &&
            pending.romIndex === this.selectedRomIndex) {
          if (pending.retryCount >= this.maxSwitchRetries) {
            LogHelper.error(
              'LibretroGame',
              'Engine',
              `切换失败且已达最大重试次数 (${this.maxSwitchRetries})，放弃重试`
            );
            this.switchError = `切换失败: ${this.switchError || '未知错误'} (已重试 ${pending.retryCount} 次)`;
            return;
          }
          // 增加重试计数
          this.pendingSwitch = {
            coreIndex: pending.coreIndex,
            romIndex: pending.romIndex,
            retryCount: pending.retryCount + 1
          };
          LogHelper.warn(
            'LibretroGame',
            'Engine',
            `切换失败，准备重试 (${pending.retryCount + 1}/${this.maxSwitchRetries})`
          );
        }

        // 执行 pending 切换
        this.selectedCoreIndex = pending.coreIndex;
        this.updateRomOptions();
        const availableRoms = this.getAvailableRoms();
        this.selectedRomIndex =
          pending.romIndex < availableRoms.length ? pending.romIndex : 0;
        this.startOrSwitchGame(true);
      }
    }
  }

  // 游戏活跃时保持屏幕常亮，暂停/离开时恢复系统息屏策略（省电）。
  // 复用项目统一的 context 获取方式 this.getUIContext().getHostContext()。
  private setKeepScreenOn(on: boolean): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      return win.setWindowKeepScreenOn(on);
    }).then(() => {
      LogHelper.info('LibretroGame', 'Window', `屏幕常亮=${on}`);
    }).catch((err: Error) => {
      LogHelper.warn('LibretroGame', 'Window', `setWindowKeepScreenOn 失败: ${err.message}`);
    });
  }

  // 暂停游戏
  pauseGame() {
    if (this.gameRunning && !this.gamePaused) {
      runtimeSessionController.pause();
      this.gamePaused = true;
      this.setKeepScreenOn(false);
      LogHelper.info('LibretroGame', 'Engine', '游戏已暂停');
    }
  }

  // 继续游戏
  resumeGame() {
    if (this.gameRunning && this.gamePaused) {
      runtimeSessionController.resume();
      this.gamePaused = false;
      this.setKeepScreenOn(true);
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
