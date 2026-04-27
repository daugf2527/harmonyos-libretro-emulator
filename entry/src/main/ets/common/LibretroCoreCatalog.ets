export interface CoreConfig {
  id: string
  name: string
  soFile: string
  description: string
}

export interface CoreExtensionRule {
  coreId: string
  extensions: string[]
  requiresExactName?: string
}

export const LIBRETRO_CORE_CATALOG: CoreConfig[] = [
  {
    id: '2048',
    name: '2048',
    soFile: 'lib2048_libretro.so',
    description: 'Libretro 2048'
  },
  {
    id: 'gambatte',
    name: 'Gambatte (GB/GBC)',
    soFile: 'gambatte_libretro.ohos-arm64.so',
    description: 'Game Boy / Game Boy Color'
  },
  {
    id: 'nestopia',
    name: 'Nestopia (NES)',
    soFile: 'nestopia_libretro.ohos-arm64.so',
    description: 'Nintendo Entertainment System'
  },
  {
    id: 'fceumm',
    name: 'FCEUmm (NES)',
    soFile: 'fceumm_libretro.ohos-arm64.so',
    description: 'Nintendo Entertainment System (FCEUmm)'
  },
  {
    id: 'quicknes',
    name: 'QuickNES (NES)',
    soFile: 'quicknes_libretro.ohos-arm64.so',
    description: 'Nintendo Entertainment System (QuickNES)'
  },
  {
    id: 'genesis_plus_gx',
    name: 'Genesis Plus GX (MD)',
    soFile: 'genesis_plus_gx_libretro.ohos-arm64.so',
    description: 'Mega Drive / Genesis'
  },
  {
    id: 'snes9x',
    name: 'Snes9x (SNES)',
    soFile: 'snes9x_libretro.ohos-arm64.so',
    description: 'Super Nintendo'
  },
  {
    id: 'mgba',
    name: 'mGBA (GBA)',
    soFile: 'mgba_libretro.ohos-arm64.so',
    description: 'Game Boy Advance'
  },
  {
    id: 'mednafen_gba',
    name: 'Beetle GBA (Mednafen)',
    soFile: 'mednafen_gba_libretro.ohos-arm64.so',
    description: 'Game Boy Advance (Mednafen)'
  },
  {
    id: 'mednafen_psx_hw',
    name: 'Beetle PSX HW',
    soFile: 'mednafen_psx_hw_libretro.ohos-arm64.so',
    description: 'PlayStation (HW render)'
  },
  {
    id: 'mednafen_ngp',
    name: 'Beetle NGP (Mednafen)',
    soFile: 'mednafen_ngp_libretro.ohos-arm64.so',
    description: 'Neo Geo Pocket'
  },
  {
    id: 'melonds',
    name: 'melonDS (NDS)',
    soFile: 'melonds_libretro.ohos-arm64.so',
    description: 'Nintendo DS'
  },
  {
    id: 'fbneo',
    name: 'FBNeo (Arcade)',
    soFile: 'fbneo_libretro.ohos-arm64.so',
    description: 'FinalBurn Neo'
  },
  {
    id: 'mame2010',
    name: 'MAME 2010',
    soFile: 'mame2010_libretro.ohos-arm64.so',
    description: 'Arcade (MAME 2010)'
  },
  {
    id: 'race',
    name: 'RACE (NGP)',
    soFile: 'race_libretro.ohos-arm64.so',
    description: 'Neo Geo Pocket (RACE)'
  },
  {
    id: 'bsnes_hd_beta',
    name: 'bsnes-hd beta',
    soFile: 'bsnes_hd_beta_libretro.ohos-arm64.so',
    description: 'bsnes-hd beta'
  },
  {
    id: 'crocods',
    name: 'Crocods',
    soFile: 'crocods_libretro.ohos-arm64.so',
    description: 'Crocods'
  },
  {
    id: 'freeintv',
    name: 'FreeIntv',
    soFile: 'freeintv_libretro.ohos-arm64.so',
    description: 'FreeIntv'
  },
  {
    id: 'mesen',
    name: 'Mesen',
    soFile: 'mesen_libretro.ohos-arm64.so',
    description: 'Mesen'
  },
  {
    id: 'minivmac',
    name: 'Mini vMac',
    soFile: 'minivmac_libretro.ohos-arm64.so',
    description: 'Mini vMac'
  },
  {
    id: 'mrboom',
    name: 'Mr.Boom',
    soFile: 'mrboom_libretro.ohos-arm64.so',
    description: 'Mr.Boom'
  },
  {
    id: 'pcsx_rearmed',
    name: 'PCSX-ReARMed',
    soFile: 'pcsx_rearmed_libretro.ohos-arm64.so',
    description: 'PCSX-ReARMed'
  },
  {
    id: 'potator',
    name: 'Potator',
    soFile: 'potator_libretro.ohos-arm64.so',
    description: 'Potator'
  },
  {
    id: 'retro8',
    name: 'Retro8',
    soFile: 'retro8_libretro.ohos-arm64.so',
    description: 'Retro8'
  },
  {
    id: 'sameboy',
    name: 'SameBoy',
    soFile: 'sameboy_libretro.ohos-arm64.so',
    description: 'SameBoy'
  },
  {
    id: 'snes9x2010',
    name: 'Snes9x 2010',
    soFile: 'snes9x2010_libretro.ohos-arm64.so',
    description: 'Snes9x 2010'
  },
  {
    id: 'vice_x128',
    name: 'VICE x128',
    soFile: 'vice_x128_libretro.ohos-arm64.so',
    description: 'VICE x128'
  },
  {
    id: 'vice_x64',
    name: 'VICE x64',
    soFile: 'vice_x64_libretro.ohos-arm64.so',
    description: 'VICE x64'
  },
  {
    id: 'vice_xcbm2',
    name: 'VICE xcbm2',
    soFile: 'vice_xcbm2_libretro.ohos-arm64.so',
    description: 'VICE xcbm2'
  },
  {
    id: 'vice_xpet',
    name: 'VICE xpet',
    soFile: 'vice_xpet_libretro.ohos-arm64.so',
    description: 'VICE xpet'
  },
  {
    id: 'xrick',
    name: 'XRick',
    soFile: 'xrick_libretro.ohos-arm64.so',
    description: 'XRick'
  }
]

