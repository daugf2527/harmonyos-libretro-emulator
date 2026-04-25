let pendingImportUris: string[] = []

export function setPendingImportUris(uris: string[]): void {
  pendingImportUris = [...uris]
}

export function consumePendingImportUris(): string[] {
  if (pendingImportUris.length === 0) {
    return []
  }
  const result = [...pendingImportUris]
  pendingImportUris = []
  return result
}
