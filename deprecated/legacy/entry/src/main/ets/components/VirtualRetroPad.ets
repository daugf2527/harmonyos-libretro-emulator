/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import libentry from 'libentry.so';

interface CircleButtonPos {
  x: number;
  y: number;
  radius: number;
}

interface RectButtonPos {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface AnalogStickPos {
  x: number;
  y: number;
  outerRadius: number;
  innerRadius: number;
}

/**
 * 虚拟 RetroPad 手柄组件
 * 
 * 实现 Libretro 标准 RetroPad 接口，支持：
 * - 14 个数字按键 (方向键、动作键、肩键、功能键)
 * - 2 个模拟摇杆 (可选)
 * - 多点触控
 * - 半透明显示
 */
@Component
export struct VirtualRetroPad {
  // 按键状态
  @State private buttonStates: Map<number, boolean> = new Map();
  @State private analogStates: Map<number, [number, number]> = new Map();
  
  // 是否显示虚拟手柄
  @Prop showGamepad: boolean = true;
  
  // 是否显示模拟摇杆
  @Prop showAnalogSticks: boolean = false;
  
  // Canvas 上下文
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  
  // 按键布局配置 (基于 1080p 屏幕)
  private layout = {
    // 十字方向键 (左下角)
    dpad: {
      up: { x: 150, y: 800, radius: 60 },
      down: { x: 150, y: 920, radius: 60 },
      left: { x: 90, y: 860, radius: 60 },
      right: { x: 210, y: 860, radius: 60 }
    },
    
    // 动作键 (右下角)
    actions: {
      B: { x: 930, y: 860, radius: 60 },   // B (右)
      A: { x: 1050, y: 860, radius: 60 },  // A (最右)
      Y: { x: 870, y: 800, radius: 60 },   // Y (上)
      X: { x: 870, y: 920, radius: 60 }    // X (下)
    },
    
    // 肩键 (顶部)
    shoulders: {
      L: { x: 50, y: 100, width: 180, height: 60 },
      R: { x: 850, y: 100, width: 180, height: 60 },
      L2: { x: 50, y: 40, width: 180, height: 50 },
      R2: { x: 850, y: 40, width: 180, height: 50 }
    },
    
    // 功能键 (中间)
    system: {
      Select: { x: 400, y: 950, width: 100, height: 50 },
      Start: { x: 580, y: 950, width: 100, height: 50 }
    },
    
    // 模拟摇杆 (可选)
    analogs: {
      left: { x: 350, y: 860, outerRadius: 100, innerRadius: 40 },
      right: { x: 730, y: 860, outerRadius: 100, innerRadius: 40 }
    }
  };
  
  // RetroPad 按键 ID 映射
  private readonly RETRO_DEVICE_ID = {
    B: 0,
    Y: 1,
    Select: 2,
    Start: 3,
    Up: 4,
    Down: 5,
    Left: 6,
    Right: 7,
    A: 8,
    X: 9,
    L: 10,
    R: 11,
    L2: 12,
    R2: 13,
    L3: 14,
    R3: 15
  };
  
  aboutToAppear() {
    // 初始化按键状态
    for (let i = 0; i < 16; i++) {
      this.buttonStates.set(i, false);
    }
    
    // 初始化摇杆状态
    this.analogStates.set(0, [0, 0]); // 左摇杆
    this.analogStates.set(1, [0, 0]); // 右摇杆
  }
  
