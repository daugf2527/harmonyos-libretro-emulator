# RetroArch 音频子系统技术分析文档

## 一、RetroArch 音频子系统技术架构深度剖析

### 1.1 整体架构设计理念与核心模块划分

RetroArch 音频子系统采用**分层抽象架构设计**，其核心设计理念基于 libretro API 规范。作为一个跨平台的游戏模拟器前端，RetroArch 本身不负责模拟游戏，而是为各种底层模拟器提供一套统一的框架，负责音频、显示等基础功能，而各种模拟器核心负责实际的游戏模拟[(14)](https://www.eet-china.com/mp/a133761.html)。

从架构层面来看，RetroArch 音频子系统主要分为以下几个核心模块：

**音频驱动抽象层**是整个架构的基础，它定义了统一的音频驱动接口。通过`audio_driver_t`结构体，RetroArch 定义了音频驱动的标准接口，包括初始化、数据写入、暂停 / 恢复、状态查询等核心功能。这种抽象层设计使得 RetroArch 能够支持多种音频后端，包括 ALSA、PulseAudio、PipeWire、SDL、XAudio2、CoreAudio、OpenAL 等[(2)](https://github.com/poweravr/RetroARCH-1.4.0/blob/master/config.def.h)。

**音频处理管线**负责音频数据的处理和转换。这一模块包括音频重采样器、混音器、DSP 滤波器等组件。RetroArch 支持多种音频重采样算法，包括 sinc、lanczos 等，并提供了不同质量等级的选择[(58)](https://blog.csdn.net/gitblog_00293/article/details/151537848)。混音器模块支持多音轨混合，能够处理来自不同源的音频数据。

**音频输出接口**负责将处理后的音频数据发送到硬件设备。RetroArch 支持多种音频输出接口，每种接口都实现了统一的驱动接口规范。例如，ALSA 驱动使用`snd_pcm_t`进行音频数据传输，而 SDL 驱动则使用`SDL_AudioDeviceID`进行设备管理。

### 1.2 音频驱动层与后端抽象层设计

RetroArch 音频子系统的**插件化架构设计**是其最大的技术特色之一。系统定义了统一的`audio_driver_t`接口，该接口包含了音频驱动所需的所有核心功能：



```
typedef struct audio\_driver {

&#x20;   void \*(\*init)(const char \*device, unsigned rate, unsigned latency, unsigned block\_frames, unsigned \*new\_rate);

&#x20;   ssize\_t (\*write)(void \*data, const void \*s, size\_t len);

&#x20;   bool (\*stop)(void \*data);

&#x20;   bool (\*start)(void \*data, bool is\_shutdown);

&#x20;   bool (\*alive)(void \*data);

&#x20;   void (\*set\_nonblock\_state)(void \*data, bool toggle);

&#x20;   void (\*free)(void \*data);

&#x20;   bool (\*use\_float)(void \*data);

&#x20;   const char \*ident;

&#x20;   void \*(\*device\_list\_new)(void \*data);

&#x20;   void (\*device\_list\_free)(void \*data, void \*data2);

&#x20;   size\_t (\*write\_avail)(void \*data);

&#x20;   size\_t (\*buffer\_size)(void \*data);

&#x20;   ssize\_t (\*write\_raw)(void \*data, const int16\_t \*samples, size\_t frames,&#x20;

&#x20;                       unsigned input\_rate, double rate\_adjust, float volume);

} audio\_driver\_t;
```

这一接口定义了音频驱动的标准行为，包括设备初始化、数据写入、状态控制等功能。每个具体的音频驱动（如 ALSA、SDL、PipeWire 等）都需要实现这些接口函数。

RetroArch 支持的音频后端非常丰富，包括：



* **Linux 平台**：ALSA、PulseAudio、PipeWire

* **Windows 平台**：DirectSound、XAudio2、WASAPI

* **macOS/iOS 平台**：CoreAudio、CoreAudio3

* **其他平台**：OpenAL、SDL、DSP 音频驱动等[(2)](https://github.com/poweravr/RetroARCH-1.4.0/blob/master/config.def.h)

以 ALSA 驱动为例，其实现结构如下：



```
typedef struct alsa {

&#x20;   snd\_pcm\_t \*pcm;

&#x20;   alsa\_stream\_info\_t stream\_info;

&#x20;   bool nonblock;

&#x20;   bool is\_paused;

} alsa\_t;
```

该结构包含了 ALSA 音频驱动所需的核心资源，包括 PCM 设备句柄、音频流信息、非阻塞模式标志和暂停状态标志。

### 1.3 音频处理管线的具体实现

RetroArch 音频处理管线采用**多阶段处理架构**，从音频数据的产生到最终输出，整个流程包括以下关键环节：

**音频数据产生阶段**：音频数据最初由 libretro 核心产生，通过`audio_batch_cb()`回调函数传递给 RetroArch 前端。在异步音频模式下，RetroArch 会创建一个独立的音频线程，持续调用音频回调函数，核心在回调中调用`audio_batch_cb()`提供新的混合音频数据[(41)](https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515)。

**音频重采样阶段**：由于不同的 libretro 核心可能使用不同的采样率，RetroArch 需要进行音频重采样以适配输出设备的采样率。RetroArch 支持多种重采样算法，其中 sinc 重采样器是默认选择[(58)](https://blog.csdn.net/gitblog_00293/article/details/151537848)。重采样器的实现支持多种优化，包括 SSE、AVX 和 NEON 指令集优化。

**音频格式转换阶段**：音频数据在传输过程中可能需要进行格式转换。RetroArch 支持两种主要的音频格式：16 位有符号整数格式和 32 位浮点格式。驱动可以通过`use_float()`函数来指示是否支持浮点格式。

**音频输出阶段**：处理后的音频数据最终通过音频驱动输出到硬件设备。输出过程支持阻塞和非阻塞两种模式，可以通过`set_nonblock_state()`函数进行设置。

### 1.4 数据流向分析

RetroArch 音频子系统的数据流向可以分为**同步模式**和**异步模式**两种：

在**同步模式**下，音频数据的处理流程如下：



1. 核心在每个视频帧处理完成后调用`audio_batch_cb()`

2. 音频数据被传递给 RetroArch 音频子系统

3. 数据经过重采样和格式转换处理

4. 通过音频驱动输出到硬件设备

在**异步模式**下，音频处理流程有所不同：



1. RetroArch 创建独立的音频线程

2. 音频线程持续调用音频回调函数

3. 核心在回调中调用`audio_batch_cb()`提供音频数据

4. 音频数据通过环形缓冲区进行缓冲

5. 音频线程负责从缓冲区读取数据并输出

这种异步架构的优势在于能够确保音频播放的连续性，即使在帧率波动的情况下也不会出现音频中断[(41)](https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515)。

音频数据在系统中的流动还涉及到**缓冲区管理**。RetroArch 使用环形缓冲区来管理音频数据的生产和消费。以 SDL 驱动为例，系统创建了一个大小为设备缓冲区两倍的环形缓冲区，并预先填充静音数据：



```
bufsize = sdl->device\_spec.samples \* 4 \* (SDL\_AUDIO\_BITSIZE(sdl->device\_spec.format) / 8);

tmp = calloc(1, bufsize);

sdl->speaker\_buffer = fifo\_new(bufsize);

if (tmp) {

&#x20;   fifo\_write(sdl->speaker\_buffer, tmp, bufsize);

&#x20;   free(tmp);

}
```

这种设计确保了音频播放的平滑性，即使在数据生产暂时中断的情况下也能维持播放。

### 1.5 插件化架构的实现机制

RetroArch 音频子系统的**插件化架构**是通过动态加载机制实现的。系统定义了一个全局的音频驱动数组：



```
extern audio\_driver\_t \*audio\_drivers\[];
```

这个数组包含了所有支持的音频驱动的指针。每个驱动在编译时被注册到这个数组中，运行时根据配置选择合适的驱动进行加载。

驱动的查找和加载过程通过`audio_driver_find_driver()`函数实现，该函数遍历`audio_drivers`数组，查找与指定名称匹配的驱动。驱动名称可以通过配置文件或命令行参数指定。

**音频混音器的插件化设计**也是一个重要特性。RetroArch 支持音频后处理插件，可以实时对音频数据进行处理。混音器支持多种流类型，包括音乐、音效、语音等，每种流都可以独立控制音量和播放状态：



```
typedef struct audio\_mixer\_stream {

&#x20;   audio\_mixer\_sound\_t \*handle;

&#x20;   audio\_mixer\_voice\_t \*voice;

&#x20;   audio\_mixer\_stop\_cb\_t stop\_cb;

&#x20;   void \*buf;

&#x20;   char \*name;

&#x20;   size\_t bufsize;

&#x20;   float volume;

&#x20;   enum audio\_mixer\_stream\_type stream\_type;

&#x20;   enum audio\_mixer\_type type;

&#x20;   enum audio\_mixer\_state state;

} audio\_mixer\_stream\_t;
```

混音器支持最大`AUDIO_MIXER_MAX_SYSTEM_STREAMS`个系统流，可以通过`audio_driver_mixer_add_stream()`函数添加新的音频流。

## 二、RetroArch 音频子系统最新版本特性分析

### 2.1 确认最新版本信息

根据最新的官方发布信息，截至 2025 年 11 月，RetroArch 的最新稳定版本是**1.22.2**[(109)](https://apps.apple.com/cn/app/retroarch/id6499539433)。这个版本于 2025 年 11 月 20 日发布，是在 11 月 14 日发布的 1.22.0 版本基础上经过两次 bug 修复后的稳定版本。

1.22.0 版本是 2025 年的重要版本更新，被认为是 "2025 年最后一个重要版本"[(106)](https://www.linuxadictos.com/retroarch-1-22-llega-con-mejoras-en-moviles-sistema-bsv-replay-redisenado-y-optimizaciones-de-graficos-y-audio.html)。而 1.22.1 和 1.22.2 版本主要包含了翻译更新和一些 bug 修复，特别是针对音频系统的稳定性改进[(105)](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)。

### 2.2 最新版本音频子系统的新功能特性

RetroArch 1.22.0 版本在音频子系统方面带来了多项重要的新功能和改进：

**PipeWire 音频驱动的全面支持**是 1.22.0 版本的重要特性之一。PipeWire 是 Linux 系统中新兴的低延迟多媒体框架，在 Ubuntu、Fedora 等现代 Linux 发行版中已成为默认选择[(91)](https://ubuntuhandbook.org/index.php/2025/01/retroarch-1-20-0-pipewire-qt6/)。新版本不仅添加了 PipeWire 音频驱动支持，还包括了 PipeWire 麦克风驱动，实现了完整的音频输入输出支持：



```
AUDIO/PIPEWIRE: Add PipeWire audio driver

AUDIO/PIPEWIRE: Add PipeWire microphone driver
```

PipeWire 驱动的实现解决了多个关键问题，包括应用启动时 PipeWire 服务停止的问题、线程视频模式下的加速问题、延迟设置和麦克风处理问题，以及新速率传递给音频驱动的问题。

**AudioWorklet 驱动的引入**是 Web 平台（Emscripten）的重要改进。AudioWorklet 是一个基于回调的快速音频驱动，相比传统的音频驱动具有更低的延迟和更好的性能：



```
EMSCRIPTEN: Added new AudioWorklet driver, a fast callback-based audio driver

EMSCRIPTEN: Add new audio driver: AudioWorklet
```

这个新驱动特别适合在网页浏览器中运行 RetroArch 的场景，能够提供更好的音频性能和更低的延迟。

**iOS 和 macOS 平台的音频增强**也是 1.22.0 版本的重要特性。新版本为 iOS 和 macOS 平台添加了 Core Audio 麦克风驱动支持，这使得 RetroArch 能够在 Apple 设备上支持音频录制功能[(105)](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)。

### 2.3 性能优化和改进措施

RetroArch 1.22.0 版本在音频性能优化方面进行了多项重要改进：

**音频混音器的线程安全改进**是一个关键的性能优化。新版本为音频混音器添加了缺失的线程安全锁，修复了内存泄漏问题，并移除了冗余的 "单线程"rthreads 实现：



```
AUDIO/AUDIO MIXER: Add missing locks for thread safety

AUDIO/AUDIO MIXER: Fix audio mixer memory leak + remove redundant 'single threaded' rthreads implementation
```

这些改进确保了音频混音器在多线程环境下的稳定性和性能[(76)](https://www.libretro.com/index.php/category/vulkan/)。

**音频同步算法的优化**针对高刷新率显示器进行了改进。新版本更好地处理了高刷新率下的 Hz 偏移调整，特别是在使用 BFI（Black Frame Insertion）和交换间隔功能时：



```
AUDIO/SYNC: Handle Hz skew adjustment for high refresh rates better (BFI, swap interval)
```

这一改进对于使用高刷新率显示器的用户来说非常重要，能够确保在启用这些高级功能时音频和视频的同步性[(79)](https://flathub.org/da/apps/org.libretro.RetroArch)。

**音频重采样器的优化**也是性能改进的重要组成部分。新版本对音频重采样器进行了多项优化，包括修复了使用 sinc 重采样器且质量低于 "normal" 时菜单声音的问题：



```
AUDIO/RESAMPLER/MIXER: Fix menu sounds (audio mixing) when using the 'sinc' resampler with quality lower than 'normal'
```

此外，新版本还改进了 FFmpeg/MPV 和音频混音器的条件判断逻辑，提高了代码的执行效率[(73)](https://www.apkmirror.com/apk/libretro/retroarch/variant-%7B%22minapi_slug%22:%22minapi-9/)。

### 2.4 音频相关的 bug 修复和兼容性增强

RetroArch 1.22.0 及后续版本包含了大量音频相关的 bug 修复：

**通用音频修复**方面，新版本修复了某些平台上缺失音频滤波器的问题，确保了跨平台音频处理的一致性：



```
AUDIO: Include missing audio filters on some platforms
```

这一修复解决了部分用户在特定平台上遇到的音频质量问题。

**平台特定的音频修复**包括多个重要问题的解决。在 Windows 平台上，WASAPI 驱动的共享缓冲区操作得到了重写，增加了灵活性，并修复了独占模式下进入菜单时最后一个缓冲区循环的问题：



```
AUDIO/WASAPI: Reworked shared buffer operation for more flexibility, fixed exclusive mode last buffer looping when entering menu
```

在 Linux 平台上，新版本改进了 PulseAudio 的设备列表支持，修复了 PipeWire 驱动的多个问题，并改进了 ALSA 设备枚举逻辑[(73)](https://www.apkmirror.com/apk/libretro/retroarch/variant-%7B%22minapi_slug%22:%22minapi-9/)。

**特定功能的音频修复**也得到了关注。新版本修复了重绕（rewind）功能中的音频处理问题，添加了重绕时静音的选项：



```
AUDIO: Option to mute on rewind
```

这一功能对于需要频繁使用重绕功能的用户来说非常实用，避免了重绕过程中产生的噪音。

### 2.5 与之前主要版本的对比分析

通过对比 RetroArch 1.21.0 和 1.22.0 版本的音频子系统改进，可以看出明显的演进趋势：

**1.21.0 版本的主要音频改进**集中在 PipeWire 驱动的初步支持和基础功能完善：



* 新增 PipeWire 音频和麦克风驱动支持

* 修复 PipeWire 驱动的多个基础问题

* 添加重绕时静音选项

* 改进 Emscripten 平台的音频支持

**1.22.0 版本的主要音频改进**则更加注重性能优化和稳定性提升：



* 音频混音器的线程安全和内存管理改进

* 高刷新率下的音频同步优化

* 重采样器的质量和性能改进

* 各平台音频驱动的深度优化

从功能演进来看，1.22.0 版本在 1.21.0 版本的基础上，不仅完善了新引入的 PipeWire 驱动，还对整个音频子系统的架构进行了优化，特别是在多线程处理和资源管理方面的改进，体现了 RetroArch 音频子系统向更高性能和更稳定方向发展的趋势。

## 三、RetroArch 音频子系统开发集成与性能优化指南

### 3.1 RetroArch 音频子系统的编译配置和集成方式

#### 3.1.1 编译配置选项设置

在进行 RetroArch 音频子系统的开发集成之前，首先需要正确配置编译选项。RetroArch 的音频功能可以通过多种编译选项进行控制：

**核心编译选项**包括音频相关的功能开关。在运行`./configure`脚本时，可以通过以下选项控制音频功能的编译：



```
\--enable-audiomixer   启用音频混音器支持

\--enable-dsp-filter   启用DSP滤波器支持

\--enable-ffmpeg       启用FFmpeg音频支持

\--enable-microphone   启用麦克风支持
```

这些选项决定了 RetroArch 音频子系统的功能特性。例如，`--enable-audiomixer`选项会编译音频混音器模块，支持多音轨混合；`--enable-dsp-filter`选项会编译 DSP 滤波器支持，允许对音频进行实时处理。

**音频驱动的编译配置**可以通过修改`config.def.h`文件来实现。该文件定义了 RetroArch 支持的所有音频驱动：



```
\#define HAVE\_AUDIO\_ALSA

\#define HAVE\_AUDIO\_PULSE

\#define HAVE\_AUDIO\_PIPEWIRE

\#define HAVE\_AUDIO\_SDL

\#define HAVE\_AUDIO\_SDL2

\#define HAVE\_AUDIO\_XAUDIO

\#define HAVE\_AUDIO\_COREAUDIO
```

通过注释或取消注释相应的宏定义，可以选择编译特定的音频驱动。例如，如果只需要支持 Linux 平台的音频输出，可以只保留 ALSA、PulseAudio 和 PipeWire 相关的宏定义[(2)](https://github.com/poweravr/RetroARCH-1.4.0/blob/master/config.def.h)。

**优化编译选项**对于性能至关重要。在所有平台上，都可以通过添加`CFLAGS='-march=native'`来触发代码优化：



```
CFLAGS='-march=native' ./configure
```

这一选项会根据目标硬件的特性生成最优的机器码，显著提升音频处理的性能[(114)](https://docs.libretro.com/guides/rpi/)。

#### 3.1.2 头文件和库文件的集成方式

RetroArch 音频子系统的集成需要包含相应的头文件并链接必要的库文件：

**核心头文件**的包含关系如下：



```
\#include \<audio/audio\_driver.h>

\#include \<audio/audio\_mixer.h>

\#include \<audio/audio\_resampler.h>

\#include \<audio/audio\_defines.h>
```

其中，`audio_driver.h`定义了音频驱动的接口规范；`audio_mixer.h`定义了音频混音器的接口；`audio_resampler.h`定义了音频重采样器的接口；`audio_defines.h`包含了音频相关的常量定义。

**音频驱动的集成**需要实现`audio_driver_t`接口并将其注册到系统中。以下是一个简单的音频驱动集成示例：



```
static audio\_driver\_t my\_audio\_driver = {

&#x20;   .init          = my\_audio\_init,

&#x20;   .write         = my\_audio\_write,

&#x20;   .stop          = my\_audio\_stop,

&#x20;   .start         = my\_audio\_start,

&#x20;   .alive         = my\_audio\_alive,

&#x20;   .set\_nonblock\_state = my\_audio\_set\_nonblock\_state,

&#x20;   .free          = my\_audio\_free,

&#x20;   .use\_float     = my\_audio\_use\_float,

&#x20;   .ident         = "my\_audio\_driver",

};

// 将驱动注册到系统中

audio\_drivers\[audio\_driver\_count++] = \&my\_audio\_driver;
```

**音频混音器的集成**需要使用混音器相关的接口函数。以下是创建音频流的示例代码：



```
audio\_mixer\_stream\_params\_t params = {

&#x20;   .buf          = audio\_buffer,

&#x20;   .basename     = "music\_stream",

&#x20;   .cb           = NULL,

&#x20;   .bufsize      = sizeof(audio\_buffer),

&#x20;   .volume       = 1.0f,

&#x20;   .stream\_type  = AUDIO\_MIXER\_STREAM\_TYPE\_MUSIC,

&#x20;   .type         = AUDIO\_MIXER\_TYPE\_WAV,

&#x20;   .state        = AUDIO\_MIXER\_STATE\_STOPPED,

};

audio\_driver\_mixer\_add\_stream(\&params);
```

这一示例创建了一个音乐类型的音频流，初始状态为停止，音量设置为 1.0。

#### 3.1.3 API 接口的使用规范和开发流程

RetroArch 音频子系统提供了清晰的 API 接口规范，开发者需要遵循以下开发流程：

**音频驱动的开发流程**包括以下步骤：



1. 实现`audio_driver_t`接口中的所有函数

2. 实现音频设备的初始化和释放功能

3. 实现音频数据的写入功能

4. 实现设备状态的控制功能

5. 注册驱动到系统中

以`init`函数为例，其实现需要完成音频设备的初始化工作：



```
static void \*my\_audio\_init(const char \*device, unsigned rate,&#x20;

&#x20;                          unsigned latency, unsigned block\_frames,&#x20;

&#x20;                          unsigned \*new\_rate) {

&#x20;   // 分配驱动上下文

&#x20;   my\_audio\_ctx\_t \*ctx = (my\_audio\_ctx\_t\*)calloc(1, sizeof(my\_audio\_ctx\_t));

&#x20;  &#x20;

&#x20;   // 打开音频设备

&#x20;   if (open\_audio\_device(\&ctx->device, device, rate, latency) != 0) {

&#x20;       free(ctx);

&#x20;       return NULL;

&#x20;   }

&#x20;  &#x20;

&#x20;   // 设置采样率

&#x20;   if (new\_rate) \*new\_rate = get\_device\_rate(ctx->device);

&#x20;  &#x20;

&#x20;   return ctx;

}
```

**音频数据处理流程**需要遵循特定的规范。音频数据可以通过两种方式写入：



```
// 使用标准的write接口（支持重采样）

ssize\_t audio\_driver\_write(void \*data, const void \*s, size\_t len);

// 使用raw write接口（不支持重采样，由驱动自行处理）

ssize\_t audio\_driver\_write\_raw(void \*data, const int16\_t \*samples,&#x20;

&#x20;                             size\_t frames, unsigned input\_rate,&#x20;

&#x20;                             double rate\_adjust, float volume);
```

标准的`write`接口会自动处理重采样和格式转换，而`write_raw`接口则由驱动自行处理这些操作。如果驱动实现了`write_raw`接口，系统会优先使用该接口以提高性能。

**音频回调机制的使用**需要特别注意线程安全。在异步音频模式下，音频数据通过回调函数提供：



```
// 设置音频回调函数

bool audio\_driver\_enable\_callback(void);

// 禁用音频回调函数

bool audio\_driver\_disable\_callback(void);

// 音频回调函数

bool audio\_driver\_callback(void);
```

音频回调函数在独立的线程中运行，因此需要确保所有音频处理操作都是线程安全的。

### 3.2 性能优化的关键技术点和策略

#### 3.2.1 音频缓冲区优化策略

音频缓冲区的配置对性能和延迟有决定性影响。RetroArch 提供了多个关键的缓冲区相关参数：

**音频延迟（Audio Latency）的优化**需要在延迟和稳定性之间找到平衡点。根据官方建议，音频延迟应该设置在**40ms 到 60ms**之间：



```
audio\_latency = 64
```

过低的延迟设置（如低于 30ms）会导致音频缓冲区频繁空转，产生爆音或卡顿；而过高的延迟设置则会增加音频延迟，影响游戏体验。建议从 40ms 开始逐步调整，找到最适合硬件配置的值[(128)](https://toxigon.com/optimizing-retroarch-settings-for-better-performance)。

**缓冲区大小的配置原则**基于以下公式：



```
缓冲区大小(字节) = 采样率 × 位深 × 通道数 × 延迟时间(秒)
```

以 48kHz 采样率、16 位、立体声为例，64ms 延迟对应的缓冲区大小为：



```
48000 × 2 × 2 × 0.064 = 12288字节
```

RetroArch 默认使用 64ms 的音频延迟，这是经过大量测试验证的最优值[(136)](https://docs.libretro.com/guides/optimal-vsync/)。

**缓冲区利用率的监控**可以通过`buffer_size`和`data_ptr`的比值来反映。理想的缓冲区利用率应该在 \*\*30% 到 70%\*\* 之间：



```
理想利用率 = 30% \~ 70%
```

如果利用率过高（接近 100%），说明音频产生速度跟不上播放速度，需要增加缓冲区大小或优化音频处理流程；如果利用率过低（接近 0%），则说明系统资源未被充分利用，可以适当减小缓冲区大小以降低延迟[(127)](https://blog.csdn.net/gitblog_00548/article/details/151536385)。

#### 3.2.2 音频重采样器优化

音频重采样是影响性能的关键因素之一，RetroArch 提供了多种优化策略：

**重采样器质量的选择**直接影响性能和音质。RetroArch 支持 5 个质量等级（0 到 4，0 为最低，4 为最高）：



```
audio\_resampler\_quality = 2  # 默认质量等级
```

降低重采样器质量可以显著提升性能，特别是在低端硬件上。在 3DS、Vita、PSP 等低功耗设备上，系统默认使用较低的质量等级以确保流畅运行[(128)](https://toxigon.com/optimizing-retroarch-settings-for-better-performance)。

**重采样算法的选择**对性能有重要影响。RetroArch 默认使用 sinc 重采样器，该算法在音质和性能之间提供了良好的平衡。sinc 重采样器支持多种优化实现：



```
// SSE优化实现

process = resampler\_sinc\_process\_sse;

// AVX优化实现

if (mask & resampler\_simd\_avx && enable\_avx) {

&#x20;   process = resampler\_sinc\_process\_avx;

}

// NEON优化实现（ARM平台）

\#ifdef \_\_ARM\_NEON\_\_

process = resampler\_sinc\_process\_neon;

\#endif
```

这些优化实现利用了现代 CPU 的 SIMD 指令集，能够显著提升重采样性能。

**采样率的匹配优化**可以避免不必要的重采样。如果音频源的采样率与输出设备的采样率相同，可以完全避免重采样过程。因此，在可能的情况下，应该尽量使音频源和输出设备使用相同的采样率[(133)](https://www.hiscorebob.lu/2014/05/retropie-tips-n-tricks/)。

#### 3.2.3 音频同步机制优化

音频同步是确保音视频协调播放的关键，RetroArch 提供了多种同步优化策略：

**动态速率控制（Dynamic Rate Control）的配置**是音频同步的核心机制。该机制通过调整核心的运行速度来实现音视频同步：



```
audio\_sync = true
```

动态速率控制在同步音视频方面要求很高的时序精度，能够平滑掉不可避免的时序缺陷。建议始终启用这一功能，否则很难获得正确的音视频同步。

**最大时序偏移（Maximum Timing Skew）的设置**决定了系统能够容忍的时序偏差范围：



```
audio\_max\_timing\_skew = 0.050000
```

默认值 0.05（5%）适用于大多数情况。但对于某些特殊的街机游戏（如某些 Mortal Kombat 版本运行在 54Hz 左右），或者需要将 50Hz PAL 内容以 60Hz NTSC 速度运行时，需要增大这一值。例如，60Hz 比 50Hz 快约 17%，因此需要将最大时序偏移设置为 0.17。

**垂直同步（Vsync）的优化配置**对音频同步有重要影响。建议使用以下配置：



```
vertical\_sync = true

vsync\_swap\_interval = auto
```

`vsync_swap_interval`设置为`auto`时，系统会自动根据刷新率选择合适的值。例如，对于 120Hz 显示器，系统会自动选择 2，使得 120Hz/2 = 60Hz，与 NTSC 标准频率匹配。

#### 3.2.4 多线程处理优化

RetroArch 音频子系统的多线程处理需要特别的优化策略：

**音频线程的优先级设置**对实时性至关重要。在支持实时调度的系统上，可以将音频线程设置为更高的优先级：



```
// 设置音频线程为实时优先级

pthread\_setschedparam(audio\_thread\_id, SCHED\_FIFO, \&sched\_param);
```

这一设置确保音频处理具有足够的响应性，避免因其他线程抢占导致的音频中断。

**线程间同步机制的优化**使用高效的同步原语。RetroArch 使用`slock`（简单锁）和`scond`（条件变量）来实现线程间同步：



```
// 创建锁和条件变量

slock\_t \*lock = slock\_new();

scond\_t \*cond = scond\_new();

// 等待条件变量

slock\_lock(lock);

scond\_wait(cond, lock);

slock\_unlock(lock);

// 唤醒等待线程

slock\_lock(lock);

scond\_signal(cond);

slock\_unlock(lock);
```

这种实现方式相比传统的 POSIX 线程同步原语具有更低的开销。

**音频缓冲区的无锁访问优化**可以进一步提升性能。通过使用环形缓冲区和原子操作，可以实现无锁的音频数据访问，避免线程竞争带来的性能损失。

### 3.3 不同平台下的集成和优化方法

#### 3.3.1 Linux 平台音频集成与优化

Linux 平台的音频集成需要特别关注不同音频后端的特性：

**ALSA 驱动的优化配置**是 Linux 平台的基础。ALSA 提供了最佳的音频性能，但需要正确的配置：



```
audio\_driver = "alsa"

audio\_device = "hw:0,0"
```

对于低延迟要求的应用，建议使用`hw`设备（直接硬件访问）而不是`snd`设备（通过 dmix 插件）。同时，可以通过设置`audio_driver = "alsathread"`来使用线程化的 ALSA 驱动，获得更好的并发性能[(113)](https://blog.csdn.net/gitblog_00510/article/details/156088085)。

**PulseAudio 的配置优化**适用于使用 PulseAudio 作为音频服务器的系统：



```
audio\_driver = "pulse"
```

PulseAudio 提供了网络音频、音频路由等高级功能，但可能引入额外的延迟。建议在不需要这些高级功能时使用 ALSA 或 PipeWire 以获得更低的延迟[(117)](https://wiki.postmarketos.org/wiki/RetroArch)。

**PipeWire 的集成优化**是 Linux 平台的最新趋势。PipeWire 在 Ubuntu 22.04 及后续版本中已成为默认的音频系统：



```
audio\_driver = "pipewire"
```

PipeWire 提供了低延迟、高音质的音频处理，同时支持音频和视频流的处理。在 RetroArch 1.22.0 中，PipeWire 驱动经过了深度优化，解决了多个关键问题[(91)](https://ubuntuhandbook.org/index.php/2025/01/retroarch-1-20-0-pipewire-qt6/)。

**Linux 平台的通用优化建议**：



1. 禁用不必要的音频服务，减少系统音频处理的复杂度

2. 使用专用的音频设备，避免与其他应用共享音频设备

3. 调整内核参数，如增大音频缓冲区、提高音频线程优先级

4. 使用实时内核或启用 PREEMPT\_RT 补丁以获得更好的实时性能

#### 3.3.2 Windows 平台音频集成与优化

Windows 平台提供了多种音频后端选择，每种都有其特点：

**XAudio2 的优化配置**是 Windows 平台的推荐选择：



```
audio\_driver = "xaudio"
```

XAudio2 是 Microsoft 提供的高级音频处理 API，支持 3D 音频、音频效果等高级功能。在 RetroArch 中，XAudio2 是默认的音频驱动选择[(60)](https://forums.libretro.com/t/quality-of-audio-resampler-driver/12424)。

**WASAPI 的高级优化**适用于对音频质量有极高要求的场景：



```
audio\_driver = "wasapi"
```

WASAPI（Windows Audio Session API）提供了低延迟的音频路径，支持独占模式和共享模式。独占模式下可以绕过 Windows 音频混合器，获得最低的延迟和最高的音质。RetroArch 1.22.0 对 WASAPI 驱动进行了重写，增加了共享缓冲区操作的灵活性：



```
AUDIO/WASAPI: Reworked shared buffer operation for more flexibility
```

**DirectSound 的兼容性优化**主要用于兼容旧系统：



```
audio\_driver = "dsound"
```

DirectSound 是较老的音频 API，提供了基本的音频功能。虽然功能相对简单，但在某些旧系统上可能是唯一可用的选择。

**Windows 平台的通用优化建议**：



1. 使用独占模式以获得最佳音质和最低延迟

2. 配置正确的音频格式，避免不必要的格式转换

3. 调整音频设备的缓冲区大小，平衡延迟和稳定性

4. 禁用 Windows 音频增强功能，避免额外的处理延迟

#### 3.3.3 macOS/iOS 平台音频集成与优化

Apple 平台的音频集成基于 Core Audio 框架：

**Core Audio 的基础配置**：



```
audio\_driver = "coreaudio"
```

Core Audio 是 Apple 平台的标准音频框架，提供了低延迟、高质量的音频处理。RetroArch 支持 Core Audio 和 Core Audio3 两种实现，后者提供了更多的功能和更好的性能[(75)](https://github.com/libretro/RetroArch/issues/18072)。

**iOS 平台的特殊优化**包括：



```
// iOS平台的音频会话配置

AVAudioSession \*session = \[AVAudioSession sharedInstance];

\[session setCategory:AVAudioSessionCategoryPlayAndRecord&#x20;

&#x20;    withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker&#x20;

&#x20;          error:nil];

\[session setActive:YES error:nil];
```

iOS 平台需要配置音频会话以确保音频能够正常播放。RetroArch 1.22.0 为 iOS 和 macOS 添加了 Core Audio 麦克风驱动支持，使得音频录制功能成为可能[(105)](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)。

**macOS 平台的高级优化**：



1. 使用正确的音频格式，优先选择硬件支持的格式

2. 配置音频设备的采样率，避免重采样

3. 使用独占访问模式以获得最佳性能

4. 注意多显示器环境可能对音频同步产生的影响

#### 3.3.4 Android 平台音频集成与优化

Android 平台的音频集成需要特别关注不同 API 级别和设备兼容性：

**Android 音频 API 的选择**：

RetroArch 支持 Android 的 OpenSL ES 和 AAudio 两种音频 API。OpenSL ES 是较老的 API，提供了基础的音频功能；AAudio 是新的音频 API，提供了更低的延迟和更好的性能。

**Android 平台的优化策略**：



1. 使用低延迟的音频缓冲区配置

2. 优化音频数据的传输路径，减少 CPU 开销

3. 合理使用音频焦点机制，处理音频中断

4. 针对不同的 Android 版本提供兼容的实现

#### 3.3.5 Web 平台（Emscripten）音频集成与优化

Web 平台的音频集成通过 Emscripten 编译器实现：

**AudioWorklet 的优化使用**是 Web 平台的重要改进：



```
audio\_driver = "audioworklet"
```

AudioWorklet 是 Web Audio API 的新特性，提供了基于回调的音频处理机制。相比传统的 JavaScript 音频处理，AudioWorklet 具有更低的延迟和更好的性能。RetroArch 1.22.0 为 Web 平台添加了 AudioWorklet 驱动支持：



```
EMSCRIPTEN: Add new AudioWorklet driver, a fast callback-based audio driver
```

**Web 平台的特殊优化建议**：



1. 使用合适的音频格式，如 Ogg Vorbis 或 MP3

2. 优化音频数据的加载和缓存策略

3. 处理网络延迟对音频同步的影响

4. 针对不同的浏览器提供兼容的实现

### 3.4 常见性能问题的诊断和解决方法

#### 3.4.1 音频卡顿和爆音问题诊断

音频卡顿和爆音是最常见的音频问题，通常由以下原因引起：

**缓冲区不足导致的问题**：

症状：音频间歇性中断，出现 "噗噗" 声。

诊断方法：监控音频缓冲区的利用率。如果`Audio->Underrun`统计值持续高于 0%，说明音频缓冲区经常空转：



```
Audio->Underrun: 15%  # 表示15%的时间音频缓冲区接近空
```

解决方法：



1. 增加音频延迟（`audio_latency`），默认 64ms 可以增加到 128ms 或 256ms

2. 检查音频处理流程中是否有耗时操作，优化相关代码

3. 确认 CPU 负载是否过高，降低其他应用的优先级

**音频同步问题导致的卡顿**：

症状：音频播放速度不稳定，与视频不同步。

诊断方法：检查`Core AV_INFO->FPS`和`Video->FPS`是否匹配。正常情况下，这两个值应该非常接近：



```
Core AV\_INFO->FPS: 60.00

Video->FPS: 59.98
```

解决方法：



1. 启用音频同步功能（`audio_sync = true`）

2. 正确设置显示器的刷新率（`video_refresh_rate`）

3. 调整最大时序偏移（`audio_max_timing_skew`）以适应特殊频率的内容

#### 3.4.2 音频延迟过高问题诊断

音频延迟过高会影响游戏的响应性，特别是在竞技游戏中：

**延迟测量方法**：

可以使用以下方法测量音频延迟：



1. 在音频输出时记录时间戳

2. 在音频输入（如有）时记录时间戳

3. 计算两者的时间差

正常的音频延迟应该在 50ms 以下，竞技游戏建议控制在 30ms 以下。

**延迟过高的常见原因和解决方法**：



1. **缓冲区过大**：

* 原因：`audio_latency`设置过高

* 解决：逐步降低延迟值，从 64ms 开始，每次减少 10ms，直到出现卡顿，然后回调一个档位

1. **音频处理链过长**：

* 原因：启用了过多的音频效果或滤波器

* 解决：禁用不必要的音频处理功能

1. **驱动选择不当**：

* 原因：使用了引入额外延迟的音频驱动

* 解决：尝试不同的音频驱动，如从 PulseAudio 切换到 ALSA

#### 3.4.3 音频质量问题诊断

音频质量问题包括噪音、失真、音质下降等：

**音频格式不匹配导致的问题**：

症状：音频出现噪音或失真。

诊断方法：检查音频源格式和输出格式是否匹配。RetroArch 支持两种音频格式：16 位有符号整数和 32 位浮点。

解决方法：



1. 确保音频源和输出设备使用相同的格式

2. 如果必须进行格式转换，使用高质量的转换算法

3. 检查音频数据的范围是否在有效值范围内（-1.0 到 1.0 对于浮点格式，-32768 到 32767 对于 16 位整数格式）

**重采样质量问题**：

症状：音频音质模糊或有噪音。

诊断方法：检查重采样器的质量设置和算法选择。

解决方法：



1. 提高重采样器质量（`audio_resampler_quality`）

2. 选择合适的重采样算法，如 sinc 算法

3. 确保输入和输出采样率的比值合理，避免过大的采样率转换

#### 3.4.4 多平台兼容性问题诊断

不同平台可能出现不同的音频问题：

**平台特定的驱动问题**：



1. **Linux 平台**：

* ALSA 配置错误：检查`/etc/asound.conf`或`~/.asoundrc`配置文件

* PulseAudio 权限问题：确保当前用户有权限访问音频设备

* PipeWire 服务问题：确保 PipeWire 服务正常运行

1. **Windows 平台**：

* WASAPI 独占模式问题：检查音频设备是否支持独占模式

* DirectSound 兼容性问题：确保驱动程序已正确安装

* 音频格式支持问题：确认硬件支持所需的音频格式

1. **macOS 平台**：

* Core Audio 设备枚举问题：检查音频设备连接

* 音频会话配置问题：确保正确配置了音频会话类别

* 多显示器音频路由问题：注意主显示器的音频输出设置

#### 3.4.5 性能分析和优化工具

RetroArch 提供了多种性能分析工具：

**内置性能统计**：

通过启用`Settings->User Interface->On-Screen Display->Display Statistics`，可以显示实时性能统计：



```
Audio Buffer Usage: 45%

Audio Underrun: 2%

Audio Blocking: 1%

CPU Usage: 35%
```

这些统计信息可以帮助开发者快速定位性能瓶颈。

**日志文件分析**：

RetroArch 的详细日志包含了大量音频相关的信息：



```
RetroArch: \[Audio] Output rate: 48000 Hz

RetroArch: \[Audio] Frame size: 960 frames

RetroArch: \[Audio] Buffer size: 61440 bytes

RetroArch: \[Audio] Using floating-point samples
```

通过分析这些日志信息，可以了解音频系统的运行状态。

**外部性能分析工具**：



1. **Linux 平台**：使用`perf`工具进行 CPU 性能分析

2. **Windows 平台**：使用 Windows Performance Analyzer 进行性能分析

3. **macOS 平台**：使用 Instruments 进行性能分析

这些工具可以帮助开发者深入分析音频子系统的性能瓶颈，针对性地进行优化。

## 结语

RetroArch 音频子系统作为一个成熟的跨平台音频处理框架，通过其分层抽象架构、插件化设计和丰富的功能特性，为开发者提供了强大而灵活的音频处理能力。从技术架构来看，其清晰的模块划分和统一的接口设计使得不同音频后端能够无缝集成；从功能特性来看，从基础的音频输出到高级的混音、滤波、重采样等功能，RetroArch 音频子系统提供了完整的音频处理方案；从性能优化来看，通过缓冲区管理、算法优化、多线程处理等技术手段，RetroArch 音频子系统能够在各种硬件平台上提供高效稳定的音频处理能力。

随着版本的不断演进，特别是 1.22.0 及后续版本在音频混音器线程安全、高刷新率同步、新驱动支持等方面的改进，RetroArch 音频子系统正在向更高性能、更稳定、更易用的方向发展。对于开发者而言，掌握 RetroArch 音频子系统的架构原理、集成方法和优化策略，不仅能够充分发挥其强大的音频处理能力，还能够针对特定平台和应用场景进行深度优化，实现最佳的音频效果和用户体验。

**参考资料&#x20;**

\[1] 如何在Linux系统上配置RetroArch的音频驱动，解决声音延迟问题-CSDN博客[ https://blog.csdn.net/gitblog\_00510/article/details/156088085](https://blog.csdn.net/gitblog_00510/article/details/156088085)

\[2] RetroARCH-1.4.0/config.def.h at master · poweravr/RetroARCH-1.4.0 · GitHub[ https://github.com/poweravr/RetroARCH-1.4.0/blob/master/config.def.h](https://github.com/poweravr/RetroARCH-1.4.0/blob/master/config.def.h)

\[3] RetroArch[ https://www.pcgamingwiki.com/wiki/RetroArch](https://www.pcgamingwiki.com/wiki/RetroArch)

\[4] Gitee 极速下载/retroarch[ https://gitee.com/mirrors/retroarch](https://gitee.com/mirrors/retroarch)

\[5] Brunnis/RetroArch[ https://github.com/Brunnis/RetroArch](https://github.com/Brunnis/RetroArch)

\[6] Asynchronous audio/video for libretro[ https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515](https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515)

\[7] github.com-libretro-RetroArch\_-\_2024-07-27\_08-14-27[ https://archive.org/details/github.com-libretro-RetroArch\_-\_2024-07-27\_08-14-27](https://archive.org/details/github.com-libretro-RetroArch_-_2024-07-27_08-14-27)

\[8] RetroPie声音均衡器终极指南:打造完美游戏音效体验-CSDN博客[ https://blog.csdn.net/gitblog\_00838/article/details/153549528](https://blog.csdn.net/gitblog_00838/article/details/153549528)

\[9] Libretro - Implementing the core(pdf)[ https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf](https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf)

\[10] RetroArch[ https://ja.wikipedia.org/wiki/RetroArch](https://ja.wikipedia.org/wiki/RetroArch)

\[11] Libretro – A crossplatform application API, powering the crossplatform gaming platform RetroArch[ https://www.libretro.com/](https://www.libretro.com/)

\[12] Highly Configurable[ https://www.retroarch.com/index.php?page=configuration](https://www.retroarch.com/index.php?page=configuration)

\[13] RetroArch 1.21.0 发布，支持 PipeWire 和 FFmpeg 摄像头驱动[ https://cn.linux-terminal.com/?p=8701](https://cn.linux-terminal.com/?p=8701)

\[14] 嵌入式界的顶流开源项目:RetroPie是怎么设计的?-电子工程专辑[ https://www.eet-china.com/mp/a133761.html](https://www.eet-china.com/mp/a133761.html)

\[15] Steam Deck上RetroArch音频失效的终极解决方案:从驱动层到内核级的深度修复指南-CSDN博客[ https://blog.csdn.net/gitblog\_00632/article/details/156289902](https://blog.csdn.net/gitblog_00632/article/details/156289902)

\[16] RetroArch[ https://github.com/Black-Seraph/RetroArch](https://github.com/Black-Seraph/RetroArch)

\[17] lambolighting/RetroArch[ https://github.com/lambolighting/RetroArch](https://github.com/lambolighting/RetroArch)

\[18] RetroArch[ https://github.com/XboxEmulationHub/RetroArch](https://github.com/XboxEmulationHub/RetroArch)

\[19] github.com-libretro-RetroArch\_-\_2024-09-21\_03-09-21[ https://archive.org/details/github.com-libretro-RetroArch\_-\_2024-09-21\_03-09-21](https://archive.org/details/github.com-libretro-RetroArch_-_2024-09-21_03-09-21)

\[20] \[iOS] sdl2 and openal audio drivers make RetroArch freeze/crash on alarms and phone calls #18127[ https://github.com/libretro/RetroArch/issues/18127](https://github.com/libretro/RetroArch/issues/18127)

\[21] RetroArch/audio/drivers/alsa.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/alsa.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/alsa.c)

\[22] RetroArch/audio/drivers/sdl\_audio.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/sdl\_audio.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/sdl_audio.c)

\[23] RetroArch/audio/drivers/ctr\_dsp\_audio.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/ctr\_dsp\_audio.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/ctr_dsp_audio.c)

\[24] 解决Steam Deck上RetroArch音频失效:从驱动配置到内核修复的完整指南-CSDN博客[ https://blog.csdn.net/gitblog\_00048/article/details/151537763](https://blog.csdn.net/gitblog_00048/article/details/151537763)

\[25] wangjun/retroarch-1.19.1[ https://gitee.com/wj8331585/retroarch-1.19.1](https://gitee.com/wj8331585/retroarch-1.19.1)

\[26] RetroArch[ https://ja.wikipedia.org/wiki/RetroArch](https://ja.wikipedia.org/wiki/RetroArch)

\[27] RetroArch[ https://es.wikipedia.org/wiki/RetroArch](https://es.wikipedia.org/wiki/RetroArch)

\[28] RetroArch/audio/audio\_driver.h at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/audio\_driver.h](https://github.com/libretro/RetroArch/blob/master/audio/audio_driver.h)

\[29] RetroArch/audio/drivers/alsa.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/alsa.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/alsa.c)

\[30] RetroArch/audio/drivers/openal.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/openal.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/openal.c)

\[31] RetroArch/driver.h at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/driver.h](https://github.com/libretro/RetroArch/blob/master/driver.h)

\[32] RetroArch[ https://wiki.postmarketos.org/wiki/RetroArch](https://wiki.postmarketos.org/wiki/RetroArch)

\[33] Libretro Development Overview[ https://docs-test-retroa.readthedocs.io/en/latest/development/libretro-overview/](https://docs-test-retroa.readthedocs.io/en/latest/development/libretro-overview/)

\[34] RetroArch/audio/drivers/ctr\_dsp\_audio.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/ctr\_dsp\_audio.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/ctr_dsp_audio.c)

\[35] Libretro - Implementing the core(pdf)[ https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf](https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf)

\[36] 如何在Linux系统上配置RetroArch的音频驱动，解决声音延迟问题-CSDN博客[ https://blog.csdn.net/gitblog\_00510/article/details/156088085](https://blog.csdn.net/gitblog_00510/article/details/156088085)

\[37] Howto use the audio callback in a core[ https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866](https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866)

\[38] RetroArch – Libretro[ https://www.libretro.com/index.php/tag/retroarch/](https://www.libretro.com/index.php/tag/retroarch/)

\[39] RetroArch[ https://ja.wikipedia.org/wiki/RetroArch](https://ja.wikipedia.org/wiki/RetroArch)

\[40] wangjun/retroarch-1.19.1[ https://gitee.com/wj8331585/retroarch-1.19.1](https://gitee.com/wj8331585/retroarch-1.19.1)

\[41] Asynchronous audio/video for libretro[ https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515](https://forums.libretro.com/t/asynchronous-audio-video-for-libretro/515)

\[42] libretro-common/audio/audio\_mixer.c at master · libretro/libretro-common · GitHub[ https://github.com/libretro/libretro-common/blob/master/audio/audio\_mixer.c](https://github.com/libretro/libretro-common/blob/master/audio/audio_mixer.c)

\[43] RetroArch/audio/audio\_driver.h at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/audio\_driver.h](https://github.com/libretro/RetroArch/blob/master/audio/audio_driver.h)

\[44] RetroArch 1.17.0 release[ https://www.libretro.com/index.php/retroarch-1-17-0-release/](https://www.libretro.com/index.php/retroarch-1-17-0-release/)

\[45] RetroArch/retroarch.cfg at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/retroarch.cfg](https://github.com/libretro/RetroArch/blob/master/retroarch.cfg)

\[46] Howto use the audio callback in a core[ https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866](https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866)

\[47] (Audio Mixer) Pad sample buffers to prevent potential heap-buffer-overflows when resampling (fixes crash when using 30 kHz menu audio files) #12987[ https://github.com/libretro/RetroArch/pull/12987](https://github.com/libretro/RetroArch/pull/12987)

\[48] Libretro – A crossplatform application API, powering the crossplatform gaming platform RetroArch[ https://www.libretro.com/](https://www.libretro.com/)

\[49] 如何在Linux系统上配置RetroArch的音频驱动，解决声音延迟问题-CSDN博客[ https://blog.csdn.net/gitblog\_00510/article/details/156088085](https://blog.csdn.net/gitblog_00510/article/details/156088085)

\[50] Libretro - Implementing the core[ https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf](https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf)

\[51] Recording and streaming video from RetroArch[ https://docs.libretro.com/guides/recording-and-streaming/](https://docs.libretro.com/guides/recording-and-streaming/)

\[52] Emulation Central - The Something Awful Forums[ https://forums.somethingawful.com/showthread.php?pagenumber=19\&threadid=4038780](https://forums.somethingawful.com/showthread.php?pagenumber=19\&threadid=4038780)

\[53] PSP RetroArch (PSP) 1.19.1[ https://www.psx-place.com/resources/retroarch-psp.766/update?resource\_update\_id=2193](https://www.psx-place.com/resources/retroarch-psp.766/update?resource_update_id=2193)

\[54] Mastering Arch Linux: Resolving Cracking Audio and Screen Centering Anomalies for a Seamless Retro Gaming Experience[ https://retroarchemu.gitlab.io/home/how-i-fixed-cracking-audio-on-my-arch-linux-system-screen-centering-issue-fix-too/](https://retroarchemu.gitlab.io/home/how-i-fixed-cracking-audio-on-my-arch-linux-system-screen-centering-issue-fix-too/)

\[55] Trying to setup "Surround Sound"[ https://forums.libretro.com/t/trying-to-setup-surround-sound/42841](https://forums.libretro.com/t/trying-to-setup-surround-sound/42841)

\[56] RetroArch/libretro-common/audio/resampler/drivers/sinc\_resampler.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/libretro-common/audio/resampler/drivers/sinc\_resampler.c](https://github.com/libretro/RetroArch/blob/master/libretro-common/audio/resampler/drivers/sinc_resampler.c)

\[57] AMD FSR – Libretro[ https://www.libretro.com/index.php/category/amd-fsr/](https://www.libretro.com/index.php/category/amd-fsr/)

\[58] RetroArch音频采样率转换:音质损失最小化技巧-CSDN博客[ https://blog.csdn.net/gitblog\_00293/article/details/151537848](https://blog.csdn.net/gitblog_00293/article/details/151537848)

\[59] PS Vita/Switch/3DS: Retroarch 1.9.9 released[ https://wololo.net/2021/09/06/ps-vita-switch-3ds-retroarch-1-9-9-released/](https://wololo.net/2021/09/06/ps-vita-switch-3ds-retroarch-1-9-9-released/)

\[60] Quality of Audio Resampler Driver[ https://forums.libretro.com/t/quality-of-audio-resampler-driver/12424](https://forums.libretro.com/t/quality-of-audio-resampler-driver/12424)

\[61] RetroArch/retroarch.cfg at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/retroarch.cfg](https://github.com/libretro/RetroArch/blob/master/retroarch.cfg)

\[62] RetroArch 1.16.0 release[ https://www.libretro.com/index.php/retroarch-1-16-0-release/](https://www.libretro.com/index.php/retroarch-1-16-0-release/)

\[63] GitHub - kode54/retroarch\_resampler\_test: A test tool originally based on blargg\_resampler tester, but now based on the RetroArch resampler[ https://github.com/kode54/retroarch\_resampler\_test](https://github.com/kode54/retroarch_resampler_test)

\[64] A Simple and Efficient Audio Resampler Implementation in C[ https://github.com/cpuimage/resampler](https://github.com/cpuimage/resampler)

\[65] audio-resampler/artest.c at master · dbry/audio-resampler · GitHub[ https://github.com/dbry/audio-resampler/blob/master/artest.c](https://github.com/dbry/audio-resampler/blob/master/artest.c)

\[66] retro/cores/snes/apu/resampler.h at master · openai/retro · GitHub[ https://github.com/openai/retro/blob/master/cores/snes/apu/resampler.h](https://github.com/openai/retro/blob/master/cores/snes/apu/resampler.h)

\[67] resample\_audio.c[ https://ffmpeg.org/doxygen/trunk/resample\_audio\_8c-example.html](https://ffmpeg.org/doxygen/trunk/resample_audio_8c-example.html)

\[68] resampler.hpp[ https://vcvrack.com/docs-v2/resampler\_8hpp\_source](https://vcvrack.com/docs-v2/resampler_8hpp_source)

\[69] RetroArch – Libretro[ https://www.libretro.com/index.php/tag/retroarch/](https://www.libretro.com/index.php/tag/retroarch/)

\[70] RetroArch 1.21.0 发布，支持 PipeWire 和 FFmpeg 摄像头驱动[ https://cn.linux-terminal.com/?p=8701](https://cn.linux-terminal.com/?p=8701)

\[71] \[iOS] sdl2 audio driver does not follow the "Respect Silent Mode" setting #18128[ https://github.com/libretro/RetroArch/issues/18128](https://github.com/libretro/RetroArch/issues/18128)

\[72] RetroArch 1.21.0 is out with PipeWire & FFmpeg Camera Driver[ https://ubuntuhandbook.org/index.php/2025/04/retroarch-1-21-0-is-out-with-pipewire-ffmpeg-camera-driver/](https://ubuntuhandbook.org/index.php/2025/04/retroarch-1-21-0-is-out-with-pipewire-ffmpeg-camera-driver/)

\[73] RetroArch[ https://www.apkmirror.com/apk/libretro/retroarch/variant-%7B%22minapi\_slug%22:%22minapi-9/](https://www.apkmirror.com/apk/libretro/retroarch/variant-%7B%22minapi_slug%22:%22minapi-9/)

\[74] \[iOS] sdl2 and openal audio drivers make RetroArch freeze/crash on alarms and phone calls #18127[ https://github.com/libretro/RetroArch/issues/18127](https://github.com/libretro/RetroArch/issues/18127)

\[75] Question: what is the difference between the audio drivers for macOS (coreaudio) #18072[ https://github.com/libretro/RetroArch/issues/18072](https://github.com/libretro/RetroArch/issues/18072)

\[76] Vulkan – Libretro[ https://www.libretro.com/index.php/category/vulkan/](https://www.libretro.com/index.php/category/vulkan/)

\[77] Cross-platform, sophisticated frontend for the libretro API. Licensed GPLv3.[ https://github.com/libretro/retroarch](https://github.com/libretro/retroarch)

\[78] configs\_all\_retroarch.cfg[ https://pastebin.com/LqsERbZJ](https://pastebin.com/LqsERbZJ)

\[79] RetroArch[ https://flathub.org/da/apps/org.libretro.RetroArch](https://flathub.org/da/apps/org.libretro.RetroArch)

\[80] Expect same controler GUID format for SDL2 on Windows as Linux #18635[ https://github.com/libretro/RetroArch/pull/18635](https://github.com/libretro/RetroArch/pull/18635)

\[81] Version 1.22.0 to 1.22.2 Stable Release but no Announcements[ https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/26](https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/26)

\[82] RetroArch/CHANGES.md at master · davidhedlund/RetroArch · GitHub[ https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)

\[83] Heavy audio crackling in tri-Ace games after Nov 12th SPU changes #103[ https://github.com/libretro/ps2/issues/103](https://github.com/libretro/ps2/issues/103)

\[84] RetroArch (f-droid version)[ https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/](https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/)

\[85] RetroArch 1.22 otimiza emulação em móveis com novidades para iOS e Android[ https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/](https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/)

\[86] Achievement sound incredibly loud #18617[ https://github.com/libretro/RetroArch/issues/18617](https://github.com/libretro/RetroArch/issues/18617)

\[87] \[RA 1.0.0.2 vs RA 1.2.2] Which version do you prefer and why?[ https://forums.libretro.com/t/ra-1-0-0-2-vs-ra-1-2-2-which-version-do-you-prefer-and-why/3212](https://forums.libretro.com/t/ra-1-0-0-2-vs-ra-1-2-2-which-version-do-you-prefer-and-why/3212)

\[88] RetroArch 1.21.0 ya disponible, con mejoras en núcleos, compatibilidad y corrigiendo fallos[ https://www.linuxadictos.com/retroarch-1-21-0-ya-disponible-con-mejoras-en-nucleos-compatibilidad-y-corrigiendo-fallos.html](https://www.linuxadictos.com/retroarch-1-21-0-ya-disponible-con-mejoras-en-nucleos-compatibilidad-y-corrigiendo-fallos.html)

\[89] configs\_all\_retroarch.cfg[ https://pastebin.com/LqsERbZJ](https://pastebin.com/LqsERbZJ)

\[90] RetroArch 1.20.0 release[ https://www.libretro.com/index.php/retroarch-1-20-0-release/?amp=1](https://www.libretro.com/index.php/retroarch-1-20-0-release/?amp=1)

\[91] RetroArch 1.20.0 Released with PipeWire Audio Driver, Qt6 Support[ https://ubuntuhandbook.org/index.php/2025/01/retroarch-1-20-0-pipewire-qt6/](https://ubuntuhandbook.org/index.php/2025/01/retroarch-1-20-0-pipewire-qt6/)

\[92] Emulation Central - The Something Awful Forums[ https://forums.somethingawful.com/showthread.php?pagenumber=19\&perpage=40\&threadid=4038780\&userid=0](https://forums.somethingawful.com/showthread.php?pagenumber=19\&perpage=40\&threadid=4038780\&userid=0)

\[93] Version 1.22.0 to 1.22.2 Stable Release but no Announcements[ https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/26](https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/26)

\[94] retroarch Cross-platform entertainment system based on libretro API[ https://www.freshports.org/games/retroarch](https://www.freshports.org/games/retroarch)

\[95] Releases · libretro/RetroArch[ https://github.com/libretro/RetroArch/releases/](https://github.com/libretro/RetroArch/releases/)

\[96] RetroArch (f-droid version)[ https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/](https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/)

\[97] RetroGFX/UnofficialOS

&#x20;20260113[ https://newreleases.io/project/github/RetroGFX/UnofficialOS/release/20260113](https://newreleases.io/project/github/RetroGFX/UnofficialOS/release/20260113)

\[98] RetroArch[ https://flathub.org/fil/apps/org.libretro.RetroArch](https://flathub.org/fil/apps/org.libretro.RetroArch)

\[99] retroarch全能模拟器电脑版下载\[Windows 11/10/8/7/Vista/XP]-万能模拟器电脑版下载v1.22.2-k73游戏之家[ http://www.k73.com/down/soft/431682.html](http://www.k73.com/down/soft/431682.html)

\[100] ‎RetroArch App - App Store[ https://apps.apple.com/cn/app/retroarch/id6499539433](https://apps.apple.com/cn/app/retroarch/id6499539433)

\[101] RetroArch 1.22 otimiza emulação em móveis com novidades para iOS e Android[ https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/](https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/)

\[102] RetroArch 1.22 llega con mejoras en móviles, sistema BSV Replay rediseñado y optimizaciones de gráficos y audio[ https://www.linuxadictos.com/retroarch-1-22-llega-con-mejoras-en-moviles-sistema-bsv-replay-redisenado-y-optimizaciones-de-graficos-y-audio.html](https://www.linuxadictos.com/retroarch-1-22-llega-con-mejoras-en-moviles-sistema-bsv-replay-redisenado-y-optimizaciones-de-graficos-y-audio.html)

\[103] RetroArch/CHANGES.md at master · davidhedlund/RetroArch · GitHub[ https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)

\[104] MME4CRT\_OLD\_CRTSwitchRes/CHANGES.md at master · alphanu1/MME4CRT\_OLD\_CRTSwitchRes · GitHub[ https://github.com/alphanu1/MME4CRT\_OLD\_CRTSwitchRes/blob/master/CHANGES.md](https://github.com/alphanu1/MME4CRT_OLD_CRTSwitchRes/blob/master/CHANGES.md)

\[105] RetroArch/CHANGES.md at master · davidhedlund/RetroArch · GitHub[ https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md](https://github.com/davidhedlund/RetroArch/blob/master/CHANGES.md)

\[106] RetroArch 1.22 llega con mejoras en móviles, sistema BSV Replay rediseñado y optimizaciones de gráficos y audio[ https://www.linuxadictos.com/retroarch-1-22-llega-con-mejoras-en-moviles-sistema-bsv-replay-redisenado-y-optimizaciones-de-graficos-y-audio.html](https://www.linuxadictos.com/retroarch-1-22-llega-con-mejoras-en-moviles-sistema-bsv-replay-redisenado-y-optimizaciones-de-graficos-y-audio.html)

\[107] RetroArch (f-droid version)[ https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/](https://www.apkmirror.com/apk/libretro/retroarch-f-droid-version/)

\[108] RetroArch 1.22 otimiza emulação em móveis com novidades para iOS e Android[ https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/](https://www.edivaldobrito.com.br/retroarch-1-22-otimiza-emulacao-em-moveis-com-novidades-para-ios-e-android/)

\[109] ‎RetroArch App - App Store[ https://apps.apple.com/cn/app/retroarch/id6499539433](https://apps.apple.com/cn/app/retroarch/id6499539433)

\[110] Version 1.22.0 to 1.22.2 Stable Release but no Announcements[ https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/8?u=hari-82](https://forums.libretro.com/t/version-1-22-0-to-1-22-2-stable-release-but-no-announcements/49150/8?u=hari-82)

\[111] Howto use the audio callback in a core[ https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866](https://forums.libretro.com/t/howto-use-the-audio-callback-in-a-core/44866)

\[112] RetroArch[ https://ja.wikipedia.org/wiki/RetroArch](https://ja.wikipedia.org/wiki/RetroArch)

\[113] 如何在Linux系统上配置RetroArch的音频驱动，解决声音延迟问题-CSDN博客[ https://blog.csdn.net/gitblog\_00510/article/details/156088085](https://blog.csdn.net/gitblog_00510/article/details/156088085)

\[114] Raspberry Pi[ https://docs.libretro.com/guides/rpi/](https://docs.libretro.com/guides/rpi/)

\[115] Mastering Arch Linux: Resolving Cracking Audio and Screen Centering Anomalies for a Seamless Retro Gaming Experience[ https://retroarchemu.gitlab.io/home/how-i-fixed-cracking-audio-on-my-arch-linux-system-screen-centering-issue-fix-too/](https://retroarchemu.gitlab.io/home/how-i-fixed-cracking-audio-on-my-arch-linux-system-screen-centering-issue-fix-too/)

\[116] 🎮 Retro Gaming Emulation: Simple Guide[ https://krython.com/post/retro-gaming-emulation](https://krython.com/post/retro-gaming-emulation)

\[117] RetroArch[ https://wiki.postmarketos.org/wiki/RetroArch](https://wiki.postmarketos.org/wiki/RetroArch)

\[118] Highly Configurable[ https://www.retroarch.com/configuration.php](https://www.retroarch.com/configuration.php)

\[119] RetroArch Openelec addon Wiki[ https://sourceforge.net/p/retroarch-openelec-addon/wiki/Audio/](https://sourceforge.net/p/retroarch-openelec-addon/wiki/Audio/)

\[120] Developing Libretro Cores[ https://docs.libretro.com/development/cores/developing-cores/](https://docs.libretro.com/development/cores/developing-cores/)

\[121] Libretro - Implementing the core(pdf)[ https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf](https://raw.githubusercontent.com/libretro/docs/master/archive/libretro.pdf)

\[122] rustro\_arch[ https://github.com/RetroGameDeveloper/rustro\_arch](https://github.com/RetroGameDeveloper/rustro_arch)

\[123] Developing Cores[ https://docs.libretro.com/tech/developing-cores/](https://docs.libretro.com/tech/developing-cores/)

\[124] Libretro Development Overview[ https://docs-test-retroa.readthedocs.io/en/latest/development/libretro-overview/](https://docs-test-retroa.readthedocs.io/en/latest/development/libretro-overview/)

\[125] API[ https://www.libretro.com/index.php/api/](https://www.libretro.com/index.php/api/)

\[126] libretro\_hello\_world\_core[ https://github.com/Lightnet/libretro\_hello\_world\_core](https://github.com/Lightnet/libretro_hello_world_core)

\[127] 零延迟游戏体验:RetroArch音频缓冲区与采样率终极优化指南-CSDN博客[ https://blog.csdn.net/gitblog\_00548/article/details/151536385](https://blog.csdn.net/gitblog_00548/article/details/151536385)

\[128] Boost Your RetroArch: Optimizing Settings for Better Performance[ https://toxigon.com/optimizing-retroarch-settings-for-better-performance](https://toxigon.com/optimizing-retroarch-settings-for-better-performance)

\[129] Mastering RAM Consumption: Optimize Your Emulation Experience for Peak Performance[ https://retroarchemu.gitlab.io/home/is-there-any-way-to-lower-ram-consumption/](https://retroarchemu.gitlab.io/home/is-there-any-way-to-lower-ram-consumption/)

\[130] Poor Performance on Retroid Pocket Flip 2 with Citra: A Comprehensive Guide[ https://retroarchemu.gitlab.io/home/poor-performance-please-help/](https://retroarchemu.gitlab.io/home/poor-performance-please-help/)

\[131] Highly Configurable[ https://www.retroarch.com/configuration.php](https://www.retroarch.com/configuration.php)

\[132] New RetroArch Feature - Audio Resampler Quality Setting\![ https://www.youtube.com/watch?v=XLQvyNt0zRk](https://www.youtube.com/watch?v=XLQvyNt0zRk)

\[133] Retropie – Tips ‘n Tricks[ https://www.hiscorebob.lu/2014/05/retropie-tips-n-tricks/](https://www.hiscorebob.lu/2014/05/retropie-tips-n-tricks/)

\[134] Retroarch setup guide[ https://docs.google.com/document/d/18GomYdlg7G28buXRfnN7i9tdzPnwc7yGRqsu5vxgm50/mobilebasic](https://docs.google.com/document/d/18GomYdlg7G28buXRfnN7i9tdzPnwc7yGRqsu5vxgm50/mobilebasic)

\[135] 怀旧游戏模拟器:如何解决声音延迟问题? - 畅玩空间[ https://www.wo1wan.com/gameguide/emulator-audio-latency](https://www.wo1wan.com/gameguide/emulator-audio-latency)

\[136] Getting Optimal Vsync Performance[ https://docs.libretro.com/guides/optimal-vsync/](https://docs.libretro.com/guides/optimal-vsync/)

\[137] RetroArchでレトロゲームの遅延を極限までおさえる設定[ https://note.com/torakurotog/n/nfd29b0de05e5](https://note.com/torakurotog/n/nfd29b0de05e5)

\[138] emulators:retroarch \[Batocera.linux - Wiki][ https://wiki.batocera.org/emulators:retroarch](https://wiki.batocera.org/emulators:retroarch)

\[139] RetroArch/audio/drivers/sdl\_audio.c at master · libretro/RetroArch · GitHub[ https://github.com/libretro/RetroArch/blob/master/audio/drivers/sdl\_audio.c](https://github.com/libretro/RetroArch/blob/master/audio/drivers/sdl_audio.c)

\[140] Libretro – A crossplatform application API, powering the crossplatform gaming platform RetroArch[ https://www.libretro.com/](https://www.libretro.com/)

> （注：文档部分内容可能由 AI 生成）