#!/usr/bin/env bash
# Static property assertions for the 5 UI fixes shipped in this branch.
# Each assertion proves the code-level intent is present; on-device pixel
# verification still requires manual testing.
set -euo pipefail

cd "$(dirname "$0")/../.."

PASS=0
FAIL=0
FAILED_CHECKS=()

check() {
  local description="$1"
  local result="$2"
  if [[ "$result" == "ok" ]]; then
    echo "  [PASS] $description"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $description"
    FAIL=$((FAIL + 1))
    FAILED_CHECKS+=("$description")
  fi
}

assert_grep() {
  local description="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    check "$description" "ok"
  else
    check "$description" "fail"
  fi
}

assert_no_grep() {
  local description="$1"
  local pattern="$2"
  local file="$3"
  if ! grep -qE "$pattern" "$file" 2>/dev/null; then
    check "$description" "ok"
  else
    check "$description" "fail"
  fi
}

echo "=== Fix 1: Game library no longer stuck on '正在读取游戏库' ==="
F=entry/src/main/ets/components/LibraryGameSections.ets
assert_grep "BottomLoader has empty state branch" \
  "games\.length === 0 && this\.recentGames\.length === 0" "$F"
assert_grep "BottomLoader shows 游戏库为空 on empty" \
  "游戏库为空" "$F"
assert_no_grep "No always-on '正在读取游戏库' spinner" \
  "正在读取游戏库" "$F"

echo ""
echo "=== Fix 2: ROM scanner walks subdirectories with hilog ==="
F=entry/src/main/ets/common/RuntimeRomSourceScanner.ets
assert_grep "Subdir list includes gba/nes/snes/etc" \
  "gba.*nes.*snes.*gb_gbc.*md.*nds.*misc.*arcade" "$F"
assert_grep "BundledRomEntry interface declared (no inline obj-literal type)" \
  "^interface BundledRomEntry" "$F"
assert_no_grep "No inline obj-literal type Promise<{...}>" \
  "Promise<\{[^}]+\}\[?\]?" "$F"
assert_grep "Per-subdir hilog emitted" \
  "LogHelper\.info.*RuntimeRomSourceScanner" "$F"

echo ""
echo "=== Fix 3: Button layout editor has real drag (PanGesture) ==="
F=entry/src/main/ets/pages/InputLayoutPage.ets
assert_grep "EditableButton has .gesture(...)" \
  "\.gesture\(" "$F"
assert_grep "PanGesture used" \
  "PanGesture\(" "$F"
assert_grep "captureDragStart method" \
  "private captureDragStart\(" "$F"
assert_grep "applyDragUpdate method" \
  "private applyDragUpdate\(" "$F"
assert_grep "dragStartX/Y state" \
  "dragStartX: number = 0" "$F"
assert_grep "applyDragUpdate clamps to layout bounds" \
  "Math\.max\(0, Math\.min\(horizontalLimit" "$F"
assert_grep "RETRO_BUTTON_OPTIONS Select for key mapping" \
  "RETRO_BUTTON_OPTIONS\[index\]" "$F"

echo ""
echo "=== Fix 4: Slider <-> percentage two-way binding via @Component ==="
F=entry/src/main/ets/pages/SettingsPage.ets
if grep -qzE "@Component\s+struct LinearSettingRow" "$F" 2>/dev/null; then
  check "LinearSettingRow is a @Component" "ok"
else
  check "LinearSettingRow is a @Component" "fail"
fi
assert_grep "LinearSettingRow has @Prop value" \
  "@Prop value: number" "$F"
assert_grep "LinearSettingBlock builder wraps LinearSettingRow" \
  "LinearSettingRow\(\{" "$F"
assert_no_grep "No direct @Prop assignment (this.value = clamped)" \
  "this\.value\s*=\s*clamped" "$F"

F=entry/src/main/ets/pages/ShaderPreviewPage.ets
assert_grep "ShaderSliderRow is a @Component" \
  "struct ShaderSliderRow" "$F"
assert_grep "ShaderSliderRow has @Prop value" \
  "@Prop value: number" "$F"
assert_no_grep "ShaderSliderRow no @Prop write" \
  "this\.value\s*=\s*clamped" "$F"

