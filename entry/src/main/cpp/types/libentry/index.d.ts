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

// Phase 3.1 - CoreLoader 测试接口
export const testCoreLoader: (corePath: string) => string;

// Phase 1 重构版引擎接口 (独立 C++ 线程)
export interface RefactoredEvent {
  event: string;
  payload: string;
}
export const refactoredStartEngine: () => boolean;
export const refactoredStopEngine: () => boolean;
export const refactoredStopEngineAsync: () => boolean;
export const refactoredResetEngine: () => boolean;
export const refactoredPauseEngine: () => boolean;
export const refactoredResumeEngine: () => boolean;
export const refactoredLoadCore: (corePath: string) => boolean;
export const refactoredLoadRom: (romPath: string, resMgr?: object) => boolean;
export function refactoredSwitchGameAsync(
  corePath: string,
  romPath: string,
  filesDir: string,
  resMgr?: object,
  timeoutMs?: number,
  token?: number
): Promise<boolean>;
export function refactoredSwitchGameAsync(
  corePath: string,
  romPath: string,
  filesDir: string,
  timeoutMs?: number,
  token?: number
): Promise<boolean>;
export const refactoredGetRawFileList: (resMgr: object, dir?: string) => Array<string>;
export const refactoredGetRawFileListAsync: (resMgr: object, dir?: string) => Promise<Array<string>>;
export const refactoredInitEventBridge: (callback: (data: RefactoredEvent) => void) => boolean;
export const refactoredSendInput: (port: number, id: number, pressed: boolean) => boolean;
export const refactoredSendAnalog: (port: number, index: number, id: number, value: number) => boolean;
export const refactoredAssignPortSource: (port: number, sourceType: number, deviceId?: string) => boolean;
export const refactoredUnassignPort: (port: number) => boolean;
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

// Video Config
export const refactoredSetScalingMode: (mode: number) => boolean; // 0=Hardware, 1=Software, 2=GLES
export const refactoredSetSwapInterval: (interval: number) => boolean; // 0=Disable VSync, 1=Enable VSync
export const refactoredSetSoftwareMaxResolution: (maxWidth: number, maxHeight: number) => boolean;
export const refactoredSetAIUpscale: (enabled: boolean) => boolean;
export const refactoredSetHwRenderAllowed: (enabled: boolean) => boolean;

// SaveState
export const refactoredGetSaveStateSize: () => number;
export const refactoredSaveState: () => ArrayBuffer | null;
export const refactoredLoadState: (data: ArrayBuffer) => boolean;

// SRAM
export const refactoredGetSRAM: () => ArrayBuffer | null;
export const refactoredSetSRAM: (data: ArrayBuffer) => boolean;

// Core Control
export const refactoredResetCore: () => boolean;

// Disk Control
export const refactoredDiskControlSetEjectState: (ejected: boolean) => boolean;
export const refactoredDiskControlGetEjectState: () => boolean;
export const refactoredDiskControlGetImageIndex: () => number;
export const refactoredDiskControlSetImageIndex: (index: number) => boolean;
export const refactoredDiskControlGetNumImages: () => number;
export const refactoredDiskControlReplaceImageIndex: (index: number, path: string) => boolean;
export const refactoredDiskControlAddImageIndex: () => boolean;

// Cheat
export const refactoredCheatReset: () => boolean;
export const refactoredCheatSet: (index: number, enabled: boolean, code: string) => boolean;

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
