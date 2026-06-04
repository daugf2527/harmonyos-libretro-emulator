/**
 * 统一错误码枚举系统
 *
 * 覆盖 5 大类错误：文件 I/O、路由、引擎操作、JSON 解析、EventHub
 * 每个错误码包含唯一标识符、人类可读描述、建议处理方式
 *
 * 基于 docs/audit/m2-t31-error-handling-audit.md 识别的错误类型设计
 */

/**
 * 错误严重级别
 */
export enum ErrorSeverity {
  /** 致命错误，需要立即停止操作 */
  FATAL = 'FATAL',
  /** 错误，操作失败但可恢复 */
  ERROR = 'ERROR',
  /** 警告，操作部分失败或降级 */
  WARNING = 'WARNING',
  /** 信息，非错误但需要用户知晓 */
  INFO = 'INFO'
}

/**
 * 错误处理策略
 */
export enum ErrorHandlingStrategy {
  /** 显示用户提示（Toast/Dialog） */
  SHOW_USER_PROMPT = 'SHOW_USER_PROMPT',
  /** 自动重试操作 */
  AUTO_RETRY = 'AUTO_RETRY',
  /** 降级到备用方案 */
  FALLBACK = 'FALLBACK',
  /** 仅记录日志，静默处理 */
  LOG_ONLY = 'LOG_ONLY',
  /** 终止当前流程 */
  ABORT = 'ABORT'
}

/**
 * 错误码定义接口
 */
export interface ErrorCodeDefinition {
  /** 错误码（唯一标识符） */
  code: string;
  /** 数值错误码（用于 NAPI 传递） */
  numericCode: number;
  /** 人类可读描述 */
  description: string;
  /** 严重级别 */
  severity: ErrorSeverity;
  /** 建议处理策略 */
  strategy: ErrorHandlingStrategy;
  /** 用户友好提示消息（可选） */
  userMessage?: string;
}

/**
 * NAPI 结构化错误返回对象
 *
 * 对应 C++ engine_napi_common.h 的 MakeErrorResult(env, success, errorCode, message)。
 * 失败时 errorCode 对应本文件各 *ErrorCodes 的 numericCode，可经
 * ErrorCodeUtils.findByNumericCode(errorCode) 还原为用户文案。
 */
export interface NapiErrorResult {
  /** 操作是否成功 */
  success: boolean;
  /** 失败时的数值错误码（成功时缺省） */
  errorCode?: number;
  /** 失败时的错误描述（成功时缺省） */
  message?: string;
}

/**
 * 文件 I/O 错误码（1000-1999）
 *
 * 覆盖场景：ROM 读取、存档加载、配置文件读写、目录操作
 */
export class FileErrorCodes {
  /** 文件不存在 */
  static readonly FILE_NOT_FOUND: ErrorCodeDefinition = {
    code: 'FILE_NOT_FOUND',
    numericCode: 1001,
    description: '文件不存在',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '文件未找到，请检查路径是否正确'
  };

  /** 文件读取失败 */
  static readonly FILE_READ_ERROR: ErrorCodeDefinition = {
    code: 'FILE_READ_ERROR',
    numericCode: 1002,
    description: '文件读取失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法读取文件，请检查文件权限'
  };

  /** 文件写入失败 */
  static readonly FILE_WRITE_ERROR: ErrorCodeDefinition = {
    code: 'FILE_WRITE_ERROR',
    numericCode: 1003,
    description: '文件写入失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法保存文件，请检查存储空间'
  };

  /** 权限拒绝 */
  static readonly PERMISSION_DENIED: ErrorCodeDefinition = {
    code: 'PERMISSION_DENIED',
    numericCode: 1004,
    description: '文件访问权限被拒绝',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '没有访问权限，请检查应用权限设置'
  };

  /** 目录不存在 */
  static readonly DIRECTORY_NOT_FOUND: ErrorCodeDefinition = {
    code: 'DIRECTORY_NOT_FOUND',
    numericCode: 1005,
    description: '目录不存在',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '目录未找到，将尝试创建'
  };

  /** 目录创建失败 */
  static readonly DIRECTORY_CREATE_ERROR: ErrorCodeDefinition = {
    code: 'DIRECTORY_CREATE_ERROR',
    numericCode: 1006,
    description: '目录创建失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法创建目录，请检查存储权限'
  };

  /** 磁盘空间不足 */
  static readonly DISK_FULL: ErrorCodeDefinition = {
    code: 'DISK_FULL',
    numericCode: 1007,
    description: '磁盘空间不足',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '存储空间不足，请清理后重试'
  };

