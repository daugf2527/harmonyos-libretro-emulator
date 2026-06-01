# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(zmw)

set(CMAKE_CXX_STANDARD 14)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/core
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${NATIVERENDER_ROOT_PATH}/interfaces)

# ========== Common 层源文件 ==========
set(COMMON_SOURCES
    common/utils.cpp
    common/fence_utils.cpp
    common/file_security.cpp
    common/cue_parser.cpp
    common/config/file_configuration.cpp
    common/diagnostics/logger_provider.cpp
)

# ========== Core层源文件 (Libretro规范) ==========
# Core层: 平台无关的libretro核心实现
set(CORE_SOURCES
    core/libretro/core_loader.cpp
    core/libretro/env_dispatcher.cpp
    core/libretro/core_options_registry.cpp
)

# Core层: 重构后的引擎核心 (Phase 1)
set(REFACTORED_ENGINE_SOURCES
    core/engine/libretro_engine.cpp
    core/engine/frame_buffer_pool.cpp
    core/engine/render_thread.cpp
    core/engine/window_session.cpp
    core/engine/video_pipeline.cpp
    core/engine/window_state_manager.cpp
    core/engine/event_bridge.cpp
    core/engine/input_manager.cpp
    core/engine/input_port_router.cpp
    core/engine/core_state_manager.cpp
    core/engine/core_quirks_manager.cpp
    core/libretro/disk_controller.cpp
)

# ========== Platform层源文件 (HarmonyOS特定) ==========
# Platform层: 音频子系统
set(PLATFORM_AUDIO_SOURCES
    platform/audio/audio_bridge.cpp
    platform/audio/audio_player.cpp
    platform/audio/audio_resampler.cpp
    platform/audio/ring_buffer.cpp
)

# Platform层: 图形子系统
set(PLATFORM_GRAPHICS_SOURCES
    platform/graphics/gles_renderer.cpp
    platform/graphics/graphics_context.cpp
    platform/graphics/hw_render_presenter.cpp
    platform/graphics/vulkan_loader.cpp
    platform/graphics/vulkan_context.cpp
    platform/graphics/vulkan_presenter.cpp
)

set(PLATFORM_SYNC_SOURCES
    platform/sync/native_vsync_driver.cpp
)

if (${OHOS_ARCH} STREQUAL "arm64-v8a" OR ${OHOS_ARCH} STREQUAL "armeabi-v7a")
    list(APPEND PLATFORM_GRAPHICS_SOURCES platform/graphics/pixel_converter_neon.cpp)
else()
    list(APPEND PLATFORM_GRAPHICS_SOURCES platform/graphics/pixel_converter_scalar.cpp)
endif()

# Platform层: 资源子系统
set(PLATFORM_RESOURCE_SOURCES
    platform/resource/rom_loader.cpp
    platform/resource/platform_resource_manager.cpp
    platform/resource/temp_file_manager.cpp
    platform/resource/rawfile_rom_processor.cpp
)

# ========== Application层源文件 (游戏应用) ==========
# Application层: 应用框架
set(APP_FRAMEWORK_SOURCES
    app/framework/plugin_manager.cpp
)

# Application层: NAPI入口 (libretro_engine_napi 已拆分为领域模块)
set(APP_NAPI_SOURCES
    app/napi/module_init.cpp
    app/napi/core_loader_napi.cpp
    app/napi/libretro_engine_napi.cpp
    app/napi/engine_lifecycle_napi.cpp
    app/napi/engine_input_napi.cpp
    app/napi/engine_video_napi.cpp
    app/napi/engine_state_napi.cpp
    app/napi/engine_disk_napi.cpp
    app/napi/engine_query_napi.cpp
    app/napi/input_mapping_napi.cpp
)

add_library(entry SHARED
    ${COMMON_SOURCES}
    ${CORE_SOURCES}
    ${REFACTORED_ENGINE_SOURCES}
    ${PLATFORM_AUDIO_SOURCES}
    ${PLATFORM_GRAPHICS_SOURCES}
    ${PLATFORM_SYNC_SOURCES}
    ${PLATFORM_RESOURCE_SOURCES}
    ${APP_FRAMEWORK_SOURCES}
    ${APP_NAPI_SOURCES}
)

find_library(
    # Sets the name of the path variable.
    hilog-lib
    # Specifies the name of the NDK library that
    # you want CMake to locate.
    hilog_ndk.z
)

# ========== 测试可执行目标 (独立于 libentry.so) ==========
# 启用方式: cmake -DBUILD_LIBRETRO_TESTS=ON ...
# 默认 OFF: HAP 构建不引入测试,避免污染发布产物。
# CI 应在独立 step 中以 ON 构建并执行 libretro_tests。
option(BUILD_LIBRETRO_TESTS "Build libretro unit/integration tests" OFF)
if(BUILD_LIBRETRO_TESTS)
    add_executable(libretro_tests
        tests/unit/core_loader_test.cpp
        tests/integration/test_gambatte_load.cpp
        tests/integration/test_gambatte_rom.cpp
    )
    target_link_libraries(libretro_tests PRIVATE ${hilog-lib} dl)
