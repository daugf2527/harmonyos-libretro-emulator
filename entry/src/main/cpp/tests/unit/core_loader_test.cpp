/*
 * CoreLoader 测试代码
 * Phase 3.1 - 验证动态加载功能
 *
 * 使用方法:
 * 1. 将 Libretro 核心 (.so) 放入 entry/libs/arm64/ 目录
 * 2. 在应用侧或其他测试入口调用此测试函数
 * 3. 查看日志验证加载是否成功
 */

#include "core/libretro/core_loader.h"
#include <hilog/log.h>
#include <string>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD000
#undef LOG_TAG
#define LOG_TAG "CoreLoaderTest"
#undef LOG_FLOW
#define LOG_FLOW "Test"
#include "common/log_prefix.h"

namespace LibretroTest {

/**
 * 测试 CoreLoader 基本功能
 *
 * @param corePath Libretro 核心的沙箱路径
 *                 例如: "/data/storage/el1/bundle/libs/arm64/libretro_core.so"
 * @return true 如果测试通过
 */
bool TestCoreLoader(const std::string &corePath) {
  LOGF(LOG_INFO, "========== CoreLoader Test Start ==========");
  LOGF(LOG_INFO, "Core path: %{public}s", corePath.c_str());

  // 1. 创建 CoreLoader 实例
  CoreLoader loader;

  // 2. 加载核心
  LOGF(LOG_INFO, "Step 1: Loading core...");
  if (!loader.LoadCore(corePath)) {
    LOGF(LOG_ERROR, " Failed to load core");
    return false;
  }
  LOGF(LOG_INFO, " Core loaded successfully");

  // 3. 验证核心已加载
  if (!loader.IsLoaded()) {
    LOGF(LOG_ERROR, " IsLoaded() returned false");
    return false;
  }
  LOGF(LOG_INFO, " IsLoaded() check passed");

  // 4. 验证必需函数指针
  LOGF(LOG_INFO, "Step 2: Verifying function pointers...");

  if (!loader.GetInit()) {
    LOGF(LOG_ERROR, " retro_init is null");
    return false;
  }

  if (!loader.GetDeinit()) {
    LOGF(LOG_ERROR, " retro_deinit is null");
    return false;
  }

  if (!loader.GetApiVersion()) {
    LOGF(LOG_ERROR, " retro_api_version is null");
    return false;
  }

  if (!loader.GetSystemInfo()) {
    LOGF(LOG_ERROR, " retro_get_system_info is null");
    return false;
  }

  if (!loader.GetSetEnvironment()) {
    LOGF(LOG_ERROR, " retro_set_environment is null");
    return false;
  }

  if (!loader.GetSetVideoRefresh()) {
    LOGF(LOG_ERROR, " retro_set_video_refresh is null");
    return false;
  }

  if (!loader.GetSetAudioSampleBatch()) {
    LOGF(LOG_ERROR, " retro_set_audio_sample_batch is null");
    return false;
  }

  if (!loader.GetSetInputPoll()) {
    LOGF(LOG_ERROR, " retro_set_input_poll is null");
    return false;
  }

  if (!loader.GetSetInputState()) {
    LOGF(LOG_ERROR, " retro_set_input_state is null");
    return false;
  }

  if (!loader.GetLoadGame()) {
    LOGF(LOG_ERROR, " retro_load_game is null");
    return false;
  }

  if (!loader.GetRun()) {
    LOGF(LOG_ERROR, " retro_run is null");
    return false;
  }

  LOGF(LOG_INFO, " All required function pointers are valid");

  // 5. 调用 API 版本函数
  LOGF(LOG_INFO, "Step 3: Calling retro_api_version()...");
  unsigned apiVersion = loader.GetApiVersion()();
  LOGF(LOG_INFO, " API Version: %{public}u", apiVersion);

  // 6. 调用系统信息函数
  LOGF(LOG_INFO, "Step 4: Calling retro_get_system_info()...");
  struct retro_system_info sysInfo = {};
  loader.GetSystemInfo()(&sysInfo);
  LOGF(LOG_INFO, " System Info:");
  LOGF(LOG_INFO, "   Name: %{public}s", sysInfo.library_name);
  LOGF(LOG_INFO, "   Version: %{public}s", sysInfo.library_version);
  LOGF(LOG_INFO, "   Extensions: %{public}s", sysInfo.valid_extensions);
  LOGF(LOG_INFO, "   Need fullpath: %{public}d", sysInfo.need_fullpath);
  LOGF(LOG_INFO, "   Block extract: %{public}d", sysInfo.block_extract);

  // 7. 卸载核心
  LOGF(LOG_INFO, "Step 5: Unloading core...");
  loader.UnloadCore();

  if (loader.IsLoaded()) {
    LOGF(LOG_ERROR, " Core still loaded after UnloadCore()");
    return false;
  }
  LOGF(LOG_INFO, " Core unloaded successfully");

  // 8. 测试重复加载
  LOGF(LOG_INFO, "Step 6: Testing reload...");
  if (!loader.LoadCore(corePath)) {
    LOGF(LOG_ERROR, " Failed to reload core");
    return false;
  }
  LOGF(LOG_INFO, " Core reloaded successfully");

  LOGF(LOG_INFO, "========== CoreLoader Test PASSED ==========");
  return true;
}

/**
 * 测试错误处理
 *
 * 已知局限 (XFAIL): Test 2 "Double loading" 依赖一个真实存在的 .so 文件,
 * 在 CI 环境下该路径永远不存在,所以 Test 2 实际上会被 Skipped(line ~180)。
 * 这导致"防止双重加载"路径在 CI 中**未被验证**。
 *
 * 改造方向(单独 PR):
 *   1) 写一个最小化 stub .so(只导出 retro_api_version 等必须符号),
 *      让 Test 2 始终能跑;或
 *   2) 改测试预期为"两次加载不存在路径都返回 false",虽然不验真实分支,
 *      但能跑;或
 *   3) 引入测试框架(doctest)按平台条件 SKIP 而非静默"成功"。
 */
bool TestErrorHandling() {
  LOGF(LOG_INFO, "========== Error Handling Test Start ==========");

  CoreLoader loader;

  // 1. 测试加载不存在的文件
  LOGF(LOG_INFO, "Test 1: Loading non-existent file...");
  if (loader.LoadCore("/invalid/path/libretro_fake.so")) {
    LOGF(LOG_ERROR, " Should have failed to load non-existent file");
    return false;
  }
  LOGF(LOG_INFO, " Correctly failed to load non-existent file");

  // 2. 测试重复加载
  LOGF(LOG_INFO, "Test 2: Double loading...");
  // 假设有一个有效的核心路径
  std::string validPath =
      "/data/storage/el1/bundle/libs/arm64/libretro_core.so";
  if (loader.LoadCore(validPath)) {
    if (loader.LoadCore(validPath)) {
      LOGF(LOG_ERROR, " Should have prevented double loading");
      return false;
    }
    LOGF(LOG_INFO, " Correctly prevented double loading");
  } else {
    LOGF(LOG_INFO, " Skipped double loading test (no valid core available)");
  }

  LOGF(LOG_INFO, "========== Error Handling Test PASSED ==========");
  return true;
}

} // namespace LibretroTest
