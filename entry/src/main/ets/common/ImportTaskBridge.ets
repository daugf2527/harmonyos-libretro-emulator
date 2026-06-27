export type PendingImportTaskState = 'IDLE' | 'PENDING' | 'CONSUMED'

export interface PendingImportTaskSnapshot {
  uris: string[]
  selectedCount: number
  state: PendingImportTaskState
}

let pendingImportUris: string[] = []
let pendingImportTaskState: PendingImportTaskState = 'IDLE'
let lastPendingImportSelectionCount: number = 0

export function setPendingImportUris(uris: string[]): void {
  pendingImportUris = [...uris]
  lastPendingImportSelectionCount = pendingImportUris.length
  pendingImportTaskState = pendingImportUris.length > 0 ? 'PENDING' : 'IDLE'
}

export function clearPendingImportUris(): void {
  pendingImportUris = []
  lastPendingImportSelectionCount = 0
  pendingImportTaskState = 'IDLE'
}

export function consumePendingImportTask(): PendingImportTaskSnapshot {
  if (pendingImportTaskState !== 'PENDING' || pendingImportUris.length === 0) {
    return {
      uris: [],
      selectedCount: lastPendingImportSelectionCount,
      state: pendingImportTaskState
    }
  }
  const result = [...pendingImportUris]
  pendingImportUris = []
  lastPendingImportSelectionCount = result.length
  pendingImportTaskState = 'CONSUMED'
  return {
    uris: result,
    selectedCount: result.length,
    state: 'PENDING'
  }
}
