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
import testNapi from 'libentry.so';
import LogHelper from '../common/LogHelper';
import { LibretroEventHub } from '../common/LibretroEventHub';

// 为 NAPI 导出的接口提供明确类型，避免使用 any/unknown
interface LibentryNapi {
  // [NEW_ARCH] 新架构接口
  refactoredPauseEngine?: () => boolean;
  refactoredResumeEngine?: () => boolean;
  refactoredStopEngine?: () => boolean;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onCreate');
    try {
      const ok = LibretroEventHub.getInstance().start();
      LogHelper.info('EntryAbility', 'EventHub', `EventHub start: ok=${ok}`);
    } catch (e) {
      LogHelper.warn('EntryAbility', 'EventHub', 'EventHub start failed');
    }
  }

  onDestroy(): void {
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err, data) => {
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

    const napi: LibentryNapi = testNapi as LibentryNapi;

    // 1. [LEGACY] 前台自动恢复正在运行的 Libretro 游戏

    // 2. [NEW_ARCH] 前台自动恢复新架构引擎
    try {
      const ok = napi.refactoredResumeEngine?.();
      LogHelper.info('EntryAbility', 'Engine', `[NEW_ARCH] 前台自动恢复: ok=${ok}`);
    } catch (e) {
      LogHelper.warn('EntryAbility', 'Engine', '[NEW_ARCH] 前台自动恢复异常');
    }
  }

  onBackground(): void {
    // Ability has back to background
    LogHelper.info('EntryAbility', 'Lifecycle', 'Ability onBackground');

    const napi: LibentryNapi = testNapi as LibentryNapi;

    // 1. [LEGACY] 后台自动暂停正在运行的 Libretro 游戏

    // 2. [NEW_ARCH] 后台自动暂停新架构引擎
    try {
      const ok = napi.refactoredPauseEngine?.();
      LogHelper.info('EntryAbility', 'Engine', `[NEW_ARCH] 后台自动暂停: ok=${ok}`);
    } catch (e) {
      LogHelper.warn('EntryAbility', 'Engine', '[NEW_ARCH] 后台自动暂停异常');
    }
  }
};
