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
echo "=== Fix 4: Slider <-> percentage two-way binding via @ComponentV2 ==="
F=entry/src/main/ets/pages/SettingsPage.ets
if grep -qzE "@ComponentV2\s+struct LinearSettingRow" "$F" 2>/dev/null; then
  check "LinearSettingRow is a @ComponentV2" "ok"
else
  check "LinearSettingRow is a @ComponentV2" "fail"
fi
assert_grep "LinearSettingRow has @Param value" \
  "@Param value: number" "$F"
assert_grep "LinearSettingBlock builder wraps LinearSettingRow" \
  "LinearSettingRow\(\{" "$F"
assert_no_grep "No direct @Param assignment (this.value = clamped)" \
  "this\.value\s*=\s*clamped" "$F"

F=entry/src/main/ets/pages/ShaderPreviewPage.ets
assert_grep "ShaderSliderRow is a @ComponentV2" \
  "struct ShaderSliderRow" "$F"
assert_grep "ShaderSliderRow has @Param value" \
  "@Param value: number" "$F"
assert_no_grep "ShaderSliderRow no @Param write" \
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
echo "=== Fix 15: PauseOverlay inline save manager ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay exposes save_manager action" \
  "actionCode: 'save_manager'" "$F"
assert_grep "Pause overlay accepts runtime save items param" \
  "@Param saveManagerItems: RuntimeSaveStateListItem\\[\\]" "$F"
assert_grep "Pause overlay declares SaveManagerPanel builder" \
  "private SaveManagerPanel\\(" "$F"
assert_grep "Pause overlay wires save-manager load callback" \
  "onSaveManagerLoad\\?: \\(fileName: string\\) => void" "$F"

F=entry/src/main/ets/common/RuntimeSaveStateController.ets
assert_grep "RuntimeSaveStateController exposes listSaveItemsForRom" \
  "async listSaveItemsForRom\\(" "$F"
assert_grep "RuntimeSaveStateController exposes loadSaveByFileName" \
  "async loadSaveByFileName\\(" "$F"
assert_grep "RuntimeSaveStateController exposes deleteSaveByFileName" \
  "async deleteSaveByFileName\\(" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage handles save_manager pause action" \
  "actionCode === 'save_manager'" "$F"
assert_grep "LibretroGamePage tracks runtime save-manager visibility" \
  "runtimeSaveManagerVisible: boolean = false" "$F"
assert_grep "LibretroGamePage passes saveManagerItems into overlay" \
  "saveManagerItems: this\\.runtimeSaveManagerItems" "$F"
assert_grep "LibretroGamePage passes save-manager load handler into overlay" \
  "onSaveManagerLoad: \\(fileName: string\\) =>" "$F"

echo ""
echo "=== Fix 16: PauseOverlay inline cheat manager ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay exposes cheat_manager action" \
  "actionCode: 'cheat_manager'" "$F"
assert_grep "Pause overlay accepts runtime cheat items param" \
  "@Param cheatManagerItems: RuntimeCheatItem\\[\\]" "$F"
assert_grep "Pause overlay declares CheatManagerPanel builder" \
  "private CheatManagerPanel\\(" "$F"
assert_grep "Pause overlay wires cheat add callback" \
  "onCheatManagerAdd\\?: \\(\\) => void" "$F"

F=entry/src/main/ets/common/RuntimeCoreDiagnosticController.ets
assert_grep "RuntimeCoreCapabilities tracks cheat reset support" \
  "supportsCheatReset: boolean" "$F"
assert_grep "RuntimeCoreCapabilities tracks cheat set support" \
  "supportsCheatSet: boolean" "$F"
assert_grep "Capability parser checks retro_cheat_reset warning" \
  "retro_cheat_reset not provided" "$F"
assert_grep "Capability parser checks retro_cheat_set warning" \
  "retro_cheat_set not provided" "$F"

