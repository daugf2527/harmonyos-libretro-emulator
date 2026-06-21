/*
 * Libretro 核心测试工具
 * 按照鸿蒙官方文档标准编写
 * DEV DIAGNOSTIC ONLY: 不注册到产品 main_pages.json，不作为默认产品路由入口。
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
import { EmuStateColors, EmuTypography } from '../common/EmuUiTokens';
import { NapiErrorResult } from '../common/ErrorCodes';

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
  testCoreLoader(path: string): Promise<string>;
}

const nativeApi = testNapi as LibretroNapi;

interface CoreExtensionRule {
  coreId: string;
  extensions: string[];
  requiresExactName?: string;
}

interface CoreDependencyHint {
  coreId: string;
  hint: string;
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

enum AutoTestLevel {
  PASS = 'PASS',
  SKIP = 'SKIP',
  FAIL = 'FAIL'
}

enum AutoTestDomain {
  ENGINE = 'ENGINE',
  RESOURCE = 'RESOURCE',
  DEPENDENCY = 'DEPENDENCY',
  TIMEOUT = 'TIMEOUT',
  LIFECYCLE = 'LIFECYCLE',
  UNKNOWN = 'UNKNOWN'
}

// 自动化测试结果接口
interface AutoTestResult {
  coreName: string;
  romName: string;
  success: boolean;
  fps: number;
  level: AutoTestLevel;
  domain: AutoTestDomain;
  stage: string;
  code: string;
  message: string;
  detail?: string;
}

@Entry
@ComponentV2
struct TestGambatte {
  @Local testStatus: string = '等待测试';
  @Local testResult: string = '选择核心和 ROM 开始测试';
  @Local selectedCoreIndex: number = 0;
  @Local selectedRomIndex: number = 0;
  @Local testRunning: boolean = false;
  @Local coreCheckRunning: boolean = false;
  @Local lastTestResult: TestResult | null = null;
  @Local coreOptions: SelectOption[] = [];
  @Local romOptions: SelectOption[] = [];
  @Local currentCoreDescription: string = '';
  @Local currentRomDescription: string = '';
  
  // 自动化测试状态
  @Local autoTesting: boolean = false;
  @Local autoTestCurrentInfo: string = '';
  @Local autoTestResults: AutoTestResult[] = [];
  @Local currentFps: number = 0;

  private eventScope: EventHubScope | undefined = undefined;
  private pageActive: boolean = false;
  private testTaskToken: number = 0;
  private autoTestTaskToken: number = 0;
  private coreCheckTaskToken: number = 0;

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
  private readonly dependencyHints: CoreDependencyHint[] = [
    { coreId: 'melonds', hint: '需要 system/bios7.bin, bios9.bin, firmware.bin' },
    { coreId: 'mednafen_psx_hw', hint: '需要有效 PSX BIOS 文件' },
    { coreId: 'pcsx_rearmed', hint: '建议提供 PSX BIOS 文件以提升兼容性' }
  ];
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
    this.pageActive = true;

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
    this.pageActive = false;
    this.testTaskToken += 1;
    this.autoTestTaskToken += 1;
    this.coreCheckTaskToken += 1;
    if (this.eventScope) {
      this.eventScope.dispose();
      this.eventScope = undefined;
    }
  }

  private beginTestTask(): number {
    this.testTaskToken += 1;
    return this.testTaskToken;
  }

  private isCurrentTestTask(token: number): boolean {
    return this.pageActive && token === this.testTaskToken;
  }

  private beginAutoTestTask(): number {
    this.autoTestTaskToken += 1;
    return this.autoTestTaskToken;
  }

  private isCurrentAutoTestTask(token: number): boolean {
    return this.pageActive && token === this.autoTestTaskToken;
  }

  private beginCoreCheckTask(): number {
    this.coreCheckTaskToken += 1;
    return this.coreCheckTaskToken;
  }

  private isCurrentCoreCheckTask(token: number): boolean {
    return this.pageActive && token === this.coreCheckTaskToken;
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
      Text('Libretro 核心测试工具')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 10 })

      Text('通用 ROM 测试平台')
        .fontSize(EmuTypography.md)
        .fontColor(Color.Gray)
        .margin({ bottom: 20 })

      // 核心选择器
      Column() {
        Text('选择核心')
          .fontSize(EmuTypography.lg)
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
          .fontSize(EmuTypography.sm)
          .fontColor(Color.Gray)
          .margin({ top: 5 })
      }
      .width('100%')
      .margin({ bottom: 20 })

      Button(this.coreCheckRunning ? '核心验证中...' : '验证核心符号')
        .fontSize(EmuTypography.lg)
        .width('80%')
        .height(45)
        .margin({ bottom: 20 })
        .backgroundColor(this.coreCheckRunning ? Color.Gray : '#546E7A')
        .enabled(!this.coreCheckRunning && !this.testRunning && !this.autoTesting)
        .onClick(() => {
          void this.runCoreCheck();
        })

      // ROM 选择器
      Column() {
        Text('选择 ROM')
          .fontSize(EmuTypography.lg)
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
          .fontSize(EmuTypography.sm)
          .fontColor(Color.Gray)
          .margin({ top: 5 })
      }
      .width('100%')
      .margin({ bottom: 20 })

      // 测试按钮
      Button(this.testRunning ? '测试中...' : '开始测试')
        .fontSize(EmuTypography.xl)
        .width('80%')
        .height(50)
        .margin({ top: 10 })
        .backgroundColor(this.testRunning ? Color.Gray : '#4CAF50')
        .enabled(!this.testRunning && !this.autoTesting && !this.coreCheckRunning && this.romOptions.length > 0)
        .onClick(() => {
          this.runTest();
        })

      // 自动化测试按钮
      Button(this.autoTesting ? `自动测试中... ${this.autoTestCurrentInfo}` : '全自动生命周期测试')
        .fontSize(EmuTypography.lg)
        .width('80%')
        .height(50)
        .margin({ top: 10 })
        .backgroundColor(this.autoTesting ? '#FF9800' : '#673AB7')
        .enabled(!this.testRunning && !this.autoTesting && !this.coreCheckRunning)
        .onClick(() => {
          this.startAutoTest();
        })

      // 测试状态
      Text(this.testStatus)
        .fontSize(EmuTypography.lg)
        .fontColor(this.testStatus.includes('通过') ? '#4CAF50' :
                   (this.testStatus.includes('失败') ||
                    this.testStatus.includes('错误') ||
                    this.testStatus.includes('异常') ||
                    this.testStatus.includes('无效')) ? EmuStateColors.dangerDefault : '#2196F3')
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
          .fontSize(EmuTypography.md)
          .fontColor(Color.Gray)
          .margin({ top: 10 })
          .padding(10)
          .width('90%')
      }

      Blank()

      // 底部提示
      Text('提示：查看完整日志请使用 hdc shell hilog')
        .fontSize(EmuTypography.sm)
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
        .fontSize(EmuTypography.lg)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 10 })

      Text(
        `PASS ${this.countAutoTestByLevel(AutoTestLevel.PASS)} | ` +
        `SKIP ${this.countAutoTestByLevel(AutoTestLevel.SKIP)} | ` +
        `FAIL ${this.countAutoTestByLevel(AutoTestLevel.FAIL)}`
      )
        .fontSize(EmuTypography.sm)
        .fontColor(Color.Gray)
        .margin({ bottom: 8 })

      List() {
        ForEach(this.autoTestResults, (item: AutoTestResult) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.coreName)
                  .fontSize(EmuTypography.md)
                  .fontWeight(FontWeight.Bold)
                Text(item.romName)
                  .fontSize(EmuTypography.sm)
                  .fontColor(Color.Gray)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text(item.level)
                  .fontSize(EmuTypography.md)
                  .fontColor(
                    item.level === AutoTestLevel.PASS
                      ? '#4CAF50'
                      : (item.level === AutoTestLevel.SKIP ? '#FB8C00' : EmuStateColors.dangerDefault)
                  )
                  .fontWeight(FontWeight.Bold)
                Text(`${item.domain} · ${item.code}`)
                  .fontSize(EmuTypography.xs)
                  .fontColor(Color.Gray)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.level === AutoTestLevel.PASS) {
                  Text(`FPS: ${item.fps.toFixed(1)}`)
                    .fontSize(EmuTypography.sm)
                    .fontColor('#4CAF50')
                } else {
                  Text(item.message)
                    .fontSize(EmuTypography.xs)
                    .fontColor(item.level === AutoTestLevel.SKIP ? '#FB8C00' : EmuStateColors.dangerDefault)
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
        }, (item: AutoTestResult) => item.id)
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
        Text('测试通过')
          .fontSize(EmuTypography.lg)
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
        Text('测试失败')
          .fontSize(EmuTypography.lg)
          .fontColor(EmuStateColors.dangerDefault)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })

        Text(this.lastTestResult?.error || '未知错误')
          .fontSize(EmuTypography.md)
          .fontColor(EmuStateColors.dangerDefault)
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
        .fontSize(EmuTypography.md)
        .fontColor(Color.Gray)
        .width('40%')

      Text(value)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Medium)
        .width('60%')
    }
    .width('100%')
    .margin({ bottom: 5 })
  }

  // 运行测试
  async runTest() {
    if (this.testRunning || this.autoTesting || this.coreCheckRunning) {
      return;
    }
    const token = this.beginTestTask();
    const core = this.cores[this.selectedCoreIndex];
    const availableRoms = this.getAvailableRoms();
    const rom = availableRoms[this.selectedRomIndex];

    if (!core || !rom) {
      this.testStatus = '配置错误';
      this.testResult = '核心或 ROM 配置无效';
      return;
    }

    LogHelper.info('TestGambatte', 'Test', `开始测试: ${core.name} - ${rom.name}`);

    this.testRunning = true;
    this.testStatus = '测试中...';
    this.testResult = '正在加载核心和 ROM...';
    this.lastTestResult = null;

    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        this.testStatus = '获取上下文失败';
        this.testRunning = false;
        return;
      }

      const bundleCodeDir = context.bundleCodeDir;
      const corePath = `${bundleCodeDir}/libs/${this.resolveAbiPath()}/${core.soFile}`;
      const resMgr = context.resourceManager;
      const filesDir = context.filesDir;
      const cacheDir = context.cacheDir;
      const xComponentId = 'libretro_test'; // 虚拟ID，用于后端测试

      LogHelper.info('TestGambatte', 'Core', `核心路径: ${LogHelper.describePathForLog(corePath)}`);
      LogHelper.info('TestGambatte', 'ROM', `ROM 文件: ${LogHelper.describePathForLog(rom.file)}`);
      
      LogHelper.info('TestGambatte', 'Test', '--- NewArch Test Start ---');
      const timeoutMs = 5000;
      nativeApi.refactoredClearLastErrorInfo();

      const stopOk = await nativeApi.refactoredStopEngineAsync();
      if (!this.isCurrentTestTask(token)) {
        return;
      }
      if (stopOk) {
        const stopped = await this.waitEngineQuiesced(timeoutMs);
        if (!this.isCurrentTestTask(token)) {
          return;
        }
        if (!stopped) {
          throw new Error('停止超时');
        }
      }

      const startResult = nativeApi.refactoredStartEngine();
      if (!startResult.success) {
        throw new Error('引擎启动失败');
      }
      const setDirOk = nativeApi.refactoredSetFilesDir(filesDir);
      if (!setDirOk) {
        throw new Error('设置目录失败');
      }

      LogHelper.info('TestGambatte', 'Core', '步骤1: 加载核心...');
      const coreLoadResult = nativeApi.refactoredLoadCore(corePath);
      if (!coreLoadResult.success) {
        throw new Error('加载核心失败');
      }
      const coreReady = await nativeApi.refactoredWaitForStateAsync(
        EngineState.CORE_LOADED,
        timeoutMs
      );
      if (!this.isCurrentTestTask(token)) {
        return;
      }
      if (!coreReady) {
        throw new Error(this.formatLastError('LoadCore'));
      }
      LogHelper.info('TestGambatte', 'Core', '核心加载成功');

      LogHelper.info('TestGambatte', 'ROM', '步骤2: 加载 ROM...');
      const romLoadResult = nativeApi.refactoredLoadRom(rom.file, resMgr);
      if (!romLoadResult.success) {
        throw new Error('加载 ROM 失败');
      }
      const running = await nativeApi.refactoredWaitForStateAsync(
        EngineState.RUNNING,
        timeoutMs
      );
      if (!this.isCurrentTestTask(token)) {
        return;
      }
      if (!running) {
        throw new Error(this.formatLastError('LoadRom'));
      }
      LogHelper.info('TestGambatte', 'ROM', 'ROM 加载成功');

      this.testStatus = '已提交到新引擎 (Phase 1)';
      this.lastTestResult = {
        success: true
      };
      LogHelper.info('TestGambatte', 'Engine', 'NewArch 请求已提交');

    } catch (error) {
      if (!this.isCurrentTestTask(token)) {
        return;
      }
      const err = error as Error;
      this.testStatus = '测试异常';
      this.lastTestResult = {
        success: false,
        error: `异常: ${err.message}`
      };
      LogHelper.error('TestGambatte', 'Test', `测试异常: ${err.message}`);
    } finally {
      if (this.isCurrentTestTask(token)) {
        this.testRunning = false;
      }
    }
  }

  // 自动化测试逻辑
  async startAutoTest() {
    if (this.testRunning || this.autoTesting || this.coreCheckRunning) {
      return;
    }
    const token = this.beginAutoTestTask();
    
    this.autoTesting = true;
    this.autoTestResults = [];
    this.testStatus = '自动化测试准备中...';
    
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
    try {
      await testQueue.reduce(async (prev, item, index) => {
        await prev;
        if (!this.isCurrentAutoTestTask(token)) {
          return;
        }
        const indexStr = `(${index + 1}/${testQueue.length})`;
        this.autoTestCurrentInfo = `${indexStr} ${item.core.name}`;

        try {
          const result = await this.runSingleTestCase(item.core, item.rom, token);
          if (!this.isCurrentAutoTestTask(token)) {
            return;
          }
          this.autoTestResults.push(result);
        } catch (e) {
          if (!this.isCurrentAutoTestTask(token)) {
            return;
          }
          const err = e as Error;
          this.autoTestResults.push(this.makeFailResult(
            item.core.name,
            item.rom?.name || 'No ROM',
            'run_single_case',
            'auto_test_exception',
            `执行异常: ${err.message}`,
            AutoTestDomain.LIFECYCLE
          ));
          LogHelper.error('TestGambatte', 'AutoTest', `测试项异常: ${err.message}`);
        }

        // 强制让 UI 渲染一帧
        await this.sleep(500);
      }, Promise.resolve());
    } finally {
      if (this.isCurrentAutoTestTask(token)) {
        this.autoTesting = false;
      }
    }

    if (!this.isCurrentAutoTestTask(token)) {
      return;
    }
    this.testStatus = '自动化测试完成';
    this.autoTestCurrentInfo = '测试完成';
  }

  // 执行单个测试用例
  async runSingleTestCase(
    core: CoreConfig,
    rom: RomConfig | null,
    token?: number
  ): Promise<AutoTestResult> {
    const romName = rom ? rom.name : (this.noGameCores.includes(core.id) ? '无需 ROM' : '无可用 ROM');
    
    // 检查是否跳过
    if (!rom && !this.noGameCores.includes(core.id)) {
      return this.makeSkipResult(
        core.name,
        '无可用 ROM',
        'precheck',
        'skip_no_rom',
        '跳过: 缺少 ROM'
      );
    }

    LogHelper.info('TestGambatte', 'AutoTest', `>>> 测试开始: ${core.name} | ${romName}`);

    const timeoutMs = 5000;
    nativeApi.refactoredClearLastErrorInfo();
    const stopOk = await nativeApi.refactoredStopEngineAsync();
    if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
      return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
    }
    if (stopOk) {
      const stopped = await this.waitEngineQuiesced(timeoutMs);
      if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
        return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
      }
      if (!stopped) {
        return this.makeFailResult(
          core.name,
          romName,
          'stop_before_start',
          'stop_timeout',
          'Stop 超时',
          AutoTestDomain.TIMEOUT
        );
      }
    }

    // 2. 准备启动
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('Context lost');
    
    const bundleCodeDir = context.bundleCodeDir;
    const filesDir = context.filesDir;
    const resMgr = context.resourceManager;
    const corePath = `${bundleCodeDir}/libs/${this.resolveAbiPath()}/${core.soFile}`;

    try {
      // Start Engine
      const startResult = nativeApi.refactoredStartEngine();
      if (!startResult.success) {
        return this.classifyFromLastError(
          core,
          romName,
          'start_engine',
          'start_engine_failed',
          'Start Engine Failed'
        );
      }
      const setDirOk = nativeApi.refactoredSetFilesDir(filesDir);
      if (!setDirOk) {
        return this.classifyFromLastError(
          core,
          romName,
          'set_files_dir',
          'set_files_dir_failed',
          'Set FilesDir Failed'
        );
      }
      
      // Load Core
      const loadCoreResult = nativeApi.refactoredLoadCore(corePath);
      if (!loadCoreResult.success) {
        return this.classifyFromLastError(
          core,
          romName,
          'load_core',
          'load_core_submit_failed',
          'Load Core Failed'
        );
      }
      const coreReady = await nativeApi.refactoredWaitForStateAsync(
        EngineState.CORE_LOADED,
        timeoutMs
      );
      if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
        return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
      }
      if (!coreReady) {
        return this.classifyFromLastError(
          core,
          romName,
          'wait_core_loaded',
          'wait_core_loaded_timeout',
          this.formatLastError('LoadCore')
        );
      }

      // Load ROM (如果有)
      if (rom) {
        const loadRomResult = nativeApi.refactoredLoadRom(rom.file, resMgr);
        if (!loadRomResult.success) {
          return this.classifyFromLastError(
            core,
            romName,
            'load_rom',
            'load_rom_submit_failed',
            'Load ROM Failed'
          );
        }
        const running = await nativeApi.refactoredWaitForStateAsync(
          EngineState.RUNNING,
          timeoutMs
        );
        if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
          return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
        }
        if (!running) {
          return this.classifyFromLastError(
            core,
            romName,
            'wait_running',
            'wait_running_timeout',
            this.formatLastError('LoadRom')
          );
        }
      } else if (this.noGameCores.includes(core.id)) {
        const running = await nativeApi.refactoredWaitForStateAsync(
          EngineState.RUNNING,
          timeoutMs
        );
        if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
          return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
        }
        if (!running) {
          return this.classifyFromLastError(
            core,
            romName,
            'wait_running_no_rom',
            'wait_running_timeout_no_rom',
            this.formatLastError('LoadCore')
          );
        }
      }

      // 3. 运行监控 (3秒)
      // 重置 FPS 计数
      if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
        return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
      }
      this.currentFps = 0;
      let maxFps = 0;
      
      // 采样 6 次，每次 500ms
      for (let i = 0; i < 6; i++) {
        await this.sleep(500);
        if (token !== undefined && !this.isCurrentAutoTestTask(token)) {
          return this.makeSkipResult(core.name, romName, 'cancelled', 'page_inactive', '页面已离开');
        }
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

      return this.makePassResult(core.name, romName, maxFps);

    } catch (e) {
      const message = (e as Error).message || String(e);
      throw new Error(message);
    } finally {
      // 再次确保清理
      void nativeApi.refactoredStopEngineAsync();
      await this.waitEngineQuiesced(2000);
    }
  }

  private async waitEngineQuiesced(timeoutMs: number): Promise<boolean> {
    const stopped = await nativeApi.refactoredWaitForStateAsync(
      EngineState.STOPPED,
      timeoutMs
    );
    if (stopped) {
      return true;
    }
    // 引擎未运行时可能保持 INIT，不一定进入 STOPPED。
    return nativeApi.refactoredWaitForStateAsync(EngineState.INIT, 0);
  }

  private makePassResult(coreName: string, romName: string, fps: number): AutoTestResult {
    return {
      coreName: coreName,
      romName: romName,
      success: true,
      fps: fps,
      level: AutoTestLevel.PASS,
      domain: AutoTestDomain.ENGINE,
      stage: 'lifecycle',
      code: 'engine_lifecycle_ok',
      message: '生命周期通过'
    };
  }

  private makeSkipResult(
    coreName: string,
    romName: string,
    stage: string,
    code: string,
    message: string
  ): AutoTestResult {
    return {
      coreName: coreName,
      romName: romName,
      success: false,
      fps: 0,
      level: AutoTestLevel.SKIP,
      domain: AutoTestDomain.RESOURCE,
      stage: stage,
      code: code,
      message: message
    };
  }

  private makeFailResult(
    coreName: string,
    romName: string,
    stage: string,
    code: string,
    message: string,
    domain: AutoTestDomain,
    detail?: string
  ): AutoTestResult {
    return {
      coreName: coreName,
      romName: romName,
      success: false,
      fps: 0,
      level: AutoTestLevel.FAIL,
      domain: domain,
      stage: stage,
      code: code,
      message: message,
      detail: detail
    };
  }

  private countAutoTestByLevel(level: AutoTestLevel): number {
    return this.autoTestResults.filter(item => item.level === level).length;
  }

  private findDependencyHint(coreId: string): string | undefined {
    const hit = this.dependencyHints.find(item => item.coreId === coreId);
    return hit?.hint;
  }

  private classifyFromLastError(
    core: CoreConfig,
    romName: string,
    stage: string,
    fallbackCode: string,
    fallbackMessage: string
  ): AutoTestResult {
    const err: EngineErrorInfo = nativeApi.refactoredGetLastErrorInfo();
    const reason = (err?.reason || '').trim();
    const step = (err?.step || '').trim();
    const rawMessage = (err?.message || '').trim();
    const lowerMessage = rawMessage.toLowerCase();
    const dependencyHint = this.findDependencyHint(core.id);

    let domain: AutoTestDomain = AutoTestDomain.UNKNOWN;
    let code = reason || fallbackCode;
    let message = fallbackMessage;

    if (reason.length === 0) {
      domain = AutoTestDomain.UNKNOWN;
    } else if (
      reason === 'stop_timeout' ||
      reason === 'switch_wait_stopped_timeout' ||
      reason === 'switch_wait_core_loaded_timeout' ||
      reason === 'switch_wait_running_timeout'
    ) {
      domain = AutoTestDomain.TIMEOUT;
      message = `超时: ${reason}`;
    } else if (
      reason === 'start_in_progress' ||
      reason === 'start_blocked_stop_in_progress' ||
      reason === 'switch_cancelled' ||
      reason === 'switch_start_failed' ||
      reason === 'switch_stop_failed'
    ) {
      domain = AutoTestDomain.LIFECYCLE;
      message = `生命周期冲突: ${reason}`;
    } else if (
      reason === 'rawfile_resource_manager_missing' ||
      reason === 'rawfile_resource_manager_init_failed' ||
      reason === 'rawfile_rom_process_failed' ||
      reason === 'rom_path_invalid' ||
      reason === 'empty_rom_path' ||
      reason === 'rom_data_missing' ||
      reason === 'need_fullpath_missing_path' ||
      reason === 'need_fullpath_rawfile' ||
      reason === 'rom_path_too_long' ||
      reason === 'rom_load_queue_closed' ||
      reason === 'files_dir_path_too_long' ||
      reason === 'files_dir_queue_closed' ||
      reason === 'files_dir_env_set_failed' ||
      reason === 'files_dir_set_ignored_state'
    ) {
      domain = AutoTestDomain.RESOURCE;
      if (reason === 'rawfile_rom_process_failed') {
        if (lowerMessage.includes('size: 0') || lowerMessage.includes('invalid rawfile size')) {
          code = 'rom_rawfile_empty';
          message = 'ROM 资源为空文件';
        } else if (lowerMessage.includes('failed to read rom file')) {
          code = 'rom_rawfile_read_failed';
          message = 'ROM 资源读取失败';
        } else {
          message = 'ROM 资源处理失败';
        }
      } else {
        message = `资源问题: ${reason}`;
      }
    } else if (
      reason === 'core_load_failed' ||
      reason === 'core_path_too_long' ||
      reason === 'core_load_queue_closed' ||
      reason === 'core_not_loaded'
    ) {
      domain = AutoTestDomain.ENGINE;
      message = `核心加载失败: ${reason}`;
    } else if (
      reason === 'load_game_failed' ||
      reason === 'no_game_load_failed'
    ) {
      if (
        lowerMessage.includes('bios') ||
        lowerMessage.includes('firmware') ||
        dependencyHint !== undefined
      ) {
        domain = AutoTestDomain.DEPENDENCY;
        code = 'core_dependency_missing';
        message = dependencyHint || '核心依赖缺失（BIOS/firmware）';
      } else {
        domain = AutoTestDomain.ENGINE;
        message = '核心执行 load_game 失败';
      }
    } else {
      domain = AutoTestDomain.UNKNOWN;
      message = `未知错误: ${reason}`;
    }

    const detail = `${step || stage}${rawMessage ? ` | ${rawMessage}` : ''}`;
    return this.makeFailResult(
      core.name,
      romName,
      stage,
      code,
      message,
      domain,
      detail
    );
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

  private resolveAbiPath(): string {
    const rawAbiList = String(deviceInfo.abiList ?? '').toLowerCase();
    return rawAbiList.indexOf('x86_64') >= 0 ? 'x86_64' : 'arm64';
  }

  // 验证核心符号
  async runCoreCheck() {
    if (this.coreCheckRunning || this.testRunning || this.autoTesting) {
      return;
    }
    const token = this.beginCoreCheckTask();
    const core = this.cores[this.selectedCoreIndex];
    if (!core) {
      this.testStatus = '核心无效';
      this.testResult = '未选择可用核心';
      return;
    }

    this.coreCheckRunning = true;
    this.testStatus = '核心验证中...';
    this.testResult = '正在验证核心符号...';
    this.lastTestResult = null;

    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        this.testStatus = '获取上下文失败';
        this.testResult = '无法获取 bundleCodeDir';
        return;
      }

      const bundleCodeDir = context.bundleCodeDir;
      const abiPath = this.resolveAbiPath();
      const corePath = `${bundleCodeDir}/libs/${abiPath}/${core.soFile}`;

      LogHelper.info('TestGambatte', 'Core', `验证核心: ${LogHelper.describePathForLog(corePath)}`);
      const result = await nativeApi.testCoreLoader(corePath);
      if (!this.isCurrentCoreCheckTask(token)) {
        return;
      }
      this.testResult = result;
      if (result.startsWith('Success')) {
        this.testStatus = '核心验证通过';
      } else {
        this.testStatus = '核心验证失败';
      }
    } catch (error) {
      if (!this.isCurrentCoreCheckTask(token)) {
        return;
      }
      const msg = (error as Error)?.message || String(error);
      this.testResult = `Failed: ${msg}`;
      this.testStatus = '核心验证异常';
      LogHelper.error('TestGambatte', 'Core', `核心验证异常: ${msg}`);
    } finally {
      if (this.isCurrentCoreCheckTask(token)) {
        this.coreCheckRunning = false;
      }
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
