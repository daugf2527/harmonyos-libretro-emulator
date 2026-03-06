/*
 * 引擎统计接口
 */

#ifndef INTERFACES_I_ENGINE_STATS_H
#define INTERFACES_I_ENGINE_STATS_H

#include <cstdint>

namespace interfaces {

struct EngineStats {
  int64_t videoRefreshCalls = 0;
  int64_t videoNullFrames = 0;
  int64_t videoDupeFrames = 0;
  int64_t videoDroppedFrames = 0;
  int64_t audioBatchCalls = 0;
  int64_t audioFramesIn = 0;
  int64_t nwRequestBufferCalls = 0;
  int64_t nwRequestBufferFailures = 0;
  int64_t nwFlushBufferCalls = 0;
  int64_t nwFlushBufferFailures = 0;
  int64_t nwAbortBufferCalls = 0;
  int64_t nbFromWindowBufferFailures = 0;
  int64_t nbMapFailures = 0;
  int64_t nbUnmapFailures = 0;
  int64_t fenceWaitCalls = 0;
  int64_t fenceWaitFailures = 0;
  int64_t fenceTimeoutCount = 0;
  int64_t frameCount = 0;
  double frameTimeMin = 0.0;
  double frameTimeMax = 0.0;
  double frameTimeSum = 0.0;
  int64_t audioBufferUsage = 0;
  int64_t audioUnderruns = 0;
  int64_t audioOverruns = 0;
};

/**
 * @brief 引擎统计接口
 * 对应 ArkTS refactoredGetStats 等接口
 */
class IEngineStats {
public:
  virtual ~IEngineStats() = default;

  virtual EngineStats GetStats() const = 0;
  virtual bool ResetStats() = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_ENGINE_STATS_H