  /** 文件列表读取失败 */
  static readonly FILE_LIST_ERROR: ErrorCodeDefinition = {
    code: 'FILE_LIST_ERROR',
    numericCode: 1008,
    description: '文件列表读取失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '无法读取文件列表，将显示空列表'
  };
}

/**
 * 路由错误码（2000-2099）
 *
 * 覆盖场景：页面跳转、参数传递、路由栈操作
 */
export class RouterErrorCodes {
  /** 路由跳转失败 */
  static readonly NAVIGATION_FAILED: ErrorCodeDefinition = {
    code: 'NAVIGATION_FAILED',
    numericCode: 2001,
    description: '页面跳转失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '页面跳转失败，请重试'
  };

  /** 路由参数缺失 */
  static readonly MISSING_ROUTE_PARAMS: ErrorCodeDefinition = {
    code: 'MISSING_ROUTE_PARAMS',
    numericCode: 2002,
    description: '路由参数缺失',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.ABORT,
    userMessage: '页面参数错误，无法继续'
  };

  /** 路由参数类型错误 */
  static readonly INVALID_ROUTE_PARAMS: ErrorCodeDefinition = {
    code: 'INVALID_ROUTE_PARAMS',
    numericCode: 2003,
    description: '路由参数类型错误',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.ABORT,
    userMessage: '页面参数格式错误'
  };

  /** 路由栈为空（无法返回） */
  static readonly EMPTY_ROUTE_STACK: ErrorCodeDefinition = {
    code: 'EMPTY_ROUTE_STACK',
    numericCode: 2004,
    description: '路由栈为空，无法返回',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };
}

/**
 * 引擎操作错误码（3000-3999）
 *
 * 覆盖场景：核心加载、游戏启动、状态切换、崩溃处理
 */
export class EngineErrorCodes {
  /** 核心加载失败（通用） */
  static readonly CORE_LOAD_FAILED: ErrorCodeDefinition = {
    code: 'CORE_LOAD_FAILED',
    numericCode: 3001,
    description: '核心加载失败',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '模拟器核心加载失败，请检查核心文件'
  };

  /** 核心符号缺失 */
  static readonly CORE_SYMBOL_MISSING: ErrorCodeDefinition = {
    code: 'CORE_SYMBOL_MISSING',
    numericCode: 3002,
    description: '核心符号缺失（retro_init 等）',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '核心文件损坏或不兼容'
  };

  /** 核心文件不存在 */
  static readonly CORE_FILE_NOT_FOUND: ErrorCodeDefinition = {
    code: 'CORE_FILE_NOT_FOUND',
    numericCode: 3003,
    description: '核心文件不存在',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '核心文件未找到，请重新安装'
  };

  /** ROM 加载失败（通用） */
  static readonly ROM_LOAD_FAILED: ErrorCodeDefinition = {
    code: 'ROM_LOAD_FAILED',
    numericCode: 3010,
    description: 'ROM 加载失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '游戏加载失败，请检查 ROM 文件'
  };

  /** ROM 格式无效 */
  static readonly ROM_INVALID_FORMAT: ErrorCodeDefinition = {
    code: 'ROM_INVALID_FORMAT',
    numericCode: 3011,
    description: 'ROM 格式无效或不支持',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: 'ROM 格式不支持，请选择其他文件'
  };

  /** ROM 文件损坏 */
  static readonly ROM_CORRUPTED: ErrorCodeDefinition = {
    code: 'ROM_CORRUPTED',
    numericCode: 3012,
    description: 'ROM 文件损坏',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: 'ROM 文件可能已损坏'
  };

  /** 引擎启动失败 */
  static readonly ENGINE_START_FAILED: ErrorCodeDefinition = {
    code: 'ENGINE_START_FAILED',
    numericCode: 3020,
    description: '引擎启动失败',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '模拟器启动失败，请重试'
  };

  /** 引擎崩溃 */
  static readonly ENGINE_CRASHED: ErrorCodeDefinition = {
    code: 'ENGINE_CRASHED',
    numericCode: 3021,
    description: '引擎运行时崩溃',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '模拟器已崩溃，请重新启动'
  };

