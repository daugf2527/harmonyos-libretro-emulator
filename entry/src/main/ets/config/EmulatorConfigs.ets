/*
 * 模拟器配置系统
 * 统一管理不同模拟器的屏幕比例、名称、特性等配置
 */

/**
 * 模拟器类型枚举
 */
export enum EmulatorType {
  // 方块游戏
  GAME_2048 = '2048',
  
  // 任天堂掌机
  GAME_BOY = 'gb',           // Game Boy (1989)
  GAME_BOY_COLOR = 'gbc',    // Game Boy Color (1998)
  GAME_BOY_ADVANCE = 'gba',  // Game Boy Advance (2001)
  
  // 任天堂家用机
  NES = 'nes',               // Nintendo Entertainment System (1983)
  SNES = 'snes',             // Super Nintendo (1990)
  N64 = 'n64',               // Nintendo 64 (1996)
  
  // 双屏掌机
  NINTENDO_DS = 'nds',       // Nintendo DS (2004)
  NINTENDO_3DS = '3ds',      // Nintendo 3DS (2011)
  
  // 世嘉
  SEGA_GENESIS = 'genesis',  // Sega Genesis / Mega Drive (1988)
  SEGA_GAME_GEAR = 'gg',     // Game Gear (1990)
  
  // 索尼
  PSP = 'psp',               // PlayStation Portable (2004)
  PS1 = 'ps1',               // PlayStation 1 (1994)
  
  // 街机
  ARCADE = 'arcade',         // MAME / FinalBurn Neo
  
  // 其他
  ATARI_2600 = 'atari2600',  // Atari 2600 (1977)
  NEO_GEO_POCKET = 'ngp',    // Neo Geo Pocket (1998)
}

/**
 * 模拟器配置接口
 */
export interface EmulatorConfig {
  // 基础信息
  id: string;                // 模拟器 ID
  name: string;              // 显示名称
  fullName: string;          // 完整名称
  manufacturer: string;      // 制造商
  releaseYear: number;       // 发行年份
  
  // 屏幕配置
  aspectRatio: number;       // 屏幕比例 (宽:高)
  nativeWidth: number;       // 原生分辨率宽度
  nativeHeight: number;      // 原生分辨率高度
  
  // 特性标记
  dualScreen: boolean;       // 是否双屏
  touchScreen: boolean;      // 是否支持触摸屏
  
  // Libretro 核心信息
  coreLibrary: string;       // 推荐的 Libretro 核心库名称
  corePath?: string;         // 核心文件路径 (可选)
}

/**
 * 模拟器配置数据库
 */
