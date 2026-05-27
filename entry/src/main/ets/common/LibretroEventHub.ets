import testNapi from 'libentry.so';
import LogHelper from './LogHelper';

// NAPI 接口定义 (遵循 AGENTS.md 规范)
interface LibretroNapi {
  refactoredInitEventBridge(callback: (data: RefactoredEvent) => void): boolean;
}

const nativeApi = testNapi as LibretroNapi;

export type EventName =
  'engine_state' |
  'core_crash' |
  'fps_update' |
  'audio_status' |
  'options_update' |
  'pixel_format_update' |
  'geometry_update' |
  'core_message' |
  'disk_control' |
  'rumble' |
  'sensor_state';

export enum EngineState {
  INIT = 0,
  CORE_LOADED = 1,
  GAME_LOADED = 2,
  RUNNING = 3,
  PAUSED = 4,
  STOPPING = 5,
  STOPPED = 6,
  STARTING = 7,
  LOADING = 8,
  ERROR = 9
}

export interface EngineStatePayload {
  state: number;
}

export interface EngineErrorInfo {
  reason: string;
  step: string;
  message: string;
}

export interface CoreCrashPayload {
  reason: string;
  step?: string;
  message?: string;
}

export interface FpsUpdatePayload {
  fps: number;
  dupes?: number;
  nulls?: number;
  drops?: number;
  underruns?: number;
  overruns?: number;
  audioBufferUsage?: number;
}

export interface AudioStatusPayload {
  active: boolean;
  occupancy: number;
  underrun: boolean;
  underruns: number;
  overruns: number;
}

export interface OptionsUpdatePayload {}

export interface PixelFormatPayload {
  format: number;
}

export interface GeometryUpdatePayload {
  base_width: number;
  base_height: number;
  aspect_ratio?: number;
}

export interface CoreMessagePayload {
  msg: string;
  frames?: number;
}

export interface DiskControlPayload {
  type: string;
}

export interface RumblePayload {
  port: number;
  effect: number;
  strength: number;
}

export interface SensorStatePayload {
  port: number;
  action: number;
  rate: number;
}

export type EventPayload =
  EngineStatePayload |
  CoreCrashPayload |
  FpsUpdatePayload |
  AudioStatusPayload |
  OptionsUpdatePayload |
  PixelFormatPayload |
  GeometryUpdatePayload |
  CoreMessagePayload |
  DiskControlPayload |
  RumblePayload |
  SensorStatePayload;

export interface RefactoredEvent {
  event: string;
  payload: string;
}

export interface EventSubscription {
  id: number;
  event: EventName;
}

export interface SubscriptionOptions {
  replayLatest?: boolean;
}

interface EventListener {
  id: number;
  callback: (payload: EventPayload) => void;
}

type PayloadValue = string | number | boolean | null | undefined;

interface RawPayload {
  state?: number | string;
  reason?: string;
  step?: string;
  message?: string;
  fps?: number | string;
  dupes?: number | string;
  nulls?: number | string;
  drops?: number | string;
  underruns?: number | string;
  overruns?: number | string;
  audioBufferUsage?: number | string;
  active?: boolean | number;
  occupancy?: number | string;
  underrun?: boolean | number;
  format?: number | string;
  base_width?: number | string;
  base_height?: number | string;
  aspect_ratio?: number | string;
  msg?: string;
  frames?: number | string;
  type?: string;
  port?: number | string;
  effect?: number | string;
  strength?: number | string;
  action?: number | string;
  rate?: number | string;
}

export class EventHubScope {
  private hub: LibretroEventHub;
  private subscriptions: EventSubscription[] = [];

  constructor(hub: LibretroEventHub) {
    this.hub = hub;
  }

  onEngineState(callback: (payload: EngineStatePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('engine_state', (payload: EventPayload) => {
      callback(payload as EngineStatePayload);
    }, options));
  }

  onCoreCrash(callback: (payload: CoreCrashPayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('core_crash', (payload: EventPayload) => {
      callback(payload as CoreCrashPayload);
    }, options));
  }

  onFpsUpdate(callback: (payload: FpsUpdatePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('fps_update', (payload: EventPayload) => {
      callback(payload as FpsUpdatePayload);
    }, options));
  }

  onAudioStatus(callback: (payload: AudioStatusPayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('audio_status', (payload: EventPayload) => {
      callback(payload as AudioStatusPayload);
    }, options));
  }

  onOptionsUpdate(callback: (payload: OptionsUpdatePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('options_update', (payload: EventPayload) => {
      callback(payload as OptionsUpdatePayload);
    }, options));
  }

