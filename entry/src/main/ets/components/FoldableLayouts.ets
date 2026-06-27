/*
 * 三折叠 UI 布局组件
 * 实现单折态、双折态、三折态的自适应布局
 * 基于华为官方折叠屏适配指南
 */

import LogHelper from '../common/LogHelper';
import { DPadControl, ABXYControl, StartSelectControl, SystemControl } from './VirtualController';
import { ScanlineBackground } from './EmuAppShell'
import { EmuTypography } from '../common/EmuUiTokens'

function getScreenCornerRadius(curvature: number, baseRadius: number): number {
  return baseRadius + Math.round(curvature * 0.24)
}

function getScreenSaturationFactor(saturation: number): number {
  return Math.max(0, saturation / 100)
}

function getScanlineOpacity(intensity: number): number {
  if (intensity <= 0) {
    return 0
  }
  return Math.min(0.42, 0.08 + intensity * 0.0034)
}

function getScanlineSpacing(intensity: number): number {
  if (intensity >= 70) {
    return 1
  }
  if (intensity >= 35) {
    return 2
  }
  return 3
}

// 单折态 UI (F态) - Phantom Overlay (幽灵悬浮)
@ComponentV2
export struct SingleModeLayout {
  // XComponent ID
  @Param xComponentId: string = 'new_arch_game_surface';
  // 屏幕比例 (宽:高) - 根据模拟器类型动态设置
  // 示例: 1.0 (2048/GB), 1.5 (GBA), 1.33 (NES/SNES)
  @Param screenAspectRatio: number = 1.0;
  // 回调函数
  @Event onKeyPress?: (keyId: number, pressed: boolean) => void;
  @Event onReset?: () => void;
  @Event onStop?: () => void;

  build() {
    Column() {
      // 上部: 游戏画面区域 (最大化显示)
      Stack() {
        // 游戏画面 (撑满容器，保持比例)
        XComponent({
          id: this.xComponentId,
          type: XComponentType.SURFACE,
          libraryname: 'entry'
        })
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .onLoad(() => {
            LogHelper.info('SingleMode', 'UI', `XComponent 加载: ${this.xComponentId}`, 0xD005);
          })
      }
      .layoutWeight(1)  // 占据剩余空间
      .width('100%')
      .backgroundColor('#000000')
      
      // 下部: 虚拟按键区域 (紧凑布局)
      Column() {
        // 主控制区 (D-Pad + ABXY)
        Row() {
          // D-Pad (左侧)
          DPadControl({
            onKeyPress: this.onKeyPress,
            buttonSize: 50,  // 缩小按钮
            buttonOpacity: 0.85,
            buttonColor: '#34495e',
            isTransparent: false
          })
            .margin({ left: 15 })
          
          Blank()
          
          // ABXY (右侧)
          ABXYControl({
            onKeyPress: this.onKeyPress,
            buttonSize: 50,  // 缩小按钮
            buttonOpacity: 0.85,
            isTransparent: false
          })
            .margin({ right: 15 })
        }
        .width('100%')
        .height(200)  // 减小高度
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        
        // 底部功能按钮
        Row() {
          StartSelectControl({
            onKeyPress: this.onKeyPress,
            buttonWidth: 85,  // 缩小宽度
            buttonHeight: 30  // 缩小高度
          })
          
          Blank()
          
          SystemControl({
            onReset: this.onReset,
            onStop: this.onStop,
            buttonWidth: 85,  // 缩小宽度
            buttonHeight: 30,  // 缩小高度
            showStop: true
          })
        }
        .width('100%')
        .padding({ left: 5, right: 5, bottom: 5, top: 5 })  // 减小边距
      }
      .width('100%')
      .backgroundColor('#1a1a1a')  // 深色背景
    }
    .width('100%')
    .height('100%')
    .padding(0)  // 移除外边距
  }
}

