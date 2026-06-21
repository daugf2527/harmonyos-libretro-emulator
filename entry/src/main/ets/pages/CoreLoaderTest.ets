/*
 * Phase 3.1 - CoreLoader 测试页面
 * 用于测试 Libretro 核心加载功能
 * DEV DIAGNOSTIC ONLY: 不注册到产品 main_pages.json，不作为默认产品路由入口。
 */

import testNapi from 'libentry.so';
import { deviceInfo } from '@kit.BasicServicesKit';
import { EmuTypography } from '../common/EmuUiTokens'
import LogHelper from '../common/LogHelper';

interface CoreConfig {
  id: string;
  name: string;
  soFile: string;
  description: string;
}

interface CoreLoaderNapi {
  testCoreLoader(corePath: string): Promise<string>;
}

const nativeApi = testNapi as CoreLoaderNapi;

@Entry
@ComponentV2
struct CoreLoaderTest {
  @Local testResult: string = '等待测试...';
  @Local corePath: string = '';
  @Local isLoading: boolean = false;
  @Local coreOptions: SelectOption[] = [];
  @Local selectedCoreIndex: number = 0;
  @Local coreDescription: string = '';
  private bundleCodeDir: string = '';
  private abiPath: string = 'arm64';
  private pageActive: boolean = false;
  private testTaskToken: number = 0;
  private cores: CoreConfig[] = [
    {
      id: 'libretro_2048',
      name: '2048 (Demo)',
      soFile: 'libretro_2048.so',
      description: '2048 示例核心'
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

  aboutToAppear() {
    this.pageActive = true;

    // 获取沙箱路径 (官方推荐方式)
    let bundleCodeDir = this.getUIContext().getHostContext()!.bundleCodeDir;

    // deviceInfo.abiList 可能是多 ABI 字符串，不能只做全等判断。
    const rawAbiList = String(deviceInfo.abiList ?? '').toLowerCase();
    let abiPath = rawAbiList.indexOf('x86_64') >= 0 ? 'x86_64' : 'arm64';

    this.bundleCodeDir = bundleCodeDir;
    this.abiPath = abiPath;
    this.coreOptions = this.cores.map((core): SelectOption => {
      return { value: core.name };
    });
    this.updateCorePath();

    LogHelper.info('CoreLoaderTest', 'Init', `Bundle code dir: ${LogHelper.describePathForLog(bundleCodeDir)}`);
    LogHelper.info('CoreLoaderTest', 'Init', `ABI: ${abiPath}`);
    LogHelper.info('CoreLoaderTest', 'Init', `Core path: ${LogHelper.describePathForLog(this.corePath)}`);
  }

  aboutToDisappear() {
    this.pageActive = false;
    this.testTaskToken += 1;
  }

  private beginTestTask(): number {
    this.testTaskToken += 1;
    return this.testTaskToken;
  }

  private isCurrentTestTask(token: number): boolean {
    return this.pageActive && token === this.testTaskToken;
  }

  build() {
    Column() {
      // 标题
      Text('Phase 3.1 - CoreLoader 测试')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 20 })

      Column() {
        Text('选择核心')
          .fontSize(EmuTypography.lg)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 20, bottom: 10 })

        Select(this.coreOptions)
          .selected(this.selectedCoreIndex)
          .value(this.coreOptions[this.selectedCoreIndex]?.value || '未选择核心')
          .font({ size: 16 })
          .selectedOptionFont({ size: 16 })
          .optionFont({ size: 16 })
          .width('90%')
          .onSelect((index: number) => {
            this.selectedCoreIndex = index;
            this.updateCorePath();
            this.isLoading = false;
            this.testResult = '等待测试...';
          })

        Text(this.coreDescription)
          .fontSize(EmuTypography.sm)
          .fontColor(Color.Gray)
          .margin({ top: 6, left: 20 })
      }
      .width('100%')
      .margin({ bottom: 20 })

      // 显示核心路径
      Column() {
        Text('核心路径:')
          .fontSize(EmuTypography.lg)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 20, bottom: 10 })

        Text(this.corePath)
          .fontSize(EmuTypography.sm)
          .fontColor(Color.Gray)
          .margin({ left: 20, right: 20, bottom: 20 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .backgroundColor('#F5F5F5')
      .borderRadius(10)
      .padding(10)
      .margin({ left: 20, right: 20, bottom: 20 })

      // 测试按钮
      Button('开始测试 CoreLoader')
        .width('80%')
        .height(50)
        .fontSize(EmuTypography.xl)
        .enabled(!this.isLoading)
        .onClick(() => {
          void this.runTest();
        })
        .margin({ bottom: 30 })

      // 测试结果显示区域
      Column() {
        Text('测试结果:')
          .fontSize(EmuTypography.lg)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 10 })

        Scroll() {
          Text(this.testResult)
            .fontSize(EmuTypography.md)
            .fontColor(this.testResult.startsWith('Success') ? Color.Green :
                      this.testResult.startsWith('Failed') ? Color.Red : Color.Black)
            .width('100%')
            .maxLines(20)
        }
        .width('100%')
        .height(300)
        .scrollBar(BarState.Auto)
      }
      .width('90%')
      .height(350)
      .backgroundColor('#F5F5F5')
      .borderRadius(10)
      .padding(15)
      .alignItems(HorizontalAlign.Start)

      // 说明文字
      Text('注意: 需要将 Libretro 核心 (.so) 文件放入 entry/libs/arm64/ 或 entry/libs/x86_64/ 目录')
        .fontSize(EmuTypography.sm)
        .fontColor(Color.Gray)
        .margin({ top: 20, left: 20, right: 20 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  /**
   * 运行 CoreLoader 测试
   */
  private async runTest() {
    const token = this.beginTestTask();
    LogHelper.info('CoreLoaderTest', 'Test', 'Starting test...');
    this.isLoading = true;
    this.testResult = '正在测试...\n请查看日志输出';

    try {
      // 调用 Native 侧的测试函数 (传递沙箱路径)
      LogHelper.info(
        'CoreLoaderTest',
        'Test',
        `Calling testCoreLoader with path: ${LogHelper.describePathForLog(this.corePath)}`
      );
      let result = await nativeApi.testCoreLoader(this.corePath);
      if (!this.isCurrentTestTask(token)) {
        return;
      }

      LogHelper.info('CoreLoaderTest', 'Test', `Test result: ${result}`);
      this.testResult = result;

      // 根据结果显示提示
      if (result.startsWith('Success')) {
        LogHelper.info('CoreLoaderTest', 'Test', 'Test PASSED');
      } else {
        LogHelper.error('CoreLoaderTest', 'Test', 'Test FAILED');
      }
    } catch (error) {
      if (!this.isCurrentTestTask(token)) {
        return;
      }
      let errorMsg = `Exception: ${error}`;
      LogHelper.error('CoreLoaderTest', 'Test', errorMsg);
      this.testResult = `Failed: ${errorMsg}`;
    } finally {
      if (this.isCurrentTestTask(token)) {
        this.isLoading = false;
      }
    }
  }

  private updateCorePath() {
    const core = this.cores[this.selectedCoreIndex];
    if (!core || !this.bundleCodeDir) {
      this.corePath = '';
      this.coreDescription = '';
      return;
    }
    this.corePath = `${this.bundleCodeDir}/libs/${this.abiPath}/${core.soFile}`;
    this.coreDescription = core.description;
  }
}