export const NO_GAME_CORE_IDS: string[] = ['mrboom', '2048']

export const LIBRETRO_CORE_EXTENSION_RULES: CoreExtensionRule[] = [
  { coreId: 'gambatte', extensions: ['gb', 'gbc', 'dmg'] },
  { coreId: 'sameboy', extensions: ['gb', 'gbc'] },
  { coreId: 'nestopia', extensions: ['nes', 'fds', 'unf', 'unif'] },
  { coreId: 'fceumm', extensions: ['fds', 'nes', 'unif', 'unf'] },
  { coreId: 'quicknes', extensions: ['nes'] },
  { coreId: 'genesis_plus_gx', extensions: ['mdx', 'md', 'smd', 'gen', 'cue', 'iso', 'sms', 'bms', 'gg', 'sg', '68k', 'sgd', 'chd', 'm3u'] },
  { coreId: 'snes9x', extensions: ['smc', 'sfc', 'swc', 'fig', 'bs', 'st'] },
  { coreId: 'snes9x2010', extensions: ['smc', 'fig', 'sfc', 'gd3', 'gd7', 'dx2', 'bsx', 'swc'] },
  { coreId: 'bsnes_hd_beta', extensions: ['smc', 'sfc', 'swc', 'fig', 'bs'] },
  { coreId: 'mgba', extensions: ['gb', 'gbc', 'gba'] },
  { coreId: 'mednafen_gba', extensions: ['gba', 'agb'] },
  { coreId: 'mednafen_psx_hw', extensions: ['cue', 'toc', 'm3u', 'ccd', 'pbp', 'chd'] },
  { coreId: 'mednafen_ngp', extensions: ['ngp', 'ngc', 'ngpc', 'npc'] },
  { coreId: 'melonds', extensions: ['nds', 'ids', 'dsi'] },
  { coreId: 'fbneo', extensions: ['zip', '7z', 'cue', 'ccd'] },
  { coreId: 'mame2010', extensions: ['zip', '7z'] },
  { coreId: 'race', extensions: ['ngp', 'ngc', 'ngpc', 'npc'] },
  { coreId: 'crocods', extensions: ['dsk', 'sna', 'kcr'] },
  { coreId: 'freeintv', extensions: ['int'] },
  { coreId: 'minivmac', extensions: ['dsk', 'hvf', 'cmd'] },
  { coreId: 'mrboom', extensions: ['desktop'] },
  { coreId: 'pcsx_rearmed', extensions: ['cue', 'iso', 'pbp', 'chd', 'toc', 'm3u', 'cbn'] },
  { coreId: 'potator', extensions: ['sv'] },
  { coreId: 'retro8', extensions: ['p8', 'png'] },
  { coreId: 'vice_x128', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
  { coreId: 'vice_x64', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
  { coreId: 'vice_xcbm2', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
  { coreId: 'vice_xpet', extensions: ['d64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap', 'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd', 'm3u', 'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'] },
  { coreId: 'xrick', extensions: ['zip'], requiresExactName: 'data.zip' }
]
