# RetroArch 音频子系统：从数学建模到跨平台驱动的科学级深度架构分析 (2026版)

## 0. 摘要
本文旨在为开发者和系统级研究者提供 RetroArch 音频子系统的终极技术透视。我们将不再满足于表层的“回调”与“重采样”描述，而是深入到 **Whittaker-Shannon 采样定理** 的工程实现、**闭环控制理论** 在动态速率控制 (DRC) 中的应用，以及从 **WASAPI Exclusive** 到 **PipeWire** 的物理层驱动博弈。

---

## 1. 信号处理核心：数学建模与算法实战

### 1.1 Whittaker-Shannon 实战：Sinc 重采样器
RetroArch 的默认高质量重采样器是基于窗口函数的 Sinc 插值（Windowed-Sinc）。其数学核心公式为：
$$x(t) = \sum_{n=-\infty}^{\infty} x[n] \cdot \text{sinc}\left(\frac{t - nT}{T}\right)$$
在 `libretro-common/audio/resamplers/sinc_resampler.c` 中，这一理论被转化为带有 **Kaiser 窗口** 的有限冲激响应 (FIR) 滤波器：
*   **Kaiser $\beta$ 参数**：控制主瓣宽度与旁瓣衰减的权衡。
*   **SIMD 优化**：利用 ARM Neon 的 `vaddvq_f32` 和 x86 AVX 的 `_mm256_fmadd_ps` 在单指令周期内完成 8 个分量的积和校验。

### 1.2 嵌入式实时性权衡：4 点 Hermite 插值
针对 HarmonyOS 等移动设备，RetroArch 实现了 4 点 Catmull-Rom (三次 Hermite) 插值。其多项式矩阵如下：
$$\begin{bmatrix} P(t) \end{bmatrix} = \frac{1}{2} \begin{bmatrix} t^3 & t^2 & t & 1 \end{bmatrix} \begin{bmatrix} -1 & 3 & -3 & 1 \\ 2 & -5 & 4 & -1 \\ -1 & 0 & 1 & 0 \\ 0 & 2 & 0 & 0 \end{bmatrix} \begin{bmatrix} y_0 \\ y_1 \\ y_2 \\ y_3 \end{bmatrix}$$
这种算法在 O(1) 的空间复杂度下提供了极高的实时性，有效避免了高阶 FIR 滤波器带来的卷积时延。

---

## 2. 动态速率控制 (DRC)：自动控制理论的模拟器应用

### 2.1 反馈环路模型
RetroArch 的 DRC 本质上是一个 **Proportional-Integral (PI) 控制器**。其目标是将音频 RingBuffer 的水位 $L$ 维持在 $50\%$ 的稳定点。
*   **过程变量 (PV)**：当前缓冲区填充率。
*   **控制变量 (CV)**：重采样率偏移 $\Delta r$ (Skew)。
*   **计算公式**：$\Delta r = K_p \cdot e(t) + K_i \int e(t)dt$，其中 $e(t) = 0.5 - L$。

### 2.2 秒级 Skew 与音频相位连续性
为防止音高跳变，`audio_max_timing_skew` 通常限制在 $0.05$ (即 $0.5\%$)。这一阈值是基于心理声学实验得出的——对于大多数人类，低于 $0.5\%$ 的音高漂移是不可感知的，但它足以修正 $60.0Hz$ 与 $59.94Hz$ 之间的时钟偏移。

---

## 3. 物理层驱动：跨平台高性能管线深度对比

### 3.1 Windows：WASAPI Exclusive 的“独占之翼”
不同于 XAudio2 仍然经过系统混音器，RetroArch 的 WASAPI 驱动在 Exclusive 模式下绕过驱动层 Buffer，直接操作音频硬件的端点（Endpoint）。
*   **拉模式 (Pull Mode)**：硬件中断直接驱动 `GetBuffer()`，实现 <10ms 的端到端延迟。
*   **陷阱**：Exclusive 模式会导致 OBS 等录屏软件因音频设备锁定而无法采集。

### 3.2 Linux：PipeWire 与 ALSA 的低时延对决
*   **ALSA**：极致性能，但缺乏多应用混音能力。
*   **PipeWire**：2026 年的主流方案。RetroArch 通过 `SPA (Signal Processing API)` 接口加入 PipeWire 图（Graph），其原子化节点设计允许动态调整 `node.latency` 到 32/48 采样点。

### 3.3 HarmonyOS：OHAudio 与音频工作组线程模型
在鸿蒙平台上，音频子系统不再是一个孤立的线程，而是通过 `OH_AudioWorkgroup_AddCurrentThread` 注册到系统调度核。这意味着：
*   **优先级逃逸**：音频线程可以绕过普通后台线程的 CPU 配额策略。
*   **零拷贝**：利用 `XComponent` 的 Native 画布与 OHAudio 的同步回调，实现完美的音画同步。

---

## 4. 极端性能优化：针对 2026 硬件的 NDK 指南

### 4.1 指令级并行 (ILP) 与寄存器重命名
在编译 NDK 核心时，应启用 `-Ofast` 与 `-funroll-loops`。现代高性能核心（如 Cortex-A78/X系列）的 Out-of-Order 执行单元能够利用解构后的重 resampling 循环，消除寄存器依赖，将吞吐量提升 40%。

### 4.2 缓存对齐与无锁 FIFO
RetroArch 内部使用的 `fifo_buffer.h` 是基于 **Acquire-Release 语义** 的强顺序模型。
```cpp
// 典型的无锁生产路径
atomic_thread_fence(memory_order_release);
fifo->ptr = (fifo->ptr + size) % fifo->capacity;
```
这种设计避免了 `std::mutex` 带来的加锁上下文切换成本，是维持 20ms 以下延迟的关键。

---

## 5. 结论：科学化集成的准则
优秀的模拟器集成不是简单的“出声就好”，它是一场关于 **时间精度** 的战争。
1.  **优先使用原生驱动** (WASAPI Exclusive, PipeWire, OHAudio Native)。
2.  **动态匹配采样率** 以跳过重采样步骤。
3.  **精确监听 Buffer Occupancy 回调** 以实现帧补偿。

> **本文档参考文献来源**：libretro-common 源码库、AES 音频工程协会《Digital Filters Review》、HarmonyOS NDK 官方白皮书、PipeWire 架构 spec。
