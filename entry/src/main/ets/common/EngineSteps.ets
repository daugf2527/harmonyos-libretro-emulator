/**
 * 引擎启动流程步骤码枚举
 *
 * 映射 C++ 层 EngineState (entry/src/main/cpp/core/engine/libretro_engine.h)
 * 用于 UI 层展示启动进度和状态跟踪
 *
 * 状态转换流程：
 * 1. 正常启动流程：
 *    INIT → STARTING → LOADING → CORE_LOADED → LOADING → GAME_LOADED → RUNNING
 *
 * 2. 简化流程（已有核心）：
 *    CORE_LOADED → LOADING → GAME_LOADED → RUNNING
 *
 * 3. 暂停/恢复：
 *    RUNNING ⇄ PAUSED
 *
 * 4. 停止流程：
 *    任意状态 → STOPPING → STOPPED
 *
 * 5. 错误处理：
 *    任意状态 → ERROR → STOPPING/INIT/STARTING（恢复）
 */

/**
 * 引擎步骤码
 * 与 C++ EngineState 枚举值保持一致
 */
export enum EngineStep {
  /** 初始状态 - 引擎已创建但未启动 */
  INIT = 0,

  /** 核心已加载 - libretro 核心 .so 已加载并初始化 */
  CORE_LOADED = 1,

  /** 游戏已加载 - ROM 文件已加载，等待启动 */
  GAME_LOADED = 2,

  /** 运行中 - 游戏正在运行（终态） */
  RUNNING = 3,

  /** 已暂停 - 游戏暂停，可恢复 */
  PAUSED = 4,

  /** 停止中 - 正在清理资源 */
  STOPPING = 5,

  /** 已停止 - 引擎已停止，可重新启动 */
  STOPPED = 6,

  /** 启动中 - 引擎线程启动中 */
  STARTING = 7,

  /** 加载中 - 正在加载核心或 ROM */
  LOADING = 8,

  /** 错误状态 - 发生错误，需要恢复（终态） */
  ERROR = 9
}

/**
 * 步骤元数据
 */
export interface EngineStepMetadata {
  /** 步骤码 */
  step: EngineStep;

  /** 显示名称 */
  displayName: string;

  /** 详细描述 */
  description: string;

  /** 是否为终态（不会自动转换到其他状态） */
  isFinalState: boolean;

  /** 是否为错误状态 */
  isError: boolean;

  /** 是否可交互（用户可以进行操作） */
  isInteractive: boolean;
}

/**
 * 步骤元数据映射表
 */
export const ENGINE_STEP_METADATA: Record<EngineStep, EngineStepMetadata> = {
  [EngineStep.INIT]: {
    step: EngineStep.INIT,
    displayName: '初始化',
    description: '引擎已创建，等待启动',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.STARTING]: {
    step: EngineStep.STARTING,
    displayName: '启动中',
    description: '引擎线程正在启动',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.LOADING]: {
    step: EngineStep.LOADING,
    displayName: '加载中',
    description: '正在加载核心或游戏',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.CORE_LOADED]: {
    step: EngineStep.CORE_LOADED,
    displayName: '核心已加载',
    description: '核心已加载，可继续选择游戏',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.GAME_LOADED]: {
    step: EngineStep.GAME_LOADED,
    displayName: '游戏已加载',
    description: 'ROM 已加载，等待开始运行',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.RUNNING]: {
    step: EngineStep.RUNNING,
    displayName: '运行中',
    description: '游戏正在运行',
    isFinalState: true,
    isError: false,
    isInteractive: true
  },

  [EngineStep.PAUSED]: {
    step: EngineStep.PAUSED,
    displayName: '已暂停',
    description: '游戏已暂停',
    isFinalState: false,
    isError: false,
    isInteractive: true
  },

  [EngineStep.STOPPING]: {
    step: EngineStep.STOPPING,
    displayName: '停止中',
    description: '正在清理资源',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.STOPPED]: {
    step: EngineStep.STOPPED,
    displayName: '已停止',
    description: '引擎已停止',
    isFinalState: false,
    isError: false,
    isInteractive: false
  },

  [EngineStep.ERROR]: {
    step: EngineStep.ERROR,
    displayName: '错误',
    description: '发生错误，需要处理',
    isFinalState: true,
    isError: true,
    isInteractive: false
  }
};

/**
 * 获取步骤元数据
 * @param step 步骤码
 * @returns 步骤元数据
 */
export function getStepMetadata(step: EngineStep): EngineStepMetadata {
  return ENGINE_STEP_METADATA[step];
}

/**
 * 判断是否为终态
 * @param step 步骤码
 * @returns 是否为终态
 */
export function isFinalState(step: EngineStep): boolean {
  return step === EngineStep.RUNNING || step === EngineStep.ERROR;
}

/**
 * 判断是否为错误状态
 * @param step 步骤码
 * @returns 是否为错误状态
 */
export function isErrorState(step: EngineStep): boolean {
  return step === EngineStep.ERROR;
}

/**
 * 判断是否可以加载游戏
 * 对应 C++ IsCoreLoadedState
 * @param step 步骤码
 * @returns 是否可以加载游戏
 */
export function canLoadGame(step: EngineStep): boolean {
  return step === EngineStep.CORE_LOADED ||
         step === EngineStep.GAME_LOADED ||
         step === EngineStep.RUNNING ||
         step === EngineStep.PAUSED;
}

/**
 * 判断游戏是否已加载
 * 对应 C++ IsGameLoadedState
 * @param step 步骤码
 * @returns 游戏是否已加载
 */
export function isGameLoaded(step: EngineStep): boolean {
  return step === EngineStep.GAME_LOADED ||
         step === EngineStep.RUNNING ||
         step === EngineStep.PAUSED;
}

/**
 * 判断是否可以暂停/恢复
 * @param step 步骤码
 * @returns 是否可以暂停/恢复
 */
export function canPauseResume(step: EngineStep): boolean {
  return step === EngineStep.RUNNING || step === EngineStep.PAUSED;
}

/**
 * 判断是否正在进行异步操作
 * @param step 步骤码
 * @returns 是否正在进行异步操作
 */
export function isTransitioning(step: EngineStep): boolean {
  return step === EngineStep.STARTING ||
         step === EngineStep.LOADING ||
         step === EngineStep.STOPPING;
}
