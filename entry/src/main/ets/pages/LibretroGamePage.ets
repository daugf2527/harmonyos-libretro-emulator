/*
 * 通用 Libretro 游戏页面 (New Architecture)
 * 基于 LibretroEngine 新架构重构
 */

import testNapi from 'libentry.so';
import LogHelper from '../common/LogHelper';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import fs from '@ohos.file.fs';
import { AnalogStickControl } from '../components/VirtualController';
import {
  createDefaultPortAssignments,
  InputDeviceInfo,
  InputSourceType,
  PortAssignState
} from '../common/InputPortRouting';
import {
  AudioStatusPayload,
  CoreCrashPayload,
  EngineErrorInfo,
  EngineState,
  EngineStatePayload,
  EventHubScope,
  FpsUpdatePayload,
  GeometryUpdatePayload,
  LibretroEventHub
} from '../common/LibretroEventHub';

// NAPI 接口定义 (遵循 AGENTS.md 规范)
interface LibretroNapi {
  refactoredStartEngine(): boolean;
  refactoredStopEngine(): boolean;
  refactoredStopEngineAsync(): boolean;
  refactoredLoadCore(path: string): boolean;
  refactoredLoadRom(
    path: string,
    resMgr?: object
  ): boolean;
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    resMgr?: object,
    timeoutMs?: number,
    token?: number
  ): Promise<boolean>;
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    timeoutMs?: number,
    token?: number
  ): Promise<boolean>;
  refactoredSetFilesDir(path: string): boolean;
  refactoredGetRawFileList(
    resMgr: object,
    dir: string
  ): string[];
  refactoredGetRawFileListAsync(
    resMgr: object,
    dir?: string
  ): Promise<string[]>;
  refactoredResetStats(): boolean;
  refactoredGetStats(): RawEngineStats;
  refactoredGetInputDebugStats(): InputDebugStats;
  refactoredPauseEngine(): boolean;
  refactoredResumeEngine(): boolean;
  refactoredSetScalingMode(mode: number): boolean;
  refactoredSetSoftwareMaxResolution(w: number, h: number): boolean;
  refactoredSetHwRenderAllowed(allowed: boolean): boolean;
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
  testCoreLoader(path: string): string;
  refactoredWaitForState(state: number, timeoutMs?: number): boolean;
  refactoredWaitForStateAsync(
    state: number,
    timeoutMs?: number
  ): Promise<boolean>;
  refactoredGetLastErrorInfo(): EngineErrorInfo;
  refactoredClearLastErrorInfo(): boolean;
}

const nativeApi = testNapi as LibretroNapi;

// 核心配置
interface CoreConfig {
  id: string;
  name: string;
  soFile: string;
  description: string;
}

// ROM 配置
interface RomConfig {
  id: string;
  name: string;
  file: string;
  coreId: string;
}

interface CoreExtensionRule {
  coreId: string;
  extensions: string[];
  requiresExactName?: string;
}

interface SoakStats {
  videoNullFrames: number;
  videoDupeFrames: number;
  audioUnderruns: number;
  audioOverruns: number;
}

interface RawEngineStats {
  videoNullFrames: number | string;
  videoDupeFrames: number | string;
  audioUnderruns: number | string;
  audioOverruns: number | string;
  audioBufferUsage: number | string;
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

interface PendingSwitch {
  coreIndex: number;
  romIndex: number;
}

interface RomPathResolution {
  romPath: string;
  useResMgr: boolean;
}

interface InputSourceItem {
  label: string;
  type: InputSourceType;
  deviceId: string;
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
  @State coreCheckRunning: boolean = false;
  @State coreCheckText: string = '';
  @State soakRunning: boolean = false;
  @State soakSecondsLeft: number = 0;
  @State soakSummaryText: string = '';
  @State selectedCoreIndex: number = 0;
  @State selectedRomIndex: number = 0;
  @State selectedPortIndex: number = 0;
  @State portAssignments: PortAssignState[] = createDefaultPortAssignments();
  @State inputDevices: InputDeviceInfo[] = [];
  @State coreOptions: SelectOption[] = [];
  @State romOptions: SelectOption[] = [];
  @State showControls: boolean = false;
  @State realtimeFps: number = 0;
  @State coreFps: number = 0;
  @State audioStatusText: string = '';
  @State perfStatsText: string = '';
  @State geometryText: string = '';
  @State inputDebugText: string = '';
  @State inputFocusText: string = '';
  @State uiInputDebugText: string = '';
  @State scalingMode: number = 2; // 默认 GLES (2)
  @State softwareMaxPresetIndex: number = 1;
  @State hwRenderAllowed: boolean = true;
  @State hideVirtualController: boolean = false;
  
  // 使用包含 "new_arch" 的 ID 以触发 C++ 侧的新引擎逻辑
  private xComponentId: string = 'new_arch_game_xcomponent';
  private soakTimer: number = -1;
  private inputDebugTimer: number = -1;
  private uiTouchCount: number = 0;
  private uiMouseCount: number = 0;
  private uiKeyCount: number = 0;
  private uiLastTouchType: number = -1;
  private uiLastMouseAction: number = -1;
  private uiLastKeyType: number = -1;
  private soakStartStats: SoakStats | undefined = undefined;
  private soakMinAudioUsage: number = 1.0;
  private soakMaxAudioUsage: number = 0.0;
  private eventScope: EventHubScope | undefined = undefined;
  private pendingStart: boolean = false;
  private switchToken: number = 0;
  private pendingSwitch: PendingSwitch | undefined = undefined;
  private romListRefreshToken: number = 0;
  private lastStartOrSwitchAtMs: number = 0;
  private readonly startOrSwitchDebounceMs: number = 600;
  // 动态输入源列表
  @State inputSourceItems: InputSourceItem[] = [];
  
