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
  error: '#ff4d4f'
}

// === 组件状态设计系统 ===
// 三原则：即时反应（每个交互态都有视觉反馈）、清晰反馈（状态之间区分明显）、
// 一致体验（同类组件用相同 token，跨页面视觉/动效一致）。
//
// 状态优先级（从高到低）：
//   disabled > loading > error > selected > active > focus > hover > default
// 高优先级状态生效时，低优先级状态视觉应被覆盖。

export interface EmuStateColorTokens {
  // danger - 危险/破坏性操作（删除、停止、终止）
  dangerDefault: string
  dangerHover: string
  dangerActive: string
  dangerDisabled: string
  // success / 校验态
  success: string
  warning: string
  // 状态文本对比色
  onDanger: string
  // 通用按下/选中态用主题色，反色文字为黑
  onPrimary: string
  // disabled 灰度色（背景与边框）
  disabledBackground: string
  disabledBorder: string
  disabledText: string
}

export const EmuStateColors: EmuStateColorTokens = {
  dangerDefault: '#ff4d4f',
  dangerHover: '#ff7875',
  dangerActive: '#d9363e',
  dangerDisabled: '#7A2628',
  success: '#52c41a',
  warning: '#faad14',
  onDanger: '#FFFFFF',
  onPrimary: '#000000',
  disabledBackground: '#1A1A1A',
  disabledBorder: '#3A3A3A',
  disabledText: '#5A5A5A'
}

export interface EmuMotionTokens {
  // 200ms - 状态切换（hover、pressed、selected、color shift）
  stateChangeMs: number
  // 300ms - 容器展开/折叠（下拉、抽屉、对话框）
  containerExpandMs: number
  // 1200ms - 一圈，loading spinner 旋转周期
  loadingSpinMs: number
  // ArkUI Curve.EaseInOut 引用（避免每个调用方都 import Curve）
  // 类型用 number 避免 strict ArkTS 跨模块枚举校验问题；实际由组件按需用
  // Curve.EaseInOut 实例化。
}

export const EmuMotion: EmuMotionTokens = {
  stateChangeMs: 200,
  containerExpandMs: 300,
  loadingSpinMs: 1200
}

// === 字号 token（与 EmuSpacing 命名风格对齐）===
// 选档原则：覆盖现网字面量分布 8/9/10/11/12/13/14/15/16/17/18/20/22/24/34
//   xxs(8) - telemetry / badge / 极小信息字
//   xs(10) - caption / 副标签
//   sm(12) - 辅助字 / 小按钮
//   md(14) - 正文 / 中按钮
//   lg(16) - 副标题 / 主按钮
//   xl(18) - 强调副标题
//   xxl(22) - 标题
//   display(28) - 大标题 / 启动屏
// 注意：新代码必须用 token；老页面 fontSize 字面量分批替换，本会话不要求一次全覆盖。
export interface EmuTypographyTokens {
  xxs: number
  xs: number
  sm: number
  md: number
  lg: number
  xl: number
  xxl: number
  display: number
}

export const EmuTypography: EmuTypographyTokens = {
  xxs: 8,
  xs: 10,
  sm: 12,
  md: 14,
  lg: 16,
  xl: 18,
  xxl: 22,
  display: 28
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