endif()

target_link_libraries(entry PUBLIC ${hilog-lib})
target_link_libraries(entry PUBLIC libace_napi.z.so)
target_link_libraries(entry PUBLIC libace_ndk.z.so)
target_link_libraries(entry PUBLIC libnative_window.so)
target_link_libraries(entry PUBLIC libnative_vsync.so)
target_link_libraries(entry PUBLIC libnative_buffer.so)
target_link_libraries(entry PUBLIC libohaudio.so)  # Phase 3.3 - 音频播放库
target_link_libraries(entry PUBLIC libohfileuri.so)  # Phase 3.6 - 文件 URI 库
target_link_libraries(entry PUBLIC librawfile.z.so)  # Rawfile 资源管理器库
target_link_libraries(entry PUBLIC libEGL.so)
target_link_libraries(entry PUBLIC libGLESv3.so)
target_link_libraries(entry PUBLIC dl) # Link dl to ensure dlopen/dlsym are available

# ========== HMS (Huawei Mobile Services) Library Configuration ==========
# Logic to automatically locate HMS Native SDK based on the OpenHarmony SDK path.
# CMAKE_SYSROOT usually points to .../openharmony/native/sysroot
get_filename_component(SDK_NATIVE_DIR ${CMAKE_SYSROOT} DIRECTORY) # .../native
get_filename_component(SDK_ROOT_DIR ${SDK_NATIVE_DIR} DIRECTORY)  # .../openharmony
get_filename_component(SDK_BASE_DIR ${SDK_ROOT_DIR} DIRECTORY)    # .../default
set(HMS_ROOT_PATH "${SDK_BASE_DIR}/hms/native/sysroot/usr")

# Add HMS include directories (for XEngine headers)
include_directories("${HMS_ROOT_PATH}/include")

# Determine architecture-specific library path
if(${OHOS_ARCH} STREQUAL "arm64-v8a")
    set(HMS_ARCH_DIR "aarch64-linux-ohos")
elseif(${OHOS_ARCH} STREQUAL "x86_64")
    set(HMS_ARCH_DIR "x86_64-linux-ohos")
else()
    set(HMS_ARCH_DIR "arm-linux-ohos")
endif()

# Find libxengine.so explicitly - REMOVED for dlopen support
# find_library(
#     xengine-lib
#     xengine
#     PATHS "${HMS_ROOT_PATH}/lib/${HMS_ARCH_DIR}"
#     NO_DEFAULT_PATH
# )

# if(xengine-lib)
#     message(STATUS "Found libxengine: ${xengine-lib}")
#     target_link_libraries(entry PUBLIC ${xengine-lib})
# else()
#     message(WARNING "libxengine not found in ${HMS_ROOT_PATH}/lib/${HMS_ARCH_DIR}")
# endif()

# Link other libraries
# QoS: official guide recommends direct link because libqos.so is in NDK link path.
target_link_libraries(entry PUBLIC libqos.so)

# Dynamic loading only - no link time dependency
# target_link_libraries(entry PUBLIC libxengine.so)

# ========== 三方 .so 库打包配置 (华为官方方案) ==========
# 参考: https://gitee.com/harmonyos_samples/NativeSoIntegration
#
# Phase 3.1: 使用 dlopen 动态加载 Libretro 核心
#
# 重要: 不要在编译时链接 libretro_2048.so!
# 原因: 编译时链接会让 libentry.so 依赖 libretro_2048.so,
#       导致加载 libentry.so 时报错 "No such file or directory"
#
# 正确做法:
# 1. 将 libretro_2048.so 放在 entry/libs/arm64-v8a/ 目录
# 2. 构建系统会自动将其打包到 HAP 中
# 3. 运行时通过 dlopen() 动态加载
#
# 不需要任何 target_link_libraries 配置!

# ========== NEON SIMD 优化配置 (华为官方方案) ==========
# 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/neon-guide
#
# arm64-v8a: NEON 默认启用,添加编译优化选项
# armeabi-v7a: 需要显式启用 NEON (当前项目不使用)

if (${OHOS_ARCH} STREQUAL "arm64-v8a")
    # 添加优化选项
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ftree-vectorize")
    message(STATUS "NEON optimization enabled for arm64-v8a")
    message(STATUS "   Compiler flags: ${CMAKE_CXX_FLAGS}")
elseif (${OHOS_ARCH} STREQUAL "armeabi-v7a")
    # armeabi-v7a 需要显式启用 NEON
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mfpu=neon -mfloat-abi=softfp -O3")
    message(STATUS "NEON optimization enabled for armeabi-v7a")
endif()