  onPixelFormatUpdate(callback: (payload: PixelFormatPayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('pixel_format_update', (payload: EventPayload) => {
      callback(payload as PixelFormatPayload);
    }, options));
  }

  onGeometryUpdate(callback: (payload: GeometryUpdatePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('geometry_update', (payload: EventPayload) => {
      callback(payload as GeometryUpdatePayload);
    }, options));
  }

  onCoreMessage(callback: (payload: CoreMessagePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('core_message', (payload: EventPayload) => {
      callback(payload as CoreMessagePayload);
    }, options));
  }

  onDiskControl(callback: (payload: DiskControlPayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('disk_control', (payload: EventPayload) => {
      callback(payload as DiskControlPayload);
    }, options));
  }

  onRumble(callback: (payload: RumblePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('rumble', (payload: EventPayload) => {
      callback(payload as RumblePayload);
    }, options));
  }

  onSensorState(callback: (payload: SensorStatePayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe('sensor_state', (payload: EventPayload) => {
      callback(payload as SensorStatePayload);
    }, options));
  }

  subscribe(event: EventName, callback: (payload: EventPayload) => void, options?: SubscriptionOptions): EventSubscription {
    return this.addSubscription(this.hub.subscribe(event, callback, options));
  }

  private addSubscription(sub: EventSubscription): EventSubscription {
    this.subscriptions.push(sub);
    return sub;
  }

  dispose(): void {
    this.subscriptions.forEach(sub => this.hub.unsubscribe(sub));
    this.subscriptions = [];
  }
}

export class LibretroEventHub {
  private static instance: LibretroEventHub | undefined = undefined;
  private initialized: boolean = false;
  private missingInitWarned: boolean = false;
  private nextListenerId: number = 1;
  private listeners: Map<EventName, EventListener[]> = new Map();
  private lastPayloads: Map<EventName, EventPayload> = new Map();
  private lastErrorMs: Map<EventName, number> = new Map();
  private readonly statefulEvents: Set<EventName> = new Set([
    'engine_state',
    'core_crash',
    'geometry_update',
    'pixel_format_update',
    'disk_control'
  ]);

  static getInstance(): LibretroEventHub {
    if (!LibretroEventHub.instance) {
      LibretroEventHub.instance = new LibretroEventHub();
    }
    return LibretroEventHub.instance;
  }

  static destroy(): void {  // Audit C-F2: reset singleton on Ability restart so new NAPI callback can be registered
    if (LibretroEventHub.instance) {
      LibretroEventHub.instance.listeners.clear();
      LibretroEventHub.instance.lastPayloads.clear();
      LibretroEventHub.instance = undefined;
    }
  }

  start(): boolean {
    return this.initializeIfNeeded();
  }

  createScope(): EventHubScope {
    this.warnIfNotInitialized();
    return new EventHubScope(this);
  }

  subscribe(event: EventName, callback: (payload: EventPayload) => void, options?: SubscriptionOptions): EventSubscription {
    this.warnIfNotInitialized();
    const listener: EventListener = {
      id: this.nextListenerId++,
      callback: callback as (payload: EventPayload) => void
    };
    const list = this.listeners.get(event);
    if (list) {
      list.push(listener);
    } else {
      this.listeners.set(event, [listener]);
    }

    const replay = options?.replayLatest ?? this.statefulEvents.has(event);
    if (replay) {
      const last = this.lastPayloads.get(event);
      if (last) {
        try {
          listener.callback(last);
        } catch (err) {
          // Audit C-F8: do NOT removeListener here — would permanently drop statefulEvent subscriptions
          this.logCallbackError(event, err);
        }
      }
    }

    return { id: listener.id, event: event };
  }

  unsubscribe(sub: EventSubscription): void {
    this.removeListener(sub.event, sub.id);
  }

  private initializeIfNeeded(): boolean {
    if (this.initialized) {
      return true;
    }
    try {
      const ok = nativeApi.refactoredInitEventBridge((data: RefactoredEvent) => {
        this.handleEvent(data);
      });
      if (!ok) {
        LogHelper.error('EventHub', 'Event', 'refactoredInitEventBridge failed');
        this.initialized = false;
        return false;
      } else {
        LogHelper.info('EventHub', 'Event', 'refactoredInitEventBridge ok');
      }
    } catch (err) {
      LogHelper.error('EventHub', 'Event', `init EventBridge error: ${err}`);
      this.initialized = false;
      return false;
    }
    this.initialized = true;
    return true;
  }

