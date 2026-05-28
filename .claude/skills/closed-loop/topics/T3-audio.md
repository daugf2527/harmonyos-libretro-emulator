# T3 — Audio bridge

## Scope
AudioBridge: 重采样、DRC、RingBuffer、underrun 统计。

**Files**: `entry/src/main/cpp/platform/audio/audio_bridge.*`

## Hazards
- resampler buffer ownership — speex 内部 buffer 与 callback owned buffer 混淆
- DRC bounds — 限幅器系数越界、过零检测错误
- ring buffer race — Producer (Engine thread) / Consumer (Audio callback thread) 同步
- underrun handling — 不足时静音输出 vs 用 last sample / 统计计数器原子性
- sample rate change — Reset 期间 Producer 不应继续写

## Done criteria 模板(场景驱动)
- [ ] Producer / Consumer 跨线程访问 RingBuffer 全部走 atomic / mutex
- [ ] underrun 时回静音(不是 last sample 重放)且 underrun_count 原子递增
- [ ] sample rate change(LoadRom 触发)时 Reset 期间 Producer 阻塞或丢帧明确
- [ ] DRC 系数 / 阈值边界场景测试覆盖(全 0 / 全峰值 / 单脉冲)
