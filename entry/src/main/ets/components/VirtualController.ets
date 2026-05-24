/*
 * 虚拟游戏控制器组件
 * 提供可复用的 D-Pad 和 ABXY 按键
 * 支持触觉反馈和透明度调节
 */

import { vibrator } from '@kit.SensorServiceKit';
import LogHelper from '../common/LogHelper';
import { EmuTypography } from '../common/EmuUiTokens'

// 按键 ID 定义 (Libretro 标准)
export const RETRO_DEVICE_ID_JOYPAD_B = 0;
export const RETRO_DEVICE_ID_JOYPAD_Y = 1;
export const RETRO_DEVICE_ID_JOYPAD_SELECT = 2;
export const RETRO_DEVICE_ID_JOYPAD_START = 3;
export const RETRO_DEVICE_ID_JOYPAD_UP = 4;
export const RETRO_DEVICE_ID_JOYPAD_DOWN = 5;
export const RETRO_DEVICE_ID_JOYPAD_LEFT = 6;
export const RETRO_DEVICE_ID_JOYPAD_RIGHT = 7;
export const RETRO_DEVICE_ID_JOYPAD_A = 8;
export const RETRO_DEVICE_ID_JOYPAD_X = 9;
export const RETRO_DEVICE_ID_JOYPAD_L = 10;
export const RETRO_DEVICE_ID_JOYPAD_R = 11;

// 触觉反馈辅助函数
function triggerHaptic(duration: number = 10) {
  try {
    vibrator.startVibration({
      type: 'time',
      duration: duration
    }, {
      usage: 'touch'
    }, (error) => {
      if (error) {
        LogHelper.error('VirtualController', 'Input', `振动失败: ${error.message}`, 0xD004);
      }
    });
  } catch (e) {
    LogHelper.error('VirtualController', 'Input', `振动异常: ${(e as Error).message}`, 0xD004);
  }
}

// D-Pad 组件 (十字键)
@Component
export struct DPadControl {
  // 回调函数
  onKeyPress?: (keyId: number, pressed: boolean) => void;
  // 样式配置
  @Prop buttonSize: number = 70;
  @Prop buttonOpacity: number = 1.0;
  @Prop buttonColor: string = '#2c3e50';
  @Prop iconColor: string = '#FFFFFF';
  @Prop isTransparent: boolean = false;  // 透明模式 (单折态)

  build() {
    Column() {
      // 上键
      Column() {
        this.DirectionButton('▲', RETRO_DEVICE_ID_JOYPAD_UP)
      }
      .margin({ bottom: 8 })
      
      Row() {
        // 左键
        Column() {
          this.DirectionButton('←', RETRO_DEVICE_ID_JOYPAD_LEFT)
        }
        .margin({ right: 8 })
        
        // 下键
        Column() {
          this.DirectionButton('▼', RETRO_DEVICE_ID_JOYPAD_DOWN)
        }
        .margin({ right: 8 })
        
        // 右键
        this.DirectionButton('→', RETRO_DEVICE_ID_JOYPAD_RIGHT)
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  DirectionButton(icon: string, keyId: number) {
    Button() {
      Text(icon)
        .fontSize(EmuTypography.display)
        .fontColor(this.isTransparent ? Color.White : this.iconColor)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .backgroundColor(this.isTransparent ? Color.Transparent : this.buttonColor)
    .border(this.isTransparent ? {
      width: 2,
      color: Color.White,
      style: BorderStyle.Solid
    } : undefined)
    .borderRadius(this.buttonSize / 2)
    .opacity(this.buttonOpacity)
    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        triggerHaptic(10);
        this.onKeyPress?.(keyId, true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onKeyPress?.(keyId, false);
      }
    })
  }
}

// 模拟摇杆组件
@Component
export struct AnalogStickControl {
  onAnalogChange?: (index: number, x: number, y: number, active: boolean) => void;
  @Prop index: number = 0;
  @Prop baseSize: number = 140;
  @Prop knobSize: number = 60;
  @Prop deadZone: number = 0.08;
  @Prop baseColor: string = '#263238';
  @Prop ringColor: string = '#546E7A';
  @Prop knobColor: string = '#90A4AE';

  @State knobOffsetX: number = 0;
  @State knobOffsetY: number = 0;

  build() {
    Stack() {
      Row() {
      }
        .width(this.baseSize)
        .height(this.baseSize)
        .backgroundColor(this.baseColor)
        .border({
          width: 2,
          color: this.ringColor,
          style: BorderStyle.Solid
        })
        .borderRadius(this.baseSize / 2)

      Row() {
      }
        .width(this.knobSize)
        .height(this.knobSize)
        .backgroundColor(this.knobColor)
        .borderRadius(this.knobSize / 2)
        .position({
          x: this.baseSize / 2 - this.knobSize / 2,
          y: this.baseSize / 2 - this.knobSize / 2
        })
        .translate({ x: this.knobOffsetX, y: this.knobOffsetY })
    }
    .width(this.baseSize)
    .height(this.baseSize)
    .onTouch((event) => {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.resetStick();
        return;
      }
      if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
        return;
      }
      const point = (event.touches && event.touches.length > 0) ?
        event.touches[0] :
        (event.changedTouches && event.changedTouches.length > 0 ?
          event.changedTouches[0] : undefined);
      if (!point) {
        return;
      }
      this.updateFromPoint(point.x, point.y);
    })
  }