  private warnIfNotInitialized(): void {
    if (this.initialized || this.missingInitWarned) {
      return;
    }
    this.missingInitWarned = true;
    LogHelper.warn('EventHub', 'Event', 'EventHub not started; call LibretroEventHub.getInstance().start()');
  }

  private handleEvent(data: RefactoredEvent): void {
    if (!data || typeof data.event !== 'string' || typeof data.payload !== 'string') {
      return;
    }
    const event = this.normalizeEventName(data.event);
    if (!event) {
      return;
    }
    const payload = this.parsePayload(event, data.payload);
    if (!payload) {
      return;
    }

    if (this.statefulEvents.has(event)) {
      this.lastPayloads.set(event, payload);
    }

    this.logDispatch(event, payload);

    const list = this.listeners.get(event);
    if (!list || list.length === 0) {
      return;
    }

    const snapshot = [...list];
    snapshot.forEach((listener) => {
      try {
        listener.callback(payload);
      } catch (err) {
        this.removeListener(event, listener.id);
        const errMsg = (err as Error)?.message || String(err);
        this.logCallbackError(event, errMsg);
      }
    });
  }

  private removeListener(event: EventName, id: number): void {
    const list = this.listeners.get(event);
    if (!list || list.length === 0) {
      return;
    }
    const next = list.filter(item => item.id !== id);
    if (next.length === 0) {
      this.listeners.delete(event);
    } else {
      this.listeners.set(event, next);
    }
  }

  private normalizeEventName(event: string): EventName | null {
    switch (event) {
      case 'engine_state':
      case 'core_crash':
      case 'fps_update':
      case 'audio_status':
      case 'options_update':
      case 'pixel_format_update':
      case 'geometry_update':
      case 'core_message':
      case 'disk_control':
      case 'rumble':
      case 'sensor_state':
        return event;
      default:
        return null;
    }
  }

  private parsePayload(event: EventName, payload: string): EventPayload | null {
    const obj = this.safeParseObject(payload, event);
    if (!obj) {
      return null;
    }
    switch (event) {
      case 'engine_state': {
        const state = this.toNumber(obj.state);
        if (state === null) {
          this.reportParseError(event, 'invalid state');
          return null;
        }
        const out: EngineStatePayload = { state: state };
        return out;
      }
      case 'core_crash': {
        const reason = this.toString(obj.reason);
        if (reason === null) {
          this.reportParseError(event, 'invalid reason');
          return null;
        }
        const payloadObj: CoreCrashPayload = { reason: reason };
        const step = this.toString(obj.step);
        const message = this.toString(obj.message);
        if (step) payloadObj.step = step;
        if (message) payloadObj.message = message;
        return payloadObj;
      }
      case 'fps_update': {
        const fps = this.toNumber(obj.fps);
        if (fps === null) {
          this.reportParseError(event, 'invalid fps');
          return null;
        }
        const payloadObj: FpsUpdatePayload = { fps: fps };
        const dupes = this.toNumber(obj.dupes);
        const nulls = this.toNumber(obj.nulls);
        const drops = this.toNumber(obj.drops);
        const underruns = this.toNumber(obj.underruns);
        const overruns = this.toNumber(obj.overruns);
        const audioBufferUsage = this.toNumber(obj.audioBufferUsage);
        if (dupes !== null) payloadObj.dupes = dupes;
        if (nulls !== null) payloadObj.nulls = nulls;
        if (drops !== null) payloadObj.drops = drops;
        if (underruns !== null) payloadObj.underruns = underruns;
        if (overruns !== null) payloadObj.overruns = overruns;
        if (audioBufferUsage !== null) payloadObj.audioBufferUsage = audioBufferUsage;
        return payloadObj;
      }
      case 'audio_status': {
        const active = this.toBoolean(obj.active);
        const occupancy = this.toNumber(obj.occupancy);
        const underrun = this.toBoolean(obj.underrun);
        const underruns = this.toNumber(obj.underruns);
        const overruns = this.toNumber(obj.overruns);
        if (active === null || occupancy === null || underrun === null || underruns === null || overruns === null) {
          this.reportParseError(event, 'invalid audio status');
          return null;
        }
        const boundedOccupancy = Math.max(0, Math.min(100, occupancy));
        const payloadObj: AudioStatusPayload = {
          active: active,
          occupancy: boundedOccupancy,
          underrun: underrun,
          underruns: underruns,
          overruns: overruns
        };
        return payloadObj;
      }
      case 'options_update': {
        const payloadObj: OptionsUpdatePayload = {};
        return payloadObj;
      }
      case 'pixel_format_update': {
        const format = this.toNumber(obj.format);
        if (format === null) {
          this.reportParseError(event, 'invalid format');
          return null;
        }
        const payloadObj: PixelFormatPayload = { format: format };
        return payloadObj;
      }
      case 'geometry_update': {
        const baseWidth = this.toNumber(obj.base_width);
        const baseHeight = this.toNumber(obj.base_height);
        if (baseWidth === null || baseHeight === null) {
          this.reportParseError(event, 'invalid geometry');
          return null;
        }
        const payloadObj: GeometryUpdatePayload = {
          base_width: baseWidth,
          base_height: baseHeight
        };
        const aspectRatio = this.toNumber(obj.aspect_ratio);
        if (aspectRatio !== null) payloadObj.aspect_ratio = aspectRatio;
        return payloadObj;
      }
      case 'core_message': {
        const msg = this.toString(obj.msg);
        if (msg === null) {
          this.reportParseError(event, 'invalid message');
          return null;
        }
        const payloadObj: CoreMessagePayload = { msg: msg };
        const frames = this.toNumber(obj.frames);
        if (frames !== null) payloadObj.frames = frames;
        return payloadObj;
      }
      case 'disk_control': {
        const type = this.toString(obj.type);
        if (type === null) {
          this.reportParseError(event, 'invalid disk control type');
          return null;
        }
        const payloadObj: DiskControlPayload = { type: type };
        return payloadObj;
      }
      case 'rumble': {
        const port = this.toNumber(obj.port);
        const effect = this.toNumber(obj.effect);
        const strength = this.toNumber(obj.strength);
        if (port === null || effect === null || strength === null) {
          this.reportParseError(event, 'invalid rumble');
          return null;
        }
        const payloadObj: RumblePayload = { port: port, effect: effect, strength: strength };
        return payloadObj;
      }
      case 'sensor_state': {
        const port = this.toNumber(obj.port);
        const action = this.toNumber(obj.action);
        const rate = this.toNumber(obj.rate);
        if (port === null || action === null || rate === null) {
          this.reportParseError(event, 'invalid sensor state');
          return null;
        }
        const payloadObj: SensorStatePayload = { port: port, action: action, rate: rate };
        return payloadObj;
      }
      default:
        return null;
    }
  }

