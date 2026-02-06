#ifndef COMMON_FENCE_UTILS_H
#define COMMON_FENCE_UTILS_H

namespace common {

/**
 * @brief 等待 Sync Fence 信号，然后关闭文件描述符。
 * 
 * @param fenceFd Fence 文件描述符
 * @param timeoutMs 超时时间（毫秒），默认 3000ms
 * @return int 0: 成功, -1: 错误, 1: 超时
 */
int WaitAndCloseFence(int fenceFd, int timeoutMs = 3000);

} // namespace common

#endif // COMMON_FENCE_UTILS_H