export const EMULATOR_CONFIGS: Record<string, EmulatorConfig> = {
  // ==================== 方块游戏 ====================
  [EmulatorType.GAME_2048]: {
    id: '2048',
    name: '2048',
    fullName: '2048 Puzzle Game',
    manufacturer: 'Gabriele Cirulli',
    releaseYear: 2014,
    aspectRatio: 1.0,          // 1:1 方形
    nativeWidth: 4,
    nativeHeight: 4,
    dualScreen: false,
    touchScreen: true,
    coreLibrary: 'libretro_2048.so'
  },
  
  // ==================== 任天堂掌机 ====================
  [EmulatorType.GAME_BOY]: {
    id: 'gb',
    name: 'Game Boy',
    fullName: 'Nintendo Game Boy',
    manufacturer: 'Nintendo',
    releaseYear: 1989,
    aspectRatio: 10 / 9,       // 160×144 ≈ 1.111
    nativeWidth: 160,
    nativeHeight: 144,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'gambatte_libretro.so'
  },
  
  [EmulatorType.GAME_BOY_COLOR]: {
    id: 'gbc',
    name: 'Game Boy Color',
    fullName: 'Nintendo Game Boy Color',
    manufacturer: 'Nintendo',
    releaseYear: 1998,
    aspectRatio: 10 / 9,       // 160×144
    nativeWidth: 160,
    nativeHeight: 144,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'gambatte_libretro.so'
  },
  
  [EmulatorType.GAME_BOY_ADVANCE]: {
    id: 'gba',
    name: 'GBA',
    fullName: 'Game Boy Advance',
    manufacturer: 'Nintendo',
    releaseYear: 2001,
    aspectRatio: 3 / 2,        // 240×160 = 1.5
    nativeWidth: 240,
    nativeHeight: 160,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'mgba_libretro.so'
  },
  
  // ==================== 任天堂家用机 ====================
  [EmulatorType.NES]: {
    id: 'nes',
    name: 'NES',
    fullName: 'Nintendo Entertainment System',
    manufacturer: 'Nintendo',
    releaseYear: 1983,
    aspectRatio: 4 / 3,        // 256×224 ≈ 1.143 (显示为 4:3)
    nativeWidth: 256,
    nativeHeight: 224,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'fceumm_libretro.so'
  },
  
  [EmulatorType.SNES]: {
    id: 'snes',
    name: 'SNES',
    fullName: 'Super Nintendo Entertainment System',
    manufacturer: 'Nintendo',
    releaseYear: 1990,
    aspectRatio: 4 / 3,        // 256×224 (显示为 4:3)
    nativeWidth: 256,
    nativeHeight: 224,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'snes9x_libretro.so'
  },
  
  [EmulatorType.N64]: {
    id: 'n64',
    name: 'N64',
    fullName: 'Nintendo 64',
    manufacturer: 'Nintendo',
    releaseYear: 1996,
    aspectRatio: 4 / 3,        // 320×240
    nativeWidth: 320,
    nativeHeight: 240,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'mupen64plus_next_libretro.so'
  },
  
  // ==================== 双屏掌机 ====================
  [EmulatorType.NINTENDO_DS]: {
    id: 'nds',
    name: 'NDS',
    fullName: 'Nintendo DS',
    manufacturer: 'Nintendo',
    releaseYear: 2004,
    aspectRatio: 4 / 3,        // 单屏 256×192，双屏垂直排列
    nativeWidth: 256,
    nativeHeight: 192,
    dualScreen: true,          // 双屏
    touchScreen: true,         // 下屏触摸
    coreLibrary: 'desmume_libretro.so'
  },
  
  [EmulatorType.NINTENDO_3DS]: {
    id: '3ds',
    name: '3DS',
    fullName: 'Nintendo 3DS',
    manufacturer: 'Nintendo',
    releaseYear: 2011,
    aspectRatio: 5 / 3,        // 上屏 400×240
    nativeWidth: 400,
    nativeHeight: 240,
    dualScreen: true,          // 双屏
    touchScreen: true,
    coreLibrary: 'citra_libretro.so'
  },
  
  // ==================== 世嘉 ====================
  [EmulatorType.SEGA_GENESIS]: {
    id: 'genesis',
    name: 'Genesis',
    fullName: 'Sega Genesis / Mega Drive',
    manufacturer: 'Sega',
    releaseYear: 1988,
    aspectRatio: 4 / 3,        // 320×224
    nativeWidth: 320,
    nativeHeight: 224,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'genesis_plus_gx_libretro.so'
  },
  
  [EmulatorType.SEGA_GAME_GEAR]: {
    id: 'gg',
    name: 'Game Gear',
    fullName: 'Sega Game Gear',
    manufacturer: 'Sega',
    releaseYear: 1990,
    aspectRatio: 160 / 144,    // 160×144
    nativeWidth: 160,
    nativeHeight: 144,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'genesis_plus_gx_libretro.so'
  },
  
  // ==================== 索尼 ====================
  [EmulatorType.PSP]: {
    id: 'psp',
    name: 'PSP',
    fullName: 'PlayStation Portable',
    manufacturer: 'Sony',
    releaseYear: 2004,
    aspectRatio: 16 / 9,       // 480×272 ≈ 1.765
    nativeWidth: 480,
    nativeHeight: 272,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'ppsspp_libretro.so'
  },
  
  [EmulatorType.PS1]: {
    id: 'ps1',
    name: 'PS1',
    fullName: 'PlayStation 1',
    manufacturer: 'Sony',
    releaseYear: 1994,
    aspectRatio: 4 / 3,        // 320×240
    nativeWidth: 320,
    nativeHeight: 240,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'pcsx_rearmed_libretro.so'
  },
  
  // ==================== 街机 ====================
  [EmulatorType.ARCADE]: {
    id: 'arcade',
    name: 'Arcade',
    fullName: 'Arcade (MAME)',
    manufacturer: 'Various',
    releaseYear: 1970,
    aspectRatio: 4 / 3,        // 通用比例
    nativeWidth: 320,
    nativeHeight: 240,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'mame_libretro.so'
  },
  
  // ==================== 其他 ====================
  [EmulatorType.ATARI_2600]: {
    id: 'atari2600',
    name: 'Atari 2600',
    fullName: 'Atari 2600',
    manufacturer: 'Atari',
    releaseYear: 1977,
    aspectRatio: 4 / 3,        // 160×192
    nativeWidth: 160,
    nativeHeight: 192,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'stella_libretro.so'
  },
  
  [EmulatorType.NEO_GEO_POCKET]: {
    id: 'ngp',
    name: 'NGP',
    fullName: 'Neo Geo Pocket',
    manufacturer: 'SNK',
    releaseYear: 1998,
    aspectRatio: 152 / 152,    // 152×152 (方形)
    nativeWidth: 152,
    nativeHeight: 152,
    dualScreen: false,
    touchScreen: false,
    coreLibrary: 'mednafen_ngp_libretro.so'
  }
};

/**
 * 工具函数: 根据 ID 获取配置
 */
export function getEmulatorConfig(id: string): EmulatorConfig | undefined {
  return EMULATOR_CONFIGS[id];
}

/**
 * 工具函数: 获取所有单屏模拟器
 */
export function getSingleScreenEmulators(): EmulatorConfig[] {
  return Object.values(EMULATOR_CONFIGS).filter(config => !config.dualScreen);
}

/**
 * 工具函数: 获取所有双屏模拟器
 */
export function getDualScreenEmulators(): EmulatorConfig[] {
  return Object.values(EMULATOR_CONFIGS).filter(config => config.dualScreen);
}

/**
 * 工具函数: 按制造商分组
 */
export function getEmulatorsByManufacturer(manufacturer: string): EmulatorConfig[] {
  return Object.values(EMULATOR_CONFIGS).filter(config => config.manufacturer === manufacturer);
}

/**
 * 工具函数: 获取所有制造商列表
 */
export function getAllManufacturers(): string[] {
  const manufacturers = new Set<string>();
  Object.values(EMULATOR_CONFIGS).forEach(config => manufacturers.add(config.manufacturer));
  return Array.from(manufacturers).sort();
}