  private safeParseObject(payload: string, event: EventName): RawPayload | null {
    try {
      const parsed = JSON.parse(payload) as RawPayload;
      if (parsed === null || typeof parsed !== 'object') {
        this.reportParseError(event, 'payload not object');
        return null;
      }
      if (parsed instanceof Array) {
        this.reportParseError(event, 'payload not object');
        return null;
      }
      return parsed as RawPayload;
    } catch (err) {
      this.reportParseError(event, 'payload json parse failed');
      return null;
    }
  }

  private toNumber(value: PayloadValue): number | null {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : null;
    }
    if (typeof value === 'string' && value.length > 0) {
      const v = Number(value);
      return Number.isFinite(v) ? v : null;
    }
    return null;
  }

  private toString(value: PayloadValue): string | null {
    if (typeof value === 'string') {
      return value;
    }
    return null;
  }

  private toBoolean(value: PayloadValue): boolean | null {
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    return null;
  }

  private reportParseError(event: EventName, reason: string): void {
    const now = Date.now();
    const last = this.lastErrorMs.get(event) ?? 0;
    if (now - last < 2000) {
      return;
    }
    this.lastErrorMs.set(event, now);
    LogHelper.warn('EventHub', 'Event', `payload dropped for ${event}: ${reason}`);
  }

  private logCallbackError(event: EventName, errMsg: string): void {
    LogHelper.warn('EventHub', 'Event', `listener error on ${event}: ${errMsg}`);
  }

  private logDispatch(event: EventName, payload: EventPayload): void {
    if (event === 'engine_state') {
      const stateValue = (payload as EngineStatePayload).state;
      LogHelper.info('EventHub', 'Event', `engine_state=${stateValue}`);
      return;
    }
    if (event === 'core_crash') {
      const crash = payload as CoreCrashPayload;
      const step = crash.step ? ` step=${crash.step}` : '';
      const message = crash.message ? ` message=${crash.message}` : '';
      LogHelper.error('EventHub', 'Event', `core_crash reason=${crash.reason}${step}${message}`);
    }
  }
}
