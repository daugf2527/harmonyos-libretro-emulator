/*
 * [LEGACY] This file is part of the old Standalone Chip8 implementation (Phase 2).
 * It is replaced by the Libretro Bridge architecture (Phase 3).
 *
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#ifndef CHIP8_CORE_H
#define CHIP8_CORE_H

#include <cstdint>
#include <random>

class Chip8Core {
public:
    Chip8Core();
    ~Chip8Core();

    // Initialize registers and memory once
    void Initialize();

    // Load a ROM file into memory
    bool LoadRom(const char *filename, uint64_t size);
    bool LoadRomFromBuffer(const uint8_t *buffer, uint64_t size);

    // Emulate one instruction cycle
    void Cycle();

    // Decrement timers (should be called at 60Hz)
    void TickTimers();

    // Input handling: Set key state (0-F)
    void SetKey(uint8_t key, bool pressed);

    // Accessors for Frontend
    const uint32_t *GetGraphicsBuffer() const { return videoBuffer_; }
    bool IsDrawFlag() const { return drawFlag_; }
    void ClearDrawFlag() { drawFlag_ = false; }
    bool ShouldPlaySound() const { return soundTimer_ > 0; }
    uint16_t GetPC() const { return pc_; }

    // Constants
    static constexpr int VIDEO_WIDTH = 64;
    static constexpr int VIDEO_HEIGHT = 32;
    static constexpr int KEY_COUNT = 16;
    static constexpr int MEMORY_SIZE = 4096;
    static constexpr int REGISTER_COUNT = 16;
    static constexpr int STACK_SIZE = 16;

private:
    uint16_t opcode_;
    uint8_t memory_[MEMORY_SIZE];
    uint8_t V_[REGISTER_COUNT]; // CPU registers V0-VF
    uint16_t I_;                // Index register
    uint16_t pc_;               // Program counter

    // Graphics system: Chip8 is 1-bit (64x32). 
    // But for easier rendering to NativeWindow (ARGB8888), 
    // we maintain a 32-bit buffer directly in the core for simplicity in this Phase.
    // In a strict emulator, this would be 1-bit and the frontend would convert it.
    uint32_t videoBuffer_[VIDEO_WIDTH * VIDEO_HEIGHT]; 

    uint8_t delayTimer_;
    uint8_t soundTimer_;

    uint16_t stack_[STACK_SIZE];
    uint16_t sp_;

    uint8_t key_[KEY_COUNT];

    bool drawFlag_;

    std::mt19937 rng_;
    std::uniform_int_distribution<uint8_t> dist_;
};

#endif // CHIP8_CORE_H
