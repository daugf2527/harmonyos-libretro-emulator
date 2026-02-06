/*
 * 引擎统计接口
 */

#ifndef INTERFACES_I_ENGINE_STATS_H
#define INTERFACES_I_ENGINE_STATS_H

#include <cstdint>

namespace interfaces {

struct EngineStats {
  int64_t videoRefreshCalls;
  int64_t videoNullFrames;
  int64_t videoDupeFrames;
  int64_t videoDroppedFrames;
  int64_t audioBatchCalls;
  int64_t audioFramesIn;
  int64_t nwRequestBufferCalls;
  int64_t nwRequestBufferFailures;
  int64_t nwFlushBufferCalls;
  int64_t nwFlushBufferFailures;
  int64_t nwAbortBufferCalls;
  int64_t nbFromWindowBufferFailures;
  int64_t nbMapFailures;
  int64_t nbUnmapFailures;
  int64_t fenceWaitCalls;
  int64_t fenceWaitFailures;
  int64_t fenceTimeoutCount;
  int64_t frameCount;
  double frameTimeMin;
  double frameTimeMax;
  double frameTimeSum;
  int64_t audioBufferUsage;
  int64_t audioUnderruns;
  int64_t audioOverruns;
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
