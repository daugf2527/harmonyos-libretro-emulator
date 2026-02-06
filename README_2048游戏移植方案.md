# HarmonyOS 移植 libretro-2048 游戏完整方案

## 项目概述

将 libretro-2048 游戏成功移植到 HarmonyOS 平台，实现从编译 SO 库、加载运行到正确渲染的完整流程。

---

## 一、编译 libretro-2048 为 HarmonyOS SO 库

### 1.1 准备工作

**所需工具:**
- HarmonyOS NDK
- CMake
- libretro-2048 源码

**目录结构:**
```
NativeSoIntegration/
├── Multiply/
│   └── src/main/cpp/
│       ├── 2048/              # libretro-2048 源码
│       ├── CMakeLists.txt     # 编译配置
│       └── ...
```

### 1.2 CMakeLists.txt 配置

关键配置点:

```cmake
cmake_minimum_required(VERSION 3.4.1)
project(2048_libretro)

# 设置 C 标准
set(CMAKE_C_STANDARD 99)

# 添加源文件
add_library(2048_libretro SHARED
    2048/libretro.c
)

# 编译选项
target_compile_options(2048_libretro PRIVATE
    -fPIC
    -Wall
)

# 链接数学库
target_link_libraries(2048_libretro
    m
    log
)
```

### 1.3 编译产物

编译成功后生成:
- `lib2048_libretro.so` (ARM64)
- 位置: `entry/libs/arm64-v8a/`

---

## 二、NAPI 封装层实现

### 2.1 核心功能

在 `game2048_wrapper.cpp` 中实现 libretro API 的 NAPI 封装:

**主要接口:**
1. `InitGame()` - 初始化游戏
2. `RunFrame()` - 运行一帧
3. `GetFrame()` - 获取帧数据
4. `SendInput()` - 发送输入

### 2.2 关键实现

#### 2.2.1 帧缓冲区管理

```cpp
static uint8_t* g_frame_buffer = nullptr;
static size_t g_frame_buffer_size = 0;
static unsigned g_frame_width = 0;
static unsigned g_frame_height = 0;
```

#### 2.2.2 视频刷新回调 (Pitch-Aware)

**问题:** libretro 提供的 `pitch` 可能不等于 `width * 4`

**解决方案:** 逐行复制

```cpp
static void video_refresh_callback(const void *data, unsigned width, 
                                   unsigned height, size_t pitch) {
    if (!data) return;
    
    size_t required_size = width * height * 4;
    
    // 重新分配缓冲区
    if (g_frame_buffer_size < required_size) {
        free(g_frame_buffer);
        g_frame_buffer = (uint8_t*)malloc(required_size);
        g_frame_buffer_size = required_size;
    }
    
    const uint8_t* src = (const uint8_t*)data;
    uint8_t* dst = g_frame_buffer;
    size_t row_bytes = width * 4;
    
    // Pitch-aware 复制
    if (pitch == row_bytes) {
        // 直接复制
        memcpy(dst, src, required_size);
    } else {
        // 逐行复制
        for (unsigned y = 0; y < height; y++) {
            memcpy(dst + y * row_bytes, src + y * pitch, row_bytes);
        }
    }
    
    g_frame_width = width;
    g_frame_height = height;
}
```

#### 2.2.3 GetFrame 返回帧数据

```cpp
static napi_value GetFrame(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);
    
    // 返回 ArrayBuffer
    void* buffer_data;
    napi_value array_buffer;
    napi_create_arraybuffer(env, g_frame_buffer_size, &buffer_data, &array_buffer);
    memcpy(buffer_data, g_frame_buffer, g_frame_buffer_size);
    
    // 设置属性
    napi_set_named_property(env, result, "data", array_buffer);
    napi_set_named_property(env, result, "width", width_value);
    napi_set_named_property(env, result, "height", height_value);
    
    return result;
}
```

---

## 三、ArkTS 层渲染实现

### 3.1 Canvas 初始化