  // 可用核心列表
  private cores: CoreConfig[] = [
    {
      id: '2048',
      name: '2048',
      soFile: 'lib2048_libretro.so',
      description: 'Libretro 2048'
    },
    {
      id: 'gambatte',
      name: 'Gambatte (GB/GBC)',
      soFile: 'gambatte_libretro.ohos-arm64.so',
      description: 'Game Boy / Game Boy Color'
    },
    {
      id: 'nestopia',
      name: 'Nestopia (NES)',
      soFile: 'nestopia_libretro.ohos-arm64.so',
      description: 'Nintendo Entertainment System'
    },
    {
      id: 'fceumm',
      name: 'FCEUmm (NES)',
      soFile: 'fceumm_libretro.ohos-arm64.so',
      description: 'Nintendo Entertainment System (FCEUmm)'
    },
    {
      id: 'quicknes',
      name: 'QuickNES (NES)',
      soFile: 'quicknes_libretro.ohos-arm64.so',
      description: 'Nintendo Entertainment System (QuickNES)'
    },
    {
      id: 'genesis_plus_gx',
      name: 'Genesis Plus GX (MD)',
      soFile: 'genesis_plus_gx_libretro.ohos-arm64.so',
      description: 'Mega Drive / Genesis'
    },
    {
      id: 'snes9x',
      name: 'Snes9x (SNES)',
      soFile: 'snes9x_libretro.ohos-arm64.so',
      description: 'Super Nintendo'
    },
    {
      id: 'mgba',
      name: 'mGBA (GBA)',
      soFile: 'mgba_libretro.ohos-arm64.so',
      description: 'Game Boy Advance'
    },
    {
      id: 'mednafen_gba',
      name: 'Beetle GBA (Mednafen)',
      soFile: 'mednafen_gba_libretro.ohos-arm64.so',
      description: 'Game Boy Advance (Mednafen)'
    },
    {
      id: 'mednafen_psx_hw',
      name: 'Beetle PSX HW',
      soFile: 'mednafen_psx_hw_libretro.ohos-arm64.so',
      description: 'PlayStation (HW render)'
    },
    {
      id: 'mednafen_ngp',
      name: 'Beetle NGP (Mednafen)',
      soFile: 'mednafen_ngp_libretro.ohos-arm64.so',
      description: 'Neo Geo Pocket'
    },
    {
      id: 'melonds',
      name: 'melonDS (NDS)',
      soFile: 'melonds_libretro.ohos-arm64.so',
      description: 'Nintendo DS'
    },
    {
      id: 'fbneo',
      name: 'FBNeo (Arcade)',
      soFile: 'fbneo_libretro.ohos-arm64.so',
      description: 'FinalBurn Neo'
    },
    {
      id: 'mame2010',
      name: 'MAME 2010',
      soFile: 'mame2010_libretro.ohos-arm64.so',
      description: 'Arcade (MAME 2010)'
    },
    {
      id: 'race',
      name: 'RACE (NGP)',
      soFile: 'race_libretro.ohos-arm64.so',
      description: 'Neo Geo Pocket (RACE)'
    },
    {
      id: 'bsnes_hd_beta',
      name: 'bsnes-hd beta',
      soFile: 'bsnes_hd_beta_libretro.ohos-arm64.so',
      description: 'bsnes-hd beta'
    },
    {
      id: 'crocods',
      name: 'Crocods',
      soFile: 'crocods_libretro.ohos-arm64.so',
      description: 'Crocods'
    },
    {
      id: 'freeintv',
      name: 'FreeIntv',
      soFile: 'freeintv_libretro.ohos-arm64.so',
      description: 'FreeIntv'
    },
    {
      id: 'mesen',
      name: 'Mesen',
      soFile: 'mesen_libretro.ohos-arm64.so',
      description: 'Mesen'
    },
    {
      id: 'minivmac',
      name: 'Mini vMac',
      soFile: 'minivmac_libretro.ohos-arm64.so',
      description: 'Mini vMac'
    },
    {
      id: 'mrboom',
      name: 'Mr.Boom',
      soFile: 'mrboom_libretro.ohos-arm64.so',
      description: 'Mr.Boom'
    },
    {
      id: 'pcsx_rearmed',
      name: 'PCSX-ReARMed',
      soFile: 'pcsx_rearmed_libretro.ohos-arm64.so',
      description: 'PCSX-ReARMed'
    },
    {
      id: 'potator',
      name: 'Potator',
      soFile: 'potator_libretro.ohos-arm64.so',
      description: 'Potator'
    },
    {
      id: 'retro8',
      name: 'Retro8',
      soFile: 'retro8_libretro.ohos-arm64.so',
      description: 'Retro8'
    },
    {
      id: 'sameboy',
      name: 'SameBoy',
      soFile: 'sameboy_libretro.ohos-arm64.so',
      description: 'SameBoy'
    },
    {
      id: 'snes9x2010',
      name: 'Snes9x 2010',
      soFile: 'snes9x2010_libretro.ohos-arm64.so',
      description: 'Snes9x 2010'
    },
    {
      id: 'vice_x128',
      name: 'VICE x128',
      soFile: 'vice_x128_libretro.ohos-arm64.so',
      description: 'VICE x128'
    },
    {
      id: 'vice_x64',
      name: 'VICE x64',
      soFile: 'vice_x64_libretro.ohos-arm64.so',
      description: 'VICE x64'
    },
    {
      id: 'vice_xcbm2',
      name: 'VICE xcbm2',
      soFile: 'vice_xcbm2_libretro.ohos-arm64.so',
      description: 'VICE xcbm2'
    },
    {
      id: 'vice_xpet',
      name: 'VICE xpet',
      soFile: 'vice_xpet_libretro.ohos-arm64.so',
      description: 'VICE xpet'
    },
    {
      id: 'xrick',
      name: 'XRick',
      soFile: 'xrick_libretro.ohos-arm64.so',
      description: 'XRick'
    }
  ];
  
