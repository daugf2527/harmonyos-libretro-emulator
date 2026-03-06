#include "engine_napi_common.h"

void RegisterLibretroRefactoredNapi(napi_env env, napi_value exports) {
  RegisterLifecycleNapi(env, exports);
  RegisterInputNapi(env, exports);
  RegisterVideoAudioNapi(env, exports);
  RegisterStateNapi(env, exports);
  RegisterDiskNapi(env, exports);
  RegisterQueryNapi(env, exports);
  LOGF(LOG_INFO, " [NEW] LibretroRefactored NAPI registered (56 functions, 6 modules)");
}
