import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

export interface RuntimeCoreOptionValue {
  value: string
  label: string
}

export interface RuntimeCoreOptionItem {
  key: string
  desc: string
  value: string
  values: RuntimeCoreOptionValue[]
}

interface RuntimeCoreOptionsNapi {
  refactoredGetCoreOptions(): string
  refactoredGetCoreOptionsAsync(): Promise<string>
  refactoredSetCoreOption(key: string, value: string): boolean
  refactoredSetCoreOptionAsync(key: string, value: string): Promise<boolean>
}

const nativeApi = testNapi as RuntimeCoreOptionsNapi

export interface RuntimeCoreOptionsTaskOptions {
  shouldCancel?: () => boolean
}

export class RuntimeCoreOptionsController {
  getOptions(): RuntimeCoreOptionItem[] {
    try {
      if (!testNapi) {
        return []
      }
      return this.parseOptionsJson(nativeApi.refactoredGetCoreOptions())
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreOptions', 'Engine', `读取核心选项失败: ${message}`)
      return []
    }
  }

  async getOptionsAsync(options?: RuntimeCoreOptionsTaskOptions): Promise<RuntimeCoreOptionItem[]> {
    if (options?.shouldCancel?.()) {
      return []
    }
    if (!testNapi) {
      LogHelper.warn('RuntimeCoreOptions', 'Engine', '读取核心选项跳过: engine not ready')
      throw new Error('engine not ready')
    }
    try {
      const raw = await nativeApi.refactoredGetCoreOptionsAsync()
      if (options?.shouldCancel?.()) {
        return []
      }
      return this.parseOptionsJson(raw)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreOptions', 'Engine', `读取核心选项失败: ${message}`)
      throw err as Error
    }
  }

  setOption(key: string, value: string): boolean {
    const safeKey = typeof key === 'string' ? key.trim() : ''
    const safeValue = typeof value === 'string' ? value.trim() : ''
    if (safeKey.length === 0 || safeValue.length === 0) {
      LogHelper.warn('RuntimeCoreOptions', 'Engine', '写入核心选项失败: key/value 为空')
      return false
    }

    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeCoreOptions', 'Engine', '写入核心选项跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetCoreOption(safeKey, safeValue) === true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreOptions', 'Engine', `写入核心选项失败: ${message}`)
      return false
    }
  }

  async setOptionAsync(
    key: string,
    value: string,
    options?: RuntimeCoreOptionsTaskOptions
  ): Promise<boolean> {
    const safeKey = typeof key === 'string' ? key.trim() : ''
    const safeValue = typeof value === 'string' ? value.trim() : ''
    if (safeKey.length === 0 || safeValue.length === 0) {
      LogHelper.warn('RuntimeCoreOptions', 'Engine', '写入核心选项失败: key/value 为空')
      return false
    }

    if (options?.shouldCancel?.()) {
      return false
    }

    if (!testNapi) {
      LogHelper.warn('RuntimeCoreOptions', 'Engine', '写入核心选项跳过: engine not ready')
      throw new Error('engine not ready')
    }

    try {
      const ok = await nativeApi.refactoredSetCoreOptionAsync(safeKey, safeValue)
      if (options?.shouldCancel?.()) {
        return false
      }
      return ok
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreOptions', 'Engine', `写入核心选项失败: ${message}`)
      throw err as Error
    }
  }

  private parseOptionsJson(raw: string): RuntimeCoreOptionItem[] {
    const parsed = JSON.parse(raw) as Partial<RuntimeCoreOptionItem>[] | null
    if (!Array.isArray(parsed)) {
      return []
    }

    return parsed
      .map((item: Partial<RuntimeCoreOptionItem>): RuntimeCoreOptionItem => {
        const key = typeof item.key === 'string' ? item.key.trim() : ''
        const desc = typeof item.desc === 'string' ? item.desc.trim() : ''
        const value = typeof item.value === 'string' ? item.value.trim() : ''
        const values = Array.isArray(item.values)
          ? item.values
            .map((option: Partial<RuntimeCoreOptionValue>): RuntimeCoreOptionValue => {
              return {
                value: typeof option.value === 'string' ? option.value.trim() : '',
                label: typeof option.label === 'string' ? option.label.trim() : ''
              }
            })
            .filter((option: RuntimeCoreOptionValue) => option.value.length > 0)
          : []

        return {
          key,
          desc: desc.length > 0 ? desc : key,
          value,
          values
        }
      })
      .filter((item: RuntimeCoreOptionItem) => item.key.length > 0)
  }
}

export const runtimeCoreOptionsController: RuntimeCoreOptionsController =
  new RuntimeCoreOptionsController()
