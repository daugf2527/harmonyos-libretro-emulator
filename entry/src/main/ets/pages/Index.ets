/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
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
@Entry
@Component
struct Index {
  build() {
    Column() {
      // Gambatte 测试按钮
      Row() {
        Button('🔬 测试 Gambatte 核心')
          .fontSize(18)
          .width('80%')
          .height(60)
          .backgroundColor('#FF6B35')
          .onClick(() => {
            // 导航到 Gambatte 测试页面
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/TestGambatte'
            }).catch((err: Error) => {
              console.error(`[Index] Router error: ${err.message}`);
            });
          })
      }
      .margin({ top: 10 })
      .width('100%')
      .justifyContent(FlexAlign.Center)
      
      // 通用 Libretro 游戏页面按钮
      Row() {
        Button('🎮 通用 Libretro 游戏')
          .fontSize(18)
          .width('80%')
          .height(60)
          .backgroundColor('#4CAF50')
          .onClick(() => {
            // 导航到通用 Libretro 游戏页面
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/LibretroGamePage'
            }).catch((err: Error) => {
              console.error(`[Index] Router error: ${err.message}`);
            });
          })
      }
      .margin({ top: 10 })
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 新架构测试页面按钮
      Row() {
        Button('🚀 新架构测试')
          .fontSize(18)
          .width('80%')
          .height(60)
          .backgroundColor('#9C27B0')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/LibretroNewArchTestPage'
            }).catch((err: Error) => {
              console.error(`[Index] Router error: ${err.message}`);
            });
          })
      }
      .margin({ top: 10 })
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