echo ""
echo "=== Fix 5: Virtual controller function buttons compact (64x28) ==="
F=entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets
if grep -qzE "shape === 'function'.{0,80}return 64" "$F" 2>/dev/null; then
  check "function-shape width branch returns 64" "ok"
else
  check "function-shape width branch returns 64" "fail"
fi
assert_grep "Width 64 present (line-level)" "return 64$" "$F"
assert_grep "Height 28 present (line-level)" "return 28$" "$F"
assert_grep "InputLayoutButton has retroButtonId field used" \
  "button\.retroButtonId" "$F"
assert_grep "getRetroButtonId takes button object" \
  "getRetroButtonId\(button: InputLayoutButton" "$F"

echo ""
echo "=== Fix 6: PlatformChipBar horizontal scroll + selected anchor ==="
F=entry/src/main/ets/components/PlatformChipBar.ets
assert_grep "Scroller for anchoring" \
  "private scroller: Scroller" "$F"
assert_grep "scrollTo on selected change" \
  "scroller\.scrollTo" "$F"
assert_grep "Horizontal scroll direction" \
  "ScrollDirection\.Horizontal" "$F"
assert_grep "Edge fade overlay" \
  "linearGradient" "$F"

echo ""
echo "=== Fix 7: FPS clamp + GameLoop frame pacer ==="
F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "normalizeFpsForDisplay clamps > 240 to 60" \
  "normalizeFpsForDisplay" "$F"
F=entry/src/main/cpp/core/engine/libretro_engine.cpp
assert_grep "GameLoop has sleep_for frame pacing" \
  "std::this_thread::sleep_for" "$F"
assert_grep "thread header included" \
  "#include <thread>" "$F"

echo ""
echo "=== Fix 8: Pause overlay font-size shrink (no more 30/25/22) ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_no_grep "No fontSize(30) for big title" \
  "fontSize\(30\)" "$F"
assert_no_grep "No fontSize(26) for cpu/fps" \
  "fontSize\(26\)" "$F"
assert_grep "Compact main title fontSize(18)" \
  "fontSize\((18|EmuTypography\.xl)\)" "$F"

echo ""
echo "=== Fix 9: EmuTelemetryPanel cells have inline progress bars ==="
F=entry/src/main/ets/components/EmuTelemetryPanel.ets
assert_grep "EmuTelemetryCellItem has progress field" \
  "progress: number" "$F"
assert_grep "EmuTelemetryCellItem has progressColor field" \
  "progressColor: string" "$F"
assert_no_grep "Dead bars prop removed" \
  "@Prop bars:" "$F"

echo ""
echo "=== Fix 10: PauseOverlay action handlers wired ==="
F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "input_mapping routes to InputLayoutPage" \
  "pages/InputLayoutPage" "$F"
assert_grep "visual_filters routes to ShaderPreviewPage" \
  "pages/ShaderPreviewPage" "$F"
assert_no_grep "No CHRONO_TRIGGER hardcoded fallback" \
  "CHRONO_TRIGGER_USA_SNES" "$F"

echo ""
echo "=== Fix 11: D-pad labels Chinese single-char (was clipped 'RI...' / 'DO...') ==="
F=entry/src/main/ets/common/InputLayoutRepository.ets
assert_grep "up label is 上" "id: 'up', label: '上'" "$F"
assert_grep "down label is 下" "id: 'down', label: '下'" "$F"
assert_grep "left label is 左" "id: 'left', label: '左'" "$F"
assert_grep "right label is 右" "id: 'right', label: '右'" "$F"
assert_grep "select label is 选择" "id: 'select', label: '选择'" "$F"
assert_grep "start label is 开始" "id: 'start', label: '开始'" "$F"
assert_grep "localizeButtonLabel migrates old English saves" \
  "localizeButtonLabel\(safeId" "$F"
echo ""
echo "=== Fix 12: Layout split + per-button press feedback + no full-screen shroud ==="
F=entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets
assert_grep "RuntimeKeyButton extracted as @Component" \
  "^@Component$" "$F"
assert_grep "RuntimeKeyButton struct declared" \
  "struct RuntimeKeyButton" "$F"
assert_grep "Per-button @State pressed" \
  "@State private pressed: boolean = false" "$F"
assert_grep "Pressed visual: primary fill" \
  "this\.pressed" "$F"
assert_grep "Pressed visual: scale-down" \
  "scale\(this\.isPressedNow\(\)" "$F"
