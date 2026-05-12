export class PageLifecycleGuard {
  private active: boolean = false
  private taskToken: number = 0
  private timeoutIds: number[] = []
  private intervalIds: number[] = []

  activate(): void {
    this.active = true
  }

  deactivate(): void {
    this.active = false
    this.taskToken += 1
    this.clearTimers()
  }

  beginTask(): number {
    this.taskToken += 1
    return this.taskToken
  }

  isCurrentTask(token: number): boolean {
    return this.active && token === this.taskToken
  }

  isActive(): boolean {
    return this.active
  }

  trackTimeout(id: number): number {
    this.timeoutIds.push(id)
    return id
  }

  trackInterval(id: number): number {
    this.intervalIds.push(id)
    return id
  }

  clearTimeoutId(id: number): void {
    clearTimeout(id)
    this.timeoutIds = this.timeoutIds.filter((item: number) => item !== id)
  }

  clearIntervalId(id: number): void {
    clearInterval(id)
    this.intervalIds = this.intervalIds.filter((item: number) => item !== id)
  }

  clearTimers(): void {
    this.timeoutIds.forEach((id: number) => clearTimeout(id))
    this.intervalIds.forEach((id: number) => clearInterval(id))
    this.timeoutIds = []
    this.intervalIds = []
  }
}
