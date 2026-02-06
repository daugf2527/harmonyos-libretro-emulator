/*
 * Tri-Morph Emulator (三态变形模拟器)
 * 华为 Mate XT 三折叠游戏模拟器 UI/UX 系统
 * 
 * 核心理念: Adaptive Immersion (自适应沉浸)
 * - 单折态 (F态): Phantom Overlay (幽灵悬浮)
 * - 双折态 (M态): Digital GameBoy (虚拟掌机)
 * - 三折态 (G态): Switch Layout (分体手柄)
 * 
 * 基于鸿蒙官方 API:
 * - @ohos.display: 折叠状态检测
 * - @ohos.vibrator: 触觉反馈
 * - backdropBlur: 高斯模糊效果
 */

import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { display } from '@kit.ArkUI';
import testNapi from 'libentry.so';
import { SingleModeLayout, DualModeLayout, TripleModeLayout } from '../components/FoldableLayouts';
import { EmulatorType, getEmulatorConfig, type EmulatorConfig } from '../config/EmulatorConfigs';

// 折叠状态枚举
enum FoldMode {
  SINGLE = 'single',  // 单折态 (F态)
  DUAL = 'dual',      // 双折态 (M态)
  TRIPLE = 'triple'   // 三折态 (G态)
}

@Entry
@Component
struct Game2048Native {
  @State message: string = 'Tri-Morph Emulator';
  @State gameStarted: boolean = false;
  @State currentMode: FoldMode = FoldMode.SINGLE;
  @State fps: number = 0;
  @State cpuUsage: number = 0;
  private xComponentId: string = 'game2048_native';
  private foldStatusCallback: number = -1;
  
  // 模拟器配置
  private currentEmulatorType: EmulatorType = EmulatorType.GAME_2048;
  @State emulatorConfig: EmulatorConfig | undefined = getEmulatorConfig(EmulatorType.GAME_2048);

  aboutToAppear() {
    hilog.info(0xD003, 'TriMorphEmulator', '=== 三折叠模拟器启动 ===');
    
    // 加载模拟器配置
    this.loadEmulatorConfig(this.currentEmulatorType);
    
    // 注册折叠状态监听
    try {
      display.on('foldStatusChange', (foldStatus: display.FoldStatus) => {
        hilog.info(0xD003, 'TriMorphEmulator', `折叠状态变化: ${foldStatus}`);
        this.updateFoldMode(foldStatus);
      });
      
      // 获取初始折叠状态
      const defaultDisplay = display.getDefaultDisplaySync();
      const foldStatus = display.getFoldStatus();
      this.updateFoldMode(foldStatus);
      
      hilog.info(0xD003, 'TriMorphEmulator', 
        `屏幕尺寸: ${defaultDisplay.width}x${defaultDisplay.height} px`);
    } catch (e) {
      hilog.error(0xD003, 'TriMorphEmulator', `折叠状态监听失败: ${(e as Error).message}`);
      // 降级方案: 根据屏幕宽度判断
      this.fallbackFoldDetection();
    }
  }
  
  // 更新折叠模式
  updateFoldMode(foldStatus: display.FoldStatus) {
    let newMode: FoldMode;
    
    switch (foldStatus) {
      case display.FoldStatus.FOLD_STATUS_FOLDED:
        newMode = FoldMode.SINGLE;
        break;
      case display.FoldStatus.FOLD_STATUS_HALF_FOLDED:
        newMode = FoldMode.DUAL;
        break;
      case display.FoldStatus.FOLD_STATUS_EXPANDED:
        newMode = FoldMode.TRIPLE;
        break;
      default:
        newMode = FoldMode.SINGLE;
    }
    
    if (this.currentMode !== newMode) {
      hilog.info(0xD003, 'TriMorphEmulator', `切换模式: ${this.currentMode} -> ${newMode}`);
      this.currentMode = newMode;
    }
  }
  