assert_no_grep "Full-screen scanline shroud removed" \
  "ScanlineBackground" "$F"
assert_no_grep "Gradient veil over game removed" \
  "0xCC000000, 1.0" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage uses Column split layout" \
  "layoutWeight\(this\.gameRunning" "$F"
assert_grep "Game area 65%, controller 35% when running" \
  "layoutWeight\(35\)" "$F"
F=entry/src/main/ets/common/InputLayoutRepository.ets
assert_grep "D-pad 上 size 60 (放大 +12)" \
  "id: 'up', label: '上', caption: 'Directional_Up', x: 80, y: 130, size: 60" "$F"
assert_grep "AB 按钮 size 72 (放大 +10)" \
  "id: 'a', label: 'A', caption: 'Primary', x: 332, y: 170, size: 72" "$F"
assert_grep "选择/开始挪到顶部 L/R 中间下方 (y: 100)" \
  "id: 'select', label: '选择', caption: 'Select', x: 156, y: 100" "$F"

echo ""
echo "=== Fix 14: Design-system tokens for state/motion (即时反应/清晰反馈/一致体验) ==="
F=entry/src/main/ets/common/EmuUiTokens.ets
assert_grep "EmuStateColors token exported" \
  "export const EmuStateColors:" "$F"
assert_grep "danger color is #ff4d4f (规范色)" \
  "dangerDefault: '#ff4d4f'" "$F"
assert_grep "EmuMotion.stateChangeMs = 200" \
  "stateChangeMs: 200" "$F"
assert_grep "EmuMotion.loadingSpinMs = 1200" \
  "loadingSpinMs: 1200" "$F"
assert_grep "EmuColors.error migrated to #ff4d4f" \
  "error: '#ff4d4f'" "$F"

F=entry/src/main/ets/components/EmuLoadingSpinner.ets
assert_grep "EmuLoadingSpinner component exists" \
  "struct EmuLoadingSpinner" "$F"
assert_grep "Spinner uses EmuMotion.loadingSpinMs" \
  "EmuMotion\.loadingSpinMs" "$F"

F=entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets
assert_grep "RuntimeKeyButton uses EaseInOut transition" \
  "Curve\.EaseInOut" "$F"
assert_grep "RuntimeKeyButton supports disabled prop" \
  "@Prop disabled: boolean" "$F"
assert_grep "RuntimeKeyButton uses disabledBackground token" \
  "EmuStateColors\.disabledBackground" "$F"
assert_grep "RuntimeKeyButton disabled overrides pressed (priority)" \
  "this\.isPressedNow\(\) && !this\.disabled" "$F"

F=entry/src/main/ets/components/RuntimeControlPanel.ets
assert_grep "RuntimeControlPanel imports EmuLoadingSpinner" \
  "import \{ EmuLoadingSpinner \}" "$F"
assert_grep "Stop button uses danger token (#ff4d4f)" \
  "EmuStateColors\.dangerDefault" "$F"
assert_grep "CoreCheck/Soak buttons have EaseInOut animation" \
  "Curve\.EaseInOut" "$F"
assert_no_grep "No more #F44336 Material red on Stop" \
  "#F44336" "$F"
assert_no_grep "No more #FF5252 error text" \
  "#FF5252" "$F"

echo ""
echo "=== Fix 13: Game viewport aspect-ratio adaptive ==="
F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "gameAspectRatio @State tracked" \
  "@State private gameAspectRatio: number" "$F"
assert_grep "handleGeometryUpdate writes gameAspectRatio" \
  "this\.gameAspectRatio = ratio" "$F"
assert_grep "XComponent uses aspectRatio not 100% stretch" \
  "\.aspectRatio\(this\.gameAspectRatio" "$F"
assert_grep "XComponent constrained inside Stack with black letterbox" \
  "constraintSize\(\{ maxWidth: '100%', maxHeight: '100%' \}\)" "$F"

echo ""
echo "============================================"
echo "Summary: $PASS passed, $FAIL failed"
echo "============================================"
if [[ $FAIL -gt 0 ]]; then
  echo "FAILED checks:"
  for c in "${FAILED_CHECKS[@]}"; do
    echo "  - $c"
  done
  exit 1
fi
echo "All static property assertions PASS."
exit 0
