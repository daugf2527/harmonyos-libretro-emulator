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
        Row() {
          Button('产品入口：导入主页')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#00FF41')
            .fontColor('#000000')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/ImportEntryPage'
              }).catch((err: Error) => {
                console.error(`[Index] Router error: ${err.message}`);
              });
            })
        }
        .margin({ top: 10 })
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // Onboarding 引导页按钮
        Row() {
          Button('Onboarding 引导页')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#00A651')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/OnboardingPage'
              }).catch((err: Error) => {
                console.error(`[Index] Router error: ${err.message}`);
              });
            })
        }
        .margin({ top: 10 })
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // 导入任务反馈页（1:1 还原）
        Row() {
          Button('导入任务反馈页（1:1）')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#111111')
            .fontColor('#00FF41')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/ImportTaskOverlayPage'
              }).catch((err: Error) => {
                console.error(`[Index] Router error: ${err.message}`);
              });
            })
        }
        .margin({ top: 10 })
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // Gambatte 测试按钮
        Row() {
          Button('测试 Gambatte 核心')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#FF6B35')
            .onClick(() => {
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
          Button('通用 Libretro 游戏')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#4CAF50')
            .onClick(() => {
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
          Button('新架构测试')
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

        Row() {
          Button('产品入口：游戏库')
            .fontSize(18)
            .width('80%')
            .height(60)
            .backgroundColor('#0A0A0A')
            .fontColor('#00FF41')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/LibraryPage'
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
