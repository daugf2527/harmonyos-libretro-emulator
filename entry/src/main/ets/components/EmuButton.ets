import {
  EmuColors,
  EmuMotion,
  EmuRadius,
  EmuSpacing,
  EmuStateColors,
  EmuTypography
} from '../common/EmuUiTokens'

// 设计三原则：即时反应（按下 scale+背景立刻变化）、清晰反馈（kind/状态视觉互不混淆）、
// 一致体验（所有按钮共享相同 token + 200ms EaseInOut 动效）。
// 状态优先级：disabled > loading > pressed > kind 配色。
export enum EmuButtonKind {
  PRIMARY = 'primary',
  SECONDARY = 'secondary',
  DANGER = 'danger',
  WARNING = 'warning',
  SUCCESS = 'success',
  GHOST = 'ghost'
}

export enum EmuButtonSize {
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  // COMPACT: height=36, fontSize=xs(10)。专为 ImportTaskOverlayPage / 半透明 overlay 场景，
  // 比 SM 高 4px 比 MD 低 4px，避免覆盖层视觉过重。
  COMPACT = 'compact'
}

export enum EmuButtonShape {
  ROUNDED = 'rounded',
  PILL = 'pill'
}

@Component
export struct EmuButton {
  @Prop label: string = ''
  // 用 string 而非联合 literal，避免 ArkTS @Prop 对窄类型的限制。
  @Prop kind: string = EmuButtonKind.PRIMARY
  @Prop buttonSize: string = EmuButtonSize.MD
  @Prop disabled: boolean = false
  @Prop loading: boolean = false
  @Prop icon: string = ''
  // tinted=true：背景用 alpha 半透明、字色用 accent 强色、自带 0.5px border。用于"次级强调"按钮。
  @Prop tinted: boolean = false
  // shape=PILL：胶囊圆角（borderRadius=pill）；ROUNDED：标准矩形圆角（EmuRadius.md）。
  @Prop shape: string = EmuButtonShape.ROUNDED
  // accent='primary'：覆盖 kind 默认 fontColor 强制用 primary 强调色（项目 CRT 绿）。
  // 适合 SettingsPage 这类需要"项目特色绿字"的次级按钮，避免为单一视觉建新 kind。
  @Prop accent: string = 'default'
  @State private pressed: boolean = false
  onTap?: () => void

  // 取当前 kind 的"强色"基色：tinted 模式下的 bg/border/text 都派生自它。
  private resolveAccent(): string {
    if (this.kind === EmuButtonKind.PRIMARY) {
      return EmuColors.primary
    }
    if (this.kind === EmuButtonKind.DANGER) {
      return EmuStateColors.dangerDefault
    }
    if (this.kind === EmuButtonKind.WARNING) {
      return EmuStateColors.warning
    }
    if (this.kind === EmuButtonKind.SUCCESS) {
      return EmuStateColors.success
    }
    if (this.kind === EmuButtonKind.GHOST) {
      return EmuColors.outline
    }
    // SECONDARY tinted 用 onSurface（亮灰 #E5E5E5）而非 onSurfaceVariant，
    // 视觉更接近 ImportTaskOverlayPage 原"白色 alpha"按钮，强调对比度。
    return EmuColors.onSurface
  }

  // 把 #RRGGBB 包装成 #AARRGGBB；alpha=1A 约 10%，33 约 20%，4D 约 30%。
  private withAlpha(base: string, alphaHex: string): string {
    return '#' + alphaHex + base.substring(1)
  }

