/*
 * Phase 3.2 - 2048 游戏页面
 * 实现 Libretro 视频桥接 (Canvas 渲染)
 * 
 * 参考: /Users/asd/NativeSoIntegration/entry/src/main/ets/pages/Game2048.ets
 */

import testNapi, { type FrameData } from 'libentry.so';
import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { LengthMetricsUnit } from '@ohos.arkui.node';

// 按键 ID 定义 (Libretro 标准)
const KEY_UP = 4;     // RETRO_DEVICE_ID_JOYPAD_UP
const KEY_DOWN = 5;   // RETRO_DEVICE_ID_JOYPAD_DOWN
const KEY_LEFT = 6;   // RETRO_DEVICE_ID_JOYPAD_LEFT
const KEY_RIGHT = 7;  // RETRO_DEVICE_ID_JOYPAD_RIGHT
const KEY_START = 3;  // RETRO_DEVICE_ID_JOYPAD_START

@Entry
@Component
struct Game2048 {
  @State message: string = '2048 游戏';
  @State gameStarted: boolean = false;
  @State frameData: ArrayBuffer | null = null;
  @State frameWidth: number = 0;
  @State frameHeight: number = 0;
  private intervalId: number = -1;
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private renderCount: number = 0;

  aboutToAppear() {
    hilog.info(0xD002, 'Game2048', '页面加载');
  }

  aboutToDisappear() {
    this.stopGame();
  }

  // 启动游戏
  startGame() {
    hilog.info(0xD002, 'Game2048', '=== 启动游戏 ===');
    
    // 先设置 gameStarted 以显示 Canvas
    this.gameStarted = true;
    this.message = '正在初始化...';
    
    // 延迟初始化,等待 Canvas 准备好
    setTimeout(() => {
      // 获取 SO 库路径
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const soPath = context.bundleCodeDir + '/libs/arm64/libretro_2048.so';
      hilog.info(0xD002, 'Game2048', `SO 路径: ${soPath}`);
      
      // 初始化游戏
      try {
        const success = testNapi.initGame(soPath);
        hilog.info(0xD002, 'Game2048', `游戏初始化: ${success}`);
        
        if (success) {
          this.message = '游戏运行中...';
          
          // 启动游戏循环 (30 FPS)
          this.intervalId = setInterval(() => {
            this.runGameFrame();
          }, 1000 / 30);
        } else {
          this.message = '游戏初始化失败';
          this.gameStarted = false;
        }
      } catch (e) {
        const error = e as Error;
        hilog.error(0xD002, 'Game2048', `错误: ${error.message}`);
        this.message = `错误: ${error.message}`;
        this.gameStarted = false;
      }
    }, 100); // 等待 100ms 让 Canvas 准备好
  }

