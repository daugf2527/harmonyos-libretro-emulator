import testNapi from 'libentry.so'
import {
  isVirtualPortActive,
  PortAssignState
} from './InputPortRouting'

export interface RuntimeInputCommandApi {
  refactoredSendInput(port: number, keyId: number, pressed: boolean): boolean
  refactoredSendAnalog(port: number, index: number, id: number, value: number): boolean
}

const nativeApi = testNapi as RuntimeInputCommandApi

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
