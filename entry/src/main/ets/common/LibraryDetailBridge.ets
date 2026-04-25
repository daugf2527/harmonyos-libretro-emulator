export interface PendingLibraryDetailRequest {
  romFile: string
}

let pendingLibraryDetailRequest: PendingLibraryDetailRequest | undefined = undefined

export function setPendingLibraryDetailRequest(request: PendingLibraryDetailRequest): void {
  pendingLibraryDetailRequest = {
    romFile: request.romFile
  }
}

export function consumePendingLibraryDetailRequest(): PendingLibraryDetailRequest | undefined {
  if (!pendingLibraryDetailRequest) {
    return undefined
  }
  const request: PendingLibraryDetailRequest = {
    romFile: pendingLibraryDetailRequest.romFile
  }
  pendingLibraryDetailRequest = undefined
  return request
}
