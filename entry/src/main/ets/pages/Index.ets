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
import LogHelper from '../common/LogHelper'

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/LibraryPage'
    }).catch((err: Error) => {
      LogHelper.error('Index', 'Route', `Router error: ${err.message}`)
    })
  }

  build() {
    Column() {
      Text('碳影')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#00FF41')
      Text('正在打开游戏库')
        .fontSize(14)
        .fontColor('#FF9EA7AD')
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FF000000')
  }
}
