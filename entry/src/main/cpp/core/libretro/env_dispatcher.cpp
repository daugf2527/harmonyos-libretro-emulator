#include "env_dispatcher.h"
#include "core/libretro/libretro_vulkan.h"
#include "common/file_security.h"
#include "common/file_utils.h"
#include "common/string_utils.h"

#include <cctype>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <array>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <mutex>
#include <utility>
#include <unistd.h>
#include <sys/stat.h>
#include <EGL/egl.h>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "LibretroEnv"
#undef LOG_FLOW
#define LOG_FLOW "Env"
#include "common/log_prefix.h"

struct retro_vfs_file_handle {
  int fd = -1;
  std::string path;
};

struct retro_vfs_dir_handle {
  DIR *dir = nullptr;
  std::string base;
  std::string current_name;
  bool current_is_dir = false;
  bool include_hidden = false;
};

namespace {
std::mutex g_vfs_mutex;
std::string g_vfs_root;
std::string g_vfs_system_dir;
std::string g_vfs_content_dir;
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";

void SetVfsRoot(const std::string &root) {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  g_vfs_root = root;
}

std::string GetVfsRoot() {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  return g_vfs_root;
}

void SetVfsSystemDir(const std::string &dir) {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  g_vfs_system_dir = dir;
}

void SetVfsContentDir(const std::string &dir) {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  g_vfs_content_dir = dir;
}

std::string GetVfsSystemDir() {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  return g_vfs_system_dir;
}

std::string GetVfsContentDir() {
  std::lock_guard<std::mutex> lock(g_vfs_mutex);
  return g_vfs_content_dir;
}

bool IsVfsPathAllowedAbs(const std::string &path) {
  if (path.empty() || path[0] != '/') {
    return false;
  }
  std::string root = GetVfsRoot();
  if (!root.empty() && security::ValidatePath(path, root)) {
    return true;
  }
  return security::ValidatePath(path, "/data/storage/el2/base/haps/entry/files");
}

bool ResolveVfsPath(const char *path, std::string &out) {
  if (!path || !path[0]) {
    return false;
  }

  std::string input(path);
  if (input.find("..") != std::string::npos) {
    return false;
  }

  if (input[0] == '/') {
    if (IsVfsPathAllowedAbs(input)) {
      out = input;
      return true;
    }
    return false;
  }

  const std::string system_dir = GetVfsSystemDir();
  if (!system_dir.empty()) {
    std::string candidate = system_dir + "/" + input;
    if (IsVfsPathAllowedAbs(candidate)) {
      out = candidate;
      return true;
    }
  }

  const std::string content_dir = GetVfsContentDir();
  if (!content_dir.empty()) {
    std::string candidate = content_dir + "/" + input;
    if (IsVfsPathAllowedAbs(candidate)) {
      out = candidate;
      return true;
    }
  }

  const std::string root = GetVfsRoot();
  if (!root.empty()) {
    std::string candidate = root + "/" + input;
    if (IsVfsPathAllowedAbs(candidate)) {
      out = candidate;
      return true;
    }
  }

  return false;
}

void LogVfsReject(const char *op, const char *path) {
  LOGF(LOG_WARN,
               "VFS %{public}s rejected: %{public}s", op, path ? path : "(null)");
}
} // namespace

static const char *RETRO_CALLCONV VfsGetPath(struct retro_vfs_file_handle *stream) {
  if (!stream) {
    return nullptr;
  }
  return stream->path.c_str();
}

static struct retro_vfs_file_handle *RETRO_CALLCONV VfsOpen(const char *path, unsigned mode,
                                                            unsigned hints) {
  (void)hints;
  if (!path) {
    return nullptr;
  }
  std::string resolvedPath;
  if (!ResolveVfsPath(path, resolvedPath)) {
    LogVfsReject("open", path);
    return nullptr;
  }

  int flags = 0;
  const bool can_read = (mode & RETRO_VFS_FILE_ACCESS_READ) != 0;
  const bool can_write = (mode & RETRO_VFS_FILE_ACCESS_WRITE) != 0;
  const bool update_existing = (mode & RETRO_VFS_FILE_ACCESS_UPDATE_EXISTING) != 0;

  if (can_read && can_write) {
    flags |= O_RDWR;
  } else if (can_read) {
    flags |= O_RDONLY;
  } else if (can_write) {
    flags |= O_WRONLY;
  } else {
    return nullptr;
  }

  if (can_write) {
    flags |= O_CREAT;
    if (!update_existing) {
      flags |= O_TRUNC;
    }
  }

  int fd = open(resolvedPath.c_str(), flags, 0600);
  if (fd < 0) {
    return nullptr;
  }

  auto h = std::make_unique<retro_vfs_file_handle>();
  h->fd = fd;
  h->path = resolvedPath;
  return h.release();
}