  private resolveBackground(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBackground
    }
    if (this.tinted) {
      return this.withAlpha(this.resolveAccent(), this.pressed ? '33' : '1A')
    }
    if (this.kind === EmuButtonKind.PRIMARY) {
      return this.pressed ? EmuColors.primaryDim : EmuColors.primary
    }
    if (this.kind === EmuButtonKind.DANGER) {
      return this.pressed ? EmuStateColors.dangerActive : EmuStateColors.dangerDefault
    }
    if (this.kind === EmuButtonKind.WARNING) {
      // warning/success 暂无 hover/active token，pressed 视觉反馈依赖 scale + animation
      return EmuStateColors.warning
    }
    if (this.kind === EmuButtonKind.SUCCESS) {
      return EmuStateColors.success
    }
    if (this.kind === EmuButtonKind.GHOST) {
      return this.pressed ? EmuColors.surfaceContainerLow : '#00000000'
    }
    return this.pressed ? EmuColors.surfaceContainerHigh : EmuColors.surfaceContainer
  }

  private resolveFontColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledText
    }
    if (this.tinted) {
      return this.resolveAccent()
    }
    if (this.accent === 'primary') {
      return EmuColors.primary
    }
    if (this.kind === EmuButtonKind.PRIMARY) {
      return EmuStateColors.onPrimary
    }
    if (this.kind === EmuButtonKind.DANGER) {
      return EmuStateColors.onDanger
    }
    if (this.kind === EmuButtonKind.WARNING || this.kind === EmuButtonKind.SUCCESS) {
      // 亮色背景上用黑字，对比清晰（复用 onPrimary token = #000000）
      return EmuStateColors.onPrimary
    }
    if (this.kind === EmuButtonKind.GHOST) {
      // GHOST 通常承载"取消/忽略"等次级动作，用 onSurfaceVariant 比 onSurface 更"低调"。
      return EmuColors.onSurfaceVariant
    }
    return EmuColors.onSurface
  }

  private resolveBorderWidth(): number {
    if (this.kind === EmuButtonKind.GHOST) {
      return 1
    }
    if (this.tinted) {
      return 0.5
    }
    return 0
  }

  private resolveBorderColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBorder
    }
    if (this.tinted) {
      return this.withAlpha(this.resolveAccent(), '4D')
    }
    if (this.kind === EmuButtonKind.GHOST) {
      return this.pressed ? EmuColors.primary : EmuColors.outline
    }
    return '#00000000'
  }

  private resolveFontSize(): number {
    if (this.buttonSize === EmuButtonSize.SM) {
      return EmuTypography.sm
    }
    if (this.buttonSize === EmuButtonSize.LG) {
      return EmuTypography.lg
    }
    if (this.buttonSize === EmuButtonSize.COMPACT) {
      return EmuTypography.xs
    }
    return EmuTypography.md
  }

  private resolveHeight(): number {
    if (this.buttonSize === EmuButtonSize.SM) {
      return 32
    }
    if (this.buttonSize === EmuButtonSize.LG) {
      return 48
    }
    if (this.buttonSize === EmuButtonSize.COMPACT) {
      return 36
    }
    return 40
  }

  private resolveHorizontalPadding(): number {
    if (this.buttonSize === EmuButtonSize.SM) {
      return EmuSpacing.sm
    }
    if (this.buttonSize === EmuButtonSize.LG) {
      return EmuSpacing.lg
    }
    if (this.buttonSize === EmuButtonSize.COMPACT) {
      return EmuSpacing.sm
    }
    return EmuSpacing.md
  }

  private resolveBorderRadius(): number {
    if (this.shape === EmuButtonShape.PILL) {
      return EmuRadius.pill
    }
    return EmuRadius.md
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: EmuSpacing.xs }) {
        if (this.loading) {
          LoadingProgress()
            .width(this.resolveFontSize())
            .height(this.resolveFontSize())
            .color(this.resolveFontColor())
        } else if (this.icon !== '') {
          Image(this.icon)
            .width(this.resolveFontSize())
            .height(this.resolveFontSize())
            .fillColor(this.resolveFontColor())
        }
        if (this.label !== '') {
          Text(this.label)
            .fontSize(this.resolveFontSize())
            .fontColor(this.resolveFontColor())
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .height(this.resolveHeight())
    .padding({
      left: this.resolveHorizontalPadding(),
      right: this.resolveHorizontalPadding(),
      top: EmuSpacing.xxs,
      bottom: EmuSpacing.xxs
    })
    .backgroundColor(this.resolveBackground())
    .borderRadius(this.resolveBorderRadius())
    .border({
      width: this.resolveBorderWidth(),
      color: this.resolveBorderColor(),
      style: BorderStyle.Solid
    })
    .opacity(this.disabled ? 0.5 : 1)
    .scale(this.pressed && !this.disabled && !this.loading
      ? { x: 0.97, y: 0.97 }
      : { x: 1, y: 1 })
    .animation({
      duration: EmuMotion.stateChangeMs,
      curve: Curve.EaseInOut
    })
    .enabled(!this.disabled && !this.loading)
    .onTouch((event: TouchEvent) => {
      if (this.disabled || this.loading) {
        return
      }
      if (event.type === TouchType.Down) {
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
    .onClick(() => {
      if (this.disabled || this.loading) {
        return
      }
      this.onTap?.()
    })
  }
}
