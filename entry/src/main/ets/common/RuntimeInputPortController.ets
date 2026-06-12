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
  refactoredSetControllerPortDevice(port: number, device: number): boolean
}

export const RETRO_DEVICE_NONE: number = 0
export const RETRO_DEVICE_JOYPAD: number = 1
export const RETRO_DEVICE_ANALOG: number = 5

export interface RuntimeControllerPortDeviceOption {
  device: number
  label: string
  detail: string
}

export const RUNTIME_CONTROLLER_PORT_DEVICE_OPTIONS: RuntimeControllerPortDeviceOption[] = [
  {
    device: RETRO_DEVICE_JOYPAD,
    label: 'Joypad',
    detail: '标准方向键 / 功能键'
  },
  {
    device: RETRO_DEVICE_ANALOG,
    label: 'Analog',
    detail: '启用双摇杆 / 模拟轴'
  }
]

const nativeApi = testNapi as RuntimeInputPortNapi

export class RuntimeInputPortController {
  listInputDevices(): InputDeviceInfo[] {
    try {
      if (!testNapi) { return []; }  // Audit C-F4: guard before engine loads
      return nativeApi.refactoredListInputDevices() || []
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeInputPort', 'Input', `获取设备列表失败: ${message}`)
      return []
    }
  }

  applyPortAssignment(portId: number, sourceType: InputSourceType, deviceId: string = ''): boolean {
    try {
      if (!testNapi) {  // Audit C-F4: guard before engine loads
        LogHelper.warn('RuntimeInputPort', 'Input', '端口映射跳过: engine not ready')
        return false
      }
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

  setControllerPortDevice(portId: number, device: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeInputPort', 'Input', '手柄类型切换跳过: engine not ready')
        return false
      }
      const normalizedDevice = normalizeRuntimeControllerPortDevice(device)
      return nativeApi.refactoredSetControllerPortDevice(portId, normalizedDevice)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeInputPort', 'Input', `手柄类型切换调用异常: ${message}`)
      return false
    }
  }
}

export function normalizeRuntimeControllerPortDevice(device: number): number {
  return device === RETRO_DEVICE_ANALOG ? RETRO_DEVICE_ANALOG : RETRO_DEVICE_JOYPAD
}

export function describeRuntimeControllerPortDevice(device: number): string {
  const normalizedDevice = normalizeRuntimeControllerPortDevice(device)
  const found = RUNTIME_CONTROLLER_PORT_DEVICE_OPTIONS.find((item: RuntimeControllerPortDeviceOption) => {
    return item.device === normalizedDevice
  })
  return found ? found.label : 'Joypad'
}

export function createDefaultRuntimeControllerPortDevices(): number[] {
  return [
    RETRO_DEVICE_JOYPAD,
    RETRO_DEVICE_JOYPAD,
    RETRO_DEVICE_JOYPAD,
    RETRO_DEVICE_JOYPAD
  ]
}

export const runtimeInputPortController: RuntimeInputPortController = new RuntimeInputPortController()
