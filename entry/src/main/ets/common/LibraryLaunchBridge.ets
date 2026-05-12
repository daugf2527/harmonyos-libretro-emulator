export interface PendingLibraryLaunchRequest {
  coreId: string
  romFile: string
  autoStart: boolean
}

let pendingLibraryLaunchRequest: PendingLibraryLaunchRequest | undefined = undefined

export function setPendingLibraryLaunchRequest(request: PendingLibraryLaunchRequest): void {
  pendingLibraryLaunchRequest = {
    coreId: request.coreId,
    romFile: request.romFile,
    autoStart: request.autoStart
  }
}

export function consumePendingLibraryLaunchRequest(): PendingLibraryLaunchRequest | undefined {
  if (!pendingLibraryLaunchRequest) {
    return undefined
  }
  const request: PendingLibraryLaunchRequest = {
    coreId: pendingLibraryLaunchRequest.coreId,
    romFile: pendingLibraryLaunchRequest.romFile,
    autoStart: pendingLibraryLaunchRequest.autoStart
  }
  pendingLibraryLaunchRequest = undefined
  return request
}
