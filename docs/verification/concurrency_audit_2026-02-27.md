# 并发问题复核结论（2026-02-27）

## 范围
- 复核对象：用户提出的 5 个并发/同步问题。
- 复核方式：静态源码审计（读写点、线程归属、同步原语）、官方接口约束比对（libretro.h + HarmonyOS OHAudio 文档）。

## 结论总览
| 编号 | 主题 | 结论 |
| --- | --- | --- |
| 1 | VideoPipeline 跨线程共享字段无锁读写 | `成立（部分）` |
| 2 | `drop_count_` 引擎线程/渲染线程无同步访问 | `成立` |
| 3 | AudioPlayer 回调统计字段竞争 + 双回调并发 | `结论需修正` |
| 4 | SwitchGameAsync token 等待无超时 | `成立` |
| 5 | `renderMutex_` 锁策略文档与实现漂移 | `成立` |

## 详细复核

### 1) VideoPipeline 跨线程字段
- 结论：`成立（部分）`。
- 已确认竞态链路：
  - 引擎线程（core 环境回调路径）写入：
    - `SetPixelFormat/SetCanDupe/SetGeometry`：
      - `entry/src/main/cpp/core/engine/libretro_engine.cpp:2267`
      - `entry/src/main/cpp/core/engine/libretro_engine.cpp:2279`
      - `entry/src/main/cpp/core/engine/libretro_engine.cpp:2286`
  - 渲染线程读取：
    - `RenderThread` 调 `VideoPipeline::Render`：
      - `entry/src/main/cpp/core/engine/render_thread.cpp:550`
    - `Render/RenderGLES/RenderCPU` 读取 `geometry_*`/`pixel_format_`：
      - `entry/src/main/cpp/core/engine/video_pipeline.cpp:346`
      - `entry/src/main/cpp/core/engine/video_pipeline.cpp:972`
      - `entry/src/main/cpp/core/engine/video_pipeline.cpp:979`
      - `entry/src/main/cpp/core/engine/video_pipeline.cpp:1254`
  - 字段为非原子：
    - `entry/src/main/cpp/core/engine/video_pipeline.h:335`
    - `entry/src/main/cpp/core/engine/video_pipeline.h:336`
    - `entry/src/main/cpp/core/engine/video_pipeline.h:337`
    - `entry/src/main/cpp/core/engine/video_pipeline.h:381`
- 修正说明：
  - `canDupe_` 当前仅确认写入点（`video_pipeline.h:430`），未找到读侧消费点，故“`canDupe_` 写读竞争”证据不足。

### 2) `drop_count_` 跨线程竞争
- 结论：`成立`（明确 data race 风险）。
- 证据：
  - 渲染线程递增 `drop_count_`（多处）：
    - `entry/src/main/cpp/core/engine/video_pipeline.cpp:882`
    - `entry/src/main/cpp/core/engine/video_pipeline.cpp:892`
    - `entry/src/main/cpp/core/engine/video_pipeline.cpp:998`
    - `entry/src/main/cpp/core/engine/video_pipeline.cpp:1420`
  - 引擎线程读取并清零：
    - `entry/src/main/cpp/core/engine/libretro_engine.cpp:1235`
    - `entry/src/main/cpp/core/engine/libretro_engine.cpp:1236`
  - 字段/接口非原子：
    - `entry/src/main/cpp/core/engine/video_pipeline.h:385`
    - `entry/src/main/cpp/core/engine/video_pipeline.h:515`
    - `entry/src/main/cpp/core/engine/video_pipeline.h:516`

### 3) AudioPlayer 回调竞争
- 结论：`原结论需修正`。
- 修正后判断：
  - “两种写回调会并发触发并共同改统计字段”这一点证据不足。
  - 官方文档明确：`SetRendererCallback` 与 `SetRendererWriteDataCallback` 同时设置时，只有最后一次设置生效。
  - 代码中顺序为先 `SetRendererCallback` 后 `SetRendererWriteDataCallback`：
    - `entry/src/main/cpp/platform/audio/audio_player.cpp:177`
    - `entry/src/main/cpp/platform/audio/audio_player.cpp:191`
- 仍存在的风险：
  - 统计字段为非原子且未串行化保护（若回调重入/并发，则可能竞争）：
    - `entry/src/main/cpp/platform/audio/audio_player.h:192`
    - `entry/src/main/cpp/platform/audio/audio_player.cpp:515`
    - `entry/src/main/cpp/platform/audio/audio_player.cpp:635`
    - `entry/src/main/cpp/platform/audio/audio_player.cpp:791`

### 4) SwitchGameAsync token 等待
- 结论：`成立`。
- 证据：
  - token 互斥等待为 `while + wait`，无超时：
    - `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:563`
    - `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:569`
  - 唤醒依赖 `ReleaseSwitchToken`：
    - `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:578`
    - `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:582`
- 结论说明：
  - 尽管后续状态等待有超时切片（`WaitForStateWithToken`），但 token 获取阶段本身确实无超时保护。

### 5) 锁策略文档漂移
- 结论：`成立`。
- 证据：
  - 头文件声明锁序约束：
    - `entry/src/main/cpp/core/engine/libretro_engine.h:345`
  - `renderMutex_` 仅声明，未见实际加锁使用；`windowMutex_` 有大量使用。

## 外部约束来源
- libretro 线程与回调语义（仓内镜像）：
  - `entry/src/main/cpp/core/libretro/libretro.h:1538`（`SET_GEOMETRY` 运行时调整）
  - `entry/src/main/cpp/core/libretro/libretro.h:7683`（`retro_run` 语义）
- HarmonyOS OHAudio 头文件文档（官方）：
  - `native_audiostreambuilder.h`：
    - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-audiostreambuilder-h
    - 关键点：`SetRendererCallback` 与 `SetRendererWriteDataCallback` 同时设置，只有最后一次设置生效。