// 双折态 UI (M态) - Digital GameBoy (虚拟掌机)
@ComponentV2
export struct DualModeLayout {
  // XComponent ID
  @Param xComponentId: string = 'new_arch_game_surface';
  // 屏幕比例 (宽:高) - 根据模拟器类型动态设置
  @Param screenAspectRatio: number = 1.0;
  @Param scanlineIntensity: number = 0;
  @Param screenCurvature: number = 0;
  @Param screenSaturation: number = 100;
  // 回调函数
  @Event onKeyPress?: (keyId: number, pressed: boolean) => void;
  @Event onReset?: () => void;
  @Event onStop?: () => void;

  build() {
    Column() {
      // 上半区: 显示器 (65% - 横向撑满)
      Stack() {
        // 黑色背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')

        // 游戏画面 (动态比例 + CRT 边框)
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: this.xComponentId,
            type: XComponentType.SURFACE,
            libraryname: 'entry'
          })
            .width('90%')
            .aspectRatio(this.screenAspectRatio)
            .onLoad(() => {
              LogHelper.info('DualMode', 'UI', `XComponent 加载: ${this.xComponentId}`, 0xD005);
            })

          if (this.scanlineIntensity > 0) {
            ScanlineBackground({
              lineColor: '#2400FF41',
              lineSpacing: getScanlineSpacing(this.scanlineIntensity),
              alternateColor: '#0F000000'
            })
              .width('90%')
              .aspectRatio(this.screenAspectRatio)
              .opacity(getScanlineOpacity(this.scanlineIntensity))
              .hitTestBehavior(HitTestMode.None)
          }
        }
          .saturate(getScreenSaturationFactor(this.screenSaturation))
          .border({
            width: 8,
            color: '#2C2C2C',
            radius: getScreenCornerRadius(this.screenCurvature, 12)
          })
          .borderRadius(getScreenCornerRadius(this.screenCurvature, 12))
          .shadow({
            radius: 20,
            color: '#000000',
            offsetX: 0,
            offsetY: 4
          })
          .clip(true)
      }
      .layoutWeight(0.65)
      .alignContent(Alignment.Center)
      
      // 分割线 (模拟转轴)
      Row()
        .width('100%')
        .height(4)
        .linearGradient({
          angle: 90,
          colors: [[0x808080, 0.0], [0x404040, 0.5], [0x808080, 1.0]]
        })
        .shadow({
          radius: 4,
          offsetY: 2,
          color: '#000000'
        })
      
      // 下半区: 控制台 (35% - 上下布局)
      Column() {
        // 主控制区 (D-Pad + ABXY 左右排列)
        Row() {
          // D-Pad (左侧)
          DPadControl({
            onKeyPress: this.onKeyPress,
            buttonSize: 65,
            buttonOpacity: 1.0,
            buttonColor: '#34495e',
            isTransparent: false
          })
          
          Blank()
          
          // ABXY (右侧)
          ABXYControl({
            onKeyPress: this.onKeyPress,
            buttonSize: 65,
            buttonOpacity: 1.0,
            isTransparent: false
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 40, right: 40 })
        
        // 底部功能按钮
        Row() {
          StartSelectControl({
            onKeyPress: this.onKeyPress,
            buttonWidth: 90,
            buttonHeight: 45
          })
          
          Blank()
          
          SystemControl({
            onReset: this.onReset,
            onStop: this.onStop,
            buttonWidth: 90,
            buttonHeight: 45,
            showStop: true
          })
        }
        .width('100%')
        .padding({ left: 40, right: 40, bottom: 20 })
      }
      .layoutWeight(0.35)
      .backgroundColor('#2C2C2C')  // 深灰色背景 (磨砂塑料质感)
      .backgroundImageSize(ImageSize.Cover)
    }
    .width('100%')
    .height('100%')
  }
}

