/*
 * [LEGACY] This file is part of the old Standalone Chip8 implementation (Phase 2).
 * It is replaced by the Libretro Bridge architecture (Phase 3).
 *
 * VSync callback implementation for Chip8App
 */
#include "chip8_app.h"

void Chip8App::OnVSyncFrame(long long timestamp) {
    // This is called on VSync thread, synchronized with screen refresh
    // 使用互斥锁保护,防止与主线程的数据竞争
    std::lock_guard<std::mutex> lock(renderMutex_);
    RenderTestFrame();
}