  private updateFromPoint(x: number, y: number) {
    const center = this.baseSize / 2;
    const maxOffset = (this.baseSize - this.knobSize) / 2;
    if (maxOffset <= 0) {
      return;
    }

    let dx = x - center;
    let dy = y - center;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > maxOffset && dist > 0) {
      const scale = maxOffset / dist;
      dx *= scale;
      dy *= scale;
    }

    this.knobOffsetX = dx;
    this.knobOffsetY = dy;

    let normX = dx / maxOffset;
    let normY = dy / maxOffset;
    if (Math.abs(normX) < this.deadZone) {
      normX = 0;
    }
    if (Math.abs(normY) < this.deadZone) {
      normY = 0;
    }
    this.onAnalogChange?.(this.index, normX, normY, true);
  }

  private resetStick() {
    this.knobOffsetX = 0;
    this.knobOffsetY = 0;
    this.onAnalogChange?.(this.index, 0, 0, false);
  }
}

// ABXY 按钮组件
@Component
export struct ABXYControl {
  // 回调函数
  onKeyPress?: (keyId: number, pressed: boolean) => void;
  // 样式配置
  @Prop buttonSize: number = 70;
  @Prop buttonOpacity: number = 1.0;
  @Prop isTransparent: boolean = false;

  build() {
    Stack() {
      // Y 键 (上)
      Column() {
        this.ActionButton('Y', RETRO_DEVICE_ID_JOYPAD_Y, '#f39c12')
      }
      .position({ x: '50%', y: 0 })
      .translate({ x: '-50%', y: 0 })
      
      // B 键 (右)
      Column() {
        this.ActionButton('B', RETRO_DEVICE_ID_JOYPAD_B, '#e74c3c')
      }
      .position({ x: '100%', y: '50%' })
      .translate({ x: '-100%', y: '-50%' })
      
      // A 键 (下)
      Column() {
        this.ActionButton('A', RETRO_DEVICE_ID_JOYPAD_A, '#27ae60')
      }
      .position({ x: '50%', y: '100%' })
      .translate({ x: '-50%', y: '-100%' })
      
      // X 键 (左)
      Column() {
        this.ActionButton('X', RETRO_DEVICE_ID_JOYPAD_X, '#3498db')
      }
      .position({ x: 0, y: '50%' })
      .translate({ x: 0, y: '-50%' })
    }
    .width(this.buttonSize * 3)
    .height(this.buttonSize * 3)
  }

  @Builder
  ActionButton(label: string, keyId: number, color: string) {
    Button() {
      Text(label)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .backgroundColor(this.isTransparent ? Color.Transparent : color)
    .border(this.isTransparent ? {
      width: 2,
      color: Color.White,
      style: BorderStyle.Solid
    } : undefined)
    .borderRadius(this.buttonSize / 2)
    .opacity(this.buttonOpacity)
    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        triggerHaptic(10);
        this.onKeyPress?.(keyId, true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onKeyPress?.(keyId, false);
      }
    })
  }
}

// Start/Select 按钮组件
@Component
export struct StartSelectControl {
  // 回调函数
  onKeyPress?: (keyId: number, pressed: boolean) => void;
  // 样式配置
  @Prop buttonWidth: number = 90;
  @Prop buttonHeight: number = 50;
  @Prop isVertical: boolean = false;  // 垂直布局 (三折态)

  build() {
    if (this.isVertical) {
      Column({ space: 10 }) {
        this.FunctionButton('START', RETRO_DEVICE_ID_JOYPAD_START, '#e74c3c')
        this.FunctionButton('SELECT', RETRO_DEVICE_ID_JOYPAD_SELECT, '#95a5a6')
      }
    } else {
      Row({ space: 10 }) {
        this.FunctionButton('START', RETRO_DEVICE_ID_JOYPAD_START, '#e74c3c')
        this.FunctionButton('SELECT', RETRO_DEVICE_ID_JOYPAD_SELECT, '#95a5a6')
      }
    }
  }

  @Builder
  FunctionButton(label: string, keyId: number, color: string) {
    Button(label)
      .width(this.buttonWidth)
      .height(this.buttonHeight)
      .fontSize(EmuTypography.lg)
      .fontWeight(FontWeight.Bold)
      .backgroundColor(color)
      .borderRadius(this.buttonHeight / 2)
      .onClick(() => {
        triggerHaptic(15);
        this.onKeyPress?.(keyId, true);
        setTimeout(() => {
          this.onKeyPress?.(keyId, false);
        }, 100);
      })
  }
}

// 系统按钮组件 (Reset/Menu)
@Component
export struct SystemControl {
  // 回调函数
  onReset?: () => void;
  onMenu?: () => void;
  onStop?: () => void;
  // 样式配置
  @Prop buttonWidth: number = 90;
  @Prop buttonHeight: number = 50;
  @Prop showStop: boolean = true;

  build() {
    Row({ space: 10 }) {
      if (this.showStop) {
        Button('停止')
          .width(this.buttonWidth)
          .height(this.buttonHeight)
          .fontSize(EmuTypography.lg)
          .backgroundColor('#95a5a6')
          .borderRadius(this.buttonHeight / 2)
          .onClick(() => {
            triggerHaptic(20);
            this.onStop?.();
          })
      }
      
      Button('重置')
        .width(this.buttonWidth)
        .height(this.buttonHeight)
        .fontSize(EmuTypography.lg)
        .backgroundColor('#3498db')
        .borderRadius(this.buttonHeight / 2)
        .onClick(() => {
          triggerHaptic(20);
          this.onReset?.();
        })
    }
  }
}
