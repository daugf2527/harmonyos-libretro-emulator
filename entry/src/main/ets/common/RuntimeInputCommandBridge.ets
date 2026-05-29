import testNapi from 'libentry.so'
import {
  isVirtualPortActive,
  PortAssignState
} from './InputPortRouting'

export interface RuntimeInputCommandApi {
  refactoredSendInput(port: number, keyId: number, pressed: boolean): boolean
  refactoredSendAnalog(port: number, index: number, id: number, value: number): boolean
  refactoredGetInputDescriptorMask(): number
}

const nativeApi = testNapi as RuntimeInputCommandApi

// 16-bit mask of RETRO_DEVICE_ID_JOYPAD_* declared by the active core via
// RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS. 0 = core hasn't declared, callers
// should fall back to the full layout instead of hiding everything.
export function getRuntimeInputDescriptorMask(): number {
  const fn = nativeApi.refactoredGetInputDescriptorMask
  if (typeof fn !== 'function') {
    return 0
  }
  const mask = fn.call(nativeApi)
  return Number.isFinite(mask) ? (mask & 0xFFFF) : 0
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
  return nativeApi.refactoredSendInput(port, buttonId, pressed)
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
  const xOk = nativeApi.refactoredSendAnalog(port, index, 0, normalizeAnalogValue(x))  // Audit C-F1
  return xOk && nativeApi.refactoredSendAnalog(port, index, 1, normalizeAnalogValue(y))
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
