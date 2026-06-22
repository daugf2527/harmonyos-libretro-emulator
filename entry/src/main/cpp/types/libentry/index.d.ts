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

import type { resourceManager } from '@kit.LocalizationKit';

// Phase 3.1 - CoreLoader 测试接口
export const testCoreLoader: (corePath: string) => Promise<string>;

// Phase 1 重构版引擎接口 (独立 C++ 线程)
export interface RefactoredEvent {
  event: string;
  payload: string;
}
/**
 * NAPI 结构化错误返回对象。
 * 对应 C++ engine_napi_common.h 的 MakeErrorResult(env, success, errorCode, message)。
 * 失败时 errorCode 对应 ets/common/ErrorCodes.ets 的 numericCode。
 */
export interface NapiErrorResult {
  success: boolean;
  errorCode?: number;
  message?: string;
}
export const refactoredStartEngine: () => NapiErrorResult;
export const refactoredStopEngine: () => boolean;
export function refactoredStopEngineAsync(): Promise<boolean>;
export const refactoredResetEngine: () => boolean;
export const refactoredPauseEngine: () => boolean;
export const refactoredResumeEngine: () => boolean;
export const refactoredLoadCore: (corePath: string) => NapiErrorResult;
export const refactoredLoadRom: (
  romPath: string,
  resMgr?: resourceManager.ResourceManager
) => NapiErrorResult;
export function refactoredSwitchGameAsync(
  corePath: string,
  romPath: string,
  filesDir: string,
  resMgr?: resourceManager.ResourceManager,
  timeoutMs?: number,
  token?: number,
  progressCallback?: (progress: number, message: string) => void
): Promise<NapiErrorResult>;
export function refactoredSwitchGameAsync(
  corePath: string,
  romPath: string,
  filesDir: string,
  timeoutMs?: number,
  token?: number,
  progressCallback?: (progress: number, message: string) => void
): Promise<NapiErrorResult>;
export const refactoredGetRawFileList: (
  resMgr: resourceManager.ResourceManager,
  dir?: string
) => Array<string>;
export const refactoredGetRawFileListAsync: (
  resMgr: resourceManager.ResourceManager,
  dir?: string
) => Promise<Array<string>>;
export const refactoredInitEventBridge: (callback: (data: RefactoredEvent) => void) => boolean;
export const refactoredSendInput: (port: number, id: number, pressed: boolean) => boolean;
export const refactoredSendAnalog: (port: number, index: number, id: number, value: number) => boolean;
export const refactoredAssignPortSource: (port: number, sourceType: number, deviceId?: string) => boolean;
export const refactoredUnassignPort: (port: number) => boolean;
// 16-bit mask of RETRO_DEVICE_ID_JOYPAD_* declared by the active core via
// RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS. 0 = core hasn't declared, frontend
// should fall back to the full key set.
export const refactoredGetInputDescriptorMask: () => number;
export interface InputDeviceInfo {
  deviceId: string;
  sourceType: number;
  name: string;
}
export const refactoredListInputDevices: () => InputDeviceInfo[];
export const refactoredSendSensor: (port: number, id: number, value: number) => boolean;
export const refactoredGetState: () => number;
export const refactoredWaitForState: (state: number, timeoutMs?: number) => boolean;
export const refactoredWaitForStateAsync: (state: number, timeoutMs?: number) => Promise<boolean>;
export const refactoredCancelSwitch: () => boolean;
export interface EngineErrorInfo {
  reason: string;
  step: string;
  message: string;
}
export const refactoredGetLastErrorInfo: () => EngineErrorInfo;
export const refactoredClearLastErrorInfo: () => boolean;
export const refactoredSetFilesDir: (filesDir: string) => boolean;
export const refactoredSetMinimumAudioLatency: (latencyMs: number) => boolean;
export const refactoredSetAudioSyncMode: (mode: number) => boolean; // 0=NonBlocking, 1=Blocking
export const refactoredSetAudioVolume: (percent: number) => boolean;

// Video Config
export const refactoredSetScalingMode: (mode: number) => boolean; // 0=Hardware, 1=Software, 2=GLES
export const refactoredSetSwapInterval: (interval: number) => boolean; // 0=Disable VSync, 1=Enable VSync
export const refactoredSetSoftwareMaxResolution: (maxWidth: number, maxHeight: number) => boolean;
export const refactoredSetAIUpscale: (enabled: boolean) => boolean;
export const refactoredSetHwRenderAllowed: (enabled: boolean) => boolean;