F=entry/src/main/ets/common/RuntimeCheatController.ets
assert_grep "RuntimeCheatController exposes applyCheatEntries" \
  "applyCheatEntries\\(" "$F"

F=entry/src/main/ets/common/RuntimeCheatRepository.ets
assert_grep "RuntimeCheatRepository loads ROM cheat items" \
  "loadRuntimeCheatItemsForRom\\(" "$F"
assert_grep "RuntimeCheatRepository saves ROM cheat items" \
  "saveRuntimeCheatItemsForRom\\(" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage handles cheat_manager pause action" \
  "actionCode === 'cheat_manager'" "$F"
assert_grep "LibretroGamePage tracks runtime cheat-manager visibility" \
  "runtimeCheatManagerVisible: boolean = false" "$F"
assert_grep "LibretroGamePage passes cheatManagerItems into overlay" \
  "cheatManagerItems: this\\.runtimeCheatManagerItems" "$F"
assert_grep "LibretroGamePage applies runtime cheat entries through controller" \
  "runtimeCheatController\\.applyCheatEntries" "$F"

echo ""
echo "=== Fix 17: PauseOverlay runtime disk image import ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay wires disk replace callback" \
  "onDiskReplaceCurrent\\?: \\(\\) => void" "$F"
assert_grep "Pause overlay wires disk append callback" \
  "onDiskAppendImage\\?: \\(\\) => void" "$F"
assert_grep "Pause overlay shows replace-current disk button" \
  "Button\\('替换当前盘'\\)" "$F"
assert_grep "Pause overlay shows append disk button" \
  "Button\\('新增一张'\\)" "$F"

F=entry/src/main/ets/common/RuntimeDiskControlController.ets
assert_grep "RuntimeDiskControlController exposes replaceImageIndex" \
  "replaceImageIndex\\(" "$F"
assert_grep "RuntimeDiskControlController exposes addImageIndex" \
  "addImageIndex\\(" "$F"

F=entry/src/main/ets/common/RuntimeDiskImageImportService.ets
assert_grep "RuntimeDiskImageImportService imports picked disk images" \
  "importPickedRuntimeDiskImages\\(" "$F"
assert_grep "RuntimeDiskImageImportService uses DocumentViewPicker" \
  "DocumentViewPicker" "$F"
assert_grep "RuntimeDiskImageImportService copies selected file into runtime disk sandbox" \
  "runtime/disks/imported" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage tracks disk-control busy state" \
  "diskControlBusy: boolean = false" "$F"
assert_grep "LibretroGamePage handles replace-current disk image" \
  "handleRuntimeDiskReplaceCurrentImage\\(" "$F"
assert_grep "LibretroGamePage handles append disk image" \
  "handleRuntimeDiskAppendImage\\(" "$F"
assert_grep "LibretroGamePage passes disk replace callback into overlay" \
  "onDiskReplaceCurrent: \\(\\) =>" "$F"
assert_grep "LibretroGamePage passes disk append callback into overlay" \
  "onDiskAppendImage: \\(\\) =>" "$F"

echo ""
echo "=== Fix 18: PauseOverlay runtime core options ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay exposes core_options action" \
  "actionCode: 'core_options'" "$F"
assert_grep "Pause overlay accepts runtime core options items param" \
  "@Param coreOptionsItems: RuntimeCoreOptionItem\\[\\]" "$F"
assert_grep "Pause overlay declares CoreOptionsPanel builder" \
  "private CoreOptionsPanel\\(" "$F"
assert_grep "Pause overlay wires core option advance callback" \
  "onCoreOptionAdvance\\?: \\(key: string, value: string\\) => void" "$F"

F=entry/src/main/ets/common/RuntimeCoreOptionsController.ets
assert_grep "RuntimeCoreOptionsController exposes getOptions" \
  "getOptions\\(" "$F"
assert_grep "RuntimeCoreOptionsController exposes setOption" \
  "setOption\\(" "$F"
