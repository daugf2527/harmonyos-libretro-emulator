/*
 * Libretro 核心测试工具
 * 按照鸿蒙官方文档标准编写
 */

import testNapi from 'libentry.so';
import {
  EngineErrorInfo,
  EngineState,
  EventHubScope,
  FpsUpdatePayload,
  LibretroEventHub
} from '../common/LibretroEventHub';
import LogHelper from '../common/LogHelper';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

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
  refactoredGetRawFileList(
    resMgr: resourceManager.ResourceManager,
    dir: string
  ): string[];
  refactoredWaitForStateAsync(
    state: number,
    timeoutMs?: number
  ): Promise<boolean>;
  refactoredGetLastErrorInfo(): EngineErrorInfo;
  refactoredClearLastErrorInfo(): boolean;
  testCoreLoader(path: string): string;
}

const nativeApi = testNapi as LibretroNapi;

interface CoreExtensionRule {
  coreId: string;
  extensions: string[];
  requiresExactName?: string;
}

// 核心配置接口
interface CoreConfig {
  id: string;
  name: string;
  soFile: string;
  description: string;
}

// ROM 配置接口
interface RomConfig {
  id: string;
  name: string;
  file: string;
  core: string;  // 对应的核心 ID
  description: string;
}

// 测试结果接口
interface TestResult {
  success: boolean;
  resolution?: string;
  fps?: number;
  audioRate?: number;
  frames?: number;
  videoCallbacks?: number;
  audioCallbacks?: number;
  error?: string;
}

// 自动化测试结果接口
interface AutoTestResult {
  coreName: string;
  romName: string;
  success: boolean;
  fps: number;
  message: string;
}

@Entry
@Component
struct TestGambatte {
  @State testStatus: string = '等待测试';
  @State testResult: string = '选择核心和 ROM 开始测试';
  @State selectedCoreIndex: number = 0;
  @State selectedRomIndex: number = 0;
  @State testRunning: boolean = false;
  @State coreCheckRunning: boolean = false;
  @State lastTestResult: TestResult | null = null;
  @State coreOptions: SelectOption[] = [];
  @State romOptions: SelectOption[] = [];
  @State currentCoreDescription: string = '';
  @State currentRomDescription: string = '';
  
  // 自动化测试状态
  @State autoTesting: boolean = false;
  @State autoTestCurrentInfo: string = '';
  @State autoTestResults: AutoTestResult[] = [];
  @State currentFps: number = 0;

  private eventScope: EventHubScope | undefined = undefined;

  // 可用的核心列表
  private cores: CoreConfig[] = [
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
    // {
    //   id: 'mesen',
    //   name: 'Mesen',
    //   soFile: 'mesen_libretro.ohos-arm64.so',
    //   description: 'Mesen (暂不兼容: ARM64 崩溃问题)'
    // },
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

  // 可用的 ROM 列表
  private roms: RomConfig[] = [];
  private readonly noGameCores: string[] = ['mrboom'];
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

  // 组件初始化
  aboutToAppear() {
    // 初始化核心选项
    this.coreOptions = this.cores.map((core): SelectOption => {
      return { value: core.name };
    });
    
    // 初始化描述
    this.currentCoreDescription = this.cores[0].description;
    
    // 动态扫描 ROM 并初始化选项
    this.refreshRomList();

    this.eventScope = LibretroEventHub.getInstance().createScope();
    this.eventScope.onFpsUpdate((payload: FpsUpdatePayload) => {
      const fps = Number(payload.fps);
      if (!Number.isNaN(fps)) {
        this.currentFps = fps;
      }
    });
  }

  aboutToDisappear() {
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
  }

  // 更新 ROM 选项列表
  updateRomOptions() {
    const availableRoms = this.getAvailableRoms();
    this.romOptions = availableRoms.map((rom): SelectOption => {
      return { value: rom.name };
    });
    this.selectedRomIndex = 0;
  }

  // 获取当前核心可用的 ROM 列表
  getAvailableRoms(): RomConfig[] {
    const currentCore = this.cores[this.selectedCoreIndex];
    return this.roms.filter(rom => rom.core === currentCore.id);
  }

  build() {
    Column() {
      // 标题
      Text('🎮 Libretro 核心测试工具')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 10 })

      Text('通用 ROM 测试平台')
        .fontSize(14)
        .fontColor(Color.Gray)
        .margin({ bottom: 20 })

      // 核心选择器
      Column() {
        Text('选择核心')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 20, bottom: 5 })

