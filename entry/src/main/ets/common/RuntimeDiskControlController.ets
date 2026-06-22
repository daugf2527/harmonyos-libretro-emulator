import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeDiskControlNapi {
  refactoredDiskControlSetEjectState(ejected: boolean): boolean
  refactoredDiskControlGetEjectState(): boolean
  refactoredDiskControlGetImageIndex(): number
  refactoredDiskControlSetImageIndex(index: number): boolean
  refactoredDiskControlGetNumImages(): number
  refactoredDiskControlGetSnapshotAsync(): Promise<RuntimeDiskControlSnapshot>
  refactoredDiskControlReplaceImageIndex(index: number, path: string): boolean
  refactoredDiskControlAddImageIndex(): boolean
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
      return this.emptySnapshot()
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
      return this.emptySnapshot()
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

  setImageIndex(index: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeDiskControl', 'Engine', '切换磁盘跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredDiskControlSetImageIndex(
        this.normalizeNonNegativeInt(index)
      )
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `切换磁盘失败: ${message}`)
      return false
    }
  }

  replaceImageIndex(index: number, path: string): boolean {
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
        this.normalizeNonNegativeInt(index),
        safePath
      )
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeDiskControl', 'Engine', `替换磁盘失败: ${message}`)
      return false
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

  private emptySnapshot(): RuntimeDiskControlSnapshot {
    return {
      ejected: false,
      imageIndex: 0,
      imageCount: 0
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
}

export const runtimeDiskControlController: RuntimeDiskControlController =
  new RuntimeDiskControlController()
