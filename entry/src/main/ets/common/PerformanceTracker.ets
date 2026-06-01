/**
 * 性能耗时统计工具类
 *
 * 用于测量页面生命周期、异步操作等场景的耗时。
 * 支持多个并发计时器，线程安全（ArkTS 单线程模型）。
 *
 * @example
 * ```typescript
 * // 页面加载耗时
 * aboutToAppear() {
 *   PerformanceTracker.startTimer('page-load');
 *   void this.loadData();
 * }
 *
 * onPageShow() {
 *   const elapsed = PerformanceTracker.endTimer('page-load');
 *   LogHelper.info(`页面加载耗时: ${elapsed}ms`);
 * }
 *
 * // 异步操作耗时
 * async loadData() {
 *   PerformanceTracker.startTimer('fetch-data');
 *   await fetchFromNetwork();
 *   const elapsed = PerformanceTracker.endTimer('fetch-data');
 *   LogHelper.info(`数据加载耗时: ${elapsed}ms`);
 * }
 *
 * // 获取当前耗时（不结束计时）
 * const current = PerformanceTracker.getElapsed('long-task');
 * if (current > 5000) {
 *   LogHelper.warn(`任务执行超过5秒: ${current}ms`);
 * }
 *
 * // 批量查看所有计时器
 * const allTimers = PerformanceTracker.getAllTimers();
 * LogHelper.debug(`所有计时器状态: ${JSON.stringify(allTimers)}`);
 * ```
 */
export class PerformanceTracker {
  private static timers: Map<string, number> = new Map();

  /**
   * 开始计时
   * @param label 计时器标签（唯一标识）
   */
  static startTimer(label: string): void {
    const now = Date.now();
    this.timers.set(label, now);
  }

  /**
   * 结束计时并返回耗时
   * @param label 计时器标签
   * @returns 耗时（毫秒），如果计时器不存在返回 -1
   */
  static endTimer(label: string): number {
    const startTime = this.timers.get(label);
    if (startTime === undefined) {
      return -1;
    }

    const elapsed = Date.now() - startTime;
    this.timers.delete(label);
    return elapsed;
  }

  /**
   * 获取当前耗时（不结束计时）
   * @param label 计时器标签
   * @returns 当前耗时（毫秒），如果计时器不存在返回 -1
   */
  static getElapsed(label: string): number {
    const startTime = this.timers.get(label);
    if (startTime === undefined) {
      return -1;
    }

    return Date.now() - startTime;
  }

  /**
   * 重置计时器（重新开始计时）
   * @param label 计时器标签
   */
  static reset(label: string): void {
    if (this.timers.has(label)) {
      this.timers.set(label, Date.now());
    }
  }

  /**
   * 获取所有计时器的当前状态
   * @returns 所有计时器的标签和当前耗时（毫秒）
   */
  static getAllTimers(): Record<string, number> {
    const result: Record<string, number> = {};
    const now = Date.now();

    this.timers.forEach((startTime, label) => {
      result[label] = now - startTime;
    });

    return result;
  }

  /**
   * 清除指定计时器
   * @param label 计时器标签
   */
  static clearTimer(label: string): void {
    this.timers.delete(label);
  }

  /**
   * 清除所有计时器
   */
  static clearAll(): void {
    this.timers.clear();
  }
}
