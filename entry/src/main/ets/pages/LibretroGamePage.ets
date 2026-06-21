/*
 * 通用 Libretro 游戏页面 (New Architecture)
 * 基于 LibretroEngine 新架构重构
 */

import LogHelper from '../common/LogHelper';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { EmuColors, EmuTypography } from '../common/EmuUiTokens';
import { ScanlineBackground } from '../components/EmuAppShell'
import { RuntimePauseOverlay } from '../components/RuntimePauseOverlay';
import { RuntimeVirtualControllerLayer } from '../components/RuntimeVirtualControllerLayer';
import { DualModeLayout, TripleModeLayout } from '../components/FoldableLayouts';
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
  DiskControlPayload,
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
import {
  RuntimeSaveStateController,
  RuntimeSaveStateListItem
} from '../common/RuntimeSaveStateController'
import {
  RuntimeAVInfo,
  RuntimePerformanceStats,
  runtimeSessionController
} from '../common/RuntimeSessionController'
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
import { runtimeCheatController } from '../common/RuntimeCheatController'
import { runtimeCoreControlController } from '../common/RuntimeCoreControlController'
import {
  RuntimeInputDebugStats,
  RuntimeStatusSnapshot,
  runtimeCoreDiagnosticController
} from '../common/RuntimeCoreDiagnosticController'
import {
  runtimeCoreOptionsController,
  RuntimeCoreOptionItem
} from '../common/RuntimeCoreOptionsController'
import {
  createRuntimeCheatItem,
  loadRuntimeCheatItemsForRom,
  RuntimeCheatItem,
  saveRuntimeCheatItemsForRom
} from '../common/RuntimeCheatRepository'
import { runtimeDiskControlController } from '../common/RuntimeDiskControlController'
import { importPickedRuntimeDiskImages } from '../common/RuntimeDiskImageImportService'
import {
  RuntimeSramBackupListItem,
  RuntimeSramController
} from '../common/RuntimeSramController'
import {
  createDefaultRuntimeInputPreferencesProfile,
  loadRuntimeInputPreferencesProfile
} from '../common/RuntimeInputPreferencesRepository'
import {
  createDefaultRuntimeControllerPortDevices,
  describeRuntimeControllerPortDevice,
  normalizeRuntimeControllerPortDevice,
  runtimeInputPortController
} from '../common/RuntimeInputPortController'
import { scanRuntimeRomSources } from '../common/RuntimeRomSourceScanner'
import {
  createDefaultRuntimeVisualSettingsProfile,
  loadRuntimeVisualSettingsProfile,
  resolveRuntimeVisualAspectRatio,
  RuntimeVisualSettingsProfile
} from '../common/RuntimeVisualSettingsRepository'

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

// 性能 HUD 状态：保持字段级追踪，避免 2Hz-5Hz 遥测刷新退化成整页重建。
// 暂停浮层 / 三折信息板只读取其中少数字段，因此必须改字段而不是整体替换对象。
@ObservedV2
class PerfDisplayState {
  @Trace realtimeFps: number = 0;
  @Trace coreFps: number = 0;
  @Trace cpuLoadPercent: number = 0;
  @Trace audioStatusText: string = '';
  @Trace perfStatsText: string = '';
  @Trace geometryText: string = '';
}

@Entry
@ComponentV2
struct LibretroGamePage {
  @Local currentCore: string = '';
  @Local currentRom: string = '';
  @Local gameRunning: boolean = false;
  @Local gamePaused: boolean = false;
  @Local switching: boolean = false;
  @Local switchError: string = '';
  @Local switchProgress: number = 0;
  @Local switchProgressText: string = '';
  @Local selectedCoreIndex: number = 0;
  @Local selectedRomIndex: number = 0;
  @Local selectedPortIndex: number = 0;
  @Local private portAssignments: PortAssignState[] = createDefaultPortAssignments();
  @Local perfDisplay: PerfDisplayState = new PerfDisplayState();
  @Local scalingMode: number = 2; // 默认 GLES (2)
  @Local swapInterval: number = 1;
  @Local softwareMaxPresetIndex: number = 1;
  @Local aiUpscaleEnabled: boolean = false;
  @Local hwRenderAllowed: boolean = true;
  @Local hideVirtualController: boolean = false;
  @Local hideUndeclaredKeys: boolean = false;
  @Local private idleHintReady: boolean = false;
  // 游戏画面 aspect ratio：0 表示尚未收到 geometry_update（用 fallback 4/3）。
  // handleGeometryUpdate 会写入真实值（如 2048 ≈ 0.81 竖屏、GBA 1.5 横屏）。
  @Local private gameAspectRatio: number = 0;
  @Local runtimeSaveStatusText: string = '存档就绪';
  @Local private runtimeSaveManagerVisible: boolean = false;
  @Local private runtimeSaveManagerBusy: boolean = false;
  @Local private runtimeSaveManagerSummaryText: string = '';
  @Local private runtimeSaveManagerItems: RuntimeSaveStateListItem[] = [];
  @Local private runtimeSramManagerVisible: boolean = false;
  @Local private runtimeSramManagerBusy: boolean = false;
  @Local private runtimeSramManagerSummaryText: string = '';
  @Local private runtimeSramManagerItems: RuntimeSramBackupListItem[] = [];
  @Local private runtimeCheatManagerVisible: boolean = false;
  @Local private runtimeCheatManagerBusy: boolean = false;
  @Local private runtimeCheatManagerSupported: boolean = false;
  @Local private runtimeCheatManagerSummaryText: string = '';
  @Local private runtimeCheatManagerItems: RuntimeCheatItem[] = [];
  @Local private runtimeCheatDraftName: string = '';
  @Local private runtimeCheatDraftCode: string = '';
  @Local private runtimeCoreOptionsVisible: boolean = false;
  @Local private runtimeCoreOptionsBusy: boolean = false;
  @Local private runtimeCoreOptionsSummaryText: string = '';
  @Local private runtimeCoreOptionsItems: RuntimeCoreOptionItem[] = [];
  @Local private runtimePortControlVisible: boolean = false;
  @Local private runtimePortControlSummaryText: string = '';
  @Local private runtimeControllerPortDevices: number[] = createDefaultRuntimeControllerPortDevices();
  @Local private runtimeRegionText: string = '';
  @Local private runtimeStateText: string = '';
  @Local private runtimeLoadStateText: string = '';
  @Local private runtimeSaveStateSizeText: string = '';
  @Local private runtimeInputDebugText: string = '';
  @Local private diskControlSupported: boolean = false;
  @Local private diskControlType: string = '';
  @Local private diskControlImageCount: number = 0;
  @Local private diskControlImageIndex: number = 0;
  @Local private diskControlEjected: boolean = false;
  @Local private diskControlStatusText: string = '';
  @Local private diskControlBusy: boolean = false;
  // 折叠屏适配状态
  @Local currentFoldMode: 'single' | 'dual' | 'triple' = 'single';
  @Local screenWidth: number = 0;
  @Local screenHeight: number = 0;
  @Local private runtimeInputLayoutButtons: InputLayoutButton[] = createDefaultInputLayoutProfile().buttons;
  // RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS mask:bit N = RETRO_DEVICE_ID_JOYPAD_N 被
  // 当前 core 声明使用,0 = core 未上报(用 fallback 全键集)。@State 触发子组件 re-render。
  @Local private runtimeInputDescriptorMask: number = 0;

  // 使用包含 "new_arch" 的 ID 以触发 C++ 侧的新引擎逻辑
  private xComponentId: string = 'new_arch_game_xcomponent';
  private eventScope: EventHubScope | undefined = undefined;
  private pendingStart: boolean = false;
  private switchToken: number = 0;
  private pendingSwitch: PendingSwitch | undefined = undefined;
  private readonly maxSwitchRetries: number = 2;
  private pageActive: boolean = false;
  private resumeAfterToolPage: boolean = false;
  private coreSupportsReset: boolean = false;
  private coreSupportsRegionQuery: boolean = false;
  private coreSupportsCheatReset: boolean = false;
  private coreSupportsCheatSet: boolean = false;
  private romListRefreshToken: number = 0;
  private runtimeSaveManagerTaskToken: number = 0;
  private runtimeSramManagerTaskToken: number = 0;
  private runtimeCheatManagerTaskToken: number = 0;
  private runtimeDiskControlTaskToken: number = 0;
  private runtimeStatusSnapshotTaskToken: number = 0;
  private lastStartOrSwitchAtMs: number = 0;
  private readonly librarySessionTracker: RuntimeLibrarySessionTracker = new RuntimeLibrarySessionTracker();
  private readonly runtimeSaveStateController: RuntimeSaveStateController = new RuntimeSaveStateController();
  private readonly runtimeSramController: RuntimeSramController = new RuntimeSramController();
  private renderSettingsProfile: RuntimeRenderSettingsProfile = createDefaultRuntimeRenderSettingsProfile();
  private audioSettingsProfile: RuntimeAudioSettingsProfile = createDefaultRuntimeAudioSettingsProfile();
  @Local private visualSettingsProfile: RuntimeVisualSettingsProfile = createDefaultRuntimeVisualSettingsProfile();
  private readonly startOrSwitchDebounceMs: number = 600;
  private readonly runtimeInputLayoutWidth: number = 440;
  private readonly runtimeInputLayoutHeight: number = 340;

  private roms: RuntimeRomConfig[] = [];
  private readonly cores: CoreConfig[] = LIBRETRO_CORE_CATALOG;
  // CRITICAL fix: cache getAvailableRoms() .filter() result (reference-equality on roms + coreIndex)
  private availableRomsCache: RuntimeRomConfig[] = [];
  private availableRomsCacheRef: RuntimeRomConfig[] | null = null;
  private availableRomsCacheCoreIndex: number = -1;

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
    this.eventScope.onDiskControl((payload) => {
      this.handleDiskControl(payload);
    });

