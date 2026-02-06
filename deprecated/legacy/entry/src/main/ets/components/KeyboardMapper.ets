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
import hilog from '@ohos.hilog';

/**
 * 键盘到 RetroPad 的映射组件
 * 
 * 支持两种键盘布局：
 * 1. WASD + IJKL (默认)
 * 2. 方向键 + ZXCV
 */
@Component
export struct KeyboardMapper {
  // 是否启用键盘映射
  @Prop enableKeyboard: boolean = true;
  
  // 键盘布局模式
  @Prop keyboardLayout: 'wasd' | 'arrows' = 'wasd';
  
  // 键盘映射配置
  private keyMappings = {
    // WASD + IJKL 布局 (推荐)
    wasd: {
      // 方向键
      'KeyW': 4,  // Up
      'KeyS': 5,  // Down
      'KeyA': 6,  // Left
      'KeyD': 7,  // Right
      
      // 动作键
      'KeyJ': 0,  // B
      'KeyK': 8,  // A
      'KeyU': 1,  // Y
      'KeyI': 9,  // X
      
      // 肩键
      'KeyQ': 10, // L
      'KeyE': 11, // R
      'Digit1': 12, // L2
      'Digit3': 13, // R2
      
      // 功能键
      'Enter': 3,      // Start
      'ShiftRight': 2  // Select
    },
    
    // 方向键 + ZXCV 布局
    arrows: {
      // 方向键
      'ArrowUp': 4,    // Up
      'ArrowDown': 5,  // Down
      'ArrowLeft': 6,  // Left
      'ArrowRight': 7, // Right
      
      // 动作键
      'KeyZ': 0,  // B
      'KeyX': 8,  // A
      'KeyA': 1,  // Y
      'KeyS': 9,  // X
      
      // 肩键
      'KeyQ': 10, // L
      'KeyW': 11, // R
      'Digit1': 12, // L2
      'Digit2': 13, // R2
      
      // 功能键
      'Enter': 3,      // Start
      'ShiftRight': 2  // Select
    }
  };
  
  // 当前按下的按键
  private pressedKeys: Set<string> = new Set();
  
  aboutToAppear() {
    if (this.enableKeyboard) {
      hilog.info(0xD003, 'KeyboardMapper', '键盘映射已启用，布局: %{public}s', this.keyboardLayout);
    }
  }
  
  build() {
    Stack() {
      // 键盘事件监听器 (透明覆盖层)
      if (this.enableKeyboard) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .focusable(true)
          .onKeyEvent((event: KeyEvent) => {
            this.handleKeyEvent(event);
          })
      }
    }
  }
  
  /**
   * 处理键盘事件
   */
  private handleKeyEvent(event: KeyEvent) {
    const keyCode = event.code;
    const mapping = this.keyMappings[this.keyboardLayout];
    const buttonId = mapping[keyCode];
    
    if (buttonId !== undefined) {
      if (event.type === KeyType.Down) {
        // 按键按下
        if (!this.pressedKeys.has(keyCode)) {
          this.pressedKeys.add(keyCode);
          libentry.updateRetroPadButton(0, buttonId, true);
          hilog.debug(0xD003, 'KeyboardMapper', '按键按下: %{public}s -> Button %{public}d', keyCode, buttonId);
        }
      }
      else if (event.type === KeyType.Up) {
        // 按键释放
        if (this.pressedKeys.has(keyCode)) {
          this.pressedKeys.delete(keyCode);
          libentry.updateRetroPadButton(0, buttonId, false);
          hilog.debug(0xD003, 'KeyboardMapper', '按键释放: %{public}s -> Button %{public}d', keyCode, buttonId);
        }
      }
    }
  }
  
  /**
   * 获取当前键盘布局的说明
   */
  getKeyboardLayoutDescription(): string {
    if (this.keyboardLayout === 'wasd') {
      return `
键盘布局 (WASD):
  方向键: W/A/S/D
  动作键: J(B) K(A) U(Y) I(X)
  肩键: Q(L) E(R) 1(L2) 3(R2)
  功能键: Enter(Start) RShift(Select)
      `.trim();
    } else {
      return `
键盘布局 (方向键):
  方向键: ↑/←/↓/→
  动作键: Z(B) X(A) A(Y) S(X)
  肩键: Q(L) W(R) 1(L2) 2(R2)
  功能键: Enter(Start) RShift(Select)
      `.trim();
    }
  }
}