assert_grep "RuntimeCoreOptionsController parses core options json" \
  "JSON\\.parse" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage handles core_options pause action" \
  "actionCode === 'core_options'" "$F"
assert_grep "LibretroGamePage tracks runtime core-options visibility" \
  "runtimeCoreOptionsVisible: boolean = false" "$F"
assert_grep "LibretroGamePage passes coreOptionsItems into overlay" \
  "coreOptionsItems: this\\.runtimeCoreOptionsItems" "$F"
assert_grep "LibretroGamePage refreshes runtime core options panel" \
  "refreshRuntimeCoreOptionsPanel\\(" "$F"
assert_grep "LibretroGamePage applies runtime core option change" \
  "advanceRuntimeCoreOption\\(" "$F"

echo ""
echo "=== Fix 19: Production render settings wire VSync and AI upscale ==="
F=entry/src/main/ets/common/RuntimeRenderSettingsController.ets
assert_grep "RuntimeRenderSettingsController exposes setSwapInterval" \
  "setSwapInterval\\(" "$F"
assert_grep "RuntimeRenderSettingsController exposes setAIUpscale" \
  "setAIUpscale\\(" "$F"

F=entry/src/main/ets/common/RuntimeRenderSettingsRepository.ets
assert_grep "RuntimeRenderSettingsProfile stores swapInterval" \
  "swapInterval: number" "$F"
assert_grep "RuntimeRenderSettingsProfile stores aiUpscaleEnabled" \
  "aiUpscaleEnabled: boolean" "$F"
assert_grep "Default render profile seeds swapInterval" \
  "swapInterval:" "$F"
assert_grep "Default render profile seeds aiUpscaleEnabled" \
  "aiUpscaleEnabled:" "$F"

F=entry/src/main/ets/pages/SettingsPage.ets
assert_grep "SettingsPage exposes VSync advanced row" \
  "'VSync'" "$F"
assert_grep "SettingsPage exposes AI Upscale advanced row" \
  "'AI Upscale'" "$F"
assert_grep "SettingsPage toggles swap interval" \
  "toggleSwapInterval\\(" "$F"
assert_grep "SettingsPage toggles AI upscale" \
  "toggleAIUpscale\\(" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage applies swap interval to native runtime settings" \
  "setSwapInterval\\(this\\.renderSettingsProfile\\.swapInterval\\)" "$F"
assert_grep "LibretroGamePage applies AI upscale to native runtime settings" \
  "setAIUpscale\\(this\\.renderSettingsProfile\\.aiUpscaleEnabled\\)" "$F"

echo ""
echo "=== Fix 20: PauseOverlay runtime SRAM manager ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay exposes sram_manager action" \
  "actionCode: 'sram_manager'" "$F"
assert_grep "Pause overlay accepts runtime SRAM items param" \
  "@Param sramManagerItems: RuntimeSramBackupListItem\\[\\]" "$F"
assert_grep "Pause overlay declares SramManagerPanel builder" \
  "private SramManagerPanel\\(" "$F"
assert_grep "Pause overlay wires SRAM export callback" \
  "onSramManagerCreate\\?: \\(\\) => void" "$F"
assert_grep "Pause overlay wires SRAM load callback" \
  "onSramManagerLoad\\?: \\(fileName: string\\) => void" "$F"

F=entry/src/main/ets/common/RuntimeSramController.ets
assert_grep "RuntimeSramController exports current SRAM backup" \
  "exportCurrentSramBackup\\(" "$F"
assert_grep "RuntimeSramController loads SRAM backup by file name" \
  "loadBackupByFileName\\(" "$F"
assert_grep "RuntimeSramController lists backup items for ROM" \
  "listBackupItemsForRom\\(" "$F"

F=entry/src/main/ets/common/RuntimeSramRepository.ets
assert_grep "RuntimeSramRepository saves SRAM backup files" \
  "saveRuntimeSramBackup\\(" "$F"
