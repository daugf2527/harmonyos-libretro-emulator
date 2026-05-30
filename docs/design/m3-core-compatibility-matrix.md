# M3: 核心兼容矩阵设计

**日期**: 2026-05-31  
**状态**: 📋 设计完成  
**关联任务**: M3 质量保障门禁

---

## 1. 设计目标

建立明确的核心兼容性测试标准，为发布前质量保障提供可执行的验证清单。

### 核心目标

1. **明确支持范围**: 列出所有支持的 libretro 核心和平台
2. **标准化测试**: 定义统一的测试维度和通过标准
3. **可追溯性**: 每个核心有明确的测试 ROM 和验证记录
4. **分级门槛**: P0/P1/P2 分级，明确发布阻塞条件

---

## 2. 支持的核心清单

基于 `LibretroCoreCatalog.ets` 和 `EmulatorConfigs.ets`，当前项目包含 **30 个 libretro 核心**。

### 2.1 核心分级策略

根据平台流行度、性能可行性、测试覆盖度，将核心分为三级：

| 级别 | 定义 | 发布要求 | 核心数量 |
|------|------|----------|----------|
| **P0 (必测)** | 主流平台，性能可玩，有测试 ROM | 必须全部通过 P0 标准 | 8 个 |
| **P1 (推荐)** | 次流行平台或性能边缘，有测试 ROM | 至少 80% 通过 P1 标准 | 7 个 |
| **P2 (实验)** | 小众平台或性能不可玩，测试覆盖有限 | 不阻塞发布，记录已知问题 | 15 个 |

---

## 3. P0 核心兼容矩阵（必测）

### 3.1 核心列表

| 核心 ID | 核心名称 | 平台 | .so 文件 | 测试 ROM | 优先级 |
|---------|----------|------|----------|----------|--------|
| `gambatte` | Gambatte | GB/GBC | `gambatte_libretro.ohos-arm64.so` | `snake_v0.1.gb` | P0 |
| `mgba` | mGBA | GBA | `mgba_libretro.ohos-arm64.so` | `Anguna.gba` | P0 |
| `fceumm` | FCEUmm | NES | `fceumm_libretro.ohos-arm64.so` | `Alter_Ego.nes` | P0 |
| `nestopia` | Nestopia | NES | `nestopia_libretro.ohos-arm64.so` | `Alter_Ego.nes` | P0 |
| `snes9x` | Snes9x | SNES | `snes9x_libretro.ohos-arm64.so` | `Classic_Kong.smc` | P0 |
| `genesis_plus_gx` | Genesis Plus GX | MD/GG | `genesis_plus_gx_libretro.ohos-arm64.so` | `30years.gen` | P0 |
| `2048` | 2048 | 内置游戏 | `lib2048_libretro.so` | (no-game) | P0 |
| `mrboom` | Mr.Boom | 内置游戏 | `mrboom_libretro.ohos-arm64.so` | `mrboom.desktop` | P0 |

**选择理由**:
- **GB/GBC/GBA/NES/SNES/MD**: 8/16 位主流平台，性能可玩，用户需求高
- **2048/Mr.Boom**: no-game 核心，测试核心加载和 HW_RENDER 基础能力
- **双 NES 核心**: 验证同平台多核心切换

### 3.2 测试 ROM 清单（P0）