// SaveState
/** @deprecated T8-B-F3: 同步版阻塞 NAPI/UI 主线程最长 5s, 优先用 refactoredGetSaveStateSizeAsync. */
export const refactoredGetSaveStateSize: () => number;
export const refactoredGetSaveStateSizeAsync: () => Promise<number>;
export interface SaveStateBundleResult {
  stateData: ArrayBuffer;
  thumbnailRgba: ArrayBuffer | null;
  thumbnailWidth: number;
  thumbnailHeight: number;
}
export const refactoredSaveState: () => ArrayBuffer | null;
export const refactoredLoadState: (data: ArrayBuffer) => boolean;
export const refactoredSaveStateAsync: () => Promise<ArrayBuffer | null>;
export const refactoredSaveStateBundleAsync: () => Promise<SaveStateBundleResult>;
export const refactoredLoadStateAsync: (data: ArrayBuffer) => Promise<boolean>;

// SRAM
export const refactoredGetSRAM: () => ArrayBuffer | null;
export const refactoredSetSRAM: (data: ArrayBuffer) => boolean;
export const refactoredGetSRAMAsync: () => Promise<ArrayBuffer | null>;
export const refactoredSetSRAMAsync: (data: ArrayBuffer) => Promise<boolean>;

// Core Control
export const refactoredResetCore: () => boolean;
export const refactoredResetCoreAsync: () => Promise<boolean>;

// Disk Control
export const refactoredDiskControlSetEjectState: (ejected: boolean) => boolean;
export const refactoredDiskControlSetEjectStateAsync: (ejected: boolean) => Promise<boolean>;
export const refactoredDiskControlGetEjectState: () => boolean;
export const refactoredDiskControlGetImageIndex: () => number;
export const refactoredDiskControlSetImageIndex: (index: number) => boolean;
export const refactoredDiskControlSetImageIndexAsync: (index: number) => Promise<boolean>;
export const refactoredDiskControlGetNumImages: () => number;
export interface DiskControlSnapshot {
  ejected: boolean;
  imageIndex: number;
  imageCount: number;
}
export const refactoredDiskControlGetSnapshotAsync: () => Promise<DiskControlSnapshot>;
export const refactoredDiskControlReplaceImageIndex: (index: number, path: string) => boolean;
export const refactoredDiskControlReplaceImageIndexAsync: (index: number, path: string) => Promise<boolean>;
export const refactoredDiskControlAddImageIndex: () => boolean;
export const refactoredDiskControlAddImageIndexAsync: () => Promise<boolean>;

// Cheat
export const refactoredCheatReset: () => boolean;
export const refactoredCheatSet: (index: number, enabled: boolean, code: string) => boolean;
export const refactoredCheatResetAsync: () => Promise<boolean>;
export const refactoredCheatSetAsync: (index: number, enabled: boolean, code: string) => Promise<boolean>;

// Stats
export interface EngineStats {
  videoRefreshCalls: number;
  videoNullFrames: number;
  videoDupeFrames: number;
  videoDroppedFrames: number;
  audioBatchCalls: number;
  audioFramesIn: number;
  nwRequestBufferCalls: number;
  nwRequestBufferFailures: number;
  nwFlushBufferCalls: number;
  nwFlushBufferFailures: number;
  nwAbortBufferCalls: number;
  nbFromWindowBufferFailures: number;
  nbMapFailures: number;
  nbUnmapFailures: number;
  fenceWaitCalls: number;
  fenceWaitFailures: number;
  fenceTimeoutCount: number;
  frameCount: number;
  frameTimeMin: number;
  frameTimeMax: number;
  frameTimeSum: number;
  queuePushed: number;
  queuePopped: number;
  queueDroppedOldest: number;
  queueDroppedStaleOnPop: number;
  queueDepthMax: number;
  renderTickNoFrame: number;
  renderThreadRenderedFrames: number;
  renderThreadDroppedFrames: number;
  vsyncCallbacks: number;
  vsyncFallbackTicks: number;
  vsyncRequestFailures: number;
  audioBufferUsage: number;
  audioUnderruns: number;
  audioOverruns: number;
}
export const refactoredGetStats: () => EngineStats;
export const refactoredResetStats: () => boolean;

export interface InputDebugStats {
  touchCount: number;
  mouseCount: number;
  keyCount: number;
  hasFocus: boolean;
  mouseDown: boolean;
  lastTouchType: number;
  lastMouseAction: number;
  lastKeyAction: number;
}
export const refactoredGetInputDebugStats: () => InputDebugStats;
export const setInputKeyMapping: (mappingMap: Record<string, number>) => boolean;

// Controller/Region
export const refactoredSetControllerPortDevice: (port: number, device: number) => boolean;
export const refactoredGetRegion: () => number;

// AV Info
export interface AVInfo {
  videoWidth: number;
  videoHeight: number;
  fps: number;
  audioSampleRate: number;
}
export const refactoredGetAVInfo: () => AVInfo;

// Options
export const refactoredGetCoreOptions: () => string;
export const refactoredSetCoreOption: (key: string, value: string) => boolean;

// State Query
export const refactoredHasCoreLoaded: () => boolean;
export const refactoredHasGameLoaded: () => boolean;
