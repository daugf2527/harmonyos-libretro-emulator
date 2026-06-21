import testNapi from 'libentry.so'
import {
  isVirtualPortActive,
  PortAssignState
} from './InputPortRouting'
import LogHelper from './LogHelper'

export interface RuntimeInputCommandApi {
  refactoredSendInput(port: number, keyId: number, pressed: boolean): boolean
  refactoredSendAnalog(port: number, index: number, id: number, value: number): boolean
  refactoredGetInputDescriptorMask?(): number
}

const nativeApi = testNapi as RuntimeInputCommandApi

// 16-bit mask of RETRO_DEVICE_ID_JOYPAD_* declared by the active core via
// RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS. 0 = core hasn't declared, callers
// should fall back to the full layout instead of hiding everything.
export function getRuntimeInputDescriptorMask(): number {
  if (!testNapi || nativeApi.refactoredGetInputDescriptorMask === undefined) {
    return 0
  }
  try {
    const mask = nativeApi.refactoredGetInputDescriptorMask()
    return Number.isFinite(mask) ? (mask & 0xFFFF) : 0
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeInputCommand', 'Input', `读取输入描述符掩码失败: ${message}`)
    return 0
  }
}

export function sendRuntimeButton(
  assignments: PortAssignState[],
  port: number,
  buttonId: number,
  pressed: boolean
): boolean {
  if (!isVirtualPortActive(assignments, port)) {
    return false
  }
  try {
    if (!testNapi) {
      return false
    }
    return nativeApi.refactoredSendInput(port, buttonId, pressed)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeInputCommand', 'Input', `发送数字按键失败: ${message}`)
    return false
  }
}

export function sendRuntimeAnalog(
  assignments: PortAssignState[],
  port: number,
  index: number,
  x: number,
  y: number
): boolean {
  if (!isVirtualPortActive(assignments, port)) {
    return false
  }
  try {
    if (!testNapi) {
      return false
    }
    const xOk = nativeApi.refactoredSendAnalog(port, index, 0, normalizeAnalogValue(x))  // Audit C-F1
    return xOk && nativeApi.refactoredSendAnalog(port, index, 1, normalizeAnalogValue(y))
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeInputCommand', 'Input', `发送模拟摇杆失败: ${message}`)
    return false
  }
}

function normalizeAnalogValue(value: number): number {
  let normalized = value
  if (normalized > 1) {
    normalized = 1
  } else if (normalized < -1) {
    normalized = -1
  }
  if (normalized >= 0) {
    return Math.round(normalized * 32767)
  }
  return Math.round(normalized * 32768)
}