```typescript
private canvasContext: CanvasRenderingContext2D = 
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

Canvas(this.canvasContext)
  .width(376)
  .height(464)
  .backgroundColor('#000000')
```

### 3.2 像素格式转换

**问题:** Native 层使用 XRGB8888 (内存中为 BGRA)，Canvas 需要 RGBA

**解决方案:** 逐字节转换

```typescript
let pixelCount = frame.width * frame.height;
let rgbaData = new Uint8ClampedArray(pixelCount * 4);
let srcData = new Uint8ClampedArray(frame.data);

// BGRA -> RGBA 转换
for (let i = 0; i < pixelCount; i++) {
  let srcIdx = i * 4;
  let dstIdx = i * 4;
  rgbaData[dstIdx + 0] = srcData[srcIdx + 2]; // R
  rgbaData[dstIdx + 1] = srcData[srcIdx + 1]; // G
  rgbaData[dstIdx + 2] = srcData[srcIdx + 0]; // B
  rgbaData[dstIdx + 3] = 255;                 // A
}
```

### 3.3 ImageData 创建 (关键修复)

**问题:** HarmonyOS 的 `ImageData` 构造函数默认使用 `vp` (虚拟像素)，在高 DPI 设备上会自动缩放

**现象:**
- 游戏帧: 376×464 = 697,856 字节
- ImageData: 1081×1334 = 5,768,216 字节 (错误!)
- 导致花屏

**解决方案:** 使用 `LengthMetricsUnit.PX` 强制指定物理像素

```typescript
import { LengthMetricsUnit } from '@ohos.arkui.node';

// 创建 ImageData - 必须指定单位为 PX
let imageData = new ImageData(
  frame.width,           // 376
  frame.height,          // 464
  rgbaData,              // 转换后的 RGBA 数据
  LengthMetricsUnit.PX   // 关键!指定单位为物理像素
);
```

### 3.4 渲染到 Canvas

```typescript
// 绘制到 Canvas
this.canvasContext.putImageData(imageData, 0, 0);
```

---

## 四、问题排查与解决

### 4.1 花屏问题诊断流程

#### 问题现象
Canvas 显示横条纹花屏，游戏内容无法正常显示

#### 排查步骤

**1. 添加详细日志**

Native 层:
```cpp
// 记录 pitch 信息
hilog_info("Pitch: %zu, 理论: %zu", pitch, width * 4);

// 记录像素数据
uint32_t* pixels = (uint32_t*)data;
hilog_info("左上角像素: 0x%08x", pixels[0]);
```

ArkTS 层:
```typescript
// 记录 ImageData 尺寸
hilog.info(`ImageData 尺寸: ${imageData.width}x${imageData.height}`);

// 记录像素值
hilog.info(`像素[0]: R=${r}, G=${g}, B=${b}, A=${a}`);
```

**2. 发现问题**

日志对比:
```
✅ 游戏帧: 376×464 = 697,856 字节
✅ 像素数据: #faf8ef (正确的浅米色背景)
✅ Pitch: 1504 字节 = 376×4 (匹配)
❌ ImageData: 1081×1334 = 5,768,216 字节 (不匹配!)
```

**3. 根因分析**

通过查阅 HarmonyOS 官方文档发现:
- `ImageData` 构造函数的 `width` 和 `height` 默认单位是 `vp` (虚拟像素)
- 在高 DPI 设备上，vp 会自动转换为物理像素
- 376vp × DPR(2.875) ≈ 1081px

### 4.2 其他可能的花屏原因

1. **Pitch 不匹配** - 已通过逐行复制解决
2. **像素格式错误** - 已通过 BGRA→RGBA 转换解决
3. **ImageData 尺寸单位** - 已通过 `LengthMetricsUnit.PX` 解决

---

## 五、完整代码示例

### 5.1 ArkTS 渲染函数