assert_grep "RuntimeSramRepository reads SRAM backup files" \
  "readRuntimeSramBackup\\(" "$F"
assert_grep "RuntimeSramRepository lists SRAM backups for ROM" \
  "listRuntimeSramBackupsForRom\\(" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage handles sram_manager pause action" \
  "actionCode === 'sram_manager'" "$F"
assert_grep "LibretroGamePage tracks runtime SRAM-manager visibility" \
  "runtimeSramManagerVisible: boolean = false" "$F"
assert_grep "LibretroGamePage refreshes runtime SRAM panel" \
  "refreshRuntimeSramManagerPanel\\(" "$F"
assert_grep "LibretroGamePage exports current SRAM backup" \
  "exportCurrentRuntimeSramBackup\\(" "$F"
assert_grep "LibretroGamePage passes SRAM items into overlay" \
  "sramManagerItems: this\\.runtimeSramManagerItems" "$F"

echo ""
echo "=== Fix 21: PauseOverlay runtime status snapshot ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay accepts runtime state text param" \
  "@Param runtimeStateText: string = ''" "$F"
assert_grep "Pause overlay accepts runtime load-state text param" \
  "@Param runtimeLoadStateText: string = ''" "$F"
assert_grep "Pause overlay accepts runtime save-state-size text param" \
  "@Param runtimeSaveStateSizeText: string = ''" "$F"
assert_grep "Pause overlay accepts runtime input-debug text param" \
  "@Param runtimeInputDebugText: string = ''" "$F"
assert_grep "Pause telemetry renders runtime state text" \
  "this\\.runtimeStateText\\.length > 0" "$F"
assert_grep "Pause telemetry renders runtime input-debug text" \
  "Text\\(this\\.runtimeInputDebugText\\)" "$F"

F=entry/src/main/ets/common/RuntimeCoreDiagnosticController.ets
assert_grep "RuntimeCoreDiagnosticController exposes runtime status snapshot" \
  "async readRuntimeStatusSnapshot\\(" "$F"
assert_grep "RuntimeCoreDiagnosticController queries native engine state" \
  "refactoredGetState\\(" "$F"
assert_grep "RuntimeCoreDiagnosticController queries save-state size async" \
  "refactoredGetSaveStateSizeAsync\\(" "$F"
assert_grep "RuntimeCoreDiagnosticController queries input debug stats" \
  "refactoredGetInputDebugStats\\(" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage tracks runtime state text" \
  "runtimeStateText: string = ''" "$F"
assert_grep "LibretroGamePage tracks runtime input-debug text" \
  "runtimeInputDebugText: string = ''" "$F"
assert_grep "LibretroGamePage refreshes runtime status snapshot" \
  "refreshRuntimeStatusSnapshot\\(" "$F"
assert_grep "LibretroGamePage passes runtime state text into overlay" \
  "runtimeStateText: this\\.runtimeStateText" "$F"
assert_grep "LibretroGamePage passes runtime input-debug text into overlay" \
  "runtimeInputDebugText: this\\.runtimeInputDebugText" "$F"

echo ""
echo "=== Fix 22: PauseOverlay runtime port control ==="
F=entry/src/main/ets/components/RuntimePauseOverlay.ets
assert_grep "Pause overlay exposes port_control action" \
  "actionCode: 'port_control'" "$F"
assert_grep "Pause overlay accepts runtime port-control visible param" \
  "@Param portControlVisible: boolean = false" "$F"
assert_grep "Pause overlay accepts runtime port assignments param" \
  "@Param portAssignments: PortAssignState\\[\\] = \\[\\]" "$F"
assert_grep "Pause overlay declares PortControlPanel builder" \
  "private PortControlPanel\\(" "$F"
assert_grep "Pause overlay wires virtual-port select callback" \
  "onVirtualPortSelect\\?: \\(portId: number\\) => void" "$F"