    void this.refreshRomList();
    this.syncPortAssignments();
    this.refreshRuntimePortControlSummaryText();
    void this.loadRuntimeInputLayout();
    void this.loadRuntimeRenderSettings();
    void this.loadRuntimeAudioSettings();
    void this.loadRuntimeInputPreferences();
    void this.loadRuntimeVisualSettings();
    this.maybeResumeAfterToolPage();
  }

  aboutToDisappear() {
    this.romListRefreshToken += 1;
    this.pageActive = false;
    this.runtimeSaveManagerTaskToken += 1;
    this.runtimeCheatManagerTaskToken += 1;
    this.runtimeDiskControlTaskToken += 1;
    this.resetRuntimeStatusSnapshot();
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
      if (!this.pageActive) {
        return;
      }
      this.runtimeInputLayoutButtons = profile.buttons;
      LogHelper.info('LibretroGame', 'Input', `已加载本地输入布局: ${profile.buttons.length} buttons`);
    } catch (err) {
      if (!this.pageActive) {
        return;
      }
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
    this.swapInterval = profile.swapInterval;
    this.softwareMaxPresetIndex = profile.softwareMaxPresetIndex;
    this.aiUpscaleEnabled = profile.aiUpscaleEnabled;
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
    runtimeAudioSettingsController.setVolumePercent(profile.volumePercent);
    // 若游戏已在运行(用户改设置后返回游戏页等场景),立即应用新延迟。
    if (this.gameRunning) {
      runtimeAudioSettingsController.setMinimumAudioLatency(profile.latencyMs);
    }
  }

  private async loadRuntimeInputPreferences(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.hideVirtualController = false;
      this.hideUndeclaredKeys = false;
      return;
    }
    try {
      const profile = await loadRuntimeInputPreferencesProfile(context);
      if (!this.pageActive) {
        return;
      }
      this.hideVirtualController = profile.hideVirtualController;
      this.hideUndeclaredKeys = profile.hideUndeclaredKeys;
    } catch (_err) {
      if (!this.pageActive) {
        return;
      }
      const fallback = createDefaultRuntimeInputPreferencesProfile();
      this.hideVirtualController = fallback.hideVirtualController;
      this.hideUndeclaredKeys = fallback.hideUndeclaredKeys;
    }
  }

  private async loadRuntimeVisualSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.visualSettingsProfile = createDefaultRuntimeVisualSettingsProfile();
      return;
    }
    try {
      const profile = await loadRuntimeVisualSettingsProfile(context);
      if (!this.pageActive) {
        return;
      }
      this.visualSettingsProfile = profile;
    } catch (_err) {
      if (!this.pageActive) {
        return;
      }
      this.visualSettingsProfile = createDefaultRuntimeVisualSettingsProfile();
    }
  }

  private getRuntimeScreenAspectRatio(): number {
    const nativeAspectRatio = this.gameAspectRatio > 0 ? this.gameAspectRatio : 4 / 3;
    return resolveRuntimeVisualAspectRatio(this.visualSettingsProfile.aspectMode, nativeAspectRatio);
  }

  private getRuntimeScreenCornerRadius(): number {
    return 4 + Math.round(this.visualSettingsProfile.curvature * 0.32);
  }

  private getRuntimeScreenSaturationFactor(): number {
    return Math.max(0, this.visualSettingsProfile.saturation / 100);
  }

  private getRuntimeScreenScanlineOpacity(): number {
    if (this.visualSettingsProfile.scanlineIntensity <= 0) {
      return 0;
    }
    return Math.min(0.42, 0.08 + this.visualSettingsProfile.scanlineIntensity * 0.0034);
  }

  private getRuntimeScreenScanlineSpacing(): number {
    if (this.visualSettingsProfile.scanlineIntensity >= 70) {
      return 1;
    }
    if (this.visualSettingsProfile.scanlineIntensity >= 35) {
      return 2;
    }
    return 3;
  }

  private getSoftwareResolutionForPreset(index: number): ResolutionPreset {
    if (index <= 0) {
      return { w: 640, h: 480 };
    }
    if (index >= 2) {
      return { w: 1920, h: 1080 };
    }
    return { w: 1280, h: 720 };
  }

  private applyRuntimeRenderSettingsToNative(phase: string): boolean {
    const okHw = runtimeRenderSettingsController.setHwRenderAllowed(this.renderSettingsProfile.hwRenderAllowed);
    const okMode = runtimeRenderSettingsController.setScalingMode(this.renderSettingsProfile.scalingMode);
    const okSwap = runtimeRenderSettingsController.setSwapInterval(this.renderSettingsProfile.swapInterval);
    let okResolution = true;
    if (this.renderSettingsProfile.scalingMode === 1) {
      const resolution = this.getSoftwareResolutionForPreset(this.renderSettingsProfile.softwareMaxPresetIndex);
      okResolution = runtimeRenderSettingsController.setSoftwareMaxResolution(resolution.w, resolution.h);
    }
    const okAi = runtimeRenderSettingsController.setAIUpscale(this.renderSettingsProfile.aiUpscaleEnabled);
    const ok = okHw && okMode && okSwap && okResolution && okAi;
    if (!ok) {
      LogHelper.warn(
        'LibretroGame',
        'Render',
        `运行时渲染配置注入失败(${phase}) mode=${this.renderSettingsProfile.scalingMode} hw=${this.renderSettingsProfile.hwRenderAllowed} swap=${this.renderSettingsProfile.swapInterval} ai=${this.renderSettingsProfile.aiUpscaleEnabled} preset=${this.renderSettingsProfile.softwareMaxPresetIndex}`
      );
    }
    return ok;
  }

  private async refreshRuntimeLaunchState(): Promise<void> {
    await Promise.all([
      this.loadRuntimeRenderSettings(),
      this.loadRuntimeAudioSettings(),
      this.loadRuntimeInputPreferences(),
      this.loadRuntimeVisualSettings(),
      this.loadRuntimeInputLayout()
    ]);
  }

  private async persistRuntimeRenderSettingsProfile(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    this.renderSettingsProfile = {
      version: this.renderSettingsProfile.version,
      scalingMode: this.scalingMode,
      swapInterval: this.swapInterval,
      softwareMaxPresetIndex: this.softwareMaxPresetIndex,
      aiUpscaleEnabled: this.aiUpscaleEnabled,
      hwRenderAllowed: this.hwRenderAllowed,
      updatedAt: this.renderSettingsProfile.updatedAt
    };
    const savedProfile = await saveRuntimeRenderSettingsProfile(context, this.renderSettingsProfile);
    if (!this.pageActive) {
      return;
    }
    this.renderSettingsProfile = savedProfile;
  }

  private getCurrentRuntimeRomFile(): string {
    if (this.librarySessionTracker.activeRomFile.length > 0) {
      return this.librarySessionTracker.activeRomFile;
    }
    const roms = this.getAvailableRoms();
    const rom = roms[this.selectedRomIndex];
    return rom ? rom.file : '';
  }

  private beginRuntimeSaveManagerTask(): number {
    this.runtimeSaveManagerTaskToken += 1;
    return this.runtimeSaveManagerTaskToken;
  }

  private isCurrentRuntimeSaveManagerTask(token: number): boolean {
    return this.pageActive && token === this.runtimeSaveManagerTaskToken;
  }

  private buildRuntimeSaveManagerSummaryText(count: number): string {
    const romFile = this.getCurrentRuntimeRomFile();
    if (count > 0) {
      return romFile.length > 0 ? `当前 ROM 共 ${count} 个即时存档` : `本地共 ${count} 个即时存档`;
    }
    return romFile.length > 0 ? '当前 ROM 暂无即时存档' : '暂无即时存档';
  }

  private closeRuntimeSaveManager(): void {
    this.runtimeSaveManagerTaskToken += 1;
    this.runtimeSaveManagerVisible = false;
    this.runtimeSaveManagerBusy = false;
    this.runtimeSaveManagerSummaryText = '';
    this.runtimeSaveManagerItems = [];
  }

  private toggleRuntimeSaveManager(): void {
    if (this.runtimeSaveManagerVisible) {
      this.closeRuntimeSaveManager();
      return;
    }
    this.closeRuntimePortControl();
    this.closeRuntimeCheatManager();
    this.closeRuntimeCoreOptions();
    this.closeRuntimeSramManager();
    this.runtimeSaveManagerVisible = true;
    void this.refreshRuntimeSaveManagerPanel();
  }

  private async refreshRuntimeSaveManagerPanel(): Promise<void> {
    const token = this.beginRuntimeSaveManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      if (!this.isCurrentRuntimeSaveManagerTask(token)) {
        return;
      }
      this.runtimeSaveManagerBusy = false;
      this.runtimeSaveManagerItems = [];
      this.runtimeSaveManagerSummaryText = '上下文缺失';
      return;
    }

    this.runtimeSaveManagerBusy = true;
    this.runtimeSaveManagerSummaryText = '正在读取当前游戏存档...';
    try {
      const items = await this.runtimeSaveStateController.listSaveItemsForRom(
        context,
        this.getCurrentRuntimeRomFile()
      );
      if (!this.isCurrentRuntimeSaveManagerTask(token)) {
        return;
      }
      this.runtimeSaveManagerItems = items;
      this.runtimeSaveManagerSummaryText = this.buildRuntimeSaveManagerSummaryText(items.length);
    } catch (err) {
      if (!this.isCurrentRuntimeSaveManagerTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Save', `读取运行态存档列表失败: ${message}`);
      this.runtimeSaveManagerItems = [];
      this.runtimeSaveManagerSummaryText = '读取存档列表失败';
      this.runtimeSaveStatusText = '读取存档列表失败';
    } finally {
      if (!this.isCurrentRuntimeSaveManagerTask(token)) {
        return;
      }
      this.runtimeSaveManagerBusy = false;
    }
  }

  private async loadRuntimeSaveStateByFileName(fileName: string): Promise<void> {
    const token = this.beginRuntimeSaveManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.runtimeSaveManagerBusy = true;
    const result = await this.runtimeSaveStateController.loadSaveByFileName(
      context,
      this.gameRunning,
      fileName
    );
    if (!this.isCurrentRuntimeSaveManagerTask(token)) {
      return;
    }
    this.runtimeSaveManagerBusy = false;
    this.runtimeSaveStatusText = result;
  }

  private async deleteRuntimeSaveStateByFileName(fileName: string): Promise<void> {
    const token = this.beginRuntimeSaveManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.runtimeSaveManagerBusy = true;
    const result = await this.runtimeSaveStateController.deleteSaveByFileName(context, fileName);
    if (!this.isCurrentRuntimeSaveManagerTask(token)) {
      return;
    }
    this.runtimeSaveManagerBusy = false;
    this.runtimeSaveStatusText = result;
    if (result === '存档已删除' && this.runtimeSaveManagerVisible) {
      await this.refreshRuntimeSaveManagerPanel();
    }
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
    if (this.runtimeSaveManagerVisible) {
      await this.refreshRuntimeSaveManagerPanel();
    }
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

  private beginRuntimeSramManagerTask(): number {
    this.runtimeSramManagerTaskToken += 1;
    return this.runtimeSramManagerTaskToken;
  }

  private isCurrentRuntimeSramManagerTask(token: number): boolean {
    return this.pageActive && token === this.runtimeSramManagerTaskToken;
  }

  private buildRuntimeSramManagerSummaryText(count: number): string {
    const romFile = this.getCurrentRuntimeRomFile();
    if (count > 0) {
      return romFile.length > 0 ? `当前 ROM 共 ${count} 个电池存档备份` : `本地共 ${count} 个电池存档备份`;
    }
    return romFile.length > 0 ? '当前 ROM 暂无电池存档备份' : '暂无电池存档备份';
  }

  private closeRuntimeSramManager(): void {
    this.runtimeSramManagerTaskToken += 1;
    this.runtimeSramManagerVisible = false;
    this.runtimeSramManagerBusy = false;
    this.runtimeSramManagerSummaryText = '';
    this.runtimeSramManagerItems = [];
  }

  private toggleRuntimeSramManager(): void {
    if (this.runtimeSramManagerVisible) {
      this.closeRuntimeSramManager();
      return;
    }
    this.closeRuntimePortControl();
    this.closeRuntimeSaveManager();
    this.closeRuntimeCheatManager();
    this.closeRuntimeCoreOptions();
    this.runtimeSramManagerVisible = true;
    void this.refreshRuntimeSramManagerPanel();
  }

  private async refreshRuntimeSramManagerPanel(): Promise<void> {
    const token = this.beginRuntimeSramManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const romFile = this.getCurrentRuntimeRomFile();
    if (!context) {
      if (!this.isCurrentRuntimeSramManagerTask(token)) {
        return;
      }
      this.runtimeSramManagerBusy = false;
      this.runtimeSramManagerItems = [];
      this.runtimeSramManagerSummaryText = '上下文缺失';
      return;
    }
    if (romFile.length === 0) {
      if (!this.isCurrentRuntimeSramManagerTask(token)) {
        return;
      }
      this.runtimeSramManagerBusy = false;
      this.runtimeSramManagerItems = [];
      this.runtimeSramManagerSummaryText = 'ROM 上下文缺失';
      return;
    }

    this.runtimeSramManagerBusy = true;
    this.runtimeSramManagerSummaryText = '正在读取当前游戏电池存档...';
    try {
      const items = await this.runtimeSramController.listBackupItemsForRom(context, romFile);
      if (!this.isCurrentRuntimeSramManagerTask(token)) {
        return;
      }
      this.runtimeSramManagerItems = items;
      this.runtimeSramManagerSummaryText = this.buildRuntimeSramManagerSummaryText(items.length);
    } catch (err) {
      if (!this.isCurrentRuntimeSramManagerTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'SRAM', `读取运行态 SRAM 列表失败: ${message}`);
      this.runtimeSramManagerItems = [];
      this.runtimeSramManagerSummaryText = '读取电池存档列表失败';
      this.runtimeSaveStatusText = '读取电池存档列表失败';
    } finally {
      if (!this.isCurrentRuntimeSramManagerTask(token)) {
        return;
      }
      this.runtimeSramManagerBusy = false;
    }
  }

  private async exportCurrentRuntimeSramBackup(): Promise<void> {
    const token = this.beginRuntimeSramManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.runtimeSramManagerBusy = true;
    const result = await this.runtimeSramController.exportCurrentSramBackup(
      context,
      this.gameRunning,
      this.getCurrentRuntimeRomFile()
    );
    if (!this.isCurrentRuntimeSramManagerTask(token)) {
      return;
    }
    this.runtimeSramManagerBusy = false;
    this.runtimeSaveStatusText = result;
    if (result === '电池存档已导出' && this.runtimeSramManagerVisible) {
      await this.refreshRuntimeSramManagerPanel();
    }
  }

  private async loadRuntimeSramBackupByFileName(fileName: string): Promise<void> {
    const token = this.beginRuntimeSramManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.runtimeSramManagerBusy = true;
    const result = await this.runtimeSramController.loadBackupByFileName(
      context,
      this.gameRunning,
      this.getCurrentRuntimeRomFile(),
      fileName
    );
    if (!this.isCurrentRuntimeSramManagerTask(token)) {
      return;
    }
    this.runtimeSramManagerBusy = false;
    this.runtimeSaveStatusText = result;
  }

  private async deleteRuntimeSramBackupByFileName(fileName: string): Promise<void> {
    const token = this.beginRuntimeSramManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.runtimeSramManagerBusy = true;
    const result = await this.runtimeSramController.deleteBackupByFileName(
      context,
      this.getCurrentRuntimeRomFile(),
      fileName
    );
    if (!this.isCurrentRuntimeSramManagerTask(token)) {
      return;
    }
    this.runtimeSramManagerBusy = false;
    this.runtimeSaveStatusText = result;
    if (result === '电池存档已删除' && this.runtimeSramManagerVisible) {
      await this.refreshRuntimeSramManagerPanel();
    }
  }

  private beginRuntimeCheatManagerTask(): number {
    this.runtimeCheatManagerTaskToken += 1;
    return this.runtimeCheatManagerTaskToken;
  }

  private isCurrentRuntimeCheatManagerTask(token: number): boolean {
    return this.pageActive && token === this.runtimeCheatManagerTaskToken;
  }

  private getRuntimeCheatCapabilityText(): string {
    if (this.coreSupportsCheatReset && this.coreSupportsCheatSet) {
      return '当前核心支持运行态金手指';
    }
    if (!this.coreSupportsCheatReset && !this.coreSupportsCheatSet) {
      return '当前核心未声明金手指接口';
    }
    if (!this.coreSupportsCheatReset) {
      return '当前核心缺少 cheat reset，无法安全重建列表';
    }
    return '当前核心缺少 cheat set，无法应用金手指';
  }

  private buildRuntimeCheatManagerSummaryText(count: number): string {
    if (!this.runtimeCheatManagerSupported) {
      return count > 0
        ? `${this.getRuntimeCheatCapabilityText()} | 已保存 ${count} 条`
        : this.getRuntimeCheatCapabilityText();
    }

    const romFile = this.getCurrentRuntimeRomFile();
    if (count > 0) {
      return romFile.length > 0 ? `当前 ROM 共 ${count} 条金手指` : `本地共 ${count} 条金手指`;
    }
    return romFile.length > 0 ? '当前 ROM 暂无金手指' : '暂无金手指';
  }

  private closeRuntimeCheatManager(): void {
    this.runtimeCheatManagerTaskToken += 1;
    this.runtimeCheatManagerVisible = false;
    this.runtimeCheatManagerBusy = false;
    this.runtimeCheatManagerSummaryText = '';
    this.runtimeCheatManagerItems = [];
    this.runtimeCheatDraftName = '';
    this.runtimeCheatDraftCode = '';
  }

  private toggleRuntimeCheatManager(): void {
    if (this.runtimeCheatManagerVisible) {
      this.closeRuntimeCheatManager();
      return;
    }
    this.closeRuntimePortControl();
    this.closeRuntimeSaveManager();
    this.closeRuntimeCoreOptions();
    this.closeRuntimeSramManager();
    this.runtimeCheatManagerVisible = true;
    void this.refreshRuntimeCheatManagerPanel();
  }

  private async refreshRuntimeCheatManagerPanel(): Promise<void> {
    const token = this.beginRuntimeCheatManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
      this.runtimeCheatManagerItems = [];
      this.runtimeCheatManagerSummaryText = '上下文缺失';
      return;
    }

    const romFile = this.getCurrentRuntimeRomFile();
    if (romFile.length === 0) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
      this.runtimeCheatManagerItems = [];
      this.runtimeCheatManagerSummaryText = 'ROM 上下文缺失';
      return;
    }

    this.runtimeCheatManagerBusy = true;
    this.runtimeCheatManagerSummaryText = '正在读取当前游戏金手指...';
    try {
      const items = await loadRuntimeCheatItemsForRom(context, romFile);
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerItems = items;
      this.runtimeCheatManagerSummaryText = this.buildRuntimeCheatManagerSummaryText(items.length);
    } catch (err) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Cheat', `读取运行态金手指失败: ${message}`);
      this.runtimeCheatManagerItems = [];
      this.runtimeCheatManagerSummaryText = '读取金手指列表失败';
      this.runtimeSaveStatusText = '读取金手指列表失败';
    } finally {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
    }
  }

  private updateRuntimeCheatDraftName(value: string): void {
    this.runtimeCheatDraftName = value;
  }

  private updateRuntimeCheatDraftCode(value: string): void {
    this.runtimeCheatDraftCode = value;
  }

  private countEnabledRuntimeCheats(items: RuntimeCheatItem[]): number {
    let count = 0;
    items.forEach((item: RuntimeCheatItem) => {
      if (item.enabled) {
        count += 1;
      }
    });
    return count;
  }

  private buildRuntimeCheatItemWithState(
    item: RuntimeCheatItem,
    enabled: boolean
  ): RuntimeCheatItem {
    return {
      id: item.id,
      label: item.label,
      code: item.code,
      enabled,
      updatedAt: Date.now()
    };
  }

  private async persistRuntimeCheatItems(
    nextItems: RuntimeCheatItem[],
    successText: string,
    clearDraft: boolean = false
  ): Promise<void> {
    const token = this.beginRuntimeCheatManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
      this.runtimeCheatManagerSummaryText = '上下文缺失';
      this.runtimeSaveStatusText = '上下文缺失';
      return;
    }

    const romFile = this.getCurrentRuntimeRomFile();
    if (romFile.length === 0) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
      this.runtimeCheatManagerSummaryText = 'ROM 上下文缺失';
      this.runtimeSaveStatusText = 'ROM 上下文缺失';
      return;
    }

    this.runtimeCheatManagerBusy = true;
    this.runtimeCheatManagerSummaryText = '正在写入当前游戏金手指...';
    try {
      const savedItems = await saveRuntimeCheatItemsForRom(context, romFile, nextItems);
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerItems = savedItems;
      this.runtimeCheatManagerSummaryText = this.buildRuntimeCheatManagerSummaryText(savedItems.length);
      if (clearDraft) {
        this.runtimeCheatDraftName = '';
        this.runtimeCheatDraftCode = '';
      }

      if (this.runtimeCheatManagerSupported && this.gameRunning) {
        const applied = runtimeCheatController.applyCheatEntries(savedItems);
        this.runtimeSaveStatusText = applied
          ? successText
          : `${successText}，但当前核心同步失败`;
      } else if (this.runtimeCheatManagerSupported) {
        this.runtimeSaveStatusText = `${successText}，将在下次运行时恢复`;
      } else {
        this.runtimeSaveStatusText = `${successText}，但当前核心未提供完整 cheat 接口`;
      }
    } catch (err) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Cheat', `写入运行态金手指失败: ${message}`);
      this.runtimeCheatManagerSummaryText = '写入金手指失败';
      this.runtimeSaveStatusText = '写入金手指失败';
    } finally {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
    }
  }

  private async addRuntimeCheat(): Promise<void> {
    const code = this.runtimeCheatDraftCode.trim();
    if (code.length === 0) {
      this.runtimeCheatManagerSummaryText = '请输入金手指代码';
      this.runtimeSaveStatusText = '请输入金手指代码';
      return;
    }

    const label = this.runtimeCheatDraftName.trim().length > 0
      ? this.runtimeCheatDraftName.trim()
      : `金手指 ${this.runtimeCheatManagerItems.length + 1}`;
    const nextItems = [
      ...this.runtimeCheatManagerItems,
      createRuntimeCheatItem(label, code, true)
    ];
    await this.persistRuntimeCheatItems(nextItems, '金手指已添加并启用', true);
  }

  private async toggleRuntimeCheatItem(id: string): Promise<void> {
    let nextEnabled = false;
    let matched = false;
    const nextItems = this.runtimeCheatManagerItems.map((item: RuntimeCheatItem) => {
      if (item.id !== id) {
        return item;
      }
      matched = true;
      nextEnabled = !item.enabled;
      return this.buildRuntimeCheatItemWithState(item, nextEnabled);
    });
    if (!matched) {
      return;
    }
    await this.persistRuntimeCheatItems(
      nextItems,
      nextEnabled ? '金手指已启用' : '金手指已关闭'
    );
  }

  private async deleteRuntimeCheatItem(id: string): Promise<void> {
    const nextItems = this.runtimeCheatManagerItems.filter((item: RuntimeCheatItem) => item.id !== id);
    if (nextItems.length === this.runtimeCheatManagerItems.length) {
      return;
    }
    await this.persistRuntimeCheatItems(nextItems, '金手指已删除');
  }

  private async disableAllRuntimeCheats(): Promise<void> {
    if (this.runtimeCheatManagerItems.length === 0) {
      this.runtimeSaveStatusText = '当前没有金手指';
      return;
    }
    const nextItems: RuntimeCheatItem[] = [];
    this.runtimeCheatManagerItems.forEach((item: RuntimeCheatItem) => {
      nextItems.push(this.buildRuntimeCheatItemWithState(item, false));
    });
    await this.persistRuntimeCheatItems(nextItems, '已关闭全部金手指');
  }

  private async restoreRuntimeCheatsForCurrentRom(notifyStatus: boolean = false): Promise<void> {
    if (!this.runtimeCheatManagerSupported || !this.gameRunning) {
      return;
    }

    const token = this.beginRuntimeCheatManagerTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const romFile = this.getCurrentRuntimeRomFile();
    if (!context || romFile.length === 0) {
      return;
    }

    try {
      const items = await loadRuntimeCheatItemsForRom(context, romFile);
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerItems = items;
      this.runtimeCheatManagerSummaryText = this.buildRuntimeCheatManagerSummaryText(items.length);
      if (items.length === 0) {
        return;
      }

      const applied = runtimeCheatController.applyCheatEntries(items);
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      const enabledCount = this.countEnabledRuntimeCheats(items);
      if (notifyStatus && enabledCount > 0) {
        this.runtimeSaveStatusText = applied
          ? `已恢复 ${enabledCount} 条金手指`
          : '已读取金手指配置，但恢复到当前核心失败';
      }
    } catch (err) {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Cheat', `恢复运行态金手指失败: ${message}`);
      if (notifyStatus) {
        this.runtimeSaveStatusText = '恢复运行态金手指失败';
      }
    } finally {
      if (!this.isCurrentRuntimeCheatManagerTask(token)) {
        return;
      }
      this.runtimeCheatManagerBusy = false;
    }
  }

  private buildRuntimeCoreOptionsSummaryText(count: number): string {
    if (count > 0) {
      return `当前核心共 ${count} 个运行时选项`;
    }
    return '当前核心未暴露运行时选项';
  }

  private closeRuntimeCoreOptions(): void {
    this.runtimeCoreOptionsVisible = false;
    this.runtimeCoreOptionsBusy = false;
    this.runtimeCoreOptionsSummaryText = '';
    this.runtimeCoreOptionsItems = [];
  }

  private toggleRuntimeCoreOptions(): void {
    if (this.runtimeCoreOptionsVisible) {
      this.closeRuntimeCoreOptions();
      return;
    }
    this.closeRuntimePortControl();
    this.closeRuntimeSaveManager();
    this.closeRuntimeCheatManager();
    this.closeRuntimeSramManager();
    this.runtimeCoreOptionsVisible = true;
    this.refreshRuntimeCoreOptionsPanel();
  }

  private refreshRuntimeCoreOptionsPanel(statusPrefix: string = ''): void {
    this.runtimeCoreOptionsBusy = true;
    try {
      const items = runtimeCoreOptionsController.getOptions();
      this.runtimeCoreOptionsItems = items;
      const summaryText = this.buildRuntimeCoreOptionsSummaryText(items.length);
      this.runtimeCoreOptionsSummaryText = statusPrefix.length > 0
        ? `${statusPrefix} · ${summaryText}`
        : summaryText;
    } catch (err) {
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'CoreOptions', `读取运行时核心选项失败: ${message}`);
      this.runtimeCoreOptionsItems = [];
      this.runtimeCoreOptionsSummaryText = '读取核心选项失败';
      this.runtimeSaveStatusText = '读取核心选项失败';
    } finally {
      this.runtimeCoreOptionsBusy = false;
    }
  }

  private advanceRuntimeCoreOption(key: string, value: string): void {
    if (this.runtimeCoreOptionsBusy) {
      return;
    }
    const safeKey = typeof key === 'string' ? key.trim() : '';
    const safeValue = typeof value === 'string' ? value.trim() : '';
    if (safeKey.length === 0 || safeValue.length === 0) {
      this.runtimeSaveStatusText = '核心选项写入失败：参数无效';
      return;
    }

    this.runtimeCoreOptionsBusy = true;
    try {
      const ok = runtimeCoreOptionsController.setOption(safeKey, safeValue);
      if (!ok) {
        this.runtimeCoreOptionsSummaryText = `写入核心选项失败 (${safeKey})`;
        this.runtimeSaveStatusText = `核心选项写入失败: ${safeKey}`;
        return;
      }
      this.runtimeSaveStatusText = `核心选项已更新: ${safeKey} -> ${safeValue}`;
      this.refreshRuntimeCoreOptionsPanel(`已更新 ${safeKey}`);
    } catch (err) {
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'CoreOptions', `写入运行时核心选项失败: ${message}`);
      this.runtimeCoreOptionsSummaryText = `写入核心选项失败 (${safeKey})`;
      this.runtimeSaveStatusText = `核心选项写入失败: ${safeKey}`;
    } finally {
      this.runtimeCoreOptionsBusy = false;
    }
  }

  private syncSelectedVirtualPortFromAssignments(): void {
    const virtualAssignment = this.portAssignments.find((item: PortAssignState) => {
      return item.sourceType === InputSourceType.Virtual;
    });
    if (virtualAssignment) {
      this.selectedPortIndex = virtualAssignment.portId;
    }
  }

  private getRuntimeControllerDeviceForPort(portId: number): number {
    const safePortId = portId >= 0 && portId < 4 ? portId : 0;
    return normalizeRuntimeControllerPortDevice(this.runtimeControllerPortDevices[safePortId]);
  }

  private setRuntimeControllerDeviceForPort(portId: number, device: number): void {
    const safePortId = portId >= 0 && portId < 4 ? portId : 0;
    const nextDevices = this.runtimeControllerPortDevices.slice();
    while (nextDevices.length < 4) {
      nextDevices.push(normalizeRuntimeControllerPortDevice(0));
    }
    nextDevices[safePortId] = normalizeRuntimeControllerPortDevice(device);
    this.runtimeControllerPortDevices = nextDevices;
  }

  private buildRuntimePortControlSummaryText(statusPrefix: string = ''): string {
    const portId = this.selectedPortIndex;
    const deviceLabel = describeRuntimeControllerPortDevice(this.getRuntimeControllerDeviceForPort(portId));
    if (statusPrefix.length > 0) {
      return `${statusPrefix} · 当前 P${portId + 1} / ${deviceLabel}`;
    }
    return `当前虚拟端口 P${portId + 1}，设备 ${deviceLabel}。部分核心可能忽略设备切换。`;
  }

  private refreshRuntimePortControlSummaryText(statusPrefix: string = ''): void {
    this.syncSelectedVirtualPortFromAssignments();
    this.runtimePortControlSummaryText = this.buildRuntimePortControlSummaryText(statusPrefix);
  }

  private closeRuntimePortControl(): void {
    this.runtimePortControlVisible = false;
  }

  private toggleRuntimePortControl(): void {
    if (this.runtimePortControlVisible) {
      this.closeRuntimePortControl();
      return;
    }
    this.closeRuntimeSaveManager();
    this.closeRuntimeSramManager();
    this.closeRuntimeCheatManager();
    this.closeRuntimeCoreOptions();
    this.runtimePortControlVisible = true;
    this.refreshRuntimePortControlSummaryText();
  }

  private requestRuntimeControllerPortDevice(
    portId: number,
    device: number,
    announce: boolean,
    statusPrefix: string = ''
  ): boolean {
    const safePortId = portId >= 0 && portId < 4 ? portId : 0;
    const normalizedDevice = normalizeRuntimeControllerPortDevice(device);
    const deviceLabel = describeRuntimeControllerPortDevice(normalizedDevice);
    const ok = runtimeInputPortController.setControllerPortDevice(safePortId, normalizedDevice);
    if (!ok) {
      const failureText = `请求 P${safePortId + 1} 使用 ${deviceLabel} 失败`;
      this.runtimePortControlSummaryText = failureText;
      if (announce) {
        this.runtimeSaveStatusText = failureText;
      }
      LogHelper.warn(
        'LibretroGame',
        'Input',
        `手柄类型切换失败: port=${safePortId} device=${normalizedDevice}`
      );
      return false;
    }
    this.setRuntimeControllerDeviceForPort(safePortId, normalizedDevice);
    this.refreshRuntimePortControlSummaryText(
      statusPrefix.length > 0 ? statusPrefix : `已请求 P${safePortId + 1} 使用 ${deviceLabel}`
    );
    if (announce) {
      this.runtimeSaveStatusText = `已请求核心将 P${safePortId + 1} 切换为 ${deviceLabel}`;
    }
    return true;
  }

  private selectRuntimeVirtualPort(portId: number): void {
    if (portId < 0 || portId >= this.portAssignments.length) {
      return;
    }
    const ok = this.applyPortAssignment(portId, InputSourceType.Virtual, true);
    if (!ok) {
      const failureText = `切换虚拟端口到 P${portId + 1} 失败`;
      this.runtimePortControlSummaryText = failureText;
      this.runtimeSaveStatusText = failureText;
      return;
    }
    this.selectedPortIndex = portId;
    this.requestRuntimeControllerPortDevice(
      portId,
      this.getRuntimeControllerDeviceForPort(portId),
      true,
      `已切换虚拟端口到 P${portId + 1}`
    );
  }

  private applyRuntimeControllerPortDevice(device: number): void {
    const portId = this.selectedPortIndex;
    const deviceLabel = describeRuntimeControllerPortDevice(device);
    this.requestRuntimeControllerPortDevice(
      portId,
      device,
      true,
      `已请求 P${portId + 1} 使用 ${deviceLabel}`
    );
  }

  private reapplyRuntimeControllerPortDevice(): void {
    const portId = this.selectedPortIndex;
    const device = this.getRuntimeControllerDeviceForPort(portId);
    this.requestRuntimeControllerPortDevice(
      portId,
      device,
      false,
      `启动后重放 P${portId + 1}`
    );
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
    if (actionCode === 'save_manager') {
      this.toggleRuntimeSaveManager();
      return;
    }
    if (actionCode === 'sram_manager') {
      this.toggleRuntimeSramManager();
      return;
    }
    if (actionCode === 'cheat_manager') {
      this.toggleRuntimeCheatManager();
      return;
    }
    if (actionCode === 'core_options') {
      this.toggleRuntimeCoreOptions();
      return;
    }
    if (actionCode === 'port_control') {
      this.toggleRuntimePortControl();
      return;
    }
    if (actionCode === 'restart_game') {
      if (this.coreSupportsReset) {
        const ok = runtimeCoreControlController.resetCore();
        this.runtimeSaveStatusText = ok
          ? '已发送核心软重置，恢复运行后将从头开始本局'
          : '核心软重置失败，改为重新载入当前游戏';
        this.resumeGame();
        if (!ok) {
          void this.startOrSwitchGame(true);
        }
        return;
      }
      this.runtimeSaveStatusText = '当前核心未声明软重置，改为重新载入当前游戏';
      this.resumeGame();
      void this.startOrSwitchGame(true);
      return;
    }
    if (actionCode === 'input_mapping') {
      this.openRuntimeToolPage('pages/InputLayoutPage', '按键映射');
      return;
    }
    if (actionCode === 'visual_filters') {
      this.openRuntimeToolPage('pages/ShaderPreviewPage', '画面风格');
      return;
    }
    this.runtimeSaveStatusText = `未知暂停菜单动作 (${actionCode})`;
  }

  private handleDiskControl(payload: DiskControlPayload): void {
    const type = typeof payload.type === 'string' ? payload.type : '';
    if (type.length === 0) {
      return;
    }
    this.diskControlSupported = true;
    this.diskControlType = type;
    this.diskControlStatusText = type === 'ext'
      ? '检测到扩展换盘接口，暂停后可切换磁盘。'
      : '检测到基础换盘接口，暂停后可切换磁盘。';
    if (this.gamePaused) {
      this.refreshRuntimeDiskControlSnapshot();
    }
    LogHelper.info('LibretroGame', 'Event', `disk_control: type=${type}`);
  }

  private beginRuntimeDiskControlTask(): number {
    this.runtimeDiskControlTaskToken += 1;
    return this.runtimeDiskControlTaskToken;
  }

  private isCurrentRuntimeDiskControlTask(token: number): boolean {
    return this.pageActive && token === this.runtimeDiskControlTaskToken;
  }

  private getRuntimeDiskControlModeText(): string {
    if (this.diskControlType === 'ext') {
      return 'EXT';
    }
    if (this.diskControlType === 'basic') {
      return 'BASIC';
    }
    return '';
  }

  private resetRuntimeCoreCapabilityState(): void {
    this.coreSupportsReset = false;
    this.coreSupportsRegionQuery = false;
    this.coreSupportsCheatReset = false;
    this.coreSupportsCheatSet = false;
    this.runtimeCheatManagerSupported = false;
    this.runtimeRegionText = '';
  }

  private inspectCurrentCoreCapabilities(corePath: string, token: number): void {
    void runtimeCoreDiagnosticController.inspectCoreCapabilities(corePath).then((capabilities) => {
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }

      this.coreSupportsReset = capabilities.supportsReset;
      this.coreSupportsRegionQuery = capabilities.supportsRegion;
      this.coreSupportsCheatReset = capabilities.supportsCheatReset;
      this.coreSupportsCheatSet = capabilities.supportsCheatSet;
      this.runtimeCheatManagerSupported =
        capabilities.supportsCheatReset && capabilities.supportsCheatSet;
      this.runtimeCheatManagerSummaryText = this.buildRuntimeCheatManagerSummaryText(
        this.runtimeCheatManagerItems.length
      );
      if (!capabilities.supportsRegion) {
        this.runtimeRegionText = '';
      }
      if (this.gamePaused) {
        this.refreshRuntimeRegionSnapshot();
      }
      if (this.runtimeCheatManagerSupported && this.gameRunning) {
        void this.restoreRuntimeCheatsForCurrentRom();
      }
    }).catch((err: Error) => {
      if (!this.isCurrentSwitchTask(token)) {
        return;
      }
      this.coreSupportsReset = false;
      this.coreSupportsRegionQuery = false;
      this.coreSupportsCheatReset = false;
      this.coreSupportsCheatSet = false;
      this.runtimeCheatManagerSupported = false;
      this.runtimeRegionText = '';
      this.runtimeCheatManagerSummaryText = this.buildRuntimeCheatManagerSummaryText(
        this.runtimeCheatManagerItems.length
      );
      LogHelper.warn(
        'LibretroGame',
        'Core',
        `核心能力探测失败: ${err.message || String(err)}`
      );
    });
  }

  private refreshRuntimeRegionSnapshot(): void {
    if (!this.coreSupportsRegionQuery || !this.gameRunning) {
      this.runtimeRegionText = '';
      return;
    }
    const regionCode = runtimeCoreControlController.getRegionCode();
    this.runtimeRegionText = this.formatRuntimeRegionText(regionCode);
  }

  private formatRuntimeRegionText(regionCode: number | undefined): string {
    if (regionCode === undefined) {
      return 'Region: AUTO / UNKNOWN';
    }
    if (regionCode === 1) {
      return 'Region: PAL';
    }
    if (regionCode === 0) {
      return 'Region: NTSC';
    }
    return `Region: AUTO / UNKNOWN (${regionCode})`;
  }

  private resetRuntimeStatusSnapshot(): void {
    this.runtimeStatusSnapshotTaskToken += 1;
    this.runtimeStateText = '';
    this.runtimeLoadStateText = '';
    this.runtimeSaveStateSizeText = '';
    this.runtimeInputDebugText = '';
  }

  private refreshRuntimeStatusSnapshot(): void {
    const token = this.runtimeStatusSnapshotTaskToken + 1;
    this.runtimeStatusSnapshotTaskToken = token;

    if (!this.pageActive || !this.gameRunning || !this.gamePaused) {
      this.runtimeStateText = '';
      this.runtimeLoadStateText = '';
      this.runtimeSaveStateSizeText = '';
      this.runtimeInputDebugText = '';
      return;
    }

    void runtimeCoreDiagnosticController.readRuntimeStatusSnapshot().then((snapshot: RuntimeStatusSnapshot) => {
      if (!this.pageActive || token !== this.runtimeStatusSnapshotTaskToken || !this.gamePaused) {
        return;
      }
      this.runtimeStateText = this.formatRuntimeStateText(snapshot.state);
      this.runtimeLoadStateText = this.formatRuntimeLoadStateText(
        snapshot.coreLoaded,
        snapshot.gameLoaded
      );
      this.runtimeSaveStateSizeText = this.formatRuntimeSaveStateSizeText(snapshot.saveStateSizeBytes);
      this.runtimeInputDebugText = this.formatRuntimeInputDebugText(snapshot.inputDebugStats);
    }).catch((err: Error) => {
      if (!this.pageActive || token !== this.runtimeStatusSnapshotTaskToken || !this.gamePaused) {
        return;
      }
      this.runtimeStateText = '运行态: 读取失败';
      this.runtimeLoadStateText = '';
      this.runtimeSaveStateSizeText = '';
      this.runtimeInputDebugText = '';
      LogHelper.warn('LibretroGame', 'Runtime', `读取运行态快照失败: ${err.message || String(err)}`);
    });
  }

  private formatRuntimeStateText(state: number): string {
    switch (state) {
      case EngineState.CORE_LOADED:
        return '运行态: 核心已加载';
      case EngineState.GAME_LOADED:
        return '运行态: 游戏已加载';
      case EngineState.RUNNING:
        return '运行态: 运行中';
      case EngineState.PAUSED:
        return '运行态: 已暂停';
      case EngineState.STOPPING:
        return '运行态: 停止中';
      case EngineState.STOPPED:
        return '运行态: 已停止';
      case EngineState.STARTING:
        return '运行态: 启动中';
      case EngineState.LOADING:
        return '运行态: 加载中';
      case EngineState.ERROR:
        return '运行态: 错误态';
      case EngineState.INIT:
        return '运行态: 初始化';
      default:
        return `运行态: 未知 (${state})`;
    }
  }

  private formatRuntimeLoadStateText(coreLoaded: boolean, gameLoaded: boolean): string {
    return `Core/Game: ${coreLoaded ? 'Y' : 'N'} / ${gameLoaded ? 'Y' : 'N'}`;
  }

  private formatRuntimeSaveStateSizeText(byteLength: number): string {
    return `即时存档大小: ${this.formatRuntimeByteSize(byteLength)}`;
  }

  private formatRuntimeInputDebugText(stats: RuntimeInputDebugStats): string {
    return `Input: ` +
      `T${stats.touchCount}(${stats.lastTouchType}) ` +
      `M${stats.mouseCount}(${stats.lastMouseAction}) ` +
      `K${stats.keyCount}(${stats.lastKeyAction}) ` +
      `F${stats.hasFocus ? 1 : 0} D${stats.mouseDown ? 1 : 0}`;
  }

  private formatRuntimeByteSize(byteLength: number): string {
    if (byteLength <= 0) {
      return '0 B';
    }
    if (byteLength < 1024) {
      return `${byteLength} B`;
    }
    if (byteLength < 1024 * 1024) {
      return `${Math.floor(byteLength / 1024)} KB`;
    }
    return `${(byteLength / (1024 * 1024)).toFixed(1)} MB`;
  }

  private resetRuntimeDiskControlState(): void {
    this.runtimeDiskControlTaskToken += 1;
    this.diskControlSupported = false;
    this.diskControlType = '';
    this.diskControlImageCount = 0;
    this.diskControlImageIndex = 0;
    this.diskControlEjected = false;
    this.diskControlStatusText = '';
    this.diskControlBusy = false;
  }

  private refreshRuntimeDiskControlSnapshot(statusPrefix: string = ''): void {
    if (!this.diskControlSupported) {
      return;
    }

    const snapshot = runtimeDiskControlController.getSnapshot();
    this.diskControlImageCount = snapshot.imageCount;
    this.diskControlImageIndex = snapshot.imageIndex;
    this.diskControlEjected = snapshot.ejected;

    const modeText = this.diskControlType === 'ext'
      ? '扩展接口'
      : (this.diskControlType === 'basic' ? '基础接口' : '已接入');
    const imageText = snapshot.imageCount > 0
      ? `当前 ${snapshot.imageIndex + 1}/${snapshot.imageCount} 张`
      : '当前未报告磁盘映像';
    const ejectText = snapshot.ejected ? '磁盘已弹出' : '磁盘已插入';
    const statusText = `换盘接口 ${modeText} | ${imageText} | ${ejectText}`;
    this.diskControlStatusText = statusPrefix.length > 0
      ? `${statusPrefix} · ${statusText}`
      : statusText;
  }

  private handleRuntimeDiskToggleEject(): void {
    if (!this.diskControlSupported || this.diskControlBusy) {
      return;
    }
    const nextEjected = !this.diskControlEjected;
    const ok = runtimeDiskControlController.setEjectState(nextEjected);
    if (!ok) {
      this.refreshRuntimeDiskControlSnapshot(
        nextEjected ? '弹出当前磁盘失败' : '插回当前磁盘失败'
      );
      return;
    }
    this.refreshRuntimeDiskControlSnapshot(
      nextEjected ? '当前磁盘已弹出' : '当前磁盘已插回'
    );
  }

  private switchRuntimeDisk(step: number): void {
    if (!this.diskControlSupported || this.diskControlBusy) {
      return;
    }
    if (this.diskControlImageCount <= 1) {
      this.refreshRuntimeDiskControlSnapshot('当前核心未报告可切换的多盘映像');
      return;
    }

    const maxIndex = this.diskControlImageCount - 1;
    const targetIndex = Math.max(0, Math.min(maxIndex, this.diskControlImageIndex + step));
    if (targetIndex === this.diskControlImageIndex) {
      this.refreshRuntimeDiskControlSnapshot(
        step < 0 ? '已经是第一张盘' : '已经是最后一张盘'
      );
      return;
    }

    const restoreInserted = !this.diskControlEjected;
    if (restoreInserted && !runtimeDiskControlController.setEjectState(true)) {
      this.refreshRuntimeDiskControlSnapshot('换盘失败：当前磁盘无法弹出');
      return;
    }

    if (!runtimeDiskControlController.setImageIndex(targetIndex)) {
      if (restoreInserted) {
        runtimeDiskControlController.setEjectState(false);
      }
      this.refreshRuntimeDiskControlSnapshot(`切换到第 ${targetIndex + 1} 张盘失败`);
      return;
    }

    if (restoreInserted && !runtimeDiskControlController.setEjectState(false)) {
      this.refreshRuntimeDiskControlSnapshot(
        `已切到第 ${targetIndex + 1} 张盘，但插回失败`
      );
      return;
    }

    this.refreshRuntimeDiskControlSnapshot(`已切换到第 ${targetIndex + 1} 张盘`);
  }

  private async handleRuntimeDiskReplaceCurrentImage(): Promise<void> {
    if (!this.diskControlSupported) {
      return;
    }
    if (this.diskControlImageCount <= 0) {
      this.refreshRuntimeDiskControlSnapshot('当前没有可替换的磁盘映像');
      return;
    }

    const token = this.beginRuntimeDiskControlTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      this.diskControlBusy = false;
      this.diskControlStatusText = '上下文缺失';
      return;
    }

    this.diskControlBusy = true;
    this.diskControlStatusText = '正在选择新的磁盘镜像...';
    try {
      const result = await importPickedRuntimeDiskImages(context);
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      if (result.canceled || result.importedEntryPath.length === 0) {
        this.refreshRuntimeDiskControlSnapshot(result.detail.length > 0 ? result.detail : '已取消选择磁盘镜像');
        return;
      }
      const statusText = this.replaceRuntimeDiskImageAtIndex(
        this.diskControlImageIndex,
        result.importedEntryPath,
        result.importedEntryName
      );
      this.refreshRuntimeDiskControlSnapshot(statusText);
    } catch (err) {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Disk', `替换运行时磁盘镜像失败: ${message}`);
      this.refreshRuntimeDiskControlSnapshot('替换磁盘镜像失败');
    } finally {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      this.diskControlBusy = false;
    }
  }

  private async handleRuntimeDiskAppendImage(): Promise<void> {
    if (!this.diskControlSupported) {
      return;
    }

    const token = this.beginRuntimeDiskControlTask();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      this.diskControlBusy = false;
      this.diskControlStatusText = '上下文缺失';
      return;
    }

    this.diskControlBusy = true;
    this.diskControlStatusText = '正在导入新的磁盘镜像...';
    try {
      const result = await importPickedRuntimeDiskImages(context);
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      if (result.canceled || result.importedEntryPath.length === 0) {
        this.refreshRuntimeDiskControlSnapshot(result.detail.length > 0 ? result.detail : '已取消选择磁盘镜像');
        return;
      }
      const statusText = this.appendRuntimeDiskImage(
        result.importedEntryPath,
        result.importedEntryName
      );
      this.refreshRuntimeDiskControlSnapshot(statusText);
    } catch (err) {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      const message = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'Disk', `新增运行时磁盘镜像失败: ${message}`);
      this.refreshRuntimeDiskControlSnapshot('新增磁盘镜像失败');
    } finally {
      if (!this.isCurrentRuntimeDiskControlTask(token)) {
        return;
      }
      this.diskControlBusy = false;
    }
  }

  private replaceRuntimeDiskImageAtIndex(
    index: number,
    imagePath: string,
    imageName: string
  ): string {
    const restoreInserted = !this.diskControlEjected;
    if (restoreInserted && !runtimeDiskControlController.setEjectState(true)) {
      return '替换磁盘失败：当前磁盘无法弹出';
    }
    if (!runtimeDiskControlController.replaceImageIndex(index, imagePath)) {
      if (restoreInserted) {
        runtimeDiskControlController.setEjectState(false);
      }
      return `替换第 ${index + 1} 张盘失败`;
    }
    if (restoreInserted && !runtimeDiskControlController.setEjectState(false)) {
      return `已替换第 ${index + 1} 张盘 (${imageName})，但插回失败`;
    }
    return `已替换第 ${index + 1} 张盘 (${imageName})`;
  }

  private appendRuntimeDiskImage(
    imagePath: string,
    imageName: string
  ): string {
    const restoreInserted = !this.diskControlEjected;
    if (restoreInserted && !runtimeDiskControlController.setEjectState(true)) {
      return '新增磁盘失败：当前磁盘无法弹出';
    }
    if (!runtimeDiskControlController.addImageIndex()) {
      if (restoreInserted) {
        runtimeDiskControlController.setEjectState(false);
      }
      return '新增磁盘槽位失败';
    }

    const snapshot = runtimeDiskControlController.getSnapshot();
    const targetIndex = snapshot.imageCount > 0 ? snapshot.imageCount - 1 : this.diskControlImageCount;
    if (!runtimeDiskControlController.replaceImageIndex(targetIndex, imagePath)) {
      if (restoreInserted) {
        runtimeDiskControlController.setEjectState(false);
      }
      return `已新增槽位，但写入第 ${targetIndex + 1} 张盘失败`;
    }
    if (restoreInserted && !runtimeDiskControlController.setEjectState(false)) {
      return `已新增第 ${targetIndex + 1} 张盘 (${imageName})，但插回失败`;
    }
    return `已新增第 ${targetIndex + 1} 张盘 (${imageName})`;
  }

  private openRuntimeToolPage(url: string, label: string): void {
    this.resumeAfterToolPage = this.gameRunning || this.gamePaused;
    if (this.resumeAfterToolPage) {
      this.runtimeSaveStatusText = `${label}页面已打开，返回后重新载入当前游戏`;
    }
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((err: Error) => {
      this.resumeAfterToolPage = false;
      LogHelper.error('LibretroGame', 'Route', `跳转${label}页失败: ${err.message}`);
      this.runtimeSaveStatusText = `${label}页面打开失败`;
    });
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
    if (paused) {
      this.refreshRuntimePortControlSummaryText();
      this.refreshRuntimeStatusSnapshot();
    } else {
      this.resetRuntimeStatusSnapshot();
    }
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
    this.syncSelectedVirtualPortFromAssignments();
  }

  private applyPortAssignment(
    portId: number,
    sourceType: InputSourceType,
    updateState: boolean,
    deviceId: string = ''
  ): boolean {
    const ok = runtimeInputPortController.applyPortAssignment(portId, sourceType, deviceId);
    if (ok && updateState) {
      this.updatePortAssignment(portId, sourceType, deviceId);
    }
    if (!ok) {
      LogHelper.warn('LibretroGame', 'Input', `端口映射失败: port=${portId} source=${sourceType}`);
    }
    return ok;
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
    this.closeRuntimeSaveManager();
    this.closeRuntimeSramManager();
    this.closeRuntimeCheatManager();
    this.closeRuntimeCoreOptions();
    this.closeRuntimePortControl();
    this.resetRuntimeCoreCapabilityState();
    this.resetRuntimeDiskControlState();
    this.resetRuntimeStatusSnapshot();
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

    // 仅更新被依赖的字段，避免整页 re-render 干扰输入触发路径。
    this.perfDisplay.coreFps = displayFps;
    this.perfDisplay.perfStatsText = `D:${drops} Du:${dupes} N:${nulls} U/O:${underruns}/${overruns} Buf:${buf.toFixed(0)}%`;
    this.syncRuntimePerformanceSnapshot();
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
    this.perfDisplay.audioStatusText =
      `Buf:${occupancy.toFixed(0)}% U/O:${underruns}/${Number(payload.overruns ?? 0)}`;
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
    this.maybeResumeAfterToolPage()
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
      LogHelper.warn(
        'LibretroGame',
        'Library',
        `未找到目标 ROM: ${LogHelper.describePathForLog(request.romFile)}`
      )
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

  private maybeResumeAfterToolPage(): void {
    if (!this.resumeAfterToolPage || this.gameRunning || this.switching) {
      return
    }
    const core = this.cores[this.selectedCoreIndex]
    const rom = this.getAvailableRoms()[this.selectedRomIndex]
    if (!core || !rom) {
      return
    }
    this.resumeAfterToolPage = false
    this.runtimeSaveStatusText = '已返回运行页，正在重新载入当前游戏'
    void this.startOrSwitchGame(true)
  }

  private getRuntimeFpsText(): string {
    const fps = this.perfDisplay.coreFps > 0 ? this.perfDisplay.coreFps : this.perfDisplay.realtimeFps;
    return fps > 0 ? fps.toFixed(1) : '--.-';
  }

  private getRuntimeCpuLoadPercent(): number {
    return this.perfDisplay.cpuLoadPercent > 0 ? this.perfDisplay.cpuLoadPercent : 0;
  }

  private getRuntimeCpuLoadText(): string {
    const load = this.getRuntimeCpuLoadPercent();
    return load > 0 ? `${load}%` : '--';
  }

  private getRuntimeProcessText(): string {
    if (this.currentRom.length > 0) {
      return getFileNameFromPath(this.currentRom).replace(/\.[^.]+$/, '').toUpperCase();
    }
    return 'IDLE';
  }

  private resetRuntimePerformanceDisplay(): void {
    this.perfDisplay.realtimeFps = 0;
    this.perfDisplay.coreFps = 0;
    this.perfDisplay.cpuLoadPercent = 0;
    this.perfDisplay.audioStatusText = '';
    this.perfDisplay.perfStatsText = '';
    this.perfDisplay.geometryText = '';
  }

  private syncRuntimePerformanceSnapshot(): void {
    try {
      const stats = runtimeSessionController.getStats();
      const avInfo = runtimeSessionController.getAVInfo();
      const loadPercent = this.estimateFrameLoadPercent(stats, avInfo);
      this.perfDisplay.cpuLoadPercent = loadPercent;

      const frameCount = Number(stats.frameCount);
      const avgFrameUs = frameCount > 0 ? Number(stats.frameTimeSum) / frameCount : 0;
      if (avgFrameUs > 0) {
        const measuredFps = 1000000 / avgFrameUs;
        if (Number.isFinite(measuredFps) && measuredFps > 0) {
          this.perfDisplay.realtimeFps = Math.min(240, measuredFps);
        } else {
          this.perfDisplay.realtimeFps = 0;
        }
      } else {
        this.perfDisplay.realtimeFps = 0;
      }
    } catch (_) {
    }
  }

  private estimateFrameLoadPercent(
    stats: RuntimePerformanceStats,
    avInfo: RuntimeAVInfo
  ): number {
    const frameCount = Number(stats.frameCount);
    const frameTimeSum = Number(stats.frameTimeSum);
    if (!Number.isFinite(frameCount) || frameCount <= 0 || !Number.isFinite(frameTimeSum) || frameTimeSum <= 0) {
      return 0;
    }

    const avgFrameUs = frameTimeSum / frameCount;
    const targetFps = Number(avInfo.fps) > 0
      ? Number(avInfo.fps)
      : (this.perfDisplay.coreFps > 0 ? this.perfDisplay.coreFps : 60);
    if (!Number.isFinite(targetFps) || targetFps <= 0) {
      return 0;
    }

    const frameBudgetUs = 1000000 / targetFps;
    if (!Number.isFinite(frameBudgetUs) || frameBudgetUs <= 0) {
      return 0;
    }

    const percent = Math.round((avgFrameUs / frameBudgetUs) * 100);
    return Math.max(0, Math.min(250, percent));
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
          screenAspectRatio: this.getRuntimeScreenAspectRatio(),
          scanlineIntensity: this.visualSettingsProfile.scanlineIntensity,
          screenCurvature: this.visualSettingsProfile.curvature,
          screenSaturation: this.visualSettingsProfile.saturation,
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
          screenAspectRatio: this.getRuntimeScreenAspectRatio(),
          scanlineIntensity: this.visualSettingsProfile.scanlineIntensity,
          screenCurvature: this.visualSettingsProfile.curvature,
          screenSaturation: this.visualSettingsProfile.saturation,
          fps: this.perfDisplay.coreFps,
          cpuUsage: this.getRuntimeCpuLoadPercent(),
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
          cpuLoadText: this.getRuntimeCpuLoadText(),
          perfStatsText: this.perfDisplay.perfStatsText,
          audioStatusText: this.perfDisplay.audioStatusText,
          geometryText: this.perfDisplay.geometryText,
          regionText: this.runtimeRegionText,
          runtimeStateText: this.runtimeStateText,
          runtimeLoadStateText: this.runtimeLoadStateText,
          runtimeSaveStateSizeText: this.runtimeSaveStateSizeText,
          runtimeInputDebugText: this.runtimeInputDebugText,
          diskControlVisible: this.diskControlSupported,
          diskControlModeText: this.getRuntimeDiskControlModeText(),
          diskControlStatusText: this.diskControlStatusText,
          diskImageIndex: this.diskControlImageIndex,
          diskImageCount: this.diskControlImageCount,
          diskEjected: this.diskControlEjected,
          diskControlBusy: this.diskControlBusy,
          saveManagerVisible: this.runtimeSaveManagerVisible,
          saveManagerBusy: this.runtimeSaveManagerBusy,
          saveManagerSummaryText: this.runtimeSaveManagerSummaryText,
          saveManagerItems: this.runtimeSaveManagerItems,
          sramManagerVisible: this.runtimeSramManagerVisible,
          sramManagerBusy: this.runtimeSramManagerBusy,
          sramManagerSummaryText: this.runtimeSramManagerSummaryText,
          sramManagerItems: this.runtimeSramManagerItems,
          cheatManagerVisible: this.runtimeCheatManagerVisible,
          cheatManagerBusy: this.runtimeCheatManagerBusy,
          cheatManagerSupported: this.runtimeCheatManagerSupported,
          cheatManagerSummaryText: this.runtimeCheatManagerSummaryText,
          cheatManagerItems: this.runtimeCheatManagerItems,
          cheatDraftName: this.runtimeCheatDraftName,
          cheatDraftCode: this.runtimeCheatDraftCode,
          coreOptionsVisible: this.runtimeCoreOptionsVisible,
          coreOptionsBusy: this.runtimeCoreOptionsBusy,
          coreOptionsSummaryText: this.runtimeCoreOptionsSummaryText,
          coreOptionsItems: this.runtimeCoreOptionsItems,
          portControlVisible: this.runtimePortControlVisible,
          portControlSummaryText: this.runtimePortControlSummaryText,
          portAssignments: this.portAssignments,
          selectedPortIndex: this.selectedPortIndex,
          selectedControllerDevice: this.getRuntimeControllerDeviceForPort(this.selectedPortIndex),
          onResume: () => {
            this.resumeGame();
          },
          onTerminate: () => {
            this.stopGame();
          },
          onAction: (actionCode: string) => {
            this.handlePauseTileAction(actionCode);
          },
          onDiskToggleEject: () => {
            this.handleRuntimeDiskToggleEject();
          },
          onDiskSelectPrevious: () => {
            this.switchRuntimeDisk(-1);
          },
          onDiskSelectNext: () => {
            this.switchRuntimeDisk(1);
          },
          onDiskRefresh: () => {
            this.refreshRuntimeDiskControlSnapshot();
          },
          onDiskReplaceCurrent: () => {
            void this.handleRuntimeDiskReplaceCurrentImage();
          },
          onDiskAppendImage: () => {
            void this.handleRuntimeDiskAppendImage();
          },
          onSaveManagerToggle: () => {
            this.toggleRuntimeSaveManager();
          },
          onSaveManagerCreate: () => {
            void this.quickSaveRuntimeState();
          },
          onSaveManagerRefresh: () => {
            void this.refreshRuntimeSaveManagerPanel();
          },
          onSaveManagerLoad: (fileName: string) => {
            void this.loadRuntimeSaveStateByFileName(fileName);
          },
          onSaveManagerDelete: (fileName: string) => {
            void this.deleteRuntimeSaveStateByFileName(fileName);
          },
          onSramManagerToggle: () => {
            this.toggleRuntimeSramManager();
          },
          onSramManagerCreate: () => {
            void this.exportCurrentRuntimeSramBackup();
          },
          onSramManagerRefresh: () => {
            void this.refreshRuntimeSramManagerPanel();
          },
          onSramManagerLoad: (fileName: string) => {
            void this.loadRuntimeSramBackupByFileName(fileName);
          },
          onSramManagerDelete: (fileName: string) => {
            void this.deleteRuntimeSramBackupByFileName(fileName);
          },
          onCheatManagerToggle: () => {
            this.toggleRuntimeCheatManager();
          },
          onCheatManagerRefresh: () => {
            void this.refreshRuntimeCheatManagerPanel();
          },
          onCheatManagerAdd: () => {
            void this.addRuntimeCheat();
          },
          onCheatManagerDisableAll: () => {
            void this.disableAllRuntimeCheats();
          },
          onCheatManagerDraftNameChange: (value: string) => {
            this.updateRuntimeCheatDraftName(value);
          },
          onCheatManagerDraftCodeChange: (value: string) => {
            this.updateRuntimeCheatDraftCode(value);
          },
          onCheatManagerToggleItem: (id: string) => {
            void this.toggleRuntimeCheatItem(id);
          },
          onCheatManagerDelete: (id: string) => {
            void this.deleteRuntimeCheatItem(id);
          },
          onCoreOptionsToggle: () => {
            this.toggleRuntimeCoreOptions();
          },
          onCoreOptionsRefresh: () => {
            this.refreshRuntimeCoreOptionsPanel();
          },
          onCoreOptionAdvance: (key: string, value: string) => {
            this.advanceRuntimeCoreOption(key, value);
          },
          onPortControlToggle: () => {
            this.toggleRuntimePortControl();
          },
          onVirtualPortSelect: (portId: number) => {
            this.selectRuntimeVirtualPort(portId);
          },
          onControllerDeviceSelect: (device: number) => {
            this.applyRuntimeControllerPortDevice(device);
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
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: this.xComponentId,
            type: XComponentType.SURFACE,
            libraryname: 'entry'
          })
            .aspectRatio(this.getRuntimeScreenAspectRatio())
            .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
            .focusable(true)
            .focusOnTouch(true)
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

          if (this.visualSettingsProfile.scanlineIntensity > 0) {
            ScanlineBackground({
              lineColor: '#2400FF41',
              lineSpacing: this.getRuntimeScreenScanlineSpacing(),
              alternateColor: '#0F000000'
            })
              .aspectRatio(this.getRuntimeScreenAspectRatio())
              .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
              .opacity(this.getRuntimeScreenScanlineOpacity())
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .saturate(this.getRuntimeScreenSaturationFactor())
        .borderRadius(this.getRuntimeScreenCornerRadius())
        .clip(true)
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
            inputDescriptorMask: this.hideUndeclaredKeys ? this.runtimeInputDescriptorMask : 0,
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
    this.resetRuntimePerformanceDisplay();
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
    this.resetRuntimeCoreCapabilityState();
    this.resetRuntimeDiskControlState();
    this.resetRuntimeStatusSnapshot();
    this.closeRuntimeSaveManager();
    this.closeRuntimeSramManager();
    this.closeRuntimeCheatManager();
    this.closeRuntimeCoreOptions();
    this.closeRuntimePortControl();
    const token = this.switchToken + 1;
    this.switchToken = token;
    await this.finalizeActiveLibrarySession();
    if (!this.isCurrentSwitchTask(token)) {
      return;
    }

    await this.refreshRuntimeLaunchState();
    if (!this.isCurrentSwitchTask(token)) {
      return;
    }
    const renderConfigApplied = this.applyRuntimeRenderSettingsToNative('prelaunch');
    if (!renderConfigApplied) {
      this.runtimeSaveStatusText = '运行时画面配置写入失败，已继续按当前引擎状态启动';
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
      this.inspectCurrentCoreCapabilities(corePath, token);
      LogHelper.info('LibretroGame', 'Engine', `加载 Core: ${LogHelper.describePathForLog(corePath)}`);
      LogHelper.info('LibretroGame', 'Engine', `加载 ROM: ${LogHelper.describePathForLog(rom.file)}`);
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
        `Resolved ROM path: ${LogHelper.describePathForLog(resolved.romPath)}, useResMgr=${resolved.useResMgr}`
      );
      const result = await runtimeSessionController.switchGame({
        corePath,
        romPath: resolved.romPath,
        filesDir,
        timeoutMs,
        token,
        resourceManager: resolved.useResMgr ? resMgr : undefined,
        progressCallback: (progress: number, message: string) => {
          if (!this.isCurrentSwitchTask(token)) {
            return;
          }
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
      this.applyRuntimeRenderSettingsToNative('postlaunch');
      // D019: 游戏启动成功(引擎 RUNNING、AudioBridge 已 Reset(sample_rate))后应用
      // 音频缓冲延迟,加深 RingBuffer 水位抗 callback 抖动(模拟器/低端机 underrun)。
      // 生产路径此前从不调用,沿用默认 latency=0(浅缓冲),故模拟器抖动即 underrun。
      runtimeAudioSettingsController.setMinimumAudioLatency(this.audioSettingsProfile.latencyMs);
      runtimeAudioSettingsController.setVolumePercent(this.audioSettingsProfile.volumePercent);
      this.reapplyRuntimeControllerPortDevice();
      // core 在 retro_load_game / retro_run 早期 frame 通过 SET_INPUT_DESCRIPTORS
      // 声明使用的按键,这里在 switchGame 成功后立刻拉一次。
      this.runtimeInputDescriptorMask = getRuntimeInputDescriptorMask();
      this.syncRuntimePerformanceSnapshot();
      if (this.runtimeCheatManagerSupported) {
        void this.restoreRuntimeCheatsForCurrentRom(true);
      }
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
      let nextSwitch: PendingSwitch | undefined = undefined;
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
          // 同一请求的失败重试直接作为下一次切换执行，避免把重试再次留在
          // pending 队列里并在成功后触发重复切换。
          nextSwitch = {
            coreIndex: pending.coreIndex,
            romIndex: pending.romIndex,
            retryCount: pending.retryCount + 1
          };
          LogHelper.warn(
            'LibretroGame',
            'Engine',
            `切换失败，准备重试 (${pending.retryCount + 1}/${this.maxSwitchRetries})`
          );
        } else {
          nextSwitch = pending;
        }
      }
      if (nextSwitch) {
        // 执行 pending 切换
        this.selectedCoreIndex = nextSwitch.coreIndex;
        this.updateRomOptions();
        const availableRoms = this.getAvailableRoms();
        this.selectedRomIndex =
          nextSwitch.romIndex < availableRoms.length ? nextSwitch.romIndex : 0;
        void this.startOrSwitchGame(true);
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
      this.syncRuntimePerformanceSnapshot();
      runtimeSessionController.pause();
      this.gamePaused = true;
      this.refreshRuntimeRegionSnapshot();
      this.refreshRuntimePortControlSummaryText();
      this.refreshRuntimeStatusSnapshot();
      if (this.diskControlSupported) {
        this.refreshRuntimeDiskControlSnapshot();
      }
      this.setKeepScreenOn(false);
      LogHelper.info('LibretroGame', 'Engine', '游戏已暂停');
    }
  }

  // 继续游戏
  resumeGame() {
    if (this.gameRunning && this.gamePaused) {
      runtimeSessionController.resume();
      this.gamePaused = false;
      this.resetRuntimeStatusSnapshot();
      this.closeRuntimeSaveManager();
      this.closeRuntimeSramManager();
      this.closeRuntimeCheatManager();
      this.closeRuntimeCoreOptions();
      this.closeRuntimePortControl();
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
      this.closeRuntimeSaveManager();
      this.closeRuntimeSramManager();
      this.closeRuntimeCheatManager();
      this.closeRuntimeCoreOptions();
      this.closeRuntimePortControl();
      this.runtimeInputDescriptorMask = 0;
      this.resetRuntimePerformanceDisplay();
      this.resetRuntimeCoreCapabilityState();
      this.resetRuntimeDiskControlState();
      this.resetRuntimeStatusSnapshot();
      LogHelper.info('LibretroGame', 'Engine', '游戏已停止');
    }
  }
}