  /** 引擎状态切换失败 */
  static readonly STATE_TRANSITION_FAILED: ErrorCodeDefinition = {
    code: 'STATE_TRANSITION_FAILED',
    numericCode: 3022,
    description: '引擎状态切换失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** 存档加载失败 */
  static readonly SAVE_STATE_LOAD_FAILED: ErrorCodeDefinition = {
    code: 'SAVE_STATE_LOAD_FAILED',
    numericCode: 3030,
    description: '存档加载失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法加载存档，可能已损坏'
  };

  /** 存档保存失败 */
  static readonly SAVE_STATE_SAVE_FAILED: ErrorCodeDefinition = {
    code: 'SAVE_STATE_SAVE_FAILED',
    numericCode: 3031,
    description: '存档保存失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法保存存档，请检查存储空间'
  };

  /** SRAM 加载失败 */
  static readonly SRAM_LOAD_FAILED: ErrorCodeDefinition = {
    code: 'SRAM_LOAD_FAILED',
    numericCode: 3032,
    description: 'SRAM 加载失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '游戏进度可能丢失'
  };

  /** SRAM 保存失败 */
  static readonly SRAM_SAVE_FAILED: ErrorCodeDefinition = {
    code: 'SRAM_SAVE_FAILED',
    numericCode: 3033,
    description: 'SRAM 保存失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '无法保存游戏进度'
  };

  /** 内存不足 */
  static readonly OUT_OF_MEMORY: ErrorCodeDefinition = {
    code: 'OUT_OF_MEMORY',
    numericCode: 3040,
    description: '内存不足',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '内存不足，请关闭其他应用后重试'
  };
}

/**
 * 渲染错误码（4000-4999）
 *
 * 覆盖场景：图形初始化、帧提交、Surface 操作
 */
export class RenderErrorCodes {
  /** 图形初始化失败 */
  static readonly GRAPHICS_INIT_FAILED: ErrorCodeDefinition = {
    code: 'GRAPHICS_INIT_FAILED',
    numericCode: 4001,
    description: '图形系统初始化失败',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.SHOW_USER_PROMPT,
    userMessage: '图形系统初始化失败，设备可能不支持'
  };

  /** GLES 初始化失败 */
  static readonly GLES_INIT_FAILED: ErrorCodeDefinition = {
    code: 'GLES_INIT_FAILED',
    numericCode: 4002,
    description: 'OpenGL ES 初始化失败',
    severity: ErrorSeverity.FATAL,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: 'OpenGL ES 初始化失败，将尝试软件渲染'
  };

  /** Surface 丢失 */
  static readonly SURFACE_LOST: ErrorCodeDefinition = {
    code: 'SURFACE_LOST',
    numericCode: 4003,
    description: '渲染 Surface 丢失',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.AUTO_RETRY,
    userMessage: '渲染表面丢失，正在恢复'
  };

  /** 帧提交失败 */
  static readonly FRAME_SUBMIT_FAILED: ErrorCodeDefinition = {
    code: 'FRAME_SUBMIT_FAILED',
    numericCode: 4004,
    description: '帧提交失败（SwapBuffers）',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** NativeWindow 操作失败 */
  static readonly NATIVE_WINDOW_ERROR: ErrorCodeDefinition = {
    code: 'NATIVE_WINDOW_ERROR',
    numericCode: 4005,
    description: 'NativeWindow 操作失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.AUTO_RETRY
  };
}

/**
 * 音频错误码（5000-5999）
 *
 * 覆盖场景：音频初始化、播放器启动、缓冲区操作
 */
export class AudioErrorCodes {
  /** 音频初始化失败 */
  static readonly AUDIO_INIT_FAILED: ErrorCodeDefinition = {
    code: 'AUDIO_INIT_FAILED',
    numericCode: 5001,
    description: '音频系统初始化失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '音频初始化失败，将静音运行'
  };

  /** 音频播放器启动失败 */
  static readonly AUDIO_PLAYER_START_FAILED: ErrorCodeDefinition = {
    code: 'AUDIO_PLAYER_START_FAILED',
    numericCode: 5002,
    description: '音频播放器启动失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '音频播放失败，将静音运行'
  };

  /** 音频缓冲区下溢 */
  static readonly AUDIO_UNDERRUN: ErrorCodeDefinition = {
    code: 'AUDIO_UNDERRUN',
    numericCode: 5003,
    description: '音频缓冲区下溢',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** 音频设备占用 */
  static readonly AUDIO_DEVICE_BUSY: ErrorCodeDefinition = {
    code: 'AUDIO_DEVICE_BUSY',
    numericCode: 5004,
    description: '音频设备被占用',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.AUTO_RETRY,
    userMessage: '音频设备被占用，正在重试'
  };
}

/**
 * JSON 解析错误码（6000-6999）
 *
 * 覆盖场景：配置文件解析、元数据读取、输入布局加载
 */
export class JsonErrorCodes {
  /** JSON 解析失败 */
  static readonly JSON_PARSE_ERROR: ErrorCodeDefinition = {
    code: 'JSON_PARSE_ERROR',
    numericCode: 6001,
    description: 'JSON 解析失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '配置文件格式错误，将使用默认配置'
  };