| ROM 文件 | 平台 | 大小 | 来源 | 用途 | 许可 |
|----------|------|------|------|------|------|
| `snake_v0.1.gb` | GB | ~32 KB | [gbSnake](https://github.com/raph080/gbSnake) | GB 基础测试 | Apache-2.0 |
| `TobuTobuGirl.gbc` | GBC | ~128 KB | [tobutobugirl](https://github.com/SimonLarsen/tobutobugirl) | GBC 彩色测试 | MIT |
| `Anguna.gba` | GBA | ~2 MB | [Anguna](https://www.pineight.com/gba/) | GBA 基础测试 | 开源 |
| `240pTestSuite.gba` | GBA | ~512 KB | [240p Test Suite](https://junkerhq.net/xrgb/index.php?title=240p_test_suite) | GBA 视频测试 | 公有领域 |
| `Alter_Ego.nes` | NES | ~40 KB | [Alter Ego](https://shiru.untergrund.net/software.shtml) | NES 基础测试 | 开源 |
| `Classic_Kong.smc` | SNES | ~512 KB | [Classic Kong](https://www.romhacking.net/) | SNES 基础测试 | 自制 |
| `30years.gen` | MD | ~256 KB | [30 Years of Nintendon't](https://www.retrorgb.com/) | MD 基础测试 | 自制 |
| (no-game) | 2048 | - | 内置 | 2048 游戏 | - |
| `mrboom.desktop` | Mr.Boom | ~1 KB | 内置 | 炸弹人游戏 | - |

**ROM 选择原则**:
- ✅ 合法开源或公有领域
- ✅ 文件小（< 5 MB），加载快
- ✅ 有明确的视觉/音频反馈
- ✅ 覆盖核心功能（画面/音频/输入）

---

## 4. P1 核心兼容矩阵（推荐）

### 4.1 核心列表

| 核心 ID | 核心名称 | 平台 | .so 文件 | 测试 ROM | 优先级 |
|---------|----------|------|----------|----------|--------|
| `sameboy` | SameBoy | GB/GBC | `sameboy_libretro.ohos-arm64.so` | `snake_v0.1.gb` | P1 |
| `quicknes` | QuickNES | NES | `quicknes_libretro.ohos-arm64.so` | `Alter_Ego.nes` | P1 |
| `snes9x2010` | Snes9x 2010 | SNES | `snes9x2010_libretro.ohos-arm64.so` | `Classic_Kong.smc` | P1 |
| `mednafen_gba` | Beetle GBA | GBA | `mednafen_gba_libretro.ohos-arm64.so` | `Anguna.gba` | P1 |
| `fbneo` | FBNeo | Arcade | `fbneo_libretro.ohos-arm64.so` | `gridlee.zip` | P1 |
| `mednafen_ngp` | Beetle NGP | NGP | `mednafen_ngp_libretro.ohos-arm64.so` | `NeoGeoPocket_PD.ngp` | P1 |
| `race` | RACE | NGP | `race_libretro.ohos-arm64.so` | `NeoGeoPocket_PD.ngp` | P1 |

**选择理由**:
- **SameBoy/QuickNES/Snes9x2010**: 同平台备选核心，验证多核心兼容性
- **Beetle GBA**: 高精度 GBA 核心，性能边缘
- **FBNeo**: 街机核心，验证 ZIP ROM 支持
- **NGP 双核心**: 小众平台，验证覆盖度

### 4.2 测试 ROM 清单（P1）

| ROM 文件 | 平台 | 大小 | 来源 | 用途 |
|----------|------|------|------|------|
| `gridlee.zip` | Arcade | ~1 MB | [FBNeo](https://github.com/libretro/FBNeo) | 街机 ZIP ROM 测试 |
| `NeoGeoPocket_PD.ngp` | NGP | ~256 KB | 公有领域 | NGP 基础测试 |

---

## 5. P2 核心清单（实验性）

以下核心为**实验性支持**，不阻塞发布，但需记录已知问题：

| 核心 ID | 核心名称 | 平台 | 已知限制 |
|---------|----------|------|----------|
| `melonds` | melonDS | NDS | 双屏布局未完成，性能边缘 |
| `mednafen_psx_hw` | Beetle PSX HW | PS1 | 需 HW_RENDER，性能不可玩 |
| `pcsx_rearmed` | PCSX-ReARMed | PS1 | 需 dynarec，HarmonyOS 禁 JIT |
| `bsnes_hd_beta` | bsnes-hd beta | SNES | 高精度，性能开销大 |
| `mame2010` | MAME 2010 | Arcade | ROM 集复杂，测试覆盖有限 |
| `mesen` | Mesen | NES | 高精度，性能边缘 |
| `crocods` | Crocods | Amstrad CPC | 小众平台 |
| `freeintv` | FreeIntv | Intellivision | 小众平台 |
| `minivmac` | Mini vMac | Macintosh | 需 BIOS，测试复杂 |
| `potator` | Potator | Watara Supervision | 小众平台 |
| `retro8` | Retro8 | PICO-8 | 需 PICO-8 ROM |
| `vice_x128` | VICE x128 | C128 | 小众平台 |
| `vice_x64` | VICE x64 | C64 | 小众平台 |
| `vice_xcbm2` | VICE xcbm2 | CBM-II | 小众平台 |
| `vice_xpet` | VICE xpet | PET | 小众平台 |
| `xrick` | XRick | Rick Dangerous | 需特定 data.zip |

**处理策略**:
- 记录到 `docs/known-issues.md`
- 标注"实验性支持"
- 不阻塞发布，但接受社区反馈

---

## 6. 测试维度与通过标准

### 6.1 测试维度

每个核心需验证以下 6 个维度：

| 维度 | 测试内容 | 验证方法 |
|------|----------|----------|
| **T1: 核心加载** | .so 文件能否成功 dlopen/dlsym | 日志无 `LoadCore failed` |
| **T2: ROM 启动** | ROM 文件能否加载并进入游戏 | 日志显示 `retro_load_game: true` |
| **T3: 画面输出** | 是否有正常画面（不黑屏/花屏） | 目视确认画面正常 |
| **T4: 音频输出** | 是否有正常音频（不静音/爆音） | 耳机确认音频正常 |
| **T5: 输入响应** | 按键是否有响应 | 虚拟手柄/物理按键有反馈 |
| **T6: 稳定性** | 运行 5 分钟无崩溃 | 日志无 crash，UI 无 ANR |

### 6.2 通过标准（分级）

| 级别 | 必须通过的维度 | 通过条件 |
|------|----------------|----------|
| **P0 标准** | T1 + T2 + T3 | 核心加载 + ROM 启动 + 画面输出 |
| **P1 标准** | T1 + T2 + T3 + T4 + T5 | P0 + 音频输出 + 输入响应 |
| **P2 标准** | T1 + T2 + T3 + T4 + T5 + T6 | P1 + 稳定性（5 分钟） |

**发布门槛**:
- ✅ **P0 核心**: 必须 100% 通过 P0 标准（8/8）
- ✅ **P1 核心**: 至少 80% 通过 P1 标准（6/7）
- ⚠️ **P2 核心**: 不阻塞发布，记录已知问题

---

## 7. 验证检查清单

### 7.1 测试前准备

- [ ] 真机环境（HarmonyOS API 12+）
- [ ] 安装最新 HAP（Debug 或 Release）
- [ ] 准备测试 ROM（见上述清单）
- [ ] 启用 hilog 过滤（`hilog | grep -E "LibretroEngine|CoreLoader"`）

### 7.2 单核心验证流程

对每个核心执行以下步骤：

1. **启动应用** → 进入 LibraryPage
2. **选择 ROM** → 点击对应平台的测试 ROM
3. **观察加载** → 检查日志 `LoadCore` / `LoadGame` 状态
4. **验证画面** → 目视确认画面正常（T3）
5. **验证音频** → 耳机确认音频正常（T4）
6. **验证输入** → 按虚拟手柄，观察游戏响应（T5）
7. **稳定性测试** → 运行 5 分钟，观察日志无 crash（T6）
8. **记录结果** → 填写验证矩阵表格

### 7.3 验证矩阵模板

```markdown
| 核心 ID | T1 加载 | T2 启动 | T3 画面 | T4 音频 | T5 输入 | T6 稳定 | 通过标准 | 备注 |
|---------|---------|---------|---------|---------|---------|---------|----------|------|
| gambatte | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | P2 | 完全通过 |
| mgba | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | P1 | 5 分钟后偶现卡顿 |
| fceumm | ✅ | ✅ | ✅ | ❌ | ✅ | - | P0 | 音频爆音 |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |
```

---

## 8. 已知限制与风险

### 8.1 平台限制

| 限制 | 影响范围 | 缓解措施 |
|------|----------|----------|
| **禁 JIT/dynarec** | PS1/PSP/N64/3DS 核心性能不可玩 | 标注"实验性"，不作为 P0/P1 |
| **HW_RENDER 稳定性** | GLES/Vulkan 核心可能崩溃 | 优先测试 Software 核心 |
| **双屏布局未完成** | NDS/3DS 核心显示不完整 | 标注"已知问题" |
| **大 ROM 加载慢** | PS1/NDS ROM > 100 MB 阻塞 UI | M1 沙盒优化后改善 |

### 8.2 测试覆盖风险

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| **测试 ROM 不代表所有 ROM** | 高 | 用户报告兼容性问题 | 文档说明"测试覆盖有限" |
| **真机环境差异** | 中 | 不同设备表现不一致 | 多设备验证（至少 2 台） |
| **长时稳定性未覆盖** | 中 | 运行 > 1 小时可能崩溃 | 标注"5 分钟基线" |

---

## 9. 后续优化方向

### 9.1 短期（M3 完成后）

- [ ] 补充 P1 核心的测试 ROM（FBNeo/NGP）
- [ ] 多设备验证（至少 2 台真机）
- [ ] 记录每个核心的性能基线（FPS/内存）

### 9.2 中期（M4-M6）

- [ ] 自动化测试脚本（NAPI 接口 + 截图对比）
- [ ] 扩展测试 ROM 清单（每平台 3+ ROM）
- [ ] 长时稳定性测试（1 小时 soak test）

### 9.3 长期（M7+）

- [ ] 社区反馈收集（GitHub Issues）
- [ ] 兼容性数据库（ROM 黑名单/白名单）
- [ ] CI 集成（PR 自动跑核心加载测试）

---

## 10. 参考资料

### 10.1 内部文档

- `entry/src/main/ets/common/LibretroCoreCatalog.ets` - 核心清单
- `entry/src/main/ets/config/EmulatorConfigs.ets` - 平台配置
- `docs/audit/m0-t29-verification-plan.md` - M0 验证方法论
- `entry/src/main/resources/rawfile/roms/README.md` - ROM 来源

### 10.2 外部资源

- [Libretro Docs](https://docs.libretro.com/) - 官方文档
- [240p Test Suite](https://junkerhq.net/xrgb/index.php?title=240p_test_suite) - 视频测试 ROM
- [Homebrew Hub](https://www.homebrewhub.net/) - 开源 ROM 集合

---

## 附录 A: 完整核心清单（30 个）

| # | 核心 ID | 核心名称 | 平台 | 级别 | 测试 ROM |
|---|---------|----------|------|------|----------|
| 1 | `2048` | 2048 | 内置 | P0 | (no-game) |
| 2 | `gambatte` | Gambatte | GB/GBC | P0 | `snake_v0.1.gb` |
| 3 | `nestopia` | Nestopia | NES | P0 | `Alter_Ego.nes` |
| 4 | `fceumm` | FCEUmm | NES | P0 | `Alter_Ego.nes` |
| 5 | `quicknes` | QuickNES | NES | P1 | `Alter_Ego.nes` |
| 6 | `genesis_plus_gx` | Genesis Plus GX | MD/GG | P0 | `30years.gen` |
| 7 | `snes9x` | Snes9x | SNES | P0 | `Classic_Kong.smc` |
| 8 | `mgba` | mGBA | GBA | P0 | `Anguna.gba` |
| 9 | `mednafen_gba` | Beetle GBA | GBA | P1 | `Anguna.gba` |
| 10 | `mednafen_psx_hw` | Beetle PSX HW | PS1 | P2 | (需 BIOS) |
| 11 | `mednafen_ngp` | Beetle NGP | NGP | P1 | `NeoGeoPocket_PD.ngp` |
| 12 | `melonds` | melonDS | NDS | P2 | (双屏未完成) |
| 13 | `fbneo` | FBNeo | Arcade | P1 | `gridlee.zip` |
| 14 | `mame2010` | MAME 2010 | Arcade | P2 | (ROM 集复杂) |
| 15 | `race` | RACE | NGP | P1 | `NeoGeoPocket_PD.ngp` |
| 16 | `bsnes_hd_beta` | bsnes-hd beta | SNES | P2 | (性能开销大) |
| 17 | `crocods` | Crocods | Amstrad CPC | P2 | `Amstrad_CPC_PD.dsk` |
| 18 | `freeintv` | FreeIntv | Intellivision | P2 | `Intellivision_PD.int` |
| 19 | `mesen` | Mesen | NES | P2 | (高精度) |
| 20 | `minivmac` | Mini vMac | Macintosh | P2 | `minivmac_disk.dsk` |
| 21 | `mrboom` | Mr.Boom | 内置 | P0 | `mrboom.desktop` |
| 22 | `pcsx_rearmed` | PCSX-ReARMed | PS1 | P2 | (需 dynarec) |
| 23 | `potator` | Potator | Watara SV | P2 | (小众平台) |
| 24 | `retro8` | Retro8 | PICO-8 | P2 | `celeste_demake.p8` |
| 25 | `sameboy` | SameBoy | GB/GBC | P1 | `snake_v0.1.gb` |
| 26 | `snes9x2010` | Snes9x 2010 | SNES | P1 | `Classic_Kong.smc` |
| 27 | `vice_x128` | VICE x128 | C128 | P2 | (小众平台) |
| 28 | `vice_x64` | VICE x64 | C64 | P2 | (小众平台) |
| 29 | `vice_xcbm2` | VICE xcbm2 | CBM-II | P2 | (小众平台) |
| 30 | `vice_xpet` | VICE xpet | PET | P2 | (小众平台) |
| 31 | `xrick` | XRick | Rick Dangerous | P2 | `data.zip` |

---

## 附录 B: 快速验证命令

### B.1 日志过滤

```bash
# 核心加载日志
hdc shell hilog -x | grep -E "LoadCore|dlopen|dlsym"

# ROM 启动日志
hdc shell hilog -x | grep -E "LoadGame|retro_load_game"

# 画面输出日志
hdc shell hilog -x | grep -E "VideoPipeline|retro_video_refresh"

# 音频输出日志
hdc shell hilog -x | grep -E "AudioBridge|retro_audio_sample"

# 崩溃日志
hdc shell hilog -x | grep -E "FATAL|CRASH|SIGSEGV"
```

### B.2 性能监控

```bash
# CPU 使用率
hdc shell top -n 1 | grep com.libretro.harmonyos

# 内存使用
hdc shell dumpsys mem | grep com.libretro.harmonyos

# FPS 监控（从日志提取）
hdc shell hilog -x | grep "FPS:"
```

---

**文档版本**: v1.0  
**最后更新**: 2026-05-31  
**维护者**: Codex Bot