  // 降级方案: 根据屏幕宽度判断折叠状态
  fallbackFoldDetection() {
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      const widthPx = defaultDisplay.width;
      const densityDPI = defaultDisplay.densityDPI || 480;  // 默认 DPI
      const widthVp = widthPx / densityDPI * 160;
      
      if (widthVp < 400) {
        this.currentMode = FoldMode.SINGLE;  // 单折态
      } else if (widthVp < 900) {
        this.currentMode = FoldMode.DUAL;    // 双折态
      } else {
        this.currentMode = FoldMode.TRIPLE;  // 三折态
      }
      
      hilog.info(0xD003, 'TriMorphEmulator', 
        `降级检测: 宽度 ${widthVp.toFixed(0)} vp -> ${this.currentMode}`);
    } catch (e) {
      hilog.error(0xD003, 'TriMorphEmulator', `降级检测失败: ${(e as Error).message}`);
    }
  }

  aboutToDisappear() {
    hilog.info(0xD003, 'TriMorphEmulator', '=== 三折叠模拟器关闭 ===');
    
    // 注销折叠状态监听
    try {
      display.off('foldStatusChange');
    } catch (e) {
      hilog.error(0xD003, 'TriMorphEmulator', `注销监听失败: ${(e as Error).message}`);
    }
    
    this.stopGame();
  }

  // 加载模拟器配置
  loadEmulatorConfig(emulatorType: EmulatorType) {
    this.currentEmulatorType = emulatorType;
    this.emulatorConfig = getEmulatorConfig(emulatorType);
    
    if (this.emulatorConfig) {
      hilog.info(0xD003, 'TriMorphEmulator', 
        `加载模拟器: ${this.emulatorConfig.fullName} (${this.emulatorConfig.aspectRatio})`);
    } else {
      hilog.error(0xD003, 'TriMorphEmulator', `未找到模拟器配置: ${emulatorType}`);
    }
  }
  
  // 启动游戏
  startGame() {
    hilog.info(0xD003, 'TriMorphEmulator', `=== 启动游戏 (${this.currentMode} 模式) ===`);
    
    // 先设置 gameStarted 以显示 XComponent
    this.gameStarted = true;
    this.message = `游戏运行中 (${this.currentMode})`;
    
    // 延迟初始化,等待 XComponent 准备好
    setTimeout(() => {
      try {
        // 获取 SO 库路径 (从配置中读取)
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const coreLibrary = this.emulatorConfig?.coreLibrary || 'libretro_2048.so';
        const soPath = context.bundleCodeDir + `/libs/arm64/${coreLibrary}`;
        const filesDir = context.filesDir;
        hilog.info(0xD003, 'TriMorphEmulator', `SO 路径: ${soPath}`);
        
        // 初始化游戏
        const success = testNapi.initGameNative(this.xComponentId, soPath, filesDir);
        hilog.info(0xD003, 'TriMorphEmulator', `游戏初始化: ${success}`);
        
        if (success) {
          // 启动游戏循环
          testNapi.startGameLoopNative(this.xComponentId);
          this.message = `游戏运行中 (${this.currentMode})`;
          
          // 启动性能监控 (仅三折态显示)
          if (this.currentMode === FoldMode.TRIPLE) {
            this.startPerformanceMonitor();
          }
        } else {
          this.message = '游戏初始化失败';
          this.gameStarted = false;
        }
      } catch (e) {
        const error = e as Error;
        hilog.error(0xD003, 'TriMorphEmulator', `错误: ${error.message}`);
        this.message = `错误: ${error.message}`;
        this.gameStarted = false;
      }
    }, 100);
  }
  
  // 启动性能监控
  startPerformanceMonitor() {
    // TODO: 实现 FPS 和 CPU 监控
    // 这里可以调用 Native 层的性能统计接口
    setInterval(() => {
      this.fps = 60;  // 模拟数据
      this.cpuUsage = 25;  // 模拟数据
    }, 1000);
  }

  // 停止游戏
  stopGame() {
    hilog.info(0xD003, 'TriMorphEmulator', '=== 停止游戏 ===');
    
    try {
      // 停止游戏循环
      testNapi.stopGameLoopNative();
      
      // 清理游戏
      testNapi.deinitGameNative(this.xComponentId);
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD003, 'TriMorphEmulator', `清理错误: ${error.message}`);
    }
    
    this.gameStarted = false;
    this.message = 'Tri-Morph Emulator';
  }

  // 重置游戏
  resetGame() {
    hilog.info(0xD003, 'TriMorphEmulator', '=== 重置游戏 ===');
    
    try {
      testNapi.resetGameNative(this.xComponentId);
      this.message = `游戏已重置 (${this.currentMode})`;
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD003, 'TriMorphEmulator', `重置错误: ${error.message}`);
    }
  }

  // 处理按键输入
  handleInput(keyId: number, pressed: boolean) {
    try {
      // Phase 3.4: 使用 RetroPad 输入系统
      const port = 0;  // 玩家 1
      testNapi.updateRetroPadButton(port, keyId, pressed);
      
      // 仅在按下时打印日志,减少日志量
      if (pressed) {
        hilog.info(0xD003, 'TriMorphEmulator', `RetroPad 按键: P${port} Button${keyId}`);
      }
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD003, 'TriMorphEmulator', `输入错误: ${error.message}`);
    }
  }

  build() {
    Stack() {
      // 根据折叠状态显示不同的 UI 布局
      if (this.gameStarted) {
        if (this.currentMode === FoldMode.SINGLE) {
          // 单折态: Phantom Overlay (幽灵悬浮)
          SingleModeLayout({
            xComponentId: this.xComponentId,
            screenAspectRatio: this.emulatorConfig?.aspectRatio || 1.0,  // 动态比例
            onKeyPress: (keyId: number, pressed: boolean) => {
              this.handleInput(keyId, pressed);
            },
            onReset: () => {
              this.resetGame();
            },
            onStop: () => {
              this.stopGame();
            }
          })
        } else if (this.currentMode === FoldMode.DUAL) {
          // 双折态: Digital GameBoy (虚拟掌机)
          DualModeLayout({
            xComponentId: this.xComponentId,
            screenAspectRatio: this.emulatorConfig?.aspectRatio || 1.0,  // 动态比例
            onKeyPress: (keyId: number, pressed: boolean) => {
              this.handleInput(keyId, pressed);
            },
            onReset: () => {
              this.resetGame();
            },
            onStop: () => {
              this.stopGame();
            }
          })
        } else {
          // 三折态: Switch Layout (分体手柄)
          TripleModeLayout({
            xComponentId: this.xComponentId,
            screenAspectRatio: this.emulatorConfig?.aspectRatio || 1.0,  // 动态比例
            onKeyPress: (keyId: number, pressed: boolean) => {
              this.handleInput(keyId, pressed);
            },
            onReset: () => {
              this.resetGame();
            },
            onStop: () => {
              this.stopGame();
            },
            fps: this.fps,
            cpuUsage: this.cpuUsage
          })
        }
      } else {
        // 未开始时显示启动界面
        Column() {
          Text(this.message)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ bottom: 20 })
          
          Text('🎮 三态变形模拟器')
            .fontSize(20)
            .fontColor('#00FF00')
            .margin({ bottom: 10 })
          
          Text(`当前模式: ${this.currentMode}`)
            .fontSize(16)
            .fontColor('#888888')
            .margin({ bottom: 30 })
          
          Button('🚀 开始游戏')
            .width(220)
            .height(70)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#27ae60')
            .borderRadius(35)
            .onClick(() => {
              this.startGame();
            })
          
          Text('自适应沉浸式体验')
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 10 })
          
          // 返回 Canvas 版本按钮
          Button('📊 Canvas 版本')
            .width(140)
            .height(50)
            .fontSize(16)
            .backgroundColor('#34495e')
            .borderRadius(25)
            .margin({ top: 30 })
            .onClick(() => {
              this.getUIContext().getRouter().back();
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#1a1a1a')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .transition({
      type: TransitionType.All,
      opacity: 1
    })
    .animation({
      duration: 300,
      curve: Curve.EaseInOut
    })
  }
}