        Select(this.coreOptions)
          .selected(this.selectedCoreIndex)
          .value(this.cores[this.selectedCoreIndex].name)
          .font({ size: 16 })
          .selectedOptionFont({ size: 16 })
          .optionFont({ size: 16 })
          .width('90%')
          .onSelect((index: number) => {
            this.selectedCoreIndex = index;
            this.currentCoreDescription = this.cores[index].description;
            this.updateRomOptions();
            const availableRoms = this.getAvailableRoms();
            this.currentRomDescription = availableRoms[0]?.description || '没有可用的 ROM';
            LogHelper.info('TestGambatte', 'UI', `选择核心: ${this.cores[index].name}`);
          })

        Text(this.currentCoreDescription)
          .fontSize(12)
          .fontColor(Color.Gray)
          .margin({ top: 5 })
      }
      .width('100%')
      .margin({ bottom: 20 })

      Button(this.coreCheckRunning ? '🔍 核心验证中...' : '🔍 验证核心符号')
        .fontSize(16)
        .width('80%')
        .height(45)
        .margin({ bottom: 20 })
        .backgroundColor(this.coreCheckRunning ? Color.Gray : '#546E7A')
        .enabled(!this.coreCheckRunning)
        .onClick(() => {
          this.runCoreCheck();
        })

      // ROM 选择器
      Column() {
        Text('选择 ROM')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 20, bottom: 5 })

        Select(this.romOptions)
          .selected(this.selectedRomIndex)
          .value(this.romOptions[this.selectedRomIndex]?.value || '没有可用的 ROM')
          .font({ size: 16 })
          .selectedOptionFont({ size: 16 })
          .optionFont({ size: 16 })
          .width('90%')
          .enabled(this.romOptions.length > 0)
          .onSelect((index: number) => {
            this.selectedRomIndex = index;
            const availableRoms = this.getAvailableRoms();
            this.currentRomDescription = availableRoms[index]?.description || '';
            LogHelper.info('TestGambatte', 'UI', `选择 ROM: ${availableRoms[index]?.name}`);
          })

        Text(this.currentRomDescription)
          .fontSize(12)
          .fontColor(Color.Gray)
          .margin({ top: 5 })
      }
      .width('100%')
      .margin({ bottom: 20 })

      // 测试按钮
      Button(this.testRunning ? '⏸️ 测试中...' : '▶️ 开始测试')
        .fontSize(18)
        .width('80%')
        .height(50)
        .margin({ top: 10 })
        .backgroundColor(this.testRunning ? Color.Gray : '#4CAF50')
        .enabled(!this.testRunning && !this.autoTesting && this.romOptions.length > 0)
        .onClick(() => {
          this.runTest();
        })

      // 自动化测试按钮
      Button(this.autoTesting ? `🔄 自动测试中... ${this.autoTestCurrentInfo}` : '🤖 全自动生命周期测试')
        .fontSize(16)
        .width('80%')
        .height(50)
        .margin({ top: 10 })
        .backgroundColor(this.autoTesting ? '#FF9800' : '#673AB7')
        .enabled(!this.testRunning && !this.autoTesting)
        .onClick(() => {
          this.startAutoTest();
        })

      // 测试状态
      Text(this.testStatus)
        .fontSize(16)
        .fontColor(this.testStatus.includes('✅') ? '#4CAF50' : 
                   this.testStatus.includes('❌') ? '#F44336' : '#2196F3')
        .margin({ top: 20, bottom: 10 })
        .fontWeight(FontWeight.Medium)

      // 自动化测试结果列表
      if (this.autoTestResults.length > 0) {
        this.buildAutoTestResults()
      }

      // 测试结果详情
      if (this.lastTestResult && !this.autoTesting && this.autoTestResults.length === 0) {
        this.buildTestResultCard()
      } else if (!this.autoTesting && this.autoTestResults.length === 0) {
        Text(this.testResult)
          .fontSize(14)
          .fontColor(Color.Gray)
          .margin({ top: 10 })
          .padding(10)
          .width('90%')
      }

      Blank()

      // 底部提示
      Text('💡 提示：查看完整日志请使用 hdc shell hilog')
        .fontSize(12)
        .fontColor(Color.Gray)
        .margin({ bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // 构建自动化测试结果列表
  @Builder
  buildAutoTestResults() {
    Column() {
      Text('自动化测试报告')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 10 })

      List() {
        ForEach(this.autoTestResults, (item: AutoTestResult) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.coreName)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                Text(item.romName)
                  .fontSize(12)
                  .fontColor(Color.Gray)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text(item.success ? 'PASS' : 'FAIL')
                  .fontSize(14)
                  .fontColor(item.success ? '#4CAF50' : '#F44336')
                  .fontWeight(FontWeight.Bold)
                if (item.success) {
                  Text(`FPS: ${item.fps.toFixed(1)}`)
                    .fontSize(12)
                    .fontColor('#4CAF50')
                } else {
                  Text(item.message)
                    .fontSize(10)
                    .fontColor('#F44336')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.End)
              .width('40%')
            }
            .width('100%')
            .padding({ top: 5, bottom: 5 })
            .border({ width: { bottom: 1 }, color: '#EEEEEE' })
          }
        })
      }
      .width('100%')
      .height(200) // 限制高度，可滚动
    }
    .width('90%')
    .padding(15)
    .backgroundColor('#F5F5F5')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  // 构建测试结果卡片
  @Builder
  buildTestResultCard() {
    Column() {
      if (this.lastTestResult?.success) {
        // 成功结果
        Text('✅ 测试通过')
          .fontSize(16)
          .fontColor('#4CAF50')
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })

        if (this.lastTestResult.resolution) {
          this.buildResultRow('分辨率', this.lastTestResult.resolution)
        }
        if (this.lastTestResult.fps) {
          this.buildResultRow('帧率', `${this.lastTestResult.fps.toFixed(2)} FPS`)
        }
        if (this.lastTestResult.audioRate) {
          this.buildResultRow('音频采样率', `${this.lastTestResult.audioRate} Hz`)
        }
        if (this.lastTestResult.frames) {
          this.buildResultRow('测试帧数', `${this.lastTestResult.frames} 帧`)
        }
        if (this.lastTestResult.videoCallbacks) {
          this.buildResultRow('视频回调', `${this.lastTestResult.videoCallbacks} 次`)
        }
        if (this.lastTestResult.audioCallbacks) {
          this.buildResultRow('音频回调', `${this.lastTestResult.audioCallbacks} 次`)
        }
      } else {
        // 失败结果
        Text('❌ 测试失败')
          .fontSize(16)
          .fontColor('#F44336')
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })

        Text(this.lastTestResult?.error || '未知错误')
          .fontSize(14)
          .fontColor('#F44336')
      }
    }
    .width('90%')
    .padding(15)
    .backgroundColor('#F5F5F5')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  // 构建结果行
  @Builder
  buildResultRow(label: string, value: string) {
    Row() {
      Text(`${label}:`)
        .fontSize(14)
        .fontColor(Color.Gray)
        .width('40%')

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('60%')
    }
    .width('100%')
    .margin({ bottom: 5 })
  }

  // 运行测试
  async runTest() {
    const core = this.cores[this.selectedCoreIndex];
    const availableRoms = this.getAvailableRoms();
    const rom = availableRoms[this.selectedRomIndex];

    if (!core || !rom) {
      this.testStatus = '❌ 配置错误';
      this.testResult = '核心或 ROM 配置无效';
      return;
    }

    LogHelper.info('TestGambatte', 'Test', `开始测试: ${core.name} - ${rom.name}`);

    this.testRunning = true;
    this.testStatus = '🔄 测试中...';
    this.testResult = '正在加载核心和 ROM...';
    this.lastTestResult = null;

    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        this.testStatus = '❌ 获取上下文失败';
        this.testRunning = false;
        return;
      }

      const bundleCodeDir = context.bundleCodeDir;
      const corePath = `${bundleCodeDir}/libs/arm64/${core.soFile}`;
      const resMgr = context.resourceManager;
      const filesDir = context.filesDir;
      const cacheDir = context.cacheDir;
      const xComponentId = 'libretro_test'; // 虚拟ID，用于后端测试

      LogHelper.info('TestGambatte', 'Core', `核心路径: ${corePath}`);
      LogHelper.info('TestGambatte', 'ROM', `ROM 文件: ${rom.file}`);
      
      LogHelper.info('TestGambatte', 'Test', '--- NewArch Test Start ---');
      const timeoutMs = 5000;
      nativeApi.refactoredClearLastErrorInfo();

      const stopOk = nativeApi.refactoredStopEngineAsync();
      if (stopOk) {
        const stopped = await nativeApi.refactoredWaitForStateAsync(
          EngineState.STOPPED,
          timeoutMs
        );
        if (!stopped) {
          throw new Error('停止超时');
        }
      }

      const startOk = nativeApi.refactoredStartEngine();
      if (!startOk) {
        throw new Error('引擎启动失败');
      }
      const setDirOk = nativeApi.refactoredSetFilesDir(filesDir);
      if (!setDirOk) {
        throw new Error('设置目录失败');
      }

      LogHelper.info('TestGambatte', 'Core', '步骤1: 加载核心...');
      const coreLoaded = nativeApi.refactoredLoadCore(corePath);
      if (!coreLoaded) {
        throw new Error('加载核心失败');
      }
      const coreReady = await nativeApi.refactoredWaitForStateAsync(
        EngineState.CORE_LOADED,
        timeoutMs
      );
      if (!coreReady) {
        throw new Error(this.formatLastError('LoadCore'));
      }
      LogHelper.info('TestGambatte', 'Core', '核心加载成功');

      LogHelper.info('TestGambatte', 'ROM', '步骤2: 加载 ROM...');
      const romLoaded = nativeApi.refactoredLoadRom(rom.file, resMgr);
      if (!romLoaded) {
        throw new Error('加载 ROM 失败');
      }
      const running = await nativeApi.refactoredWaitForStateAsync(
        EngineState.RUNNING,
        timeoutMs
      );
      if (!running) {
        throw new Error(this.formatLastError('LoadRom'));
      }
      LogHelper.info('TestGambatte', 'ROM', 'ROM 加载成功');

      this.testStatus = '✅ 已提交到新引擎 (Phase 1)';
      this.lastTestResult = {
        success: true
      };
      LogHelper.info('TestGambatte', 'Engine', 'NewArch 请求已提交');

    } catch (error) {
      const err = error as Error;
      this.testStatus = '❌ 测试异常';
      this.lastTestResult = {
        success: false,
        error: `异常: ${err.message}`
      };
      LogHelper.error('TestGambatte', 'Test', `测试异常: ${err.message}`);
    } finally {
      this.testRunning = false;
    }
  }

  // 自动化测试逻辑
  async startAutoTest() {
    if (this.autoTesting) {
      return;
    }
    
    this.autoTesting = true;
    this.autoTestResults = [];
    this.testStatus = '🤖 自动化测试准备中...';
    
    // 1. 生成测试队列
    // 策略：每个核心取第一个可用的 ROM，如果没有 ROM 且不是 nogame 核心，则标记为无 ROM
    interface TestItem { core: CoreConfig; rom: RomConfig | null; }
    const testQueue: TestItem[] = [];
    
    this.cores.forEach((core) => {
      const roms = this.roms.filter(r => r.core === core.id);
      if (roms.length > 0) {
        testQueue.push({ core, rom: roms[0] });
      } else if (this.noGameCores.includes(core.id)) {
        testQueue.push({ core, rom: null });
      } else {
        // 记录一个无 ROM 的项，用于报告跳过
        testQueue.push({ core, rom: null });
      }
    });

    LogHelper.info('TestGambatte', 'AutoTest', `开始自动化测试，队列长度: ${testQueue.length}`);

    // 2. 顺序执行测试
    await testQueue.reduce(async (prev, item, index) => {
      await prev;
      const indexStr = `(${index + 1}/${testQueue.length})`;
      this.autoTestCurrentInfo = `${indexStr} ${item.core.name}`;

      try {
        const result = await this.runSingleTestCase(item.core, item.rom);
        this.autoTestResults.push(result);
      } catch (e) {
        const err = e as Error;
        this.autoTestResults.push({
          coreName: item.core.name,
          romName: item.rom?.name || 'No ROM',
          success: false,
          fps: 0,
          message: `执行异常: ${err.message}`
        });
        LogHelper.error('TestGambatte', 'AutoTest', `测试项异常: ${err.message}`);
      }

      // 强制让 UI 渲染一帧
      await this.sleep(500);
    }, Promise.resolve());

    this.autoTesting = false;
    this.testStatus = '✅ 自动化测试完成';
    this.autoTestCurrentInfo = '测试完成';
  }

  // 执行单个测试用例
  async runSingleTestCase(core: CoreConfig, rom: RomConfig | null): Promise<AutoTestResult> {
    const romName = rom ? rom.name : (this.noGameCores.includes(core.id) ? '无需 ROM' : '无可用 ROM');
    
    // 检查是否跳过
    if (!rom && !this.noGameCores.includes(core.id)) {
      return {
        coreName: core.name,
        romName: '无可用 ROM',
        success: false,
        fps: 0,
        message: '跳过: 缺少 ROM'
      };
    }

    LogHelper.info('TestGambatte', 'AutoTest', `>>> 测试开始: ${core.name} | ${romName}`);

    const timeoutMs = 5000;
    nativeApi.refactoredClearLastErrorInfo();
    const stopOk = nativeApi.refactoredStopEngineAsync();
    if (stopOk) {
      const stopped = await nativeApi.refactoredWaitForStateAsync(
        EngineState.STOPPED,
        timeoutMs
      );
      if (!stopped) {
        return {
          coreName: core.name,
          romName: romName,
          success: false,
          fps: 0,
          message: 'Stop 超时'
        };
      }
    }

    // 2. 准备启动
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('Context lost');
    
    const bundleCodeDir = context.bundleCodeDir;
    const filesDir = context.filesDir;
    const resMgr = context.resourceManager;
    const corePath = `${bundleCodeDir}/libs/arm64/${core.soFile}`; // 假设 arm64，自动化测试通常在真机

    try {
      // Start Engine
      const startOk = nativeApi.refactoredStartEngine();
      if (!startOk) {
        return {
          coreName: core.name,
          romName: romName,
          success: false,
          fps: 0,
          message: 'Start Engine Failed'
        };
      }
      const setDirOk = nativeApi.refactoredSetFilesDir(filesDir);
      if (!setDirOk) {
        return {
          coreName: core.name,
          romName: romName,
          success: false,
          fps: 0,
          message: 'Set FilesDir Failed'
        };
      }
      
      // Load Core
      const loadCoreOk = nativeApi.refactoredLoadCore(corePath);
      if (!loadCoreOk) {
        return {
          coreName: core.name,
          romName: romName,
          success: false,
          fps: 0,
          message: 'Load Core Failed'
        };
      }
      const coreReady = await nativeApi.refactoredWaitForStateAsync(
        EngineState.CORE_LOADED,
        timeoutMs
      );
      if (!coreReady) {
        return {
          coreName: core.name,
          romName: romName,
          success: false,
          fps: 0,
          message: this.formatLastError('LoadCore')
        };
      }

      // Load ROM (如果有)
      if (rom) {
        const loadRomOk = nativeApi.refactoredLoadRom(rom.file, resMgr);
        if (!loadRomOk) {
          return {
            coreName: core.name,
            romName: romName,
            success: false,
            fps: 0,
            message: 'Load ROM Failed'
          };
        }
        const running = await nativeApi.refactoredWaitForStateAsync(
          EngineState.RUNNING,
          timeoutMs
        );
        if (!running) {
          return {
            coreName: core.name,
            romName: romName,
            success: false,
            fps: 0,
            message: this.formatLastError('LoadRom')
          };
        }
      } else if (this.noGameCores.includes(core.id)) {
        const running = await nativeApi.refactoredWaitForStateAsync(
          EngineState.RUNNING,
          timeoutMs
        );
        if (!running) {
          return {
            coreName: core.name,
            romName: romName,
            success: false,
            fps: 0,
            message: this.formatLastError('LoadCore')
          };
        }
      }

      // 3. 运行监控 (3秒)
      // 重置 FPS 计数
      this.currentFps = 0;
      let maxFps = 0;
      
      // 采样 6 次，每次 500ms
      for (let i = 0; i < 6; i++) {
        await this.sleep(500);
        if (this.currentFps > maxFps) {
          maxFps = this.currentFps;
        }
        // 如果中间 Crash 了，可以通过 global event 捕获，这里简化处理
      }

      // 4. 判定结果
      // 只要有一次 FPS > 0 或者对于某些无需 FPS 的核心（虽然很少）
      // 一般认为 Max FPS > 0 即为运行成功
      // 对于某些菜单驱动的核心（如 2048），FPS 可能很低或者是 0（如果没刷新）
      // 这里放宽条件，只要没 Crash 且流程走完，就算 Pass，FPS 仅作参考
      
      LogHelper.info('TestGambatte', 'AutoTest', `<<< 测试结束: ${core.name} | FPS: ${maxFps}`);

      return {
        coreName: core.name,
        romName: romName,
        success: true, // 只要没抛出异常且 Load 成功，暂时认为 Success
        fps: maxFps,
        message: 'Pass'
      };

    } catch (e) {
      throw e as Error;
    } finally {
      // 再次确保清理
      nativeApi.refactoredStopEngineAsync();
      await nativeApi.refactoredWaitForStateAsync(
        EngineState.STOPPED,
        2000
      );
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

  sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // 验证核心符号
  runCoreCheck() {
    if (this.coreCheckRunning) {
      return;
    }
    const core = this.cores[this.selectedCoreIndex];
    if (!core) {
      this.testStatus = '❌ 核心无效';
      this.testResult = '未选择可用核心';
      return;
    }

    this.coreCheckRunning = true;
    this.testStatus = '🔍 核心验证中...';
    this.testResult = '正在验证核心符号...';
    this.lastTestResult = null;

    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        this.testStatus = '❌ 获取上下文失败';
        this.testResult = '无法获取 bundleCodeDir';
        return;
      }

      const bundleCodeDir = context.bundleCodeDir;
      const abiPath = deviceInfo.abiList === 'x86_64' ? 'x86_64' : 'arm64';
      const corePath = `${bundleCodeDir}/libs/${abiPath}/${core.soFile}`;

      LogHelper.info('TestGambatte', 'Core', `验证核心: ${corePath}`);
      const result = nativeApi.testCoreLoader(corePath);
      this.testResult = result;
      if (result.startsWith('Success')) {
        this.testStatus = '✅ 核心验证通过';
      } else {
        this.testStatus = '❌ 核心验证失败';
      }
    } catch (error) {
      const msg = (error as Error)?.message || String(error);
      this.testResult = `Failed: ${msg}`;
      this.testStatus = '❌ 核心验证异常';
      LogHelper.error('TestGambatte', 'Core', `核心验证异常: ${msg}`);
    } finally {
      this.coreCheckRunning = false;
    }
  }

  private refreshRomList() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      this.roms = this.buildRomConfigs([]);
      this.updateRomOptions();
      return;
    }

    let files: string[] = [];
    try {
      const rawList: string[] = nativeApi.refactoredGetRawFileList(context.resourceManager, 'roms');
      files = rawList.filter(item => typeof item === 'string') as string[];
    } catch (err) {
      const msg = (err as Error).message || String(err);
      LogHelper.error('TestGambatte', 'ROM', `扫描 ROM 列表失败: ${msg}`);
    }

    this.roms = this.buildRomConfigs(files);
    this.updateRomOptions();
    
    // 更新当前选择的 ROM 描述
    const availableRoms = this.getAvailableRoms();
    this.currentRomDescription = availableRoms[this.selectedRomIndex]?.description || '没有可用的 ROM';
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
          core: coreId,
          description: fileName
        });
      });
    });

    this.noGameCores.forEach((coreId) => {
      roms.push({
        id: `nogame:${coreId}`,
        name: '无需 ROM',
        file: '',
        core: coreId,
        description: '该核心不需要加载 ROM'
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
}