  // 运行一帧
  runGameFrame() {
    try {
      const frame = testNapi.runFrame();
      if (frame) {
        this.frameWidth = frame.width;
        this.frameHeight = frame.height;
        this.frameData = frame.data;
        
        // 第一次获取帧时打印信息
        if (this.renderCount === 0) {
          hilog.info(0xD002, 'Game2048', `首帧: ${frame.width}x${frame.height}, 数据: ${frame.data.byteLength} 字节`);
        }
        
        // 渲染到 Canvas
        this.renderFrame(frame);
      }
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD002, 'Game2048', `运行帧错误: ${error.message}`);
    }
  }

  // 渲染帧到 Canvas
  renderFrame(frame: FrameData) {
    try {
      // 打印详细调试信息 (仅首帧)
      if (this.renderCount === 0) {
        hilog.info(0xD002, 'Game2048', '========== 首帧渲染调试信息 ==========');
        hilog.info(0xD002, 'Game2048', 
          `Canvas 尺寸: ${this.canvasContext.width}x${this.canvasContext.height}, 帧尺寸: ${frame.width}x${frame.height}`);
        hilog.info(0xD002, 'Game2048', `帧数据大小: ${frame.data.byteLength} 字节`);
      }
      
      // 先清空画布
      this.canvasContext.clearRect(0, 0, this.canvasContext.width, this.canvasContext.height);
      
      // ========== 像素格式转换: XRGB8888 → RGBA8888 ==========
      let pixelCount = frame.width * frame.height;
      let rgbaData = new Uint8ClampedArray(pixelCount * 4);
      let srcData = new Uint8ClampedArray(frame.data);
      
      // 逐像素转换 (交换 R 和 B)
      for (let i = 0; i < pixelCount; i++) {
        let srcIdx = i * 4;
        let dstIdx = i * 4;
        
        // XRGB8888: [B, G, R, X] → RGBA8888: [R, G, B, A]
        rgbaData[dstIdx + 0] = srcData[srcIdx + 2]; // R
        rgbaData[dstIdx + 1] = srcData[srcIdx + 1]; // G
        rgbaData[dstIdx + 2] = srcData[srcIdx + 0]; // B
        rgbaData[dstIdx + 3] = 255;                 // A
      }
      
      // ========== 创建 ImageData ==========
      let imageData = new ImageData(
        frame.width, 
        frame.height, 
        rgbaData, 
        LengthMetricsUnit.PX
      );
      
      // ========== 计算缩放和居中 ==========
      // 保持宽高比,尽可能放大游戏画面
      let canvasWidth = this.canvasContext.width;
      let canvasHeight = this.canvasContext.height;
      let scaleX = canvasWidth / frame.width;
      let scaleY = canvasHeight / frame.height;
      let scale = Math.min(scaleX, scaleY);  // 保持宽高比
      
      let scaledWidth = frame.width * scale;
      let scaledHeight = frame.height * scale;
      let offsetX = (canvasWidth - scaledWidth) / 2;
      let offsetY = (canvasHeight - scaledHeight) / 2;
      
      // 绘制黑色背景
      this.canvasContext.fillStyle = '#000000';
      this.canvasContext.fillRect(0, 0, canvasWidth, canvasHeight);
      
      // 保存当前状态
      this.canvasContext.save();
      
      // 设置缩放和偏移
      this.canvasContext.translate(offsetX, offsetY);
      this.canvasContext.scale(scale, scale);
      
      // 使用 putImageData 绘制 (不支持缩放,所以用 transform)
      this.canvasContext.putImageData(imageData, 0, 0);
      
      // 恢复状态
      this.canvasContext.restore();
      
      // 每30帧打印一次确认
      if (this.renderCount++ % 30 === 0) {
        hilog.info(0xD002, 'Game2048', `✅ 已渲染 ${this.renderCount} 帧 (缩放: ${scale.toFixed(2)}x)`);
      }
    } catch (e) {
      let error = e as Error;
      hilog.error(0xD002, 'Game2048', `渲染错误: ${error.message}`);
    }
  }

  // 处理按键输入
  handleInput(keyId: number, pressed: boolean) {
    try {
      testNapi.setInput(keyId, pressed);
      hilog.info(0xD002, 'Game2048', `按键: ${keyId}, 按下: ${pressed}`);
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD002, 'Game2048', `输入错误: ${error.message}`);
    }
  }

  // 停止游戏
  stopGame() {
    hilog.info(0xD002, 'Game2048', '=== 停止游戏 ===');
    
    if (this.intervalId !== -1) {
      clearInterval(this.intervalId);
      this.intervalId = -1;
    }
    
    try {
      testNapi.deinitGame();
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD002, 'Game2048', `清理错误: ${error.message}`);
    }
    
    this.gameStarted = false;
    this.message = '游戏已停止';
  }

  // 重置游戏
  resetGame() {
    hilog.info(0xD002, 'Game2048', '=== 重置游戏 ===');
    
    try {
      testNapi.resetGame();
      this.message = '游戏已重置';
    } catch (e) {
      const error = e as Error;
      hilog.error(0xD002, 'Game2048', `重置错误: ${error.message}`);
    }
  }

  build() {
    Column() {
      // 游戏画布 - 占据大部分屏幕
      if (this.gameStarted) {
        Canvas(this.canvasContext)
          .width('100%')
          .height('55%')  // 占据 55% 屏幕高度
          .backgroundColor('#000000')
          .onReady(() => {
            hilog.info(0xD002, 'Game2048', `Canvas onReady: ${this.canvasContext.width}x${this.canvasContext.height}`);
          })
      } else {
        // 未开始时显示占位区域
        Column() {
          Text(this.message)
            .fontSize(24)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('55%')
        .backgroundColor('#1a1a1a')
        .justifyContent(FlexAlign.Center)
      }

      // 游戏控制区 - 参考任天堂/索尼布局
      if (this.gameStarted) {
        Row() {
          // 左侧: 方向键 (十字键布局)
          Column() {
            // 上键
            Button() {
              Text('▲')
                .fontSize(28)
                .fontColor('#FFFFFF')
            }
            .width(70)
            .height(70)
            .backgroundColor('#2c3e50')
            .borderRadius(35)
            .margin({ bottom: 8 })
            .onTouch((event) => {
              if (event.type === TouchType.Down) {
                this.handleInput(KEY_UP, true);
              } else if (event.type === TouchType.Up) {
                this.handleInput(KEY_UP, false);
              }
            })
            
            Row() {
              // 左键
              Button() {
                Text('◀')
                  .fontSize(28)
                  .fontColor('#FFFFFF')
              }
              .width(70)
              .height(70)
              .backgroundColor('#2c3e50')
              .borderRadius(35)
              .margin({ right: 8 })
              .onTouch((event) => {
                if (event.type === TouchType.Down) {
                  this.handleInput(KEY_LEFT, true);
                } else if (event.type === TouchType.Up) {
                  this.handleInput(KEY_LEFT, false);
                }
              })
              
              // 下键
              Button() {
                Text('▼')
                  .fontSize(28)
                  .fontColor('#FFFFFF')
              }
              .width(70)
              .height(70)
              .backgroundColor('#2c3e50')
              .borderRadius(35)
              .margin({ right: 8 })
              .onTouch((event) => {
                if (event.type === TouchType.Down) {
                  this.handleInput(KEY_DOWN, true);
                } else if (event.type === TouchType.Up) {
                  this.handleInput(KEY_DOWN, false);
                }
              })
              
              // 右键
              Button() {
                Text('▶')
                  .fontSize(28)
                  .fontColor('#FFFFFF')
              }
              .width(70)
              .height(70)
              .backgroundColor('#2c3e50')
              .borderRadius(35)
              .onTouch((event) => {
                if (event.type === TouchType.Down) {
                  this.handleInput(KEY_RIGHT, true);
                } else if (event.type === TouchType.Up) {
                  this.handleInput(KEY_RIGHT, false);
                }
              })
            }
          }
          .width('40%')
          .justifyContent(FlexAlign.Center)
          
          // 右侧: 功能按钮 (类似 A/B/START/SELECT)
          Column() {
            Row() {
              // START 按钮
              Button('START')
                .width(90)
                .height(50)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .backgroundColor('#e74c3c')
                .borderRadius(25)
                .margin({ right: 10 })
                .onClick(() => {
                  this.handleInput(KEY_START, true);
                  setTimeout(() => {
                    this.handleInput(KEY_START, false);
                  }, 100);
                })
              
              // 重置按钮
              Button('RESET')
                .width(90)
                .height(50)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .backgroundColor('#3498db')
                .borderRadius(25)
                .onClick(() => {
                  this.resetGame();
                })
            }
            .margin({ bottom: 15 })
          }
          .width('60%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('35%')
        .padding({ left: 30, right: 30, top: 20 })
        .justifyContent(FlexAlign.SpaceBetween)
      } else {
        // 未开始时显示开始按钮
        Column() {
          Button('🎮 开始游戏')
            .width(200)
            .height(70)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#27ae60')
            .borderRadius(35)
            .onClick(() => {
              this.startGame();
            })
        }
        .width('100%')
        .height('35%')
        .justifyContent(FlexAlign.Center)
      }
      
      // 底部控制栏
      Row() {
        if (this.gameStarted) {
          Button('⏹ 停止')
            .width(120)
            .height(50)
            .fontSize(18)
            .backgroundColor('#95a5a6')
            .borderRadius(25)
            .onClick(() => {
              this.stopGame();
            })
        }
        
        // 切换到 Native 版本按钮
        Button('⚡ Native 版本')
          .width(140)
          .height(50)
          .fontSize(16)
          .backgroundColor('#9b59b6')
          .borderRadius(25)
          .margin({ left: 10 })
          .onClick(() => {
            // 导航到 Native 版本
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/Game2048Native'
            }).catch((err: Error) => {
              hilog.error(0xD002, 'Game2048', `Router error: ${err.message}`);
            });
          })
      }
      .width('100%')
      .height('10%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1a1a1a')
  }
}
