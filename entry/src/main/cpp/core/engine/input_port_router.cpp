#include "input_port_router.h"
#include <algorithm>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD005
#undef LOG_TAG
#define LOG_TAG "InputPortRouter"
#undef LOG_FLOW
#define LOG_FLOW "Input"
#include "common/log_prefix.h"

namespace libretro {

InputPortRouter::InputPortRouter(InputManager *inputManager)
    : inputManager_(inputManager) {
  for (int i = 0; i < InputSnapshot::kMaxPorts; ++i) {
    portSources_[i].sourceType = InputSourceType::None;
    portSources_[i].deviceId.clear();
  }
}

bool InputPortRouter::IsValidPort(int port) const {
  return port >= 0 && port < InputSnapshot::kMaxPorts;
}

void InputPortRouter::ClearPortStateLocked(int port) {
  if (!inputManager_) {
    return;
  }
  inputManager_->ClearPort(port);
}

bool InputPortRouter::AssignPort(int port, InputSourceType sourceType,
                                 const std::string &deviceId) {
  if (!IsValidPort(port)) {
    return false;
  }

  std::lock_guard<std::mutex> lock(mutex_);

  if (sourceType == InputSourceType::None) {
    return UnassignPortLocked(port);
  }

  if (sourceType == InputSourceType::Virtual) {
    for (int i = 0; i < InputSnapshot::kMaxPorts; ++i) {
      if (i == port) {
        continue;
      }
      if (portSources_[i].sourceType == InputSourceType::Virtual) {
        LOGF(LOG_INFO,
             "Auto-unbind virtual port %{public}d for new port %{public}d",
             i, port);
        const std::string staleDeviceId = portSources_[i].deviceId;
        if (!staleDeviceId.empty()) {
          auto staleIt = deviceToPort_.find(staleDeviceId);
          if (staleIt != deviceToPort_.end() && staleIt->second == i) {
            deviceToPort_.erase(staleIt);
          }
        }
        ClearPortStateLocked(i);
        portSources_[i].sourceType = InputSourceType::None;
        portSources_[i].deviceId.clear();
      }
    }
  }

  if (!deviceId.empty()) {
    auto it = deviceToPort_.find(deviceId);
    if (it != deviceToPort_.end() && it->second != port) {
      LOGF(LOG_WARN,
           "AssignPort conflict: device %{public}s already bound to port %{public}d",
           deviceId.c_str(), it->second);
      return false;
    }
  }

  const std::string oldDeviceId = portSources_[port].deviceId;
  if (!oldDeviceId.empty() && oldDeviceId != deviceId) {
    auto oldIt = deviceToPort_.find(oldDeviceId);
    if (oldIt != deviceToPort_.end() && oldIt->second == port) {
      deviceToPort_.erase(oldIt);
    }
  }

  if (portSources_[port].sourceType != sourceType ||
      portSources_[port].deviceId != deviceId) {
    ClearPortStateLocked(port);
  }

  portSources_[port].sourceType = sourceType;
  portSources_[port].deviceId = deviceId;

  if (!deviceId.empty()) {
    deviceToPort_[deviceId] = port;
  }

  LOGF(LOG_INFO,
       "AssignPort ok: port=%{public}d type=%{public}u device=%{public}s",
       port, static_cast<unsigned>(sourceType), deviceId.c_str());
  return true;
}

bool InputPortRouter::UnassignPort(int port) {
  if (!IsValidPort(port)) {
    return false;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  return UnassignPortLocked(port);
}

bool InputPortRouter::UnassignPortLocked(int port) {
  const std::string deviceId = portSources_[port].deviceId;
  if (!deviceId.empty()) {
    auto it = deviceToPort_.find(deviceId);
    if (it != deviceToPort_.end() && it->second == port) {
      deviceToPort_.erase(it);
    }
  }

  if (portSources_[port].sourceType != InputSourceType::None) {
    ClearPortStateLocked(port);
  }

  portSources_[port].sourceType = InputSourceType::None;
  portSources_[port].deviceId.clear();

  LOGF(LOG_INFO, "UnassignPort ok: port=%{public}d", port);
  return true;
}

bool InputPortRouter::CanSendVirtual(int port) const {
  if (!IsValidPort(port)) {
    return false;
  }
  if (!inputManager_) {
    return false;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  return portSources_[port].sourceType == InputSourceType::Virtual;
}

bool InputPortRouter::MatchSourceType(InputSourceType portType,
                                      InputSourceType incomingType) const {
  if (portType == incomingType) {
    return true;
  }
  if (incomingType == InputSourceType::Unknown) {
    return portType != InputSourceType::None &&
           portType != InputSourceType::Virtual;
  }
  return false;
}

bool InputPortRouter::ResolvePortForDevice(const std::string &deviceId,
                                           InputSourceType sourceType,
                                           int &outPort) {
  if (deviceId.empty()) {
    return false;
  }

  std::lock_guard<std::mutex> lock(mutex_);

  auto existing = deviceToPort_.find(deviceId);
  if (existing != deviceToPort_.end()) {
    int port = existing->second;
    if (IsValidPort(port)) {
      const PortSource &source = portSources_[port];
      if (source.deviceId == deviceId &&
          MatchSourceType(source.sourceType, sourceType)) {
        outPort = port;
        return true;
      }
    }
    deviceToPort_.erase(existing);
  }

  for (int port = 0; port < InputSnapshot::kMaxPorts; ++port) {
    const PortSource &source = portSources_[port];
    if (!MatchSourceType(source.sourceType, sourceType)) {
      continue;
    }
    if (!source.deviceId.empty() && source.deviceId != deviceId) {
      continue;
    }
    if (source.deviceId.empty()) {
      portSources_[port].deviceId = deviceId;
      deviceToPort_[deviceId] = port;
      LOGF(LOG_INFO,
           "Auto-bind device %{public}s to port %{public}d (type=%{public}u)",
           deviceId.c_str(), port, static_cast<unsigned>(sourceType));
    }
    outPort = port;
    return true;
  }

  return false;
}

void InputPortRouter::RecordDeviceSeen(const std::string &deviceId,
                                       InputSourceType sourceType,
                                       const std::string &name) {
  if (deviceId.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = devices_.find(deviceId);
  if (it != devices_.end()) {
    if (it->second.sourceType == InputSourceType::Unknown &&
        sourceType != InputSourceType::Unknown) {
      it->second.sourceType = sourceType;
    }
    if (!name.empty()) {
      it->second.name = name;
    }
    return;
  }
  InputDeviceInfo info;
  info.deviceId = deviceId;
  info.sourceType = sourceType;
  info.name = name;
  devices_[deviceId] = info;
}

std::vector<InputDeviceInfo> InputPortRouter::ListDevices() const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<InputDeviceInfo> list;
  list.reserve(devices_.size());
  for (const auto &kv : devices_) {
    list.push_back(kv.second);
  }
  std::sort(list.begin(), list.end(),
            [](const InputDeviceInfo &a, const InputDeviceInfo &b) {
              return a.deviceId < b.deviceId;
            });
  return list;
}

PortSource InputPortRouter::GetPortSource(int port) const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!IsValidPort(port)) {
    return {};
  }
  return portSources_[port];
}

} // namespace libretro
