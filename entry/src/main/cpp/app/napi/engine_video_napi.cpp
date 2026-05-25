#include "engine_napi_common.h"
#include "interfaces/graphics/i_renderer.h"
#include "platform/audio/audio_bridge.h"

static napi_value SetScalingMode(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetScalingMode")) {
    return MakeBool(env, false);
  }

  int32_t mode = 0;
  if (!GetInt32Arg(env, args[0], mode, "SetScalingMode", "mode")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetScalingMode(mode);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetSwapInterval(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetSwapInterval")) {
    return MakeBool(env, false);
  }

  int32_t interval = 1;
  if (!GetInt32Arg(env, args[0], interval, "SetSwapInterval", "interval")) {
    return MakeBool(env, false);
  }

  GetEngine()->SetSwapInterval(static_cast<int>(interval));
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetSoftwareMaxResolution(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetSoftwareMaxResolution")) {
    return MakeBool(env, false);
  }

  int32_t w = 0, h = 0;
  if (!GetInt32Arg(env, args[0], w, "SetSoftwareMaxResolution", "width") ||
      !GetInt32Arg(env, args[1], h, "SetSoftwareMaxResolution", "height")) {
    return MakeBool(env, false);
  }
  if (w <= 0 || h <= 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetSoftwareMaxResolution invalid: %{public}dx%{public}d", w,
         h);
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetSoftwareMaxResolution(w, h);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetAIUpscale(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetAIUpscale")) {
    return MakeBool(env, false);
  }

  bool enabled = false;
  if (!GetBoolArg(env, args[0], enabled, "SetAIUpscale", "enabled")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetAIUpscale(enabled);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetHwRenderAllowed(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetHwRenderAllowed")) {
    return MakeBool(env, false);
  }

  bool enabled = false;
  if (!GetBoolArg(env, args[0], enabled, "SetHwRenderAllowed", "enabled")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetHwRenderAllowed(enabled);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetMinimumAudioLatency(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 0, 1, args, &argc, "SetMinimumAudioLatency")) {
    return MakeBool(env, false);
  }
  int32_t v = 0;
  if (argc >= 1) {
    if (!GetInt32Arg(env, args[0], v, "SetMinimumAudioLatency", "latencyMs")) {
      return MakeBool(env, false);
    }
  }
  if (v < 0) v = 0;
  LOGF(LOG_INFO, "[NEW] SetMinimumAudioLatency called: %{public}d ms", v);
  GetEngine()->SetMinimumAudioLatency(static_cast<unsigned>(v));
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetAudioSyncMode(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetAudioSyncMode")) {
    return MakeBool(env, false);
  }

  int32_t mode = 1;
  if (!GetInt32Arg(env, args[0], mode, "SetAudioSyncMode", "mode")) {
    return MakeBool(env, false);
  }

  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    auto syncMode = (mode == 0) ? libretro::AudioBridge::SyncMode::NON_BLOCKING
                                : libretro::AudioBridge::SyncMode::AUDIO_BLOCKING;
    // Audit T1-F4: SetSyncMode is sync_mode_.store() (std::atomic) — safe to call from NAPI thread
    audioBridge->SetSyncMode(syncMode);
    LOGF(LOG_INFO, "[NEW] SetAudioSyncMode: %{public}d", mode);
  }

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterVideoAudioNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredSetScalingMode", nullptr, SetScalingMode, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetSwapInterval", nullptr, SetSwapInterval, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetSoftwareMaxResolution", nullptr, SetSoftwareMaxResolution, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetAIUpscale", nullptr, SetAIUpscale, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetHwRenderAllowed", nullptr, SetHwRenderAllowed, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetMinimumAudioLatency", nullptr, SetMinimumAudioLatency, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetAudioSyncMode", nullptr, SetAudioSyncMode, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
