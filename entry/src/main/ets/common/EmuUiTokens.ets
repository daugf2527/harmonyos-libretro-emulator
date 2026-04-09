export interface EmuColorTokens {
  background: string
  surfaceContainerLowest: string
  surfaceContainerLow: string
  surfaceContainer: string
  surfaceContainerHigh: string
  surfaceContainerHighest: string
  primary: string
  primaryDim: string
  onSurface: string
  onSurfaceVariant: string
  outlineVariant: string
  outline: string
  secondary: string
  error: string
}

export interface EmuSpacingTokens {
  xxs: number
  xs: number
  sm: number
  md: number
  lg: number
  xl: number
  xxl: number
}

export interface EmuRadiusTokens {
  sm: number
  md: number
  lg: number
  pill: number
}

export interface EmuMetricsTokens {
  headerHeight: number
  bottomNavHeight: number
  contentMaxWidth: number
  gridSize: number
  gridLineColor: string
  panelBorderColor: string
}

export const EmuColors: EmuColorTokens = {
  background: '#000000',
  surfaceContainerLowest: '#000000',
  surfaceContainerLow: '#131313',
  surfaceContainer: '#191919',
  surfaceContainerHigh: '#1F1F1F',
  surfaceContainerHighest: '#262626',
  primary: '#00FF41',
  primaryDim: '#00D635',
  onSurface: '#E5E5E5',
  onSurfaceVariant: '#ABABAB',
  outlineVariant: '#484848',
  outline: '#757575',
  secondary: '#9D9E9E',
  error: '#ED7F64'
}

export const EmuSpacing: EmuSpacingTokens = {
  xxs: 4,
  xs: 8,
  sm: 12,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48
}

export const EmuRadius: EmuRadiusTokens = {
  sm: 4,
  md: 8,
  lg: 12,
  pill: 999
}

export const EmuMetrics: EmuMetricsTokens = {
  headerHeight: 56,
  bottomNavHeight: 80,
  contentMaxWidth: 520,
  gridSize: 40,
  gridLineColor: '#1A484848',
  panelBorderColor: '#33484848'
}

export function createIndexRange(size: number): number[] {
  const values: number[] = []
  let index: number = 0
  while (index < size) {
    values.push(index)
    index += 1
  }
  return values
}
