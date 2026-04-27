import testNapi from 'libentry.so'

interface RuntimeCoreDiagnosticNapi {
  testCoreLoader(path: string): string
}

const nativeApi = testNapi as RuntimeCoreDiagnosticNapi

export class RuntimeCoreDiagnosticController {
  testCoreLoader(path: string): string {
    return nativeApi.testCoreLoader(path)
  }
}

export const runtimeCoreDiagnosticController: RuntimeCoreDiagnosticController =
  new RuntimeCoreDiagnosticController()