static int RETRO_CALLCONV VfsClose(struct retro_vfs_file_handle *stream) {
  if (!stream) {
    return -1;
  }

  std::unique_ptr<retro_vfs_file_handle> h(stream);

  int ret = 0;
  if (h->fd >= 0) {
    ret = close(h->fd);
  } else {
    ret = -1;
  }
  h->fd = -1;
  return (ret == 0) ? 0 : -1;
}

static int64_t RETRO_CALLCONV VfsSize(struct retro_vfs_file_handle *stream) {
  if (!stream || stream->fd < 0) {
    return -1;
  }
  struct stat st;
  if (fstat(stream->fd, &st) != 0) {
    return -1;
  }
  return static_cast<int64_t>(st.st_size);
}

static int64_t RETRO_CALLCONV VfsTell(struct retro_vfs_file_handle *stream) {
  if (!stream || stream->fd < 0) {
    return -1;
  }
  off_t pos = lseek(stream->fd, 0, SEEK_CUR);
  return (pos < 0) ? -1 : static_cast<int64_t>(pos);
}

static int64_t RETRO_CALLCONV VfsSeek(struct retro_vfs_file_handle *stream, int64_t offset,
                                      int seek_position) {
  if (!stream || stream->fd < 0) {
    return -1;
  }

  int whence = SEEK_SET;
  switch (seek_position) {
  case RETRO_VFS_SEEK_POSITION_START:
    whence = SEEK_SET;
    break;
  case RETRO_VFS_SEEK_POSITION_CURRENT:
    whence = SEEK_CUR;
    break;
  case RETRO_VFS_SEEK_POSITION_END:
    whence = SEEK_END;
    break;
  default:
    whence = SEEK_SET;
    break;
  }

  off_t pos = lseek(stream->fd, static_cast<off_t>(offset), whence);
  return (pos < 0) ? -1 : static_cast<int64_t>(pos);
}

static int64_t RETRO_CALLCONV VfsRead(struct retro_vfs_file_handle *stream, void *s,
                                      uint64_t len) {
  if (!stream || stream->fd < 0 || !s) {
    return -1;
  }
  ssize_t r = read(stream->fd, s, static_cast<size_t>(len));
  return (r < 0) ? -1 : static_cast<int64_t>(r);
}

static int64_t RETRO_CALLCONV VfsWrite(struct retro_vfs_file_handle *stream, const void *s,
                                       uint64_t len) {
  if (!stream || stream->fd < 0 || !s) {
    return -1;
  }
  ssize_t w = write(stream->fd, s, static_cast<size_t>(len));
  return (w < 0) ? -1 : static_cast<int64_t>(w);
}

static int RETRO_CALLCONV VfsFlush(struct retro_vfs_file_handle *stream) {
  if (!stream || stream->fd < 0) {
    return -1;
  }
  return (fsync(stream->fd) == 0) ? 0 : -1;
}

static int RETRO_CALLCONV VfsRemove(const char *path) {
  if (!path) {
    return -1;
  }
  std::string resolvedPath;
  if (!ResolveVfsPath(path, resolvedPath)) {
    LogVfsReject("remove", path);
    return -1;
  }
  return (unlink(resolvedPath.c_str()) == 0) ? 0 : -1;
}

static int RETRO_CALLCONV VfsRename(const char *old_path, const char *new_path) {
  if (!old_path || !new_path) {
    return -1;
  }
  std::string resolvedOld;
  std::string resolvedNew;
  if (!ResolveVfsPath(old_path, resolvedOld) ||
      !ResolveVfsPath(new_path, resolvedNew)) {
    LogVfsReject("rename", old_path);
    LogVfsReject("rename", new_path);
    return -1;
  }
  return (rename(resolvedOld.c_str(), resolvedNew.c_str()) == 0) ? 0 : -1;
}

static int64_t RETRO_CALLCONV VfsTruncate(struct retro_vfs_file_handle *stream, int64_t length) {
  if (!stream || stream->fd < 0) {
    return -1;
  }
  return (ftruncate(stream->fd, static_cast<off_t>(length)) == 0) ? 0 : -1;
}

static int RETRO_CALLCONV VfsStat(const char *path, int32_t *size) {
  if (!path) {
    return 0;
  }
  std::string resolvedPath;
  if (!ResolveVfsPath(path, resolvedPath)) {
    LogVfsReject("stat", path);
    return 0;
  }

  struct stat st;
  if (stat(resolvedPath.c_str(), &st) != 0) {
    return 0;
  }

  if (size) {
    const auto maxSize = std::numeric_limits<int32_t>::max();
    if (st.st_size < 0) {
      *size = 0;
    } else if (st.st_size > maxSize) {
      *size = maxSize;
      LOGF(LOG_WARN,
                   "VFS stat size truncated: %{public}s", resolvedPath.c_str());
    } else {
      *size = static_cast<int32_t>(st.st_size);
    }
  }

  int flags = RETRO_VFS_STAT_IS_VALID;
  if (S_ISDIR(st.st_mode)) {
    flags |= RETRO_VFS_STAT_IS_DIRECTORY;
  }
  if (S_ISCHR(st.st_mode)) {
    flags |= RETRO_VFS_STAT_IS_CHARACTER_SPECIAL;
  }
  return flags;
}