```typescript
private renderFrame(frame: FrameData) {
  if (!this.canvasContext) return;
  
  // 清空画布
  this.canvasContext.clearRect(0, 0, 
    this.canvasContext.width, 
    this.canvasContext.height);
  
  // 创建 RGBA 数据
  let pixelCount = frame.width * frame.height;
  let rgbaData = new Uint8ClampedArray(pixelCount * 4);
  let srcData = new Uint8ClampedArray(frame.data);
  
  // BGRA -> RGBA 转换
  for (let i = 0; i < pixelCount; i++) {
    let srcIdx = i * 4;
    let dstIdx = i * 4;
    rgbaData[dstIdx + 0] = srcData[srcIdx + 2]; // R
    rgbaData[dstIdx + 1] = srcData[srcIdx + 1]; // G
    rgbaData[dstIdx + 2] = srcData[srcIdx + 0]; // B
    rgbaData[dstIdx + 3] = 255;                 // A
  }
  
  // 创建 ImageData (指定 PX 单位)
  let imageData = new ImageData(
    frame.width, 
    frame.height, 
    rgbaData, 
    LengthMetricsUnit.PX
  );
  
  // 渲染到 Canvas
  this.canvasContext.putImageData(imageData, 0, 0);
  
  this.renderCount++;
}
```

### 5.2 游戏循环

```typescript
private startGame() {
  this.intervalId = setInterval(() => {
    testNapi.runFrame();
    let frame = testNapi.getFrame();
    if (frame && frame.data) {
      this.renderFrame(frame);
    }
  }, 33); // ~30 FPS
}
```

---

## 六、关键技术点总结

### 6.1 必须注意的问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Pitch 不匹配 | libretro 可能使用内存对齐 | 逐行复制而非直接 memcpy |
| 像素格式错误 | Native BGRA vs Canvas RGBA | 逐字节转换 B↔R |
| ImageData 尺寸错误 | HarmonyOS 默认使用 vp 单位 | 指定 `LengthMetricsUnit.PX` |

### 6.2 性能优化

1. **帧缓冲区复用** - 避免频繁分配内存
2. **批量像素转换** - 使用循环而非逐像素处理
3. **合理的帧率** - 30-60 FPS

### 6.3 调试技巧

1. **添加详细日志** - 记录尺寸、pitch、像素值
2. **对比数据** - Native 层 vs ArkTS 层
3. **查阅官方文档** - 确认 API 行为而非猜测

---

## 七、项目文件清单

```
NativeSoIntegration/
├── Multiply/
│   └── src/main/cpp/
│       ├── 2048/                    # libretro-2048 源码
│       └── CMakeLists.txt           # 编译配置
├── entry/
│   ├── libs/
│   │   └── arm64-v8a/
│   │       └── lib2048_libretro.so  # 编译产物
│   └── src/main/
│       ├── cpp/
│       │   └── game2048_wrapper.cpp # NAPI 封装
│       └── ets/pages/
│           └── Game2048.ets         # ArkTS 渲染
└── README_2048游戏移植方案.md       # 本文档
```

---

## 八、运行效果

✅ **成功指标:**
- ImageData 尺寸: 376×464 (正确)
- 像素数据: 697,856 字节 (匹配)
- 游戏画面清晰，无花屏
- 帧率稳定 ~30 FPS

---

## 九、参考资料

1. [HarmonyOS ImageData 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-components-canvas-imagedata)
2. [Libretro API 文档](https://docs.libretro.com/)
3. [HarmonyOS Canvas API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-components-canvas-canvasrenderingcontext2d)

---

## 十、总结

本项目成功实现了 libretro-2048 游戏在 HarmonyOS 平台的完整移植，关键突破点在于:

1. ✅ **正确处理 Pitch** - 逐行复制帧数据
2. ✅ **像素格式转换** - BGRA → RGBA
3. ✅ **ImageData 单位指定** - 使用 `LengthMetricsUnit.PX` (最关键)

通过详细的日志分析和官方文档查阅，最终定位并解决了花屏问题，为后续移植其他 libretro 核心提供了完整的参考方案。

---

**文档版本:** 1.0  
**最后更新:** 2024-12-09  
**作者:** Cascade AI Assistant
