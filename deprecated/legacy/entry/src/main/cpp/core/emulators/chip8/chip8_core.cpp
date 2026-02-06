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
#include "chip8_core.h"
#include <cstring>
#include <fstream>
#include <iostream>

// Standard Chip8 Fontset
const uint8_t chip8_fontset[80] = {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
};

Chip8Core::Chip8Core() : rng_(std::random_device{}()), dist_(0, 255) {
  Initialize();
}

Chip8Core::~Chip8Core() {}

void Chip8Core::Initialize() {
  pc_ = 0x200; // Program counter starts at 0x200
  opcode_ = 0;
  I_ = 0;
  sp_ = 0;

  // Clear display
  memset(videoBuffer_, 0, sizeof(videoBuffer_));
  // Clear stack
  memset(stack_, 0, sizeof(stack_));
  // Clear registers
  memset(V_, 0, sizeof(V_));
  // Clear memory
  memset(memory_, 0, sizeof(memory_));

  // Load fontset
  for (int i = 0; i < 80; ++i) {
    memory_[i] = chip8_fontset[i];
  }

  // Reset timers
  delayTimer_ = 0;
  soundTimer_ = 0;

  drawFlag_ = true;
}

bool Chip8Core::LoadRomFromBuffer(const uint8_t *buffer, uint64_t size) {
  if (size > (MEMORY_SIZE - 512)) {
    return false; // ROM too large
  }

  Initialize(); // Reset before loading

  for (int i = 0; i < size; ++i) {
    memory_[i + 512] = buffer[i];
  }
  return true;
}

bool Chip8Core::LoadRom(const char *filename, uint64_t size) {
  // Phase 4: Will implement file loading here
  return false;
}

void Chip8Core::SetKey(uint8_t key, bool pressed) {
  if (key < KEY_COUNT) {
    key_[key] = pressed ? 1 : 0;
  }
}

void Chip8Core::TickTimers() {
  if (delayTimer_ > 0) {
    --delayTimer_;
  }
  if (soundTimer_ > 0) {
    if (soundTimer_ == 1) {
      // BEEP! (Handled by Audio Loop)
    }
    --soundTimer_;
  }
}

void Chip8Core::Cycle() {
  // Fetch Opcode
  // Opcode is 2 bytes, memory is 1 byte. Merge two bytes.
  opcode_ = (memory_[pc_] << 8) | memory_[pc_ + 1];

  // CPU cycle execution (no logging for performance)

  // Decode & Execute
  // We switch based on the first nibble (4 bits)
  switch (opcode_ & 0xF000) {
  case 0x0000:
    switch (opcode_ & 0x000F) {
    case 0x0000: // 00E0: Clear the screen
      memset(videoBuffer_, 0, sizeof(videoBuffer_));
      drawFlag_ = true;
      pc_ += 2;
      break;

    case 0x000E: // 00EE: Return from subroutine
      --sp_;
      pc_ = stack_[sp_];
      pc_ += 2;
      break;

    default:
      // 0NNN: Ignored in modern interpreters
      pc_ += 2;
      break;
    }
    break;

  case 0x1000: // 1NNN: Jump to address NNN
    pc_ = opcode_ & 0x0FFF;
    break;

  case 0x6000: // 6XNN: Set VX to NN
    V_[(opcode_ & 0x0F00) >> 8] = opcode_ & 0x00FF;
    pc_ += 2;
    break;

  case 0x7000: // 7XNN: Add NN to VX (No carry flag change)
    V_[(opcode_ & 0x0F00) >> 8] += opcode_ & 0x00FF;
    pc_ += 2;
    break;

  case 0xA000: // ANNN: Set I to address NNN
    I_ = opcode_ & 0x0FFF;
    pc_ += 2;
    break;

  case 0xD000: // DXYN: Draw sprite at (VX, VY) with width N
  {
    uint16_t x = V_[(opcode_ & 0x0F00) >> 8];
    uint16_t y = V_[(opcode_ & 0x00F0) >> 4];
    uint16_t height = opcode_ & 0x000F;
    uint16_t pixel;

    V_[0xF] = 0; // Collision flag

    for (int yline = 0; yline < height; yline++) {
      pixel = memory_[I_ + yline];

      for (int xline = 0; xline < 8; xline++) {
        if ((pixel & (0x80 >> xline)) != 0) {
          int targetX = (x + xline) % VIDEO_WIDTH;
          int targetY = (y + yline) % VIDEO_HEIGHT;
          int index = targetX + (targetY * VIDEO_WIDTH);

          // XOR pixel: 0xFFFFFFFF is White, 0x00000000 is Black
          // If pixel is currently on (White)
          if (videoBuffer_[index] == 0xFFFFFFFF) {
            V_[0xF] = 1;                      // Collision!
            videoBuffer_[index] = 0xFF000000; // XOR -> Black
          } else {
            videoBuffer_[index] = 0xFFFFFFFF; // XOR -> White
          }
        }
      }
    }
    drawFlag_ = true;
    pc_ += 2;
  } break;

  default:
    // Unknown opcode, just skip it to avoid infinite loop
    // In real dev, we should log this.
    pc_ += 2;
    break;
  }
}
