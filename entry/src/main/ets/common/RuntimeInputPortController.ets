import testNapi from 'libentry.so'
import {
  InputDeviceInfo,
  InputSourceType
} from './InputPortRouting'
import LogHelper from './LogHelper'

interface RuntimeInputPortNapi {
  refactoredAssignPortSource(port: number, sourceType: number, deviceId?: string): boolean
  refactoredUnassignPort(port: number): boolean
  refactoredListInputDevices(): InputDeviceInfo[]
}

const nativeApi = testNapi as RuntimeInputPortNapi

export class RuntimeInputPortController {
  listInputDevices(): InputDeviceInfo[] {
    try {
      return nativeApi.refactoredListInputDevices() || []
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeInputPort', 'Input', `获取设备列表失败: ${message}`)
      return []
    }
  }

  applyPortAssignment(portId: number, sourceType: InputSourceType, deviceId: string = ''): boolean {
    try {
      if (sourceType === InputSourceType.None) {
        return nativeApi.refactoredUnassignPort(portId)
      }
      return nativeApi.refactoredAssignPortSource(portId, sourceType, deviceId ?? '')
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeInputPort', 'Input', `端口映射调用异常: ${message}`)
      return false
    }
  }
}

export const runtimeInputPortController: RuntimeInputPortController = new RuntimeInputPortController()