  /** JSON 格式无效 */
  static readonly JSON_INVALID_FORMAT: ErrorCodeDefinition = {
    code: 'JSON_INVALID_FORMAT',
    numericCode: 6002,
    description: 'JSON 格式无效',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '文件格式错误'
  };

  /** JSON 字段缺失 */
  static readonly JSON_MISSING_FIELD: ErrorCodeDefinition = {
    code: 'JSON_MISSING_FIELD',
    numericCode: 6003,
    description: 'JSON 必需字段缺失',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.FALLBACK,
    userMessage: '配置不完整，将使用默认值'
  };

  /** JSON 字段类型错误 */
  static readonly JSON_TYPE_MISMATCH: ErrorCodeDefinition = {
    code: 'JSON_TYPE_MISMATCH',
    numericCode: 6004,
    description: 'JSON 字段类型不匹配',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.FALLBACK
  };
}

/**
 * EventHub 错误码（7000-7999）
 *
 * 覆盖场景：事件订阅、回调执行、事件分发
 */
export class EventHubErrorCodes {
  /** EventHub 启动失败 */
  static readonly EVENT_HUB_START_FAILED: ErrorCodeDefinition = {
    code: 'EVENT_HUB_START_FAILED',
    numericCode: 7001,
    description: 'EventHub 启动失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** 事件订阅失败 */
  static readonly EVENT_SUBSCRIBE_FAILED: ErrorCodeDefinition = {
    code: 'EVENT_SUBSCRIBE_FAILED',
    numericCode: 7002,
    description: '事件订阅失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** 事件回调执行失败 */
  static readonly EVENT_CALLBACK_ERROR: ErrorCodeDefinition = {
    code: 'EVENT_CALLBACK_ERROR',
    numericCode: 7003,
    description: '事件回调执行失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };

  /** 事件分发失败 */
  static readonly EVENT_DISPATCH_FAILED: ErrorCodeDefinition = {
    code: 'EVENT_DISPATCH_FAILED',
    numericCode: 7004,
    description: '事件分发失败',
    severity: ErrorSeverity.WARNING,
    strategy: ErrorHandlingStrategy.LOG_ONLY
  };
}

/**
 * NAPI 错误码（8000-8999）
 *
 * 覆盖场景：参数校验、类型转换、NAPI 调用
 */
export class NapiErrorCodes {
  /** 参数数量错误 */
  static readonly INVALID_ARGUMENT_COUNT: ErrorCodeDefinition = {
    code: 'INVALID_ARGUMENT_COUNT',
    numericCode: 8001,
    description: 'NAPI 参数数量错误',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.ABORT,
    userMessage: '内部错误：参数数量不匹配'
  };

  /** 参数类型错误 */
  static readonly INVALID_ARGUMENT_TYPE: ErrorCodeDefinition = {
    code: 'INVALID_ARGUMENT_TYPE',
    numericCode: 8002,
    description: 'NAPI 参数类型错误',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.ABORT,
    userMessage: '内部错误：参数类型不匹配'
  };

  /** NAPI 调用失败 */
  static readonly NAPI_CALL_FAILED: ErrorCodeDefinition = {
    code: 'NAPI_CALL_FAILED',
    numericCode: 8003,
    description: 'NAPI 调用失败',
    severity: ErrorSeverity.ERROR,
    strategy: ErrorHandlingStrategy.ABORT,
    userMessage: '内部错误：原生调用失败'
  };
}

const ALL_ERROR_CODE_DEFINITIONS: ErrorCodeDefinition[] = [
  FileErrorCodes.FILE_NOT_FOUND,
  FileErrorCodes.FILE_READ_ERROR,
  FileErrorCodes.FILE_WRITE_ERROR,
  FileErrorCodes.PERMISSION_DENIED,
  FileErrorCodes.DIRECTORY_NOT_FOUND,
  FileErrorCodes.DIRECTORY_CREATE_ERROR,
  FileErrorCodes.DISK_FULL,
  FileErrorCodes.FILE_LIST_ERROR,
  RouterErrorCodes.NAVIGATION_FAILED,
  RouterErrorCodes.MISSING_ROUTE_PARAMS,
  RouterErrorCodes.INVALID_ROUTE_PARAMS,
  RouterErrorCodes.EMPTY_ROUTE_STACK,
  EngineErrorCodes.CORE_LOAD_FAILED,
  EngineErrorCodes.CORE_SYMBOL_MISSING,
  EngineErrorCodes.CORE_FILE_NOT_FOUND,
  EngineErrorCodes.ROM_LOAD_FAILED,
  EngineErrorCodes.ROM_INVALID_FORMAT,
  EngineErrorCodes.ROM_CORRUPTED,
  EngineErrorCodes.ENGINE_START_FAILED,
  EngineErrorCodes.ENGINE_CRASHED,
  EngineErrorCodes.STATE_TRANSITION_FAILED,
  EngineErrorCodes.SAVE_STATE_LOAD_FAILED,
  EngineErrorCodes.SAVE_STATE_SAVE_FAILED,
  EngineErrorCodes.SRAM_LOAD_FAILED,
  EngineErrorCodes.SRAM_SAVE_FAILED,
  EngineErrorCodes.OUT_OF_MEMORY,
  RenderErrorCodes.GRAPHICS_INIT_FAILED,
  RenderErrorCodes.GLES_INIT_FAILED,
  RenderErrorCodes.SURFACE_LOST,
  RenderErrorCodes.FRAME_SUBMIT_FAILED,
  RenderErrorCodes.NATIVE_WINDOW_ERROR,
  AudioErrorCodes.AUDIO_INIT_FAILED,
  AudioErrorCodes.AUDIO_PLAYER_START_FAILED,
  AudioErrorCodes.AUDIO_UNDERRUN,
  AudioErrorCodes.AUDIO_DEVICE_BUSY,
  JsonErrorCodes.JSON_PARSE_ERROR,
  JsonErrorCodes.JSON_INVALID_FORMAT,
  JsonErrorCodes.JSON_MISSING_FIELD,
  JsonErrorCodes.JSON_TYPE_MISMATCH,
  EventHubErrorCodes.EVENT_HUB_START_FAILED,
  EventHubErrorCodes.EVENT_SUBSCRIBE_FAILED,
  EventHubErrorCodes.EVENT_CALLBACK_ERROR,
  EventHubErrorCodes.EVENT_DISPATCH_FAILED,
  NapiErrorCodes.INVALID_ARGUMENT_COUNT,
  NapiErrorCodes.INVALID_ARGUMENT_TYPE,
  NapiErrorCodes.NAPI_CALL_FAILED
];

/**
 * 错误码工具类
 */
export class ErrorCodeUtils {
  /**
   * 根据数值错误码查找错误定义
   */
  static findByNumericCode(numericCode: number): ErrorCodeDefinition | undefined {
    for (const definition of ALL_ERROR_CODE_DEFINITIONS) {
      if (definition.numericCode === numericCode) {
        return definition;
      }
    }

    return undefined;
  }

  /**
   * 根据字符串错误码查找错误定义
   */
  static findByCode(code: string): ErrorCodeDefinition | undefined {
    for (const definition of ALL_ERROR_CODE_DEFINITIONS) {
      if (definition.code === code) {
        return definition;
      }
    }

    return undefined;
  }

  /**
   * 获取用户友好的错误消息
   */
  static getUserMessage(codeOrNumeric: string | number): string {
    let definition: ErrorCodeDefinition | undefined;

    if (typeof codeOrNumeric === 'number') {
      definition = ErrorCodeUtils.findByNumericCode(codeOrNumeric);
    } else {
      definition = ErrorCodeUtils.findByCode(codeOrNumeric);
    }

    if (definition?.userMessage) {
      return definition.userMessage;
    }

    return '操作失败，请重试';
  }

  /**
   * 判断错误是否需要显示用户提示
   */
  static shouldShowUserPrompt(codeOrNumeric: string | number): boolean {
    let definition: ErrorCodeDefinition | undefined;

    if (typeof codeOrNumeric === 'number') {
      definition = ErrorCodeUtils.findByNumericCode(codeOrNumeric);
    } else {
      definition = ErrorCodeUtils.findByCode(codeOrNumeric);
    }

    return definition?.strategy === ErrorHandlingStrategy.SHOW_USER_PROMPT;
  }

  /**
   * 判断错误是否应该自动重试
   */
  static shouldAutoRetry(codeOrNumeric: string | number): boolean {
    let definition: ErrorCodeDefinition | undefined;

    if (typeof codeOrNumeric === 'number') {
      definition = ErrorCodeUtils.findByNumericCode(codeOrNumeric);
    } else {
      definition = ErrorCodeUtils.findByCode(codeOrNumeric);
    }

    return definition?.strategy === ErrorHandlingStrategy.AUTO_RETRY;
  }
}
