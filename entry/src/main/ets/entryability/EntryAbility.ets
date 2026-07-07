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
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import LogHelper from '../common/LogHelper';
import { LibretroEventHub } from '../common/LibretroEventHub';
import { getInputMappingService } from '../common/InputMappingService';

// REMOVED: import testNapi from 'libentry.so' — eager load caused ~157 MB native
// allocations (168 MB RSS) before page rendering.  The static constructors in
// libentry.so (LibretroEngine, VideoPipeline, AudioBridge, InputManager, etc.)
// made malloc slow under memory pressure, causing APP_INPUT_BLOCK ANRs on
// lightweight pages like OnboardingPage.
//
// libentry.so is now loaded lazily by LibretroGamePage via
// RuntimeSessionController / RuntimeInputCommandBridge imports — only when the
// user actually navigates to the game page.

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onCreate');
    try {
      const ok = LibretroEventHub.getInstance().start();
      LogHelper.info('EntryAbility', 'EventHub', `EventHub start: ok=${ok}`);
      if (!ok) {
        LogHelper.warn('EntryAbility', 'EventHub', 'EventHub 未完成初始化，运行时事件可能缺失');
      }
    } catch (e) {
      const message = (e as Error)?.message || String(e);
      LogHelper.warn('EntryAbility', 'EventHub', `EventHub start failed: ${message}`);
    }

    // Initialize Input Mapping Service (does not trigger libentry.so load)
    void getInputMappingService().initialize(this.context).then(() => {
      LogHelper.info('EntryAbility', 'InputMapping', 'Input Mapping Service initialized');
    }).catch((e: Error) => {
      const message = e?.message || String(e);
      LogHelper.warn('EntryAbility', 'InputMapping', `Input Mapping Service init failed: ${message}`);
    });
  }

  onDestroy(): void {
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onDestroy');
    LibretroEventHub.destroy();  // Audit C-F2: reset singleton so Ability restart re-registers NAPI callback
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onWindowStageCreate');

    // Keep the ability entry on the product library path.
    // LibraryPage internally routes to ImportEntryPage when the library is empty.
    windowStage.loadContent('pages/LibraryPage', (err, data) => {
      if (err.code) {
        LogHelper.error('EntryAbility', 'Lifecycle', `Failed to load the content. Cause: ${JSON.stringify(err) ?? ''}`);
        return;
      }
      LogHelper.info('EntryAbility', 'Lifecycle', `Succeeded in loading the content. Data: ${JSON.stringify(data) ?? ''}`);
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onForeground');
    // Engine pause/resume is handled by LibretroGamePage's lifecycle
    // (aboutToAppear / aboutToDisappear).  libentry.so is loaded lazily
    // when the user navigates to the game page — see imports note above.
  }

  onBackground(): void {
    // Ability has back to background
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onBackground');
    // Engine pause/resume is handled by LibretroGamePage's lifecycle
    // (aboutToAppear / aboutToDisappear).  libentry.so is loaded lazily
    // when the user navigates to the game page — see imports note above.
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    // 内存压力回调（诊断用）：系统内存不足时触发。
    // 模拟器内存大头（ROM / core .so）无法在运行时释放，此回调目前仅做日志。
    // 未来可在此处释放 shader 缓存、降低音频缓冲等不关键资源。
    LogHelper.info('EntryAbility', 'Lifecycle', `onMemoryLevel: ${level}`);
  }
};