  private roms: RomConfig[] = [];
  private readonly noGameCores: string[] = ['mrboom', '2048'];
  private readonly coreExtensionRules: CoreExtensionRule[] = [
    { coreId: 'gambatte', extensions: ['gb', 'gbc', 'dmg'] },
    { coreId: 'sameboy', extensions: ['gb', 'gbc'] },
    { coreId: 'nestopia', extensions: ['nes', 'fds', 'unf', 'unif'] },
    { coreId: 'fceumm', extensions: ['fds', 'nes', 'unif', 'unf'] },
    { coreId: 'quicknes', extensions: ['nes'] },
    { coreId: 'genesis_plus_gx', extensions: ['mdx', 'md', 'smd', 'gen', 'cue', 'iso', 'sms', 'bms', 'gg', 'sg', '68k', 'sgd', 'chd', 'm3u'] },
    { coreId: 'snes9x', extensions: ['smc', 'sfc', 'swc', 'fig', 'bs', 'st'] },
    { coreId: 'snes9x2010', extensions: ['smc', 'fig', 'sfc', 'gd3', 'gd7', 'dx2', 'bsx', 'swc'] },
    { coreId: 'bsnes_hd_beta', extensions: ['smc', 'sfc', 'swc', 'fig', 'bs'] },
    { coreId: 'mgba', extensions: ['gb', 'gbc', 'gba'] },
    { coreId: 'mednafen_gba', extensions: ['gba', 'agb'] },
    { coreId: 'mednafen_psx_hw', extensions: ['cue', 'toc', 'm3u', 'ccd', 'pbp', 'chd'] },
    { coreId: 'mednafen_ngp', extensions: ['ngp', 'ngc', 'ngpc', 'npc'] },
    { coreId: 'melonds', extensions: ['nds', 'ids', 'dsi'] },
    { coreId: 'fbneo', extensions: ['zip', '7z', 'cue', 'ccd'] },
    { coreId: 'mame2010', extensions: ['zip', '7z'] },
    { coreId: 'race', extensions: ['ngp', 'ngc', 'ngpc', 'npc'] },
    { coreId: 'crocods', extensions: ['dsk', 'sna', 'kcr'] },
    { coreId: 'freeintv', extensions: ['int'] },
    // { coreId: 'mesen', extensions: ['nes', 'fds', 'unf', 'unif'] },
    { coreId: 'minivmac', extensions: ['dsk', 'hvf', 'cmd'] },
    { coreId: 'mrboom', extensions: ['desktop'] },
    { coreId: 'pcsx_rearmed', extensions: ['cue', 'iso', 'pbp', 'chd', 'toc', 'm3u', 'cbn'] },
    { coreId: 'potator', extensions: ['sv'] },
    { coreId: 'retro8', extensions: ['p8', 'png'] },
    { coreId: 'vice_x128', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
    { coreId: 'vice_x64', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
    { coreId: 'vice_xcbm2', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
    { coreId: 'vice_xpet', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
    { coreId: 'xrick', extensions: ['zip'], requiresExactName: 'data.zip' }
  ];
  
  aboutToAppear() {
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
    
    this.refreshRomList();
    this.startInputDebug();
    this.refreshInputDevices();
    this.syncPortAssignments();
  }
  
  aboutToDisappear() {
    this.romListRefreshToken += 1;
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
    this.stopGame(true);
    this.stopSoak();
    this.stopInputDebug();
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
    if (stateValue === EngineState.RUNNING && this.pendingStart) {
      this.pendingStart = false;
      LogHelper.info('LibretroGame', 'Engine', '游戏启动成功');
    }
    if (!running) {
      this.stopSoak();
    }
  }

  @State inputSourceOptions: SelectOption[] = [];

  private refreshInputDevices() {
    let devices: InputDeviceInfo[] = [];
    try {
      devices = nativeApi.refactoredListInputDevices() || [];
    } catch (e) {
      LogHelper.warn('LibretroGame', 'Input', `获取设备列表失败: ${(e as Error).message}`);
    }
    this.inputDevices = devices;

    const items: InputSourceItem[] = [];
    items.push({ label: '未分配', type: InputSourceType.None, deviceId: '' });
    items.push({ label: '虚拟手柄', type: InputSourceType.Virtual, deviceId: '' });

    devices.forEach((d) => {
      let label = d.name;
      switch (d.sourceType) {
        case InputSourceType.Keyboard: label = `键盘 ${d.name}`; break;
        case InputSourceType.Mouse: label = `鼠标 ${d.name}`; break;
        case InputSourceType.Gamepad: label = `手柄 ${d.name}`; break;
        case InputSourceType.BluetoothGamepad: label = `蓝牙手柄 ${d.name}`; break;
      }
      items.push({ label: label, type: d.sourceType, deviceId: d.deviceId });
    });
    this.inputSourceItems = items;
    
    // 更新下拉框选项
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

  private getInputSourceIndex(sourceType: InputSourceType, deviceId: string): number {
    const index = this.inputSourceItems.findIndex(item => {
      if (item.type !== sourceType) return false;
      if (sourceType === InputSourceType.None || sourceType === InputSourceType.Virtual) {
        return true;
      }
      return item.deviceId === deviceId;
    });
    return index >= 0 ? index : 0;
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
      // 必须确保传递字符串，避免 NAPI 因 undefined 参数崩溃
      ok = nativeApi.refactoredAssignPortSource(portId, sourceType, deviceId ?? '');
    }
    if (updateState) {
      this.updatePortAssignment(portId, sourceType, deviceId);
    }
    if (!ok) {
      LogHelper.warn('LibretroGame', 'Input', `端口映射失败: port=${portId} source=${sourceType}`);
    }
  }

  private isVirtualPortActive(portId: number): boolean {
    const assignment = this.getPortAssignment(portId);
    return assignment.sourceType === InputSourceType.Virtual;
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
    this.stopSoak();
    LogHelper.error('LibretroGame', 'Event', `core_crash: ${message}`);
  }

  handleFpsUpdate(payload: FpsUpdatePayload) {
    const fps = Number(payload.fps);
    if (!Number.isNaN(fps)) {
      this.coreFps = Math.round(fps);
    }

    const drops = Number(payload.drops ?? 0);
    const dupes = Number(payload.dupes ?? 0);
    const nulls = Number(payload.nulls ?? 0);
    const underruns = Number(payload.underruns ?? 0);
    const overruns = Number(payload.overruns ?? 0);
    const buf = Number(payload.audioBufferUsage ?? 0);

    this.perfStatsText = `D:${drops} Du:${dupes} N:${nulls} U/O:${underruns}/${overruns} Buf:${buf.toFixed(0)}%`;
  }

  handleAudioStatus(payload: AudioStatusPayload) {
    const occupancy = Number(payload.occupancy);
    const underruns = Number(payload.underruns);
    if (Number.isNaN(occupancy) || Number.isNaN(underruns)) {
      return;
    }
    this.audioStatusText = `Buf:${occupancy.toFixed(0)}% U:${underruns}`;
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
  
  // 获取当前核心可用的 ROM
  getAvailableRoms(): RomConfig[] {
    const currentCore = this.cores[this.selectedCoreIndex];
    return this.roms.filter(rom => rom.coreId === currentCore.id);
  }

  private async refreshRomList() {
    const refreshToken = this.romListRefreshToken + 1;
    this.romListRefreshToken = refreshToken;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.roms = this.buildRomConfigs([]);
      this.updateRomOptions();
      return;
    }

    let files: string[] = [];
    try {
      const rawList: string[] = await nativeApi.refactoredGetRawFileListAsync(
        context.resourceManager,
        'roms'
      );
      if (refreshToken !== this.romListRefreshToken) {
        return;
      }
      files = rawList.filter(item => typeof item === 'string') as string[];
    } catch (err) {
      const msg = (err as Error).message || String(err);
      LogHelper.error('LibretroGame', 'ROM', `扫描 ROM 列表失败: ${msg}`);
    }

    if (refreshToken !== this.romListRefreshToken) {
      return;
    }

    this.roms = this.buildRomConfigs(files);
    this.updateRomOptions();
  }

  private buildRomConfigs(files: string[]): RomConfig[] {
    const uniqueFiles = Array.from(new Set(files.filter(fileName => fileName)));

    uniqueFiles.sort((a, b) => a.localeCompare(b));

    const roms: RomConfig[] = [];
    uniqueFiles.forEach((fileName) => {
      const lowerName = fileName.toLowerCase();
      const ext = this.getFileExtension(lowerName);
      if (!ext) {
        return;
      }
      const coreIds = this.matchCoreIds(ext, lowerName);
      if (coreIds.length === 0) {
        return;
      }
      coreIds.forEach((coreId) => {
        roms.push({
          id: `${coreId}:${fileName}`,
          name: fileName,
          file: `roms/${fileName}`,
          coreId: coreId
        });
      });
    });

    this.noGameCores.forEach((coreId) => {
      roms.push({
        id: `nogame:${coreId}`,
        name: '无需 ROM',
        file: '',
        coreId: coreId
      });
    });

    return roms;
  }

  private matchCoreIds(ext: string, fileName: string): string[] {
    const matched: string[] = [];
    this.coreExtensionRules.forEach((rule) => {
      if (rule.coreId === 'mrboom') {
        return;
      }
      if (rule.requiresExactName) {
        let nameOnly = fileName;
        const lastSlash = fileName.lastIndexOf('/');
        if (lastSlash >= 0) {
          nameOnly = fileName.substring(lastSlash + 1);
        }
        if (rule.requiresExactName !== nameOnly) {
          return;
        }
      }
      if (this.hasExtension(rule.extensions, ext)) {
        matched.push(rule.coreId);
      }
    });
    return matched;
  }

  private hasExtension(extensions: string[], ext: string): boolean {
    return extensions.includes(ext);
  }

  private getFileExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex === fileName.length - 1) {
      return '';
    }
    return fileName.slice(dotIndex + 1);
  }

  runCoreCheck() {
    if (this.coreCheckRunning) {
      return;
    }
    const core = this.cores[this.selectedCoreIndex];
    if (!core) {
      this.coreCheckText = '核心无效';
      return;
    }
    this.coreCheckRunning = true;
    this.coreCheckText = '正在验证核心符号...';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        this.coreCheckText = '获取 Context 失败';
        this.coreCheckRunning = false;
        return;
      }
      const bundleCodeDir = context.bundleCodeDir;
      let abiPath = deviceInfo.abiList === 'x86_64' ? 'x86_64' : 'arm64';
      const corePath = `${bundleCodeDir}/libs/${abiPath}/${core.soFile}`;
      const result = nativeApi.testCoreLoader(corePath);
      this.coreCheckText = result;
    } catch (e) {
      const msg = (e as Error)?.message || String(e);
      this.coreCheckText = `Failed: ${msg}`;
      LogHelper.error('LibretroGame', 'Core', `符号验证异常: ${msg}`);
    } finally {
      this.coreCheckRunning = false;
    }
  }