  build() {
    Stack() {
      // 虚拟按键覆盖层
      if (this.showGamepad) {
        Canvas(this.canvasContext)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onReady(() => {
            this.drawGamepad();
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
      }
    }
  }
  
  /**
   * 绘制虚拟手柄
   */
  private drawGamepad() {
    const ctx = this.canvasContext;
    
    // 清空画布
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    
    // 绘制十字方向键
    this.drawDPad(ctx);
    
    // 绘制动作键
    this.drawActionButtons(ctx);
    
    // 绘制肩键
    this.drawShoulderButtons(ctx);
    
    // 绘制功能键
    this.drawSystemButtons(ctx);
    
    // 绘制模拟摇杆 (可选)
    if (this.showAnalogSticks) {
      this.drawAnalogSticks(ctx);
    }
  }
  
  /**
   * 绘制十字方向键
   */
  private drawDPad(ctx: CanvasRenderingContext2D) {
    const buttons = [
      { name: 'Up', pos: this.layout.dpad.up, label: '↑' },
      { name: 'Down', pos: this.layout.dpad.down, label: '↓' },
      { name: 'Left', pos: this.layout.dpad.left, label: '←' },
      { name: 'Right', pos: this.layout.dpad.right, label: '→' }
    ];
    
    buttons.forEach(btn => {
      const id = this.RETRO_DEVICE_ID[btn.name];
      const pressed = this.buttonStates.get(id) || false;
      
      // 绘制圆形按键
      ctx.beginPath();
      ctx.arc(btn.pos.x, btn.pos.y, btn.pos.radius, 0, Math.PI * 2);
      ctx.fillStyle = pressed ? 'rgba(255, 255, 255, 0.6)' : 'rgba(255, 255, 255, 0.3)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
      ctx.lineWidth = 3;
      ctx.stroke();
      
      // 绘制标签
      ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
      ctx.font = '32px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(btn.label, btn.pos.x, btn.pos.y);
    });
  }
  
  /**
   * 绘制动作键
   */
  private drawActionButtons(ctx: CanvasRenderingContext2D) {
    const buttons = [
      { name: 'A', pos: this.layout.actions.A, label: 'A' },
      { name: 'B', pos: this.layout.actions.B, label: 'B' },
      { name: 'X', pos: this.layout.actions.X, label: 'X' },
      { name: 'Y', pos: this.layout.actions.Y, label: 'Y' }
    ];
    
    buttons.forEach(btn => {
      const id = this.RETRO_DEVICE_ID[btn.name];
      const pressed = this.buttonStates.get(id) || false;
      
      // 绘制圆形按键
      ctx.beginPath();
      ctx.arc(btn.pos.x, btn.pos.y, btn.pos.radius, 0, Math.PI * 2);
      ctx.fillStyle = pressed ? 'rgba(255, 100, 100, 0.6)' : 'rgba(255, 100, 100, 0.3)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 100, 100, 0.8)';
      ctx.lineWidth = 3;
      ctx.stroke();
      
      // 绘制标签
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.font = 'bold 28px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(btn.label, btn.pos.x, btn.pos.y);
    });
  }
  
  /**
   * 绘制肩键
   */
  private drawShoulderButtons(ctx: CanvasRenderingContext2D) {
    const buttons = [
      { name: 'L', pos: this.layout.shoulders.L, label: 'L' },
      { name: 'R', pos: this.layout.shoulders.R, label: 'R' },
      { name: 'L2', pos: this.layout.shoulders.L2, label: 'L2' },
      { name: 'R2', pos: this.layout.shoulders.R2, label: 'R2' }
    ];
    
    buttons.forEach(btn => {
      const id = this.RETRO_DEVICE_ID[btn.name];
      const pressed = this.buttonStates.get(id) || false;
      
      // 绘制矩形按键
      ctx.fillStyle = pressed ? 'rgba(100, 150, 255, 0.6)' : 'rgba(100, 150, 255, 0.3)';
      ctx.fillRect(btn.pos.x, btn.pos.y, btn.pos.width, btn.pos.height);
      ctx.strokeStyle = 'rgba(100, 150, 255, 0.8)';
      ctx.lineWidth = 3;
      ctx.strokeRect(btn.pos.x, btn.pos.y, btn.pos.width, btn.pos.height);
      
      // 绘制标签
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.font = 'bold 24px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(btn.label, btn.pos.x + btn.pos.width / 2, btn.pos.y + btn.pos.height / 2);
    });
  }
  
  /**
   * 绘制功能键
   */
  private drawSystemButtons(ctx: CanvasRenderingContext2D) {
    const buttons = [
      { name: 'Select', pos: this.layout.system.Select, label: 'SELECT' },
      { name: 'Start', pos: this.layout.system.Start, label: 'START' }
    ];
    
    buttons.forEach(btn => {
      const id = this.RETRO_DEVICE_ID[btn.name];
      const pressed = this.buttonStates.get(id) || false;
      
      // 绘制矩形按键
      ctx.fillStyle = pressed ? 'rgba(150, 150, 150, 0.6)' : 'rgba(150, 150, 150, 0.3)';
      ctx.fillRect(btn.pos.x, btn.pos.y, btn.pos.width, btn.pos.height);
      ctx.strokeStyle = 'rgba(150, 150, 150, 0.8)';
      ctx.lineWidth = 2;
      ctx.strokeRect(btn.pos.x, btn.pos.y, btn.pos.width, btn.pos.height);
      
      // 绘制标签
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.font = 'bold 16px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(btn.label, btn.pos.x + btn.pos.width / 2, btn.pos.y + btn.pos.height / 2);
    });
  }
  
  /**
   * 绘制模拟摇杆
   */
  private drawAnalogSticks(ctx: CanvasRenderingContext2D) {
    const sticks = [
      { index: 0, pos: this.layout.analogs.left },
      { index: 1, pos: this.layout.analogs.right }
    ];
    
    sticks.forEach(stick => {
      const [x, y] = this.analogStates.get(stick.index) || [0, 0];
      
      // 绘制外圈
      ctx.beginPath();
      ctx.arc(stick.pos.x, stick.pos.y, stick.pos.outerRadius, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(100, 100, 100, 0.3)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(100, 100, 100, 0.6)';
      ctx.lineWidth = 2;
      ctx.stroke();
      
      // 计算摇杆位置
      const stickX = stick.pos.x + (x / 32767) * (stick.pos.outerRadius - stick.pos.innerRadius);
      const stickY = stick.pos.y + (y / 32767) * (stick.pos.outerRadius - stick.pos.innerRadius);
      
      // 绘制摇杆
      ctx.beginPath();
      ctx.arc(stickX, stickY, stick.pos.innerRadius, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(200, 200, 200, 0.7)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
      ctx.lineWidth = 3;
      ctx.stroke();
    });
  }
  
  /**
   * 处理触摸事件
   */
  private handleTouch(event: TouchEvent) {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      // 处理多点触控
      const activeTouches = new Set<number>();
      
      for (let i = 0; i < event.touches.length; i++) {
        const touch = event.touches[i];
        
        // 检测数字按键
        const button = this.detectButton(touch.x, touch.y);
        if (button !== null) {
          activeTouches.add(button);
          if (!this.buttonStates.get(button)) {
            this.buttonStates.set(button, true);
            libentry.updateRetroPadButton(0, button, true);
          }
        }
        
        // 检测模拟摇杆
        if (this.showAnalogSticks) {
          const analog = this.detectAnalog(touch.x, touch.y);
          if (analog !== null) {
            const [index, normX, normY] = analog;
            this.analogStates.set(index, [normX, normY]);
            libentry.updateRetroPadAnalog(0, index * 2, normX);
            libentry.updateRetroPadAnalog(0, index * 2 + 1, normY);
          }
        }
      }
      
      // 释放未触摸的按键
      this.buttonStates.forEach((pressed, button) => {
        if (pressed && !activeTouches.has(button)) {
          this.buttonStates.set(button, false);
          libentry.updateRetroPadButton(0, button, false);
        }
      });
      
      // 重绘
      this.drawGamepad();
    }
    else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      // 释放所有按键
      this.buttonStates.forEach((pressed, button) => {
        if (pressed) {
          this.buttonStates.set(button, false);
          libentry.updateRetroPadButton(0, button, false);
        }
      });
      
      // 重置摇杆
      if (this.showAnalogSticks) {
        this.analogStates.set(0, [0, 0]);
        this.analogStates.set(1, [0, 0]);
        libentry.updateRetroPadAnalog(0, 0, 0);
        libentry.updateRetroPadAnalog(0, 1, 0);
        libentry.updateRetroPadAnalog(0, 2, 0);
        libentry.updateRetroPadAnalog(0, 3, 0);
      }
      
      // 重绘
      this.drawGamepad();
    }
  }
  
  /**
   * 检测按键碰撞
   */
  private detectButton(x: number, y: number): number | null {
    // 检测圆形按键
    const checkCircle = (pos: CircleButtonPos, id: number): number | null => {
      const dx = x - pos.x;
      const dy = y - pos.y;
      return dx * dx + dy * dy <= pos.radius * pos.radius ? id : null;
    };
    
    // 检测矩形按键
    const checkRect = (pos: RectButtonPos, id: number): number | null => {
      return x >= pos.x && x <= pos.x + pos.width &&
             y >= pos.y && y <= pos.y + pos.height ? id : null;
    };
    
    // 检测所有按键 (按优先级)
    const checks = [
      // 十字方向键
      checkCircle(this.layout.dpad.up, this.RETRO_DEVICE_ID.Up),
      checkCircle(this.layout.dpad.down, this.RETRO_DEVICE_ID.Down),
      checkCircle(this.layout.dpad.left, this.RETRO_DEVICE_ID.Left),
      checkCircle(this.layout.dpad.right, this.RETRO_DEVICE_ID.Right),
      
      // 动作键
      checkCircle(this.layout.actions.A, this.RETRO_DEVICE_ID.A),
      checkCircle(this.layout.actions.B, this.RETRO_DEVICE_ID.B),
      checkCircle(this.layout.actions.X, this.RETRO_DEVICE_ID.X),
      checkCircle(this.layout.actions.Y, this.RETRO_DEVICE_ID.Y),
      
      // 肩键
      checkRect(this.layout.shoulders.L, this.RETRO_DEVICE_ID.L),
      checkRect(this.layout.shoulders.R, this.RETRO_DEVICE_ID.R),
      checkRect(this.layout.shoulders.L2, this.RETRO_DEVICE_ID.L2),
      checkRect(this.layout.shoulders.R2, this.RETRO_DEVICE_ID.R2),
      
      // 功能键
      checkRect(this.layout.system.Start, this.RETRO_DEVICE_ID.Start),
      checkRect(this.layout.system.Select, this.RETRO_DEVICE_ID.Select)
    ];
    
    for (const result of checks) {
      if (result !== null) return result;
    }
    
    return null;
  }
  
  /**
   * 检测模拟摇杆
   */
  private detectAnalog(x: number, y: number): [number, number, number] | null {
    const checkAnalog = (pos: AnalogStickPos, index: number): [number, number, number] | null => {
      const dx = x - pos.x;
      const dy = y - pos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      
      if (dist <= pos.outerRadius) {
        // 限制在外圈内
        const maxDist = pos.outerRadius - pos.innerRadius;
        const clampedDist = Math.min(dist, maxDist);
        
        // 归一化到 -32767 ~ 32767
        const normX = Math.round((dx / maxDist) * 32767);
        const normY = Math.round((dy / maxDist) * 32767);
        
        return [index, normX, normY];
      }
      return null;
    };
    
    return checkAnalog(this.layout.analogs.left, 0) ||
           checkAnalog(this.layout.analogs.right, 1);
  }
}