static int RETRO_CALLCONV VfsMkdir(const char *dir) {
  if (!dir) {
    return -1;
  }
  std::string resolvedDir;
  if (!ResolveVfsPath(dir, resolvedDir)) {
    LogVfsReject("mkdir", dir);
    return -1;
  }
  if (mkdir(resolvedDir.c_str(), 0700) == 0) {
    return 0;
  }
  if (errno == EEXIST) {
    struct stat st;
    if (stat(resolvedDir.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
      return -2;
    }
  }
  return -1;
}

static struct retro_vfs_dir_handle *RETRO_CALLCONV VfsOpenDir(const char *dir,
                                                              bool include_hidden) {
  if (!dir) {
    return nullptr;
  }
  std::string resolvedDir;
  if (!ResolveVfsPath(dir, resolvedDir)) {
    LogVfsReject("opendir", dir);
    return nullptr;
  }
  DIR *d = opendir(resolvedDir.c_str());
  if (!d) {
    return nullptr;
  }
  auto h = std::make_unique<retro_vfs_dir_handle>();
  h->dir = d;
  h->base = resolvedDir;
  h->include_hidden = include_hidden;
  return h.release();
}

static bool RETRO_CALLCONV VfsReadDir(struct retro_vfs_dir_handle *dirstream) {
  if (!dirstream || !dirstream->dir) {
    return false;
  }

  for (;;) {
    errno = 0;
    struct dirent *ent = readdir(dirstream->dir);
    if (!ent) {
      return false;
    }

    const char *name = ent->d_name;
    if (!name || name[0] == '\0') {
      continue;
    }

    if (std::strcmp(name, ".") == 0 || std::strcmp(name, "..") == 0) {
      continue;
    }

    if (!dirstream->include_hidden && name[0] == '.') {
      continue;
    }

    dirstream->current_name = name;
    dirstream->current_is_dir = false;

#ifdef DT_DIR
    if (ent->d_type == DT_DIR) {
      dirstream->current_is_dir = true;
    } else if (ent->d_type == DT_UNKNOWN) {
      // fall through to stat
    }
#endif

    if (!dirstream->current_is_dir) {
      const std::string full = dirstream->base + "/" + dirstream->current_name;
      struct stat st;
      if (stat(full.c_str(), &st) == 0) {
        dirstream->current_is_dir = S_ISDIR(st.st_mode);
      }
    }

    return true;
  }
}

static const char *RETRO_CALLCONV VfsDirentGetName(struct retro_vfs_dir_handle *dirstream) {
  if (!dirstream) {
    return nullptr;
  }
  return dirstream->current_name.c_str();
}

static bool RETRO_CALLCONV VfsDirentIsDir(struct retro_vfs_dir_handle *dirstream) {
  if (!dirstream) {
    return false;
  }
  return dirstream->current_is_dir;
}

static int RETRO_CALLCONV VfsCloseDir(struct retro_vfs_dir_handle *dirstream) {
  if (!dirstream) {
    return -1;
  }

  std::unique_ptr<retro_vfs_dir_handle> h(dirstream);

  int ret = 0;
  if (h->dir) {
    ret = closedir(h->dir);
    h->dir = nullptr;
  } else {
    ret = -1;
  }
  return (ret == 0) ? 0 : -1;
}

static struct retro_vfs_interface g_vfs_interface = {
    VfsGetPath,
    VfsOpen,
    VfsClose,
    VfsSize,
    VfsTell,
    VfsSeek,
    VfsRead,
    VfsWrite,
    VfsFlush,
    VfsRemove,
    VfsRename,
    VfsTruncate,
    VfsStat,
    VfsMkdir,
    VfsOpenDir,
    VfsReadDir,
    VfsDirentGetName,
    VfsDirentIsDir,
    VfsCloseDir,
};

// Global callbacks for static interfaces
static libretro::RumbleCallback g_rumble_cb = nullptr;
static libretro::SensorSetStateCallback g_sensor_set_cb = nullptr;
static libretro::SensorGetInputCallback g_sensor_get_cb = nullptr;
static std::function<uintptr_t(void)> g_hw_framebuffer_cb;

namespace libretro {
void SetGlobalRumbleCallback(RumbleCallback cb) { g_rumble_cb = cb; }
void SetGlobalSensorCallbacks(SensorSetStateCallback set_cb, SensorGetInputCallback get_cb) {
  g_sensor_set_cb = set_cb;
  g_sensor_get_cb = get_cb;
}
void SetGlobalHwRenderFramebufferCallback(HwRenderFramebufferCallback cb) {
  g_hw_framebuffer_cb = cb;
}
} // namespace libretro

static bool RETRO_CALLCONV RumbleSetState(unsigned port, enum retro_rumble_effect effect,
                                         uint16_t strength) {
  if (g_rumble_cb) {
    return g_rumble_cb(port, effect, strength);
  }
  return false;
}

static struct retro_rumble_interface g_rumble_interface = {RumbleSetState};

static void RETRO_CALLCONV LedSetState(int led, int state) {
  (void)led;
  (void)state;
}

static struct retro_led_interface g_led_interface = {LedSetState};

static bool RETRO_CALLCONV SensorSetState(unsigned port, enum retro_sensor_action action,
                                          unsigned rate) {
  if (g_sensor_set_cb) {
    return g_sensor_set_cb(port, action, rate);
  }
  return false;
}

static float RETRO_CALLCONV SensorGetInput(unsigned port, unsigned id) {
  if (g_sensor_get_cb) {
    return g_sensor_get_cb(port, id);
  }
  return 0.0f;
}

static struct retro_sensor_interface g_sensor_interface = {SensorSetState, SensorGetInput};


static bool RETRO_CALLCONV CameraStart(void) { return false; }
static void RETRO_CALLCONV CameraStop(void) {}

namespace libretro {

static uintptr_t RETRO_CALLCONV GetCurrentFramebuffer(void) {
  if (g_hw_framebuffer_cb) {
    return g_hw_framebuffer_cb();
  }
  static uint32_t logCount = 0;
  if (logCount < 3) {
    logCount++;
    LOGF(LOG_WARN, "get_current_framebuffer callback not set");
  }
  return 0;
}

static retro_proc_address_t RETRO_CALLCONV GetProcAddress(const char *sym) {
  return (retro_proc_address_t)eglGetProcAddress(sym);
}

static void RetroLog(enum retro_log_level level, const char *fmt, ...) {
  char buf[1024];

  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);

  LogLevel prio = LOG_INFO;
  switch (level) {
  case RETRO_LOG_DEBUG:
    prio = LOG_DEBUG;
    break;
  case RETRO_LOG_INFO:
    prio = LOG_DEBUG;
    break;
  case RETRO_LOG_WARN:
    prio = LOG_WARN;
    break;
  case RETRO_LOG_ERROR:
    prio = LOG_ERROR;
    break;
  default:
    prio = LOG_INFO;
    break;
  }

  LOGF(prio, "%{public}s", buf);
}

static std::string ParseDefaultOptionValue(const char *value) {
  if (!value) {
    return std::string();
  }

  std::string s(value);
  size_t semi = s.find(';');
  if (semi == std::string::npos) {
    return common::TrimCopy(s);
  }

  std::string opts = s.substr(semi + 1);
  size_t pipe = opts.find('|');
  std::string first = (pipe == std::string::npos) ? opts : opts.substr(0, pipe);
  return common::TrimCopy(first);
}

bool EnvState::SetBaseDir(const std::string &filesDir) {
  if (filesDir.empty()) {
    base_directory_.clear();
    system_directory_.clear();
    save_directory_.clear();
    content_directory_.clear();
    core_assets_directory_.clear();
    cache_directory_.clear();
    config_directory_.clear();
    SetVfsRoot(std::string());
    SetVfsSystemDir(std::string());
    SetVfsContentDir(std::string());
    core_options_config_path_.clear();
    return true;
  }

  base_directory_ = filesDir;
  system_directory_ = filesDir + "/system";
  save_directory_ = filesDir + "/saves";
  content_directory_ = filesDir + "/roms";
  core_assets_directory_ = filesDir + "/core_assets";
  cache_directory_ = filesDir + "/cache";
  config_directory_ = filesDir + "/config";
  core_options_config_path_ = config_directory_ + "/retroarch-core-options.cfg";
  SetVfsRoot(filesDir);
  SetVfsSystemDir(system_directory_);
  SetVfsContentDir(content_directory_);

  bool success = true;
  auto ensureDir = [&](const std::string &dir) {
    if (!common::EnsureDirExists(dir)) {
      LOGF(LOG_WARN, "EnsureDirExists failed: %{public}s", dir.c_str());
      success = false;
    }
  };

  ensureDir(system_directory_);
  ensureDir(save_directory_);
  ensureDir(content_directory_);
  ensureDir(core_assets_directory_);
  ensureDir(cache_directory_);
  ensureDir(config_directory_);

  // 常用子目录（避免 VFS 在父目录不存在时被拒绝）
  const std::string arcade_dir = system_directory_ + "/arcade";
  const std::string arc_dir = system_directory_ + "/arc";
  const std::string fbneo_dir = system_directory_ + "/fbneo";
  const std::string fbneo_patched_dir = fbneo_dir + "/patched";
  const std::string fbneo_path_dir = fbneo_dir + "/path";
  const std::string fbneo_channel_dir = fbneo_dir + "/channelf";

  ensureDir(arcade_dir);
  ensureDir(arc_dir);
  ensureDir(fbneo_dir);
  ensureDir(fbneo_patched_dir);
  ensureDir(fbneo_path_dir);
  ensureDir(fbneo_channel_dir);

  return success;
}

void EnvState::ResetCoreState() {
  const bool hwRenderAllowed = hw_render_allowed_.load();
  frame_time_callback_ = nullptr;
  frame_time_reference_ = 0;
  audio_buffer_status_callback_ = nullptr;
  pending_min_audio_latency_ms_ = 0;
  has_pending_min_audio_latency_ = false;
  in_retro_run_ = false;

  {
    std::lock_guard<std::mutex> lock(variables_mutex_);
    variables_.clear();
    variable_updated_ = false;
  }

  can_dupe_ = true;
  overscan_ = false;
  supports_no_game_ = false;
  pixel_format_ = ::RETRO_PIXEL_FORMAT_0RGB1555;
  geometry_base_width_ = 0;
  geometry_base_height_ = 0;
  geometry_aspect_ratio_ = 0.0f;
  geometry_updated_ = false;
  performance_level_ = 0;

  input_capabilities_ =
      (1ULL << RETRO_DEVICE_JOYPAD) | (1ULL << RETRO_DEVICE_ANALOG);
  input_max_users_ = 4;
  supports_input_bitmasks_ = true;

  ClearCoreOptions();

  has_keyboard_callback_ = false;
  keyboard_callback_ = {};
  has_disk_control_cb_ = false;
  has_disk_control_ext_cb_ = false;
  disk_control_cb_ = {};
  disk_control_ext_cb_ = {};

  hw_render_enabled_.store(false);
  hw_render_allowed_.store(hwRenderAllowed);
  hw_render_cb_ = {};
  vulkan_interface_ = nullptr;
  vulkan_negotiation_ = {};
  has_vulkan_negotiation_ = false;
  hw_context_type_ = ::RETRO_HW_CONTEXT_NONE;
  libretro_path_.clear();
}

void EnvState::ClearCoreOptions() {
  std::lock_guard<std::mutex> lock(core_options_mutex_);
  core_option_categories_.clear();
  core_option_definitions_.clear();
}

void EnvState::SetCoreOptions(
    std::vector<core_options::CoreOptionCategory> categories,
    std::vector<core_options::CoreOptionDefinition> definitions) {
  std::lock_guard<std::mutex> lock(core_options_mutex_);
  core_option_categories_ = std::move(categories);
  core_option_definitions_ = std::move(definitions);
}

bool EnvState::SetCoreOptionValue(const char *key, const char *value) {
  return core_options::SetCoreOptionValue(*this, key, value);
}

bool EnvState::SetVariable(const char *key, const char *value) {
  if (!key || !value) {
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(variables_mutex_);
    variables_[key] = value;
    variable_updated_ = true;
  }
  return true;
}

const char *EnvState::GetVariable(const char *key) const {
  if (!key) {
    return nullptr;
  }

  {
    static thread_local std::array<std::string, 8> tls_values;
    static thread_local size_t tls_index = 0;
    std::lock_guard<std::mutex> lock(variables_mutex_);
    auto it = variables_.find(key);
    if (it != variables_.end()) {
      // Return a stable pointer for the caller without holding the lock.
      std::string &slot = tls_values[tls_index];
      tls_index = (tls_index + 1) % tls_values.size();
      slot = it->second;
      return slot.c_str();
    }
  }

  return nullptr;
}

bool EnvState::ConsumeVariableUpdated() {
  std::lock_guard<std::mutex> lock(variables_mutex_);
  bool updated = variable_updated_;
  variable_updated_ = false;
  return updated;
}

bool HandleEnvironmentCommand(EnvState &state, unsigned cmd, void *data) {
  switch (cmd) {
  case RETRO_ENVIRONMENT_SET_ROTATION:
    return true;

  case RETRO_ENVIRONMENT_GET_OVERSCAN: {
    if (!data)
      return false;
    bool *overscan = (bool *)data;
    *overscan = state.GetOverscan();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
    if (!data)
      return false;
    bool *can_dupe = (bool *)data;
    *can_dupe = state.CanDupe();
    return true;
  }

  case RETRO_ENVIRONMENT_SET_MESSAGE: {
    if (!data)
      return false;
    const ::retro_message *msg = (const ::retro_message *)data;
    if (msg && msg->msg) {
      LOGF(LOG_INFO, "%{public}s", msg->msg);
    }
    return true;
  }

  case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: {
    return true;
  }

  case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: {
    if (!data) {
      return false;
    }
    // Frontend may cache controller descriptions; we currently accept and ignore.
    return true;
  }

  case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: {
    if (!data) {
      return false;
    }
    const ::retro_keyboard_callback *cb = (const ::retro_keyboard_callback *)data;
    if (!cb) {
      return false;
    }
    state.SetKeyboardCallback(*cb);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE: {
    if (!data) {
      return false;
    }
    ::retro_rumble_interface *iface = (::retro_rumble_interface *)data;
    *iface = g_rumble_interface;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE: {
    if (!data) {
      state.ClearDiskControlCallbacks();
      return true;
    }
    const ::retro_disk_control_callback *cb = (const ::retro_disk_control_callback *)data;
    if (!cb) {
      return false;
    }
    state.SetDiskControlCallback(*cb);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION: {
    if (!data) {
      return false;
    }
    unsigned *version = (unsigned *)data;
    *version = 1;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE: {
    if (!data) {
      state.ClearDiskControlCallbacks();
      return true;
    }
    const ::retro_disk_control_ext_callback *cb =
        (const ::retro_disk_control_ext_callback *)data;
    if (!cb) {
      return false;
    }
    state.SetDiskControlExtCallback(*cb);
    return true;
  }

  case RETRO_ENVIRONMENT_SHUTDOWN:
    return true;

  case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL: {
    if (!data)
      return false;
    unsigned *level = (unsigned *)data;
    state.SetPerformanceLevel(*level);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
    if (!data)
      return false;
    const char **dir = (const char **)data;
    if (!state.GetSystemDirectory() || state.GetSystemDirectory()[0] == '\0') {
      *dir = nullptr;
      return true;
    }
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOGF(LOG_INFO, "GET_SYSTEM_DIRECTORY -> %{public}s",
                   state.GetSystemDirectory());
    }
    *dir = state.GetSystemDirectory();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
    if (!data)
      return false;
    const char **dir = (const char **)data;
    if (!state.GetSaveDirectory() || state.GetSaveDirectory()[0] == '\0') {
      *dir = nullptr;
      return true;
    }
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOGF(LOG_INFO, "GET_SAVE_DIRECTORY -> %{public}s",
                   state.GetSaveDirectory());
    }
    *dir = state.GetSaveDirectory();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_CONTENT_DIRECTORY: {
    if (!data)
      return false;
    const char **dir = (const char **)data;
    if (!state.GetContentDirectory() || state.GetContentDirectory()[0] == '\0') {
      *dir = nullptr;
      return true;
    }
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOGF(LOG_INFO,
                   "GET_CONTENT_DIRECTORY -> %{public}s",
                   state.GetContentDirectory());
    }
    *dir = state.GetContentDirectory();
    return true;
  }

  case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK: {
    if (!data) {
      return false;
    }
    const ::retro_frame_time_callback *cb = (const ::retro_frame_time_callback *)data;
    if (!cb) {
      return false;
    }
    state.SetFrameTimeCallback(cb->callback, cb->reference);
    return true;
  }

#ifdef RETRO_ENVIRONMENT_GET_CACHE_DIRECTORY
  case RETRO_ENVIRONMENT_GET_CACHE_DIRECTORY: {
    if (!data)
      return false;
    const char **dir = (const char **)data;
    if (!state.GetCacheDirectory() || state.GetCacheDirectory()[0] == '\0') {
      *dir = nullptr;
      return true;
    }
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOGF(LOG_INFO, "GET_CACHE_DIRECTORY -> %{public}s",
                   state.GetCacheDirectory());
    }
    *dir = state.GetCacheDirectory();
    return true;
  }
#endif

  case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER: {
    if (!data) {
      return false;
    }
    if (!state.IsHwRenderAllowed()) {
      return false;
    }
    enum retro_hw_context_type *type = (enum retro_hw_context_type *)data;
    *type = RETRO_HW_CONTEXT_OPENGLES3;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_HW_RENDER: {
    if (!data) {
      return false;
    }
    const ::retro_hw_render_callback *cb_in =
        (const ::retro_hw_render_callback *)data;
    if (!cb_in) {
      return false;
    }
    if (!state.IsHwRenderAllowed()) {
      LOGF(LOG_WARN, "SET_HW_RENDER rejected: disabled by frontend toggle");
      return false;
    }
    LOGF(LOG_INFO,
                 "SET_HW_RENDER request: type=%{public}d version=%{public}u.%{public}u depth=%{public}d stencil=%{public}d bottom_left=%{public}d cache=%{public}d debug=%{public}d",
                 static_cast<int>(cb_in->context_type), cb_in->version_major,
                 cb_in->version_minor, cb_in->depth, cb_in->stencil,
                 cb_in->bottom_left_origin, cb_in->cache_context,
                 cb_in->debug_context);
    bool supported = false;
    switch (cb_in->context_type) {
    case RETRO_HW_CONTEXT_OPENGLES2:
    case RETRO_HW_CONTEXT_OPENGLES3:
    case RETRO_HW_CONTEXT_VULKAN:
      supported = true;
      break;
    case RETRO_HW_CONTEXT_OPENGLES_VERSION:
      supported = (cb_in->version_major <= 3 && cb_in->version_minor == 0);
      break;
    default:
      supported = false;
      break;
    }
    if (!supported) {
      LOGF(LOG_WARN,
                   "SET_HW_RENDER rejected: unsupported context_type=%{public}d",
                   static_cast<int>(cb_in->context_type));
      return false;
    }
    ::retro_hw_render_callback cb = *cb_in;
    if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
      cb.get_current_framebuffer = nullptr;
      cb.get_proc_address = nullptr;
    } else {
      cb.get_current_framebuffer = GetCurrentFramebuffer;
      cb.get_proc_address = GetProcAddress;
    }
    state.SetHwRenderCallback(cb);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE: {
    if (!data) {
      return false;
    }
    if (state.GetHwContextType() == RETRO_HW_CONTEXT_VULKAN) {
      const retro_hw_render_interface_vulkan *vk_iface =
          state.GetVulkanInterface();
      if (!vk_iface) {
        return false;
      }
      auto **iface = (const struct retro_hw_render_interface **)data;
      *iface = reinterpret_cast<const struct retro_hw_render_interface *>(
          vk_iface);
      return true;
    }
    return false;
  }

  case RETRO_ENVIRONMENT_GET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_SUPPORT: {
    if (!data) {
      return false;
    }
    ::retro_hw_render_context_negotiation_interface *iface =
        (::retro_hw_render_context_negotiation_interface *)data;
    if (!iface) {
      return false;
    }
    if (iface->interface_type ==
        RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) {
      iface->interface_version =
          RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN_VERSION;
      return true;
    }
    iface->interface_version = 0;
    return false;
  }

  case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
    if (!data) {
      return false;
    }
    const auto *iface =
        (const retro_hw_render_context_negotiation_interface *)data;
    if (!iface) {
      return false;
    }
    if (iface->interface_type ==
        RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) {
      const auto *vk_iface =
          (const retro_hw_render_context_negotiation_interface_vulkan *)data;
      state.SetVulkanNegotiationInterface(*vk_iface);
      return true;
    }
    return false;
  }

  case RETRO_ENVIRONMENT_GET_LED_INTERFACE: {
    if (!data) {
      return false;
    }
    ::retro_led_interface *iface = (::retro_led_interface *)data;
    *iface = g_led_interface;
    return true;
  }

  case RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE: {
    if (!data) {
      return false;
    }
    ::retro_sensor_interface *iface = (::retro_sensor_interface *)data;
    *iface = g_sensor_interface;
    return true;
  }

  case RETRO_ENVIRONMENT_GET_CAMERA_INTERFACE: {
    if (!data) {
      return false;
    }
    ::retro_camera_callback *cb = (::retro_camera_callback *)data;
    cb->start = CameraStart;
    cb->stop = CameraStop;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_AUDIO_CALLBACK: {
    const ::retro_audio_callback *cb =
        (const ::retro_audio_callback *)data;
    if (!cb || !cb->callback) {
      LOGF(LOG_INFO, "%{public}s SET_AUDIO_CALLBACK: cleared/disabled",
           kAudioChainPrefix);
    } else {
      LOGF(LOG_WARN,
           "%{public}s SET_AUDIO_CALLBACK: core provided callback (frontend does NOT drive it) "
           "callback=%{public}p, set_state=%{public}p",
           kAudioChainPrefix, cb->callback, cb->set_state);
    }
    // Supported but currently unused by this frontend.
    return true;
  }

  case RETRO_ENVIRONMENT_GET_VFS_INTERFACE: {
    if (!data) {
      return false;
    }
    ::retro_vfs_interface_info *info = (::retro_vfs_interface_info *)data;
    if (!info) {
      return false;
    }

    if (info->required_interface_version > 3) {
      return false;
    }

    info->required_interface_version = 3;
    info->iface = &g_vfs_interface;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
    if (!data)
      return false;
    ::retro_pixel_format *fmt = (::retro_pixel_format *)data;
    const bool supported = (*fmt == ::RETRO_PIXEL_FORMAT_XRGB8888 ||
                            *fmt == ::RETRO_PIXEL_FORMAT_RGB565 ||
                            *fmt == ::RETRO_PIXEL_FORMAT_0RGB1555);
    if (!supported) {
      return false;
    }
    state.SetPixelFormat(*fmt);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_VARIABLE: {
    if (!data)
      return false;
    ::retro_variable *var = (::retro_variable *)data;
    if (!var || !var->key)
      return false;
    var->value = state.GetVariable(var->key);
    return var->value != nullptr;
  }

  case RETRO_ENVIRONMENT_SET_VARIABLE: {
    if (!data) {
      return true;
    }
    const ::retro_variable *var = (const ::retro_variable *)data;
    if (!var || !var->key || !var->value) {
      return false;
    }
    return state.SetCoreOptionValue(var->key, var->value);
  }

  case RETRO_ENVIRONMENT_SET_VARIABLES: {
    const ::retro_variable *vars = (const ::retro_variable *)data;
    while (vars && vars->key) {
      const std::string selected = ParseDefaultOptionValue(vars->value);
      if (!selected.empty()) {
        state.SetVariable(vars->key, selected.c_str());
      }
      vars++;
    }
    return true;
  }

  case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
    if (!data)
      return false;
    bool *updated = (bool *)data;
    *updated = state.ConsumeVariableUpdated();
    return true;
  }

  case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: {
    if (!data)
      return false;
    bool *no_game = (bool *)data;
    state.SetSupportsNoGame(*no_game);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_LIBRETRO_PATH: {
    if (!data)
      return false;
    const char **path = (const char **)data;
    *path = state.GetLibretroPath();
    return true;
  }

  case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
    if (!data)
      return false;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_GEOMETRY: {
    if (!data)
      return false;
    const ::retro_game_geometry *geom = (const ::retro_game_geometry *)data;
    if (!geom)
      return false;
    
    // 更新几何参数 (max_width/max_height 被忽略，符合 Libretro 规范)
    state.SetGeometry(geom->base_width, geom->base_height, geom->aspect_ratio);
    
    LOGF(LOG_INFO, "SET_GEOMETRY: base=%{public}ux%{public}u, aspect=%{public}.3f",
                 geom->base_width, geom->base_height, geom->aspect_ratio);
    return true;
  }

  case RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES: {
    if (!data)
      return false;
    uint64_t *caps = (uint64_t *)data;
    *caps = state.GetInputDeviceCapabilities();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
    if (!data)
      return false;
    ::retro_log_callback *cb = (::retro_log_callback *)data;
    cb->log = RetroLog;
    return true;
  }

  case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: {
    return state.SupportsInputBitmasks();
  }

  case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: {
    if (!data)
      return false;
    unsigned *version = (unsigned *)data;
    *version = 2;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
    return core_options::SetCoreOptionsV2(state,
                                          (const ::retro_core_options_v2 *)data);
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
    const ::retro_core_options_v2_intl *intl =
        (const ::retro_core_options_v2_intl *)data;
    if (!intl || !intl->us) {
      return false;
    }
    return core_options::SetCoreOptionsV2(state, intl->us);
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
    return core_options::SetCoreOptionsV1(state,
                                          (const ::retro_core_option_definition *)data);
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
    const ::retro_core_options_intl *intl =
        (const ::retro_core_options_intl *)data;
    if (!intl || !intl->us) {
      return false;
    }
    return core_options::SetCoreOptionsV1(state, intl->us);
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY: {
    return true;
  }

  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK: {
    return true;
  }

  case RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS: {
    if (!data)
      return false;
    unsigned *max_users = (unsigned *)data;
    *max_users = state.GetInputMaxUsers();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_USERNAME: {
    if (!data)
      return false;
    const char **username = (const char **)data;
    *username = state.GetUsername();
    return true;
  }

  case RETRO_ENVIRONMENT_GET_LANGUAGE: {
    if (!data)
      return false;
    ::retro_language *lang = (::retro_language *)data;
    *lang = state.GetLanguage();
    return true;
  }

  case RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK: {
    const ::retro_audio_buffer_status_callback *cb =
        (const ::retro_audio_buffer_status_callback *)data;
    if (!cb || !cb->callback) {
      state.SetAudioBufferStatusCallback(nullptr);
      LOGF(LOG_INFO, "%{public}s SET_AUDIO_BUFFER_STATUS_CALLBACK: cleared",
           kAudioChainPrefix);
      return true;
    }
    state.SetAudioBufferStatusCallback(cb->callback);
    LOGF(LOG_INFO,
         "%{public}s SET_AUDIO_BUFFER_STATUS_CALLBACK: set callback=%{public}p",
         kAudioChainPrefix, cb->callback);
    return true;
  }

  case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY: {
    if (!state.IsInRetroRun()) {
      LOGF(LOG_WARN,
           "%{public}s SET_MINIMUM_AUDIO_LATENCY rejected: not in retro_run",
           kAudioChainPrefix);
      return false;
    }

    unsigned latency_ms = 0;
    if (data) {
      latency_ms = *(const unsigned *)data;
    }
    state.SetPendingMinimumAudioLatencyMs(latency_ms);
    LOGF(LOG_INFO, "%{public}s SET_MINIMUM_AUDIO_LATENCY: %{public}u ms",
         kAudioChainPrefix, latency_ms);
    return true;
  }

  default:
    return false;
  }
}

} // namespace libretro
