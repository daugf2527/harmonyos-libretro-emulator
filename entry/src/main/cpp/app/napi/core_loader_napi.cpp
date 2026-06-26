/*
 * CoreLoader NAPI 接口
 * Phase 3.1 - 暴露给 ArkTS 的测试接口
 * 遵循鸿蒙官方最佳实践: Native侧实现文件访问
 * 参考:
 * https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-file-native-side
 */

#include "core/libretro/core_loader.h"
#include "common/file_security.h"
#include "napi/native_api.h"
#include <elf.h>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD001
#define LOG_TAG "CoreLoaderNapi"
#undef LOG_FLOW
#define LOG_FLOW "NAPI"
#include "common/log_prefix.h"

namespace {
struct NeededResult {
  std::vector<std::string> libs;
  std::string error;
};

static bool ReadFile(const std::string &path, std::vector<uint8_t> &data,
                     std::string &error) {
  int fd = open(path.c_str(), O_RDONLY);
  if (fd < 0) {
    error = "open failed";
    return false;
  }
  struct stat st;
  if (fstat(fd, &st) != 0 || st.st_size <= 0) {
    close(fd);
    error = "stat failed";
    return false;
  }
  constexpr off_t kMaxElfSize = 256 * 1024 * 1024;
  if (st.st_size > kMaxElfSize) {
    close(fd);
    error = "file too large";
    return false;
  }
  data.resize(static_cast<size_t>(st.st_size));
  size_t total = 0;
  while (total < data.size()) {
    ssize_t rd = read(fd, data.data() + total, data.size() - total);
    if (rd <= 0) {
      close(fd);
      error = "read failed";
      return false;
    }
    total += static_cast<size_t>(rd);
  }
  close(fd);
  return true;
}

static bool GetStringArg(napi_env env, napi_value arg, std::string &out,
                         const char *func, const char *argName) {
  size_t size = 0;
  napi_status status = napi_get_value_string_utf8(env, arg, nullptr, 0, &size);
  if (status != napi_ok || size == 0) {
    LOGF(LOG_ERROR,
                 "%s invalid string arg: %{public}s", func, argName);
    return false;
  }
  std::string buffer;
  buffer.resize(size + 1);
  status =
      napi_get_value_string_utf8(env, arg, &buffer[0], buffer.size(), &size);
  if (status != napi_ok || size == 0) {
    LOGF(LOG_ERROR,
                 "%s invalid string arg: %{public}s", func, argName);
    return false;
  }
  buffer.resize(size);
  out.swap(buffer);
  return true;
}

static napi_value MakeString(napi_env env, const std::string &value) {
  napi_value result = nullptr;
  if (napi_create_string_utf8(env, value.c_str(), NAPI_AUTO_LENGTH, &result) !=
      napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create string value");
    return nullptr;
  }
  return result;
}

static napi_value MakeString(napi_env env, const char *value) {
  return MakeString(env, std::string(value ? value : ""));
}

static napi_value MakeUndefined(napi_env env) {
  napi_value result = nullptr;
  if (napi_get_undefined(env, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create undefined value");
    return nullptr;
  }
  return result;
}

static bool ResolveDeferredChecked(napi_env env, napi_deferred deferred,
                                   napi_value value) {
  if (!deferred || !value) {
    napi_throw_error(env, nullptr, "Invalid promise resolution value");
    return false;
  }
  if (napi_resolve_deferred(env, deferred, value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to resolve promise");
    return false;
  }
  return true;
}

static bool RejectDeferredChecked(napi_env env, napi_deferred deferred,
                                  napi_value reason) {
  if (!deferred || !reason) {
    napi_throw_error(env, nullptr, "Invalid promise rejection reason");
    return false;
  }
  if (napi_reject_deferred(env, deferred, reason) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to reject promise");
    return false;
  }
  return true;
}

static napi_value MakeResolvedStringPromise(napi_env env, const char *message) {
  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok || !deferred) {
    napi_throw_error(env, nullptr, "Failed to create promise");
    return nullptr;
  }
  napi_value str = MakeString(env, message);
  if (!str) {
    return nullptr;
  }
  if (!ResolveDeferredChecked(env, deferred, str)) {
    return nullptr;
  }
  return promise;
}

static bool MapVaddrToOffset64(const Elf64_Phdr *phdrs, uint16_t phnum,
                               Elf64_Addr vaddr, size_t &out_offset) {
  for (uint16_t i = 0; i < phnum; ++i) {
    if (phdrs[i].p_type != PT_LOAD) {
      continue;
    }
    const Elf64_Addr seg_start = phdrs[i].p_vaddr;
    const Elf64_Addr seg_end = seg_start + phdrs[i].p_memsz;
    if (vaddr >= seg_start && vaddr < seg_end) {
      out_offset = static_cast<size_t>(vaddr - seg_start + phdrs[i].p_offset);
      return true;
    }
  }
  return false;
}

static bool MapVaddrToOffset32(const Elf32_Phdr *phdrs, uint16_t phnum,
                               Elf32_Addr vaddr, size_t &out_offset) {
  for (uint16_t i = 0; i < phnum; ++i) {
    if (phdrs[i].p_type != PT_LOAD) {
      continue;
    }
    const Elf32_Addr seg_start = phdrs[i].p_vaddr;
    const Elf32_Addr seg_end = seg_start + phdrs[i].p_memsz;
    if (vaddr >= seg_start && vaddr < seg_end) {
      out_offset = static_cast<size_t>(vaddr - seg_start + phdrs[i].p_offset);
      return true;
    }
  }
  return false;
}

static bool IsRangeWithin(size_t offset, size_t length, size_t total) {
  return offset <= total && length <= (total - offset);
}

template <typename HeaderType>
static bool IsProgramHeaderTableValid(size_t phoff, uint16_t phnum,
                                      uint16_t phentsize, size_t total) {
  if (phentsize != sizeof(HeaderType)) {
    return false;
  }
  const size_t entrySize = sizeof(HeaderType);
  if (phnum > 0 &&
      phnum > (std::numeric_limits<size_t>::max() / entrySize)) {
    return false;
  }
  const size_t tableSize = static_cast<size_t>(phnum) * entrySize;
  return IsRangeWithin(phoff, tableSize, total);
}

static bool ReadBoundedCString(const std::vector<uint8_t> &data, size_t offset,
                               std::string &out) {
  if (offset >= data.size()) {
    return false;
  }
  const char *start = reinterpret_cast<const char *>(data.data() + offset);
  const size_t maxLen = data.size() - offset;
  const void *nul = std::memchr(start, '\0', maxLen);
  if (!nul) {
    return false;
  }
  const char *end = reinterpret_cast<const char *>(nul);
  out.assign(start, static_cast<size_t>(end - start));
  return !out.empty();
}

static NeededResult ReadNeededLibrariesFromElf(const std::string &corePath) {
  NeededResult result;
  std::vector<uint8_t> data;
  if (!ReadFile(corePath, data, result.error)) {
    return result;
  }
  if (data.size() < EI_NIDENT) {
    result.error = "ELF header too small";
    return result;
  }
  const unsigned char *ident = data.data();
  if (ident[EI_MAG0] != ELFMAG0 || ident[EI_MAG1] != ELFMAG1 ||
      ident[EI_MAG2] != ELFMAG2 || ident[EI_MAG3] != ELFMAG3) {
    result.error = "not an ELF file";
    return result;
  }

  if (ident[EI_CLASS] == ELFCLASS64) {
    if (data.size() < sizeof(Elf64_Ehdr)) {
      result.error = "ELF64 header too small";
      return result;
    }
    const Elf64_Ehdr *ehdr =
        reinterpret_cast<const Elf64_Ehdr *>(data.data());
    const size_t phoff = static_cast<size_t>(ehdr->e_phoff);
    if (static_cast<Elf64_Off>(phoff) != ehdr->e_phoff) {
      result.error = "ELF64 phoff overflow";
      return result;
    }
    if (!IsProgramHeaderTableValid<Elf64_Phdr>(phoff, ehdr->e_phnum,
                                               ehdr->e_phentsize,
                                               data.size())) {
      result.error = "ELF64 phdr table out of range";
      return result;
    }
    const Elf64_Phdr *phdrs =
        reinterpret_cast<const Elf64_Phdr *>(data.data() + phoff);
    Elf64_Off dyn_offset = 0;
    Elf64_Xword dyn_size = 0;
    bool dyn_found = false;
    for (uint16_t i = 0; i < ehdr->e_phnum; ++i) {
      if (phdrs[i].p_type == PT_DYNAMIC) {
        dyn_offset = phdrs[i].p_offset;
        dyn_size = phdrs[i].p_filesz;
        dyn_found = true;
        break;
      }
    }
    if (!dyn_found || dyn_size == 0) {
      result.error = "PT_DYNAMIC not found";
      return result;
    }
    const size_t dynOffset = static_cast<size_t>(dyn_offset);
    const size_t dynSize = static_cast<size_t>(dyn_size);
    if (static_cast<Elf64_Off>(dynOffset) != dyn_offset ||
        static_cast<Elf64_Xword>(dynSize) != dyn_size ||
        !IsRangeWithin(dynOffset, dynSize, data.size())) {
      result.error = "ELF64 dynamic section out of range";
      return result;
    }
    const Elf64_Dyn *dyn =
        reinterpret_cast<const Elf64_Dyn *>(data.data() + dynOffset);
    size_t dyn_count = dynSize / sizeof(Elf64_Dyn);
    Elf64_Addr strtab_vaddr = 0;
    bool strtab_found = false;
    for (size_t i = 0; i < dyn_count; ++i) {
      if (dyn[i].d_tag == DT_STRTAB) {
        strtab_vaddr = static_cast<Elf64_Addr>(dyn[i].d_un.d_ptr);
        strtab_found = true;
        break;
      }
    }
    if (!strtab_found) {
      result.error = "DT_STRTAB not found";
      return result;
    }
    size_t strtab_offset = 0;
    if (!MapVaddrToOffset64(phdrs, ehdr->e_phnum, strtab_vaddr,
                            strtab_offset)) {
      result.error = "failed to map strtab vaddr";
      return result;
    }
    for (size_t i = 0; i < dyn_count; ++i) {
      if (dyn[i].d_tag == DT_NEEDED) {
        const size_t needed_offset = static_cast<size_t>(dyn[i].d_un.d_val);
        if (strtab_offset > data.size() ||
            needed_offset > data.size() - strtab_offset) {
          result.error = "ELF64 DT_NEEDED offset out of range";
          return result;
        }
        const size_t name_offset = strtab_offset + needed_offset;
        std::string libName;
        if (!ReadBoundedCString(data, name_offset, libName)) {
          result.error = "ELF64 DT_NEEDED string not terminated";
          return result;
        }
        result.libs.emplace_back(std::move(libName));
      }
    }
    return result;
  }

  if (ident[EI_CLASS] == ELFCLASS32) {
    if (data.size() < sizeof(Elf32_Ehdr)) {
      result.error = "ELF32 header too small";
      return result;
    }
    const Elf32_Ehdr *ehdr =
        reinterpret_cast<const Elf32_Ehdr *>(data.data());
    const size_t phoff = static_cast<size_t>(ehdr->e_phoff);
    if (static_cast<Elf32_Off>(phoff) != ehdr->e_phoff) {
      result.error = "ELF32 phoff overflow";
      return result;
    }
    if (!IsProgramHeaderTableValid<Elf32_Phdr>(phoff, ehdr->e_phnum,
                                               ehdr->e_phentsize,
                                               data.size())) {
      result.error = "ELF32 phdr table out of range";
      return result;
    }
    const Elf32_Phdr *phdrs =
        reinterpret_cast<const Elf32_Phdr *>(data.data() + phoff);
    Elf32_Off dyn_offset = 0;
    Elf32_Word dyn_size = 0;
    bool dyn_found = false;
    for (uint16_t i = 0; i < ehdr->e_phnum; ++i) {
      if (phdrs[i].p_type == PT_DYNAMIC) {
        dyn_offset = phdrs[i].p_offset;
        dyn_size = phdrs[i].p_filesz;
        dyn_found = true;
        break;
      }
    }
    if (!dyn_found || dyn_size == 0) {
      result.error = "PT_DYNAMIC not found";
      return result;
    }
    const size_t dynOffset = static_cast<size_t>(dyn_offset);
    const size_t dynSize = static_cast<size_t>(dyn_size);
    if (static_cast<Elf32_Off>(dynOffset) != dyn_offset ||
        static_cast<Elf32_Word>(dynSize) != dyn_size ||
        !IsRangeWithin(dynOffset, dynSize, data.size())) {
      result.error = "ELF32 dynamic section out of range";
      return result;
    }
    const Elf32_Dyn *dyn =
        reinterpret_cast<const Elf32_Dyn *>(data.data() + dynOffset);
    size_t dyn_count = dynSize / sizeof(Elf32_Dyn);
    Elf32_Addr strtab_vaddr = 0;
    bool strtab_found = false;
    for (size_t i = 0; i < dyn_count; ++i) {
      if (dyn[i].d_tag == DT_STRTAB) {
        strtab_vaddr = static_cast<Elf32_Addr>(dyn[i].d_un.d_ptr);
        strtab_found = true;
        break;
      }
    }
    if (!strtab_found) {
      result.error = "DT_STRTAB not found";
      return result;
    }
    size_t strtab_offset = 0;
    if (!MapVaddrToOffset32(phdrs, ehdr->e_phnum, strtab_vaddr,
                            strtab_offset)) {
      result.error = "failed to map strtab vaddr";
      return result;
    }
    for (size_t i = 0; i < dyn_count; ++i) {
      if (dyn[i].d_tag == DT_NEEDED) {
        const size_t needed_offset = static_cast<size_t>(dyn[i].d_un.d_val);
        if (strtab_offset > data.size() ||
            needed_offset > data.size() - strtab_offset) {
          result.error = "ELF32 DT_NEEDED offset out of range";
          return result;
        }
        const size_t name_offset = strtab_offset + needed_offset;
        std::string libName;
        if (!ReadBoundedCString(data, name_offset, libName)) {
          result.error = "ELF32 DT_NEEDED string not terminated";
          return result;
        }
        result.libs.emplace_back(std::move(libName));
      }
    }
    return result;
  }

  result.error = "unsupported ELF class";
  return result;
}
} // namespace

// --- TestCoreLoader (napi_async_work) ---
struct TestCoreLoaderAsyncCtx {
  std::string corePath;
  std::string resultMessage;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
};

static void ExecuteTestCoreLoader(napi_env /*env*/, void *data) {
  auto *ctx = static_cast<TestCoreLoaderAsyncCtx *>(data);
  if (!ctx) {
    return;
  }

  const std::string &corePath = ctx->corePath;
  LOGF(LOG_INFO, "========== TestCoreLoader NAPI Called ==========");

  NeededResult neededEarly = ReadNeededLibrariesFromElf(corePath);
  if (!neededEarly.libs.empty()) {
    LOGF(LOG_INFO, "NEEDED (preload): %{public}zu", neededEarly.libs.size());
    for (const auto &lib : neededEarly.libs) {
      LOGF(LOG_INFO, "  NEEDED: %{public}s", lib.c_str());
    }
  } else if (!neededEarly.error.empty()) {
    LOGF(LOG_WARN, "NEEDED (preload) failed: %{public}s", neededEarly.error.c_str());
  } else {
    LOGF(LOG_WARN, "NEEDED (preload) empty");
  }

  CoreLoader loader;
  bool success = true;
  std::string &resultMessage = ctx->resultMessage;

  const std::string corePathForLog = security::DescribePathForLog(corePath);

  LOGF(LOG_INFO, "Step 1: Loading core: %{public}s",
       corePathForLog.c_str());
  if (!loader.LoadCore(corePath)) {
    resultMessage = "Failed: Could not load core (" + corePathForLog + ")";
    if (!loader.GetLastErrorStep().empty() || !loader.GetLastErrorMessage().empty()) {
      resultMessage += " (step=" + loader.GetLastErrorStep() + ", message=" +
                       loader.GetLastErrorMessage() + ")";
    }
    LOGF(LOG_ERROR, "%{public}s", resultMessage.c_str());
    success = false;
  } else {
    LOGF(LOG_INFO, " Core loaded successfully");

    if (!loader.IsLoaded()) {
      resultMessage = "Failed: IsLoaded() returned false";
      LOGF(LOG_ERROR, "%{public}s", resultMessage.c_str());
      success = false;
    } else {
      LOGF(LOG_INFO, " IsLoaded() check passed");

      LOGF(LOG_INFO, "Step 2: Verifying function pointers...");
      if (!loader.GetInit() || !loader.GetRun() || !loader.GetApiVersion()) {
        resultMessage = "Failed: Required function pointers are null";
        LOGF(LOG_ERROR, "%{public}s", resultMessage.c_str());
        success = false;
      } else {
        LOGF(LOG_INFO, " All required function pointers are valid");

        std::vector<std::string> warnings;
        auto addWarning = [&warnings](const std::string &msg) {
          warnings.push_back(msg);
        };

        if (!loader.GetSetEnvironment()) { addWarning("retro_set_environment missing"); }
        if (!loader.GetSetVideoRefresh()) { addWarning("retro_set_video_refresh missing"); }
        if (!loader.GetSetAudioSample()) { addWarning("retro_set_audio_sample missing"); }
        if (!loader.GetSetAudioSampleBatch()) { addWarning("retro_set_audio_sample_batch missing"); }
        if (!loader.GetSetInputPoll()) { addWarning("retro_set_input_poll missing"); }
        if (!loader.GetSetInputState()) { addWarning("retro_set_input_state missing"); }
        if (!loader.GetReset()) { addWarning("retro_reset missing"); }
        if (!loader.GetLoadGame()) { addWarning("retro_load_game missing"); }
        if (!loader.GetUnloadGame()) { addWarning("retro_unload_game missing"); }
        if (!loader.GetSerializeSize()) { addWarning("retro_serialize_size not provided"); }
        if (!loader.GetSerialize()) { addWarning("retro_serialize not provided"); }
        if (!loader.GetUnserialize()) { addWarning("retro_unserialize not provided"); }
        if (!loader.GetCheatReset()) { addWarning("retro_cheat_reset not provided"); }
        if (!loader.GetCheatSet()) { addWarning("retro_cheat_set not provided"); }
        if (!loader.GetLoadGameSpecial()) { addWarning("retro_load_game_special not provided"); }
        if (!loader.GetGetRegion()) { addWarning("retro_get_region not provided"); }
        if (!loader.GetGetMemoryData()) { addWarning("retro_get_memory_data not provided"); }
        if (!loader.GetGetMemorySize()) { addWarning("retro_get_memory_size not provided"); }

        LOGF(LOG_INFO, "Step 3: Calling retro_api_version()...");
        unsigned apiVersion = loader.GetApiVersion()();
        LOGF(LOG_INFO, " API Version: %{public}u", apiVersion);

        LOGF(LOG_INFO, "Step 4: Calling retro_get_system_info()...");
        struct retro_system_info sysInfo = {};
        loader.GetSystemInfo()(&sysInfo);
        const char *libraryName = sysInfo.library_name ? sysInfo.library_name : "unknown";
        const char *libraryVersion = sysInfo.library_version ? sysInfo.library_version : "unknown";
        const char *extensions = sysInfo.valid_extensions ? sysInfo.valid_extensions : "";
        LOGF(LOG_INFO, " System Info:");
        LOGF(LOG_INFO, "   Name: %{public}s", libraryName);
        LOGF(LOG_INFO, "   Version: %{public}s", libraryVersion);
        LOGF(LOG_INFO, "   Extensions: %{public}s", extensions);

        if (!sysInfo.library_name || !sysInfo.library_name[0]) {
          addWarning("retro_get_system_info.library_name empty");
        }
        if (!sysInfo.library_version || !sysInfo.library_version[0]) {
          addWarning("retro_get_system_info.library_version empty");
        }
        if (!sysInfo.valid_extensions || !sysInfo.valid_extensions[0]) {
          addWarning("retro_get_system_info.valid_extensions empty");
        }

        if (apiVersion != RETRO_API_VERSION) {
          resultMessage = "Failed: API version mismatch";
          LOGF(LOG_ERROR, "%{public}s", resultMessage.c_str());
          success = false;
        }

        if (success) {
          resultMessage = "Success: Core loaded: " + std::string(libraryName) +
                          " v" + std::string(libraryVersion);
          resultMessage += "\nExtensions: ";
          resultMessage += extensions;
          resultMessage += "\nneed_fullpath: ";
          resultMessage += sysInfo.need_fullpath ? "true" : "false";
          if (sysInfo.need_fullpath) {
            resultMessage += " (requires content path, no in-memory data)";
            addWarning("need_fullpath=true; provide real content path");
          }
          resultMessage += "\nblock_extract: ";
          resultMessage += sysInfo.block_extract ? "true" : "false";
          if (sysInfo.block_extract) {
            resultMessage += " (do not extract archives)";
            addWarning("block_extract=true; keep archives intact");
          }

          NeededResult needed = ReadNeededLibrariesFromElf(corePath);
          resultMessage += "\nNEEDED: ";
          if (!needed.libs.empty()) {
            for (size_t i = 0; i < needed.libs.size(); ++i) {
              if (i > 0) { resultMessage += ", "; }
              resultMessage += needed.libs[i];
            }
          } else if (!needed.error.empty()) {
            resultMessage += "unavailable";
            addWarning("NEEDED parse failed: " + needed.error);
          } else {
            resultMessage += "none";
          }

          if (!warnings.empty()) {
            resultMessage += "\nWarnings:";
            for (const auto &warning : warnings) {
              resultMessage += "\n- ";
              resultMessage += warning;
            }
          }
          if (!needed.error.empty()) {
            LOGF(LOG_WARN, "NEEDED parse failed: %{public}s", needed.error.c_str());
          }
          if (!needed.libs.empty()) {
            LOGF(LOG_INFO, "NEEDED libs: %{public}zu", needed.libs.size());
          }
        }
      }
    }

    LOGF(LOG_INFO, "Step 5: Unloading core...");
    loader.UnloadCore();
    if (loader.IsLoaded()) {
      resultMessage = "Warning: Core still loaded after UnloadCore()";
      LOGF(LOG_ERROR, "%{public}s", resultMessage.c_str());
    } else {
      LOGF(LOG_INFO, " Core unloaded successfully");
    }
  }

  LOGF(LOG_INFO, "========== TestCoreLoader NAPI Finished ==========");
  LOGF(LOG_INFO, "Result: %{public}s", resultMessage.c_str());
}

static void CompleteTestCoreLoader(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<TestCoreLoaderAsyncCtx *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] TestCoreLoader cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] TestCoreLoader work failed: status=%{public}d",
         static_cast<int>(status));
    napi_value reason = nullptr;
    if (napi_get_undefined(env, &reason) != napi_ok) {
      if (ctx->work) {
        napi_delete_async_work(env, ctx->work);
        ctx->work = nullptr;
      }
      delete ctx;
      return;
    }
    (void)RejectDeferredChecked(env, ctx->deferred, reason);
  } else {
    napi_value result = MakeString(env, ctx->resultMessage);
    if (!result) {
      LOGF(LOG_ERROR, "[NEW] TestCoreLoader failed to allocate result string");
      napi_value reason = MakeUndefined(env);
      if (reason) {
        (void)RejectDeferredChecked(env, ctx->deferred, reason);
      }
      if (ctx->work) {
        napi_delete_async_work(env, ctx->work);
        ctx->work = nullptr;
      }
      delete ctx;
      return;
    }
    (void)ResolveDeferredChecked(env, ctx->deferred, result);
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

/**
 * 测试 CoreLoader 加载功能 (async)
 *
 * ArkTS 调用方式:
 * import testNapi from 'libentry.so';
 * let result = await testNapi.testCoreLoader(corePath);
 *
 * @param corePath - Libretro 核心的沙箱路径 (从 ArkTS 传递)
 * @return Promise<string> 测试结果字符串
 */
static napi_value TestCoreLoader(napi_env env, napi_callback_info info) {
  // Audit T1-F6: offload dlopen/GetApiVersion/GetSystemInfo to worker thread
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok) {
    return MakeResolvedStringPromise(env, "Error: Failed to read arguments");
  }

  if (argc < 1) {
    LOGF(LOG_ERROR, "Missing parameter: corePath");
    return MakeResolvedStringPromise(env, "Error: Missing corePath parameter");
  }

  std::string corePath;
  if (!GetStringArg(env, argv[0], corePath, "TestCoreLoader", "corePath")) {
    return MakeResolvedStringPromise(env, "Error: Invalid corePath parameter");
  }

  LOGF(LOG_INFO, "Received corePath from ArkTS: %{public}s",
       security::DescribePathForLog(corePath).c_str());

  if (!security::ValidateCorePath(corePath)) {
    LOGF(LOG_ERROR, "Security: Core path validation failed in TestCoreLoader: %{public}s",
         security::DescribePathForLog(corePath).c_str());
    return MakeResolvedStringPromise(env,
                                     "Error: Core path not in allowed directories");
  }

  auto *ctx = new TestCoreLoaderAsyncCtx();
  ctx->corePath = std::move(corePath);

  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "TestCoreLoader");
  if (!resourceName) {
    napi_value errStr = MakeString(env, "Error: async work creation failed");
    if (errStr) {
      (void)ResolveDeferredChecked(env, ctx->deferred, errStr);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteTestCoreLoader, CompleteTestCoreLoader,
      ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] TestCoreLoader create work failed");
    napi_value errStr = MakeString(env, "Error: async work creation failed");
    if (errStr) {
      (void)ResolveDeferredChecked(env, ctx->deferred, errStr);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] TestCoreLoader queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value errStr = MakeString(env, "Error: async work queue failed");
    if (errStr) {
      (void)ResolveDeferredChecked(env, ctx->deferred, errStr);
    }
    delete ctx;
    return promise;
  }

  return promise;
}

/**
 * 注册 NAPI 函数到模块
 * 这个函数会被 hello.cpp 中的 Init 函数调用
 */
void RegisterCoreLoaderNapi(napi_env env, napi_value exports) {
  LOGF(LOG_INFO, "RegisterCoreLoaderNapi START");

  // 定义要导出的函数 (官方标准方式)
  napi_property_descriptor desc[] = {{"testCoreLoader", nullptr, TestCoreLoader,
                                      nullptr, nullptr, nullptr, napi_default,
                                      nullptr}};

  LOGF(LOG_INFO, "Defining %{public}zu properties...",
               sizeof(desc) / sizeof(desc[0]));

  // 注册函数到 exports 对象
  napi_status status = napi_define_properties(
      env, exports, sizeof(desc) / sizeof(desc[0]), desc);

  if (status != napi_ok) {
    LOGF(LOG_ERROR, "napi_define_properties FAILED with status: %{public}d",
                 status);
    return;
  }

  LOGF(LOG_INFO, " CoreLoader NAPI functions registered successfully");
}