// 三折态 UI (G态) - Switch Layout (分体手柄)
@ComponentV2
export struct TripleModeLayout {
  // XComponent ID
  @Param xComponentId: string = 'new_arch_game_surface';
  // 屏幕比例 (宽:高) - 根据模拟器类型动态设置
  @Param screenAspectRatio: number = 1.0;
  @Param scanlineIntensity: number = 0;
  @Param screenCurvature: number = 0;
  @Param screenSaturation: number = 100;
  // 回调函数
  @Event onKeyPress?: (keyId: number, pressed: boolean) => void;
  @Event onReset?: () => void;
  @Event onStop?: () => void;
  // 性能信息
  @Param fps: number = 0;
  @Param cpuUsage: number = 0;

  build() {
    Stack() {
      // 背景层: 模糊效果 (可选)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#1a1a1a')
        .blur(50)
      
      // 前景层: 三栏布局
      Row() {
        // 左手柄区 (20%)
        Column() {
          // 主控制区 (垂直居中)
          Column() {
            // Start/Select (上方)
            StartSelectControl({
              onKeyPress: this.onKeyPress,
              buttonWidth: 85,
              buttonHeight: 45,
              isVertical: true
            })
              .margin({ bottom: 25 })
            
            // D-Pad (下方)
            DPadControl({
              onKeyPress: this.onKeyPress,
              buttonSize: 70,
              buttonOpacity: 1.0,
              buttonColor: '#34495e',
              isTransparent: false
            })
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('20%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backdropBlur(30)  // 背景模糊
        .backgroundColor('#80000000')  // 半透明黑色

        // 游戏视窗 (60% - 保持比例，不裁切)
        Stack() {
          // 黑色背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#000000')

          // 游戏画面 (动态比例)
          Stack({ alignContent: Alignment.Center }) {
            XComponent({
              id: this.xComponentId,
              type: XComponentType.SURFACE,
              libraryname: 'entry'
            })
              .height('100%')
              .aspectRatio(this.screenAspectRatio)
              .backgroundColor('#000000')
              .onLoad(() => {
                LogHelper.info('TripleMode', 'UI', `XComponent 加载: ${this.xComponentId}`, 0xD005);
              })

            if (this.scanlineIntensity > 0) {
              ScanlineBackground({
                lineColor: '#2400FF41',
                lineSpacing: getScanlineSpacing(this.scanlineIntensity),
                alternateColor: '#0F000000'
              })
                .height('100%')
                .aspectRatio(this.screenAspectRatio)
                .opacity(getScanlineOpacity(this.scanlineIntensity))
                .hitTestBehavior(HitTestMode.None)
            }
          }
            .saturate(getScreenSaturationFactor(this.screenSaturation))
            .borderRadius(getScreenCornerRadius(this.screenCurvature, 10))
            .clip(true)
        }
        .width('60%')
        .height('100%')
        .alignContent(Alignment.Center)
        
        // 右手柄区 (20%)
        Column() {
          // 信息面板 (顶部)
          Column() {
            this.InfoPanel()
          }
          .padding({ top: 30 })
          
          Blank()
          
          // 主控制区 (垂直居中)
          Column() {
            // ABXY (上方)
            ABXYControl({
              onKeyPress: this.onKeyPress,
              buttonSize: 70,
              buttonOpacity: 1.0,
              isTransparent: false
            })
              .margin({ bottom: 25 })
            
            // System Control (下方)
            SystemControl({
              onReset: this.onReset,
              onStop: this.onStop,
              buttonWidth: 85,
              buttonHeight: 45,
              showStop: true
            })
          }
          .justifyContent(FlexAlign.Center)
          
          Blank()
        }
        .width('20%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backdropBlur(30)
        .backgroundColor('#80000000')
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  InfoPanel() {
    Column() {
      Text(`帧率: ${this.fps > 0 ? this.fps.toFixed(1) : '--.-'}`)
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
        .margin({ bottom: 5 })

      Text(this.cpuUsage > 0 ? `负载: ${this.cpuUsage}%` : '负载: --')
        .fontSize(EmuTypography.md)
        .fontColor(Color.White)
    }
    .padding(15)
    .backgroundColor('#80000000')
    .borderRadius(8)
    .border({
      width: 1,
      color: '#FFFFFF40'
    })
  }
}
