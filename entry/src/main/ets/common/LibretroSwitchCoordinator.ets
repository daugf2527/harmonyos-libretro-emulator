import testNapi from 'libentry.so';
import type resourceManager from '@ohos.resourceManager';
import LogHelper from './LogHelper';
import { EngineErrorInfo, EngineState } from './LibretroEventHub';

// NAPI 接口定义 (遵循 AGENTS.md 规范)
interface LibretroNapi {
  refactoredStartEngine(): boolean;
  refactoredStopEngine(): boolean;
  refactoredStopEngineAsync(): boolean;
  refactoredLoadCore(path: string): boolean;
  refactoredLoadRom(
    path: string,
    resMgr?: resourceManager.ResourceManager
  ): boolean;
  refactoredSetFilesDir(path: string): boolean;
  refactoredWaitForState(state: number, timeoutMs?: number): boolean;
  refactoredWaitForStateAsync(
    state: number,
    timeoutMs?: number
  ): Promise<boolean>;
  refactoredGetLastErrorInfo(): EngineErrorInfo;
  refactoredClearLastErrorInfo(): boolean;
}

const nativeApi = testNapi as LibretroNapi;

export interface LibretroSwitchRequest {
  id: string;
  corePath: string;
  romPath: string;
  resMgr: resourceManager.ResourceManager;
  filesDir: string;
  cacheDir?: string;
  timeoutMs?: number;
}

export type LibretroSwitchStep =
  'close_request' |
  'wait_close_complete' |
  'load_core' |
  'load_rom' |
  'start_game';

export interface LibretroSwitchError {
  step: LibretroSwitchStep;
  code: string;
  message: string;
}

export interface LibretroSwitchResult {
  ok: boolean;
  error?: LibretroSwitchError;
}

export default class LibretroSwitchCoordinator {
  private tail: Promise<void> = Promise.resolve();

  enqueueClose(
    id: string,
    timeoutMs: number = 5000
  ): Promise<LibretroSwitchResult> {
    const op = this.tail.then(() => this.performClose(id, timeoutMs));
    this.tail = op.then(() => undefined, () => undefined);
    return op;
  }

  enqueueSwitch(req: LibretroSwitchRequest): Promise<LibretroSwitchResult> {
    const op = this.tail.then(() => this.performSwitch(req));
    this.tail = op.then(() => undefined, () => undefined);
    return op;
  }

  private ok(): LibretroSwitchResult {
    return { ok: true };
  }

  private fail(
    step: LibretroSwitchStep,
    code: string,
    message: string
  ): LibretroSwitchResult {
    return {
      ok: false,
      error: {
        step: step,
        code: code,
        message: message
      }
    };
  }

  private async performClose(
    id: string,
    timeoutMs: number
  ): Promise<LibretroSwitchResult> {
    nativeApi.refactoredStopEngineAsync();
    const ok = await nativeApi.refactoredWaitForStateAsync(
      EngineState.STOPPED,
      timeoutMs
    );
    if (!ok) {
      const message = `Stop timeout: id=${id}`;
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail('wait_close_complete', 'stop_timeout', message);
    }
    return this.ok();
  }

  private async performSwitch(
    req: LibretroSwitchRequest
  ): Promise<LibretroSwitchResult> {
    const timeoutMs = req.timeoutMs ?? 5000;

    const closed = await this.performClose(req.id, timeoutMs);
    if (!closed.ok) {
      return closed;
    }

    nativeApi.refactoredClearLastErrorInfo();

    if (!nativeApi.refactoredStartEngine()) {
      const message = `StartEngine failed`;
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail('start_game', 'start_engine_failed', message);
    }

    if (!nativeApi.refactoredSetFilesDir(req.filesDir)) {
      const message = `SetFilesDir failed: dir=${req.filesDir}`;
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail('load_core', 'set_files_dir_failed', message);
    }

    if (!nativeApi.refactoredLoadCore(req.corePath)) {
      const message = `LoadCore failed: core=${req.corePath}`;
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail('load_core', 'load_core_failed', message);
    }
    const coreLoaded = await nativeApi.refactoredWaitForStateAsync(
      EngineState.CORE_LOADED,
      timeoutMs
    );
    if (!coreLoaded) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const message = this.formatErrorMessage('LoadCore', err);
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail(
        'load_core',
        err.reason || 'load_core_timeout',
        message
      );
    }

    if (req.romPath &&
        !nativeApi.refactoredLoadRom(req.romPath, req.resMgr)) {
      const message = `LoadRom failed: rom=${req.romPath}`;
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail('load_rom', 'load_rom_failed', message);
    }
    const running = await nativeApi.refactoredWaitForStateAsync(
      EngineState.RUNNING,
      timeoutMs
    );
    if (!running) {
      const err = nativeApi.refactoredGetLastErrorInfo();
      const message = this.formatErrorMessage('LoadRom', err);
      LogHelper.error('LibretroSwitch', 'Engine', message);
      return this.fail(
        'load_rom',
        err.reason || 'load_rom_timeout',
        message
      );
    }

    return this.ok();
  }

  private formatErrorMessage(prefix: string, err: EngineErrorInfo): string {
    if (!err || !err.reason) {
      return `${prefix} failed: unknown_error`;
    }
    const step = err.step ? ` step=${err.step}` : '';
    const message = err.message ? ` message=${err.message}` : '';
    return `${prefix} failed: reason=${err.reason}${step}${message}`;
  }
}