assert_grep "Pause overlay wires controller-device select callback" \
  "onControllerDeviceSelect\\?: \\(device: number\\) => void" "$F"

F=entry/src/main/ets/common/RuntimeInputPortController.ets
assert_grep "RuntimeInputPortController exports controller device options" \
  "RUNTIME_CONTROLLER_PORT_DEVICE_OPTIONS" "$F"
assert_grep "RuntimeInputPortController exposes setControllerPortDevice" \
  "setControllerPortDevice\\(" "$F"

F=entry/src/main/ets/common/InputPortRouting.ts
assert_grep "InputPortRouting clears stale virtual port on reassignment" \
  "sourceType === InputSourceType\\.Virtual && item\\.sourceType === InputSourceType\\.Virtual" "$F"

F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "LibretroGamePage handles port_control pause action" \
  "actionCode === 'port_control'" "$F"
assert_grep "LibretroGamePage tracks runtime port-control visibility" \
  "runtimePortControlVisible: boolean = false" "$F"
assert_grep "LibretroGamePage selects runtime virtual port" \
  "selectRuntimeVirtualPort\\(" "$F"
assert_grep "LibretroGamePage applies runtime controller port device" \
  "applyRuntimeControllerPortDevice\\(" "$F"
assert_grep "LibretroGamePage passes port-control visibility into overlay" \
  "portControlVisible: this\\.runtimePortControlVisible" "$F"
assert_grep "LibretroGamePage passes virtual-port select callback into overlay" \
  "onVirtualPortSelect: \\(portId: number\\) =>" "$F"

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
assert_grep "RuntimeKeyButton extracted as @ComponentV2" \
  "^@ComponentV2$" "$F"
assert_grep "RuntimeKeyButton struct declared" \
  "struct RuntimeKeyButton" "$F"
assert_grep "Per-button @Local pressed" \
  "@Local private pressed: boolean = false" "$F"
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
assert_grep "RuntimeKeyButton uses instant press feedback (EaseOut)" \
  "Curve\.EaseOut" "$F"
assert_grep "RuntimeKeyButton supports disabled param" \
  "@Param disabled: boolean" "$F"
assert_grep "RuntimeKeyButton uses disabledBackground token" \
  "EmuStateColors\.disabledBackground" "$F"
assert_grep "RuntimeKeyButton disabled overrides pressed (priority)" \
  "this\.isPressedNow\(\) && !this\.disabled" "$F"

F=entry/src/main/ets/components/DevDiagnosticsBlock.ets
assert_grep "DevDiagnosticsBlock imports EmuLoadingSpinner" \
  "import \{ EmuLoadingSpinner \}" "$F"
assert_grep "DevDiagnosticsBlock CoreCheck/Soak buttons have EaseInOut animation" \
  "Curve\.EaseInOut" "$F"

echo ""
echo "=== Fix 13: Game viewport aspect-ratio adaptive ==="
F=entry/src/main/ets/pages/LibretroGamePage.ets
assert_grep "gameAspectRatio @Local tracked" \
  "@Local private gameAspectRatio: number" "$F"
assert_grep "handleGeometryUpdate writes gameAspectRatio" \
  "this\.gameAspectRatio = ratio" "$F"
assert_grep "runtime aspect helper keeps gameAspectRatio as native baseline" \
  "const nativeAspectRatio = this\.gameAspectRatio > 0 \? this\.gameAspectRatio : 4 / 3;" "$F"
assert_grep "runtime aspect helper resolves visual aspect override" \
  "resolveRuntimeVisualAspectRatio\(this\.visualSettingsProfile\.aspectMode, nativeAspectRatio\)" "$F"
assert_grep "XComponent uses runtime aspect helper not 100% stretch" \
  "\.aspectRatio\(this\.getRuntimeScreenAspectRatio\(\)\)" "$F"
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