  private resetCoreCheckState() {
    this.coreCheckRunning = false;
    this.coreCheckText = '';
  }
  
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // XComponent 游戏画面
      XComponent({
        id: this.xComponentId,
        type: XComponentType.SURFACE,
        libraryname: 'entry'
      })
        .width('100%')
        .height('100%')
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
          LogHelper.info(
            'LibretroGame',
            'UI',
            `XComponent 加载完成 (New Arch) id=${this.xComponentId}`
          );
          // 新架构：XComponent 会自动触发 OnSurfaceCreated，C++ 侧 LibretroEngine 会捕获 Window
        })
        .onDestroy(() => {
          LogHelper.info(
            'LibretroGame',
            'UI',
            `XComponent 销毁 (New Arch) id=${this.xComponentId}`
          );
        })

      // FPS 监控面板 (仅在游戏运行时显示)
      if (this.gameRunning) {
        Column() {
          Text(`XComponentId: ${this.xComponentId}`)
            .fontSize(10)
            .fontColor(Color.White)
            .margin({ bottom: 2 })
            .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          // Realtime FPS 暂时用 Core FPS 代替，或者后续通过 JS 定时器计算
          Text(`FPS: ${this.coreFps}`)
            .fontSize(14)
            .fontColor(this.coreFps < 55 ? Color.Red : Color.Green)
            .fontWeight(FontWeight.Bold)
            .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          
          Text(this.audioStatusText)
            .fontSize(10)
            .fontColor(Color.White)
            .margin({ top: 2 })
            .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })

          Text(this.perfStatsText)
            .fontSize(10)
            .fontColor(Color.White)
            .margin({ top: 2 })
            .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })

          if (this.geometryText.length > 0) {
            Text(this.geometryText)
              .fontSize(10)
              .fontColor(Color.White)
              .margin({ top: 2 })
              .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          }
          if (this.inputDebugText.length > 0) {
            Text(this.inputDebugText)
              .fontSize(10)
              .fontColor(Color.White)
              .margin({ top: 2 })
              .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          }
          if (this.inputFocusText.length > 0) {
            Text(this.inputFocusText)
              .fontSize(10)
              .fontColor(Color.White)
              .margin({ top: 2 })
              .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          }
          if (this.uiInputDebugText.length > 0) {
            Text(this.uiInputDebugText)
              .fontSize(10)
              .fontColor(Color.White)
              .margin({ top: 2 })
              .shadow({ radius: 1, color: Color.Black, offsetX: 1, offsetY: 1 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10, top: 60 }) // 避开菜单按钮
        .padding(4)
        .backgroundColor('#44000000')
        .borderRadius(4)
        .hitTestBehavior(HitTestMode.None) // 不拦截点击
      }

      // 虚拟按键 (如果游戏运行中)
      if (this.gameRunning && !this.gamePaused && !this.hideVirtualController) {
        this.buildVirtualController();
      }

      // 左上角菜单按钮（默认常驻）
      Button('≡')
        .width(44)
        .height(44)
        .fontSize(20)
        .fontColor(Color.White)
        .backgroundColor('#66000000')
        .borderRadius(22)
        .margin({ left: 10, top: 10 })
        .enabled(!this.switching)
        .onClick(() => {
          this.refreshInputDevices();
          this.selectedPortIndex = 0; // 默认选中 P1
          this.showControls = true;
        })

      if (this.showControls) {
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

          this.buildControlPanel();
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
  
  // 构建控制面板
  @Builder
  buildControlPanel() {
    Column() {
      // 标题栏
      Row() {
        Text('菜单 (New Arch)')
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)

        Blank()

        Button('关闭')
          .fontSize(14)
          .height(32)
          .onClick(() => {
            this.showControls = false;
          })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#E6000000') // 加深背景不透明度
      .alignItems(VerticalAlign.Center)

      // 列表内容区
      List({ space: 16 }) {
        // 1. 端口选择
        ListItem() {
          Column({ space: 8 }) {
            Text('选择端口')
              .fontSize(14)
              .fontColor('#AAAAAA')
            
            Select(this.portOptions)
              .selected(this.safePortIndex)
              .value(this.currentPortLabel)
              .font({ size: 16 })
              .fontColor(Color.White)
              .selectedOptionFont({ size: 16 })
              .optionFont({ size: 16 })
              .width('100%')
              .height(44)
              .backgroundColor('#333333')
              .borderRadius(8)
              .enabled(!this.switching)
              .onSelect((index: number) => {
                this.selectedPortIndex = this.clampIndex(index, this.portOptions.length);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 2. 输入来源
        ListItem() {
          Column({ space: 8 }) {
            Text('输入来源')
              .fontSize(14)
              .fontColor('#AAAAAA')

            Select(this.inputSourceOptions)
              .selected(this.safeInputSourceIndex)
              .value(this.currentInputSourceLabel)
              .font({ size: 16 })
              .fontColor(Color.White)
              .selectedOptionFont({ size: 16 })
              .optionFont({ size: 16 })
              .width('100%')
              .height(44)
              .backgroundColor('#333333')
              .borderRadius(8)
              .enabled(!this.switching)
              .onSelect((index: number) => {
                const item = this.inputSourceItems[index];
                if (!item) {
                   return;
                }
                
                LogHelper.info('LibretroGame', 'Input', `选择输入源: ${item.label} (type=${item.type}, id=${item.deviceId})`);
                this.applyPortAssignment(this.selectedPortIndex, item.type, true, item.deviceId);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        
        // 3. 核心选择
        ListItem() {
          Column({ space: 8 }) {
            Text('选择核心')
              .fontSize(14)
              .fontColor('#AAAAAA')
            
            Select(this.coreOptions)
              .selected(this.safeCoreIndex)
              .value(this.currentCoreLabel)
              .font({ size: 16 })
              .fontColor(Color.White)
              .selectedOptionFont({ size: 16 })
              .optionFont({ size: 16 })
              .width('100%')
              .height(44)
              .backgroundColor('#333333')
              .borderRadius(8)
              .enabled(!this.switching)
              .onSelect((index: number) => {
                this.selectedCoreIndex = this.clampIndex(index, this.cores.length);
                this.updateRomOptions();
                this.resetCoreCheckState();
                const core = this.cores[this.selectedCoreIndex];
                LogHelper.info('LibretroGame', 'UI', `选择核心: ${core ? core.name : '未知'}`);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        
        // 4. ROM 选择
        ListItem() {
          Column({ space: 8 }) {
            Text('选择 ROM')
              .fontSize(14)
              .fontColor('#AAAAAA')
            
            Select(this.romOptions)
              .selected(this.safeRomIndex)
              .value(this.currentRomLabel)
              .font({ size: 16 })
              .fontColor(Color.White)
              .selectedOptionFont({ size: 16 })
              .optionFont({ size: 16 })
              .width('100%')
              .height(44)
              .backgroundColor('#333333')
              .borderRadius(8)
              .enabled(this.hasRomOptions && !this.switching)
              .onSelect((index: number) => {
                this.selectedRomIndex = this.clampIndex(index, this.romOptions.length);
                this.resetCoreCheckState();
                const roms = this.getAvailableRoms();
                const rom = roms.length > 0 ? roms[this.selectedRomIndex] : null;
                LogHelper.info('LibretroGame', 'UI', `选择 ROM: ${rom ? rom.name : '未知'}`);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 5. 核心验证按钮
        ListItem() {
          Column({ space: 8 }) {
            Button(this.coreCheckRunning ? '验证中...' : '验证核心符号')
              .fontSize(16)
              .height(44)
              .width('100%')
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor(this.coreCheckRunning ? '#607D8B' : '#546E7A')
              .enabled(!this.coreCheckRunning && !this.switching)
              .onClick(() => {
                this.runCoreCheck();
              })

            if (this.coreCheckText) {
              Text(this.coreCheckText)
                .fontSize(12)
                .fontColor(Color.White)
                .padding(4)
            }
          }
          .width('100%')
        }

        // 6. 画质模式
        ListItem() {
          Column({ space: 8 }) {
            Text('渲染模式')
              .fontSize(14)
              .fontColor('#AAAAAA')

            Select([
              { value: '硬件渲染 (Buffer Map)' }, // 0
              { value: '软件渲染 (CPU)' },       // 1
              { value: 'GLES渲染 (GPU)' }       // 2
            ])
              .selected(this.scalingMode)
              .value(['硬件渲染', '软件渲染', 'GLES渲染'][this.scalingMode])
              .font({ size: 16 })
              .fontColor(Color.White)
              .selectedOptionFont({ size: 16 })
              .optionFont({ size: 16 })
              .width('100%')
              .height(44)
              .backgroundColor('#333333')
              .borderRadius(8)
              .enabled(!this.switching)
              .onSelect((index: number) => {
                if (this.soakRunning) {
                  this.stopSoak();
                  this.soakSummaryText = '';
                }

                this.scalingMode = index;
                // 0=HW, 1=SW, 2=GLES
                const okMode = nativeApi.refactoredSetScalingMode(index);
                // 如果是软件模式，默认设为 720p 上限
                if (index === 1) {
                    const presets: ResolutionPreset[] = [
                      { w: 640, h: 480 },
                      { w: 1280, h: 720 },
                      { w: 1920, h: 1080 }
                    ];
                    const preset = presets[this.softwareMaxPresetIndex] || presets[1];
                    nativeApi.refactoredSetSoftwareMaxResolution(preset.w, preset.h);
                }

                const okStats = nativeApi.refactoredResetStats();
                this.realtimeFps = 0;
                this.coreFps = 0;
                this.audioStatusText = '';
                this.perfStatsText = '';
                this.geometryText = '';

                LogHelper.info('LibretroGame', 'Config', `设置缩放模式: ${index}, okMode=${okMode}, okStats=${okStats}`);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 7. 软件分辨率 (仅模式1)
        if (this.scalingMode === 1) {
          ListItem() {
            Column({ space: 8 }) {
              Text('软件分辨率')
                .fontSize(14)
                .fontColor('#AAAAAA')

              Select([
                { value: '480p (640x480)' },
                { value: '720p (1280x720)' },
                { value: '1080p (1920x1080)' },
              ])
                .selected(this.softwareMaxPresetIndex)
                .value(['480p', '720p', '1080p'][this.softwareMaxPresetIndex])
                .font({ size: 16 })
                .fontColor(Color.White)
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .width('100%')
                .height(44)
                .backgroundColor('#333333')
                .borderRadius(8)
                .enabled(!this.switching)
                .onSelect((index: number) => {
                  if (this.soakRunning) {
                    this.stopSoak();
                    this.soakSummaryText = '';
                  }

                  this.softwareMaxPresetIndex = index;
                  const presets: ResolutionPreset[] = [
                    { w: 640, h: 480 },
                    { w: 1280, h: 720 },
                    { w: 1920, h: 1080 }
                  ];
                  const preset = presets[index] || presets[1];
                  const okMax = nativeApi.refactoredSetSoftwareMaxResolution(preset.w, preset.h);

                  const okStats = nativeApi.refactoredResetStats();
                  this.realtimeFps = 0;
                  this.coreFps = 0;
                  this.audioStatusText = '';
                  this.perfStatsText = '';
                  this.geometryText = '';

                  LogHelper.info('LibretroGame', 'Config', `设置软件最大分辨率: ${preset.w}x${preset.h}, okMax=${okMax}, okStats=${okStats}`);
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }

        // 8. 开关选项组
        ListItem() {
          Column({ space: 12 }) {
            // HW Render
            Row() {
              Column() {
                Text('允许 HW_RENDER')
                  .fontSize(16)
                  .fontColor(Color.White)
                Text('需核心支持，重启生效')
                  .fontSize(12)
                  .fontColor('#888888')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.hwRenderAllowed })
                .enabled(!this.switching)
                .onChange((v: boolean) => {
                  this.hwRenderAllowed = v;
                  const ok = nativeApi.refactoredSetHwRenderAllowed(v);
                  LogHelper.info('LibretroGame', 'Config', `设置 HW_RENDER 允许: ${v}, ok=${ok}`);
                })
            }
            .width('100%')

            // 虚拟手柄
            Row() {
              Column() {
                Text('隐藏虚拟手柄')
                  .fontSize(16)
                  .fontColor(Color.White)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.hideVirtualController })
                .onChange((v: boolean) => {
                  this.hideVirtualController = v;
                  LogHelper.info('LibretroGame', 'Input', `隐藏虚拟手柄: ${v}`);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }

        // 9. 游戏控制按钮
        ListItem() {
          Column({ space: 12 }) {
            if (!this.gameRunning) {
              Button('开始游戏')
                .fontSize(18)
                .height(50)
                .width('100%')
                .type(ButtonType.Normal)
                .borderRadius(8)
                .backgroundColor('#4CAF50')
                .enabled(!this.switching)
                .onClick(async () => {
                  await this.startOrSwitchGame();
                })
            } else {
              Row({ space: 10 }) {
                if (this.gamePaused) {
                  Button('继续')
                    .fontSize(20)
                    .height(50)
                    .layoutWeight(1)
                    .type(ButtonType.Normal)
                    .borderRadius(8)
                    .backgroundColor('#4CAF50')
                    .onClick(() => {
                      this.resumeGame();
                    })
                } else {
                  Button('暂停')
                    .fontSize(20)
                    .height(50)
                    .layoutWeight(1)
                    .type(ButtonType.Normal)
                    .borderRadius(8)
                    .backgroundColor('#FF9800')
                    .onClick(() => {
                      this.pauseGame();
                    })
                }

                Button('重启')
                  .fontSize(20)
                  .height(50)
                  .layoutWeight(1)
                  .type(ButtonType.Normal)
                  .borderRadius(8)
                  .backgroundColor('#2196F3')
                  .enabled(!this.switching)
                  .onClick(async () => {
                    await this.startOrSwitchGame();
                  })

                Button('停止')
                  .fontSize(20)
                  .height(50)
                  .layoutWeight(1)
                  .type(ButtonType.Normal)
                  .borderRadius(8)
                  .backgroundColor('#F44336')
                  .margin({ left: 10 })
                  .onClick(() => {
                    this.stopGame();
                  })
              }
              .width('100%')
            }
          }
          .width('100%')
        }

        // 10. Soak Test
        ListItem() {
          Column({ space: 8 }) {
            Button(this.soakRunning ? `压力测试中 ${this.soakSecondsLeft}s` : '压力测试 (10min)')
              .fontSize(14)
              .height(40)
              .width('100%')
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor(this.soakRunning ? '#607D8B' : '#455A64')
              .enabled(!this.switching)
              .onClick(() => {
                if (this.soakRunning) {
                  this.stopSoak();
                } else {
                  this.startSoak(600);
                }
              })

            if (this.soakSummaryText) {
              Text(this.soakSummaryText)
                .fontSize(12)
                .fontColor('#CCCCCC')
                .width('100%')
            }
          }
          .width('100%')
        }

        // 11. 错误信息
        if (this.switchError) {
          ListItem() {
            Text(this.switchError)
              .fontSize(12)
              .fontColor('#FF5252')
              .width('100%')
              .padding(8)
              .backgroundColor('#33FF0000')
              .borderRadius(4)
          }
        }
        
        // 底部留白，防止被遮挡
        ListItem() {
          Column().height(40).width('100%')
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .width('320vp') // 稍微加宽一点
    .height('100%')
    .backgroundColor('#1F1F1F') // 统一深色背景
    .shadow({ radius: 30, color: Color.Black, offsetX: -10, offsetY: 0 })
    .position({ x: '100%', y: 0 })
    .markAnchor({ x: '100%', y: 0 })
  }
  
  // 构建虚拟控制器
  @Builder
  buildVirtualController() {
    Column() {
      Blank()
      
      Row() {
        // 左侧：十字键 + 模拟摇杆
        Column() {
          this.buildDPad();
          this.buildAnalogStick();
        }
        
        Blank()
        
        // 右侧：A/B 按钮 + 右摇杆
        Column() {
          this.buildActionButtons();
          this.buildRightAnalogStick();
        }
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
  }
  
  // 十字键
  @Builder
  buildDPad() {
    Column() {
      // 上
      Button('↑')
        .width(60)
        .height(60)
        .fontSize(24)
        .onTouch((event) => {
          if (event.type === TouchType.Down) {
            this.setButton(4, true);  // RETRO_DEVICE_ID_JOYPAD_UP
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.setButton(4, false);
          }
        })
      
      Row() {
        // 左
        Button('←')
          .width(60)
          .height(60)
          .fontSize(24)
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.setButton(6, true);  // RETRO_DEVICE_ID_JOYPAD_LEFT
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.setButton(6, false);
            }
          })
        
        // 右
        Button('→')
          .width(60)
          .height(60)
          .fontSize(24)
          .margin({ left: 60 })
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.setButton(7, true);  // RETRO_DEVICE_ID_JOYPAD_RIGHT
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.setButton(7, false);
            }
          })
      }
      
      // 下
      Button('↓')
        .width(60)
        .height(60)
        .fontSize(24)
        .onTouch((event) => {
          if (event.type === TouchType.Down) {
            this.setButton(5, true);  // RETRO_DEVICE_ID_JOYPAD_DOWN
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.setButton(5, false);
          }
        })
    }
  }
  
  // A/B 按钮
  @Builder
  buildActionButtons() {
    Column() {
      // SELECT / START
      Row() {
        Button('SELECT')
          .width(90)
          .height(40)
          .fontSize(14)
          .backgroundColor('#546E7A')
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.setButton(2, true);  // RETRO_DEVICE_ID_JOYPAD_SELECT
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.setButton(2, false);
            }
          })

        Button('START')
          .width(90)
          .height(40)
          .fontSize(14)
          .backgroundColor('#546E7A')
          .margin({ left: 10 })
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.setButton(3, true);  // RETRO_DEVICE_ID_JOYPAD_START
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.setButton(3, false);
            }
          })
      }
      .margin({ bottom: 20 })

      // B 按钮
      Button('B')
        .width(70)
        .height(70)
        .fontSize(24)
        .backgroundColor('#E53935')
        .margin({ bottom: 20 })
        .onTouch((event) => {
          if (event.type === TouchType.Down) {
            this.setButton(0, true);  // RETRO_DEVICE_ID_JOYPAD_B
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.setButton(0, false);
          }
        })
      
      // A 按钮
      Button('A')
        .width(70)
        .height(70)
        .fontSize(24)
        .backgroundColor('#43A047')
        .onTouch((event) => {
          if (event.type === TouchType.Down) {
            this.setButton(8, true);  // RETRO_DEVICE_ID_JOYPAD_A
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.setButton(8, false);
          }
        })
    }
    .margin({ right: 40 })
  }
  
  // 模拟摇杆 (左摇杆 index=0)
  @Builder
  buildAnalogStick() {
    AnalogStickControl({
      index: 0,
      baseSize: 140,
      knobSize: 60,
      onAnalogChange: (index: number, x: number, y: number) => {
        this.setAnalog(index, x, y);
      }
    })
    .margin({ top: 20 })
  }

  // 右摇杆 (index=1)
  @Builder
  buildRightAnalogStick() {
    AnalogStickControl({
      index: 1,
      baseSize: 120,
      knobSize: 50,
      onAnalogChange: (index: number, x: number, y: number) => {
        this.setAnalog(index, x, y);
      }
    })
    .margin({ top: 20, right: 20 })
  }
  
  // 设置按键状态 (新架构)
  setButton(buttonId: number, pressed: boolean) {
    // refactoredSendInput(port, keyId, pressed)
    const port = this.selectedPortIndex;
    if (!this.isVirtualPortActive(port)) {
      return;
    }
    nativeApi.refactoredSendInput(port, buttonId, pressed);
  }

  setAnalog(index: number, x: number, y: number) {
    const port = this.selectedPortIndex;
    if (!this.isVirtualPortActive(port)) {
      return;
    }
    const xVal = this.normalizeAnalogValue(x);
    const yVal = this.normalizeAnalogValue(y);
    nativeApi.refactoredSendAnalog(port, index, 0, xVal);
    nativeApi.refactoredSendAnalog(port, index, 1, yVal);
  }

  normalizeAnalogValue(value: number): number {
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
    
    LogHelper.info(
      'LibretroGame',
      'Engine',
      `[NewArch] 开始游戏: ${core.name} - ${rom.name}`
    );
    this.switchError = '';
    let success = false;
    let token = 0;

    try {
      // 1. 获取上下文
      const context = this.getUIContext().getHostContext() as
        common.UIAbilityContext;
      if (!context) throw new Error('获取 Context 失败');
      
      const filesDir = context.filesDir;
      const bundleCodeDir = context.bundleCodeDir;
      const resMgr = context.resourceManager;
      const timeoutMs = 5000;

      nativeApi.refactoredClearLastErrorInfo();
      
      let abiPath = deviceInfo.abiList === 'x86_64' ? 'x86_64' : 'arm64';
      const corePath = `${bundleCodeDir}/libs/${abiPath}/${core.soFile}`;
      LogHelper.info('LibretroGame', 'Engine', `加载 ROM: ${rom.file}`);
      token = this.switchToken + 1;
      this.switchToken = token;
      const resolved = await this.resolveRomPathForSwitch(
        rom.file,
        resMgr,
        filesDir
      );
      LogHelper.info(
        'LibretroGame',
        'Engine',
        `Resolved ROM path: ${resolved.romPath}, useResMgr=${resolved.useResMgr}`
      );
      const ok = resolved.useResMgr ?
        await nativeApi.refactoredSwitchGameAsync(
          corePath,
          resolved.romPath,
          filesDir,
          resMgr,
          timeoutMs,
          token
        ) :
        await nativeApi.refactoredSwitchGameAsync(
          corePath,
          resolved.romPath,
          filesDir,
          timeoutMs,
          token
        );
      if (token !== this.switchToken) {
        return;
      }
      if (!ok) {
        throw new Error(this.formatLastError('SwitchGame'));
      }
      
      this.currentCore = core.name;
      this.currentRom = rom.name;
      this.gameRunning = true;
      this.gamePaused = false;
      this.pendingStart = false;
      LogHelper.info('LibretroGame', 'Engine', '游戏启动成功');
      success = true;

    } catch (e) {
      if (token !== 0 && token !== this.switchToken) {
        return;
      }
      this.switchError = e.message || String(e);
      LogHelper.error(
        'LibretroGame',
        'Engine',
        `启动异常: ${this.switchError}`
      );
    } finally {
      if (token !== 0 && token !== this.switchToken) {
        return;
      }
      if (!success) {
        nativeApi.refactoredStopEngineAsync();
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

  private formatLastError(prefix: string): string {
    const err: EngineErrorInfo = nativeApi.refactoredGetLastErrorInfo();
    if (!err || !err.reason) {
      return `${prefix} failed: unknown_error`;
    }
    const step = err.step ? ` step=${err.step}` : '';
    const message = err.message ? ` message=${err.message}` : '';
    return `${prefix} failed: reason=${err.reason}${step}${message}`;
  }

  private async resolveRomPathForSwitch(
    romPath: string,
    resMgr: resourceManager.ResourceManager,
    filesDir: string
  ): Promise<RomPathResolution> {
    if (!romPath) {
      return { romPath: '', useResMgr: false };
    }
    if (!this.isRawfilePath(romPath)) {
      return { romPath, useResMgr: false };
    }
    // 对 rawfile ROM 一律走 native RawfileRomProcessor，避免前端落地路径不一致。
    // native 侧会按需写入 temp_roms，并返回可用的 fullpath（兼容 need_fullpath core）。
    void resMgr;
    void filesDir;
    return { romPath, useResMgr: true };
  }

  private isRawfilePath(path: string): boolean {
    return path.startsWith('roms/');
  }

  private isCueRawfile(path: string): boolean {
    return path.toLowerCase().endsWith('.cue');
  }

  private isArcadeRawfile(path: string): boolean {
    return path.startsWith('roms/arcade/');
  }

  private async ensureBundledRomExtracted(
    resMgr: resourceManager.ResourceManager,
    filesDir: string,
    rawfilePath: string
  ): Promise<string> {
    const filename = this.getFilename(rawfilePath);
    const isArcade = this.isArcadeRawfile(rawfilePath);
    const systemDir = `${filesDir}/system`;
    await this.ensureDirExists(systemDir);
    const baseDir = isArcade ?
      `${systemDir}/arcade` :
      systemDir;
    if (isArcade) {
      await this.ensureDirExists(baseDir);
    }
    const destPath = `${baseDir}/${filename}`;
    if (await this.fileExists(destPath)) {
      return destPath;
    }

    try {
      const content = await resMgr.getRawFileContent(rawfilePath);
      await this.writeBytesToFile(destPath, content);
      if (isArcade) {
        const mirrorDir = `${filesDir}/system/arc`;
        await this.ensureDirExists(mirrorDir);
        const mirrorPath = `${mirrorDir}/${filename}`;
        await this.writeBytesToFile(mirrorPath, content);
      }
    } catch (e) {
      LogHelper.error('LibretroGame', 'File', `Failed to copy asset ${rawfilePath}: ${e.message}`);
    }
    return destPath;
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      await fs.access(path);
      return true;
    } catch (err) {
      return false;
    }
  }

  private async ensureDirExists(path: string): Promise<void> {
    try {
      await fs.mkdir(path);
    } catch (err) {
      // ignore if already exists
    }
  }

  private async writeBytesToFile(
    path: string,
    data: Uint8Array
  ): Promise<void> {
    let file: fs.File | undefined;
    try {
      file = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data.buffer, {
        offset: data.byteOffset,
        length: data.byteLength
      });
    } catch (e) {
      LogHelper.error('LibretroGame', 'File', `Failed to write file ${path}: ${e.message}`);
    } finally {
      if (file) {
        try {
          await fs.close(file.fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  private getFilename(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.slice(slash + 1) : path;
  }
  
  // 暂停游戏
  pauseGame() {
    if (this.gameRunning && !this.gamePaused) {
      nativeApi.refactoredPauseEngine();
      this.gamePaused = true;
      LogHelper.info('LibretroGame', 'Engine', '游戏已暂停');
    }
  }
  
  // 继续游戏
  resumeGame() {
    if (this.gameRunning && this.gamePaused) {
      nativeApi.refactoredResumeEngine();
      this.gamePaused = false;
      LogHelper.info('LibretroGame', 'Engine', '游戏已继续');
    }
  }
  
  // 停止游戏
  stopGame(asyncStop: boolean = false) {
    if (this.gameRunning || this.gamePaused) {
      // 避免 UI 线程同步 Stop 阻塞导致卡死
      nativeApi.refactoredStopEngineAsync();
      this.gameRunning = false;
      this.gamePaused = false;
      this.stopSoak();
      LogHelper.info('LibretroGame', 'Engine', '游戏已停止');
    }
  }

  // Soak Test (使用 refactoredGetStats)
  startSoak(durationSeconds: number) {
    if (this.soakRunning) {
      return;
    }
    if (!this.gameRunning) {
      this.soakSummaryText = '请先启动游戏';
      return;
    }

    const ok = nativeApi.refactoredResetStats();
    if (!ok) {
      this.soakSummaryText = 'resetStats 失败';
      return;
    }

    this.soakRunning = true;
    this.soakSecondsLeft = durationSeconds;
    this.soakSummaryText = '';
    
    // 获取初始状态
    try {
        const s = nativeApi.refactoredGetStats() as RawEngineStats;
        this.soakStartStats = {
            videoNullFrames: Number(s.videoNullFrames),
            videoDupeFrames: Number(s.videoDupeFrames),
            audioUnderruns: Number(s.audioUnderruns),
            audioOverruns: Number(s.audioOverruns)
        };
    } catch (e) {
        this.soakSummaryText = '获取初始 Stats 失败';
        this.soakRunning = false;
        return;
    }

    this.soakMinAudioUsage = 1.0;
    this.soakMaxAudioUsage = 0.0;

    if (this.soakTimer !== -1) {
      clearInterval(this.soakTimer);
    }

    this.soakTimer = setInterval(() => {
      this.soakSecondsLeft -= 1;
      
      try {
        const s = nativeApi.refactoredGetStats() as RawEngineStats;
        const usage = Number(s.audioBufferUsage);
        if (usage > 0) {
            this.soakMinAudioUsage = Math.min(this.soakMinAudioUsage, usage);
            this.soakMaxAudioUsage = Math.max(this.soakMaxAudioUsage, usage);
        }
      } catch (e) {}

      if (this.soakSecondsLeft <= 0) {
        this.finishSoak();
      }
    }, 1000);
  }

  stopSoak() {
    if (this.soakTimer !== -1) {
      clearInterval(this.soakTimer);
      this.soakTimer = -1;
    }
    this.soakRunning = false;
    this.soakSecondsLeft = 0;
  }

  finishSoak() {
    this.stopSoak();
    try {
        const end = nativeApi.refactoredGetStats() as RawEngineStats;
        const start = this.soakStartStats;
        if (!start) {
          return;
        }
        
        const dNull = Number(end.videoNullFrames) - start.videoNullFrames;
        const dDupe = Number(end.videoDupeFrames) - start.videoDupeFrames;
        const dUnder = Number(end.audioUnderruns) - start.audioUnderruns;
        const dOver = Number(end.audioOverruns) - start.audioOverruns;
        
        this.soakSummaryText = `Null:${dNull} Dupe:${dDupe} U:${dUnder} O:${dOver} Buf:[${this.soakMinAudioUsage.toFixed(2)}-${this.soakMaxAudioUsage.toFixed(2)}]`;
    } catch (e) {
        this.soakSummaryText = '统计失败';
    }
  }
}
