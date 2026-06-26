import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeDiskControlNapi {
  refactoredDiskControlSetEjectState(ejected: boolean): boolean
  refactoredDiskControlSetEjectStateAsync(ejected: boolean): Promise<boolean>
  refactoredDiskControlGetEjectState(): boolean
  refactoredDiskControlGetImageIndex(): number
  refactoredDiskControlSetImageIndex(index: number): boolean
  refactoredDiskControlSetImageIndexAsync(index: number): Promise<boolean>
  refactoredDiskControlGetNumImages(): number
  refactoredDiskControlGetSnapshotAsync(): Promise<RuntimeDiskControlSnapshot>
  refactoredDiskControlReplaceImageIndex(index: number, path: string): boolean
  refactoredDiskControlReplaceImageIndexAsync(index: number, path: string): Promise<boolean>
  refactoredDiskControlAddImageIndex(): boolean
  refactoredDiskControlAddImageIndexAsync(): Promise<boolean>
}

export interface RuntimeDiskControlSnapshot {
  ejected: boolean
  imageIndex: number
  imageCount: number
}

const nativeApi = testNapi as RuntimeDiskControlNapi

export class RuntimeDiskControlController {
  async getSnapshotAsync(): Promise<RuntimeDiskControlSnapshot> {
    if (!testNapi) {
      LogHelper.warn('RuntimeDiskControl', 'Engine', '读取换盘快照跳过: engine not ready')
      throw new Error('engine not ready')
    }
    try {
      const snapshot = await nativeApi.refactoredDiskControlGetSnapshotAsync()
      const imageCount = this.normalizeNonNegativeInt(snapshot.imageCount)
      const imageIndex = this.normalizeIndex(snapshot.imageIndex, imageCount)

      return {
        ejected: snapshot.ejected === true,
        imageIndex,
        imageCount
      }
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `读取换盘快照失败: ${message}`)
      throw err as Error
    }
  }

  setEjectState(ejected: boolean): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '换盘弹仓跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredDiskControlSetEjectState(ejected)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `换盘弹仓失败: ${message}`)
      return false
    }
  }

  async setEjectStateAsync(ejected: boolean): Promise<boolean> {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '换盘弹仓跳过: engine not ready')
        return false
      }
      return await nativeApi.refactoredDiskControlSetEjectStateAsync(ejected)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `换盘弹仓失败: ${message}`)
      throw err as Error
    }
  }

  setImageIndex(index: number): boolean {
    const safeIndex = this.validateNonNegativeInt(index, '切换磁盘')
    if (safeIndex === undefined) {
      return false
    }
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '切换磁盘跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredDiskControlSetImageIndex(safeIndex)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `切换磁盘失败: ${message}`)
      return false
    }
  }

  async setImageIndexAsync(index: number): Promise<boolean> {
    const safeIndex = this.validateNonNegativeInt(index, '切换磁盘')
    if (safeIndex === undefined) {
      return false
    }
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '切换磁盘跳过: engine not ready')
        return false
      }
      return await nativeApi.refactoredDiskControlSetImageIndexAsync(safeIndex)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `切换磁盘失败: ${message}`)
      throw err as Error
    }
  }

  replaceImageIndex(index: number, path: string): boolean {
    const safeIndex = this.validateNonNegativeInt(index, '替换磁盘')
    if (safeIndex === undefined) {
      return false
    }
    const safePath = typeof path === 'string' ? path.trim() : ''
    if (safePath.length === 0) {
      LogHelper.warn('RuntimeDiskControl', 'Engine', '替换磁盘失败: path 为空')
      return false
    }
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '替换磁盘跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredDiskControlReplaceImageIndex(
        safeIndex,
        safePath
      )
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `替换磁盘失败: ${message}`)
      return false
    }
  }

  async replaceImageIndexAsync(index: number, path: string): Promise<boolean> {
    const safeIndex = this.validateNonNegativeInt(index, '替换磁盘')
    if (safeIndex === undefined) {
      return false
    }
    const safePath = typeof path === 'string' ? path.trim() : ''
    if (safePath.length === 0) {
      LogHelper.warn('RuntimeDiskControl', 'Engine', '替换磁盘失败: path 为空')
      return false
    }
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '替换磁盘跳过: engine not ready')
        return false
      }
      return await nativeApi.refactoredDiskControlReplaceImageIndexAsync(
        safeIndex,
        safePath
      )
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `替换磁盘失败: ${message}`)
      throw err as Error
    }
  }

  addImageIndex(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '新增磁盘跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredDiskControlAddImageIndex()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `新增磁盘失败: ${message}`)
      return false
    }
  }

  async addImageIndexAsync(): Promise<boolean> {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '新增磁盘跳过: engine not ready')
        return false
      }
      return await nativeApi.refactoredDiskControlAddImageIndexAsync()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `新增磁盘失败: ${message}`)
      throw err as Error
    }
  }

  private normalizeNonNegativeInt(value: number): number {
    if (!Number.isFinite(value) || value < 0) {
      return 0
    }
    return Math.floor(value)
  }

  private normalizeIndex(value: number, count: number): number {
    const normalized = this.normalizeNonNegativeInt(value)
    if (count <= 0) {
      return 0
    }
    return Math.min(normalized, count - 1)
  }

  private validateNonNegativeInt(value: number, actionLabel: string): number | undefined {
    if (!Number.isFinite(value) || value < 0) {
      LogHelper.warn('RuntimeDiskControl', 'Engine', `${actionLabel}失败: index 非法`)
      return undefined
    }
    return Math.floor(value)
  }
}

export const runtimeDiskControlController: RuntimeDiskControlController =
  new RuntimeDiskControlController()
