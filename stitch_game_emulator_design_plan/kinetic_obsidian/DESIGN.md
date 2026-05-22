```markdown
# Design System Strategy: The Precision Instrument

## 1. Overview & Creative North Star
The Creative North Star for this system is **"The Technical Monolith."** 

Moving away from the cluttered, neon-soaked aesthetics of traditional "gaming" interfaces, this design system treats the game emulator as a high-performance scientific instrument—think Leica camera internals or SpaceX telemetry displays. It is a system of extreme restraint, where every pixel must justify its existence. 

We break the "template" look through **Rigid Information Density**. Rather than using oversized cards and friendly white space, we utilize a compact, editorial-style grid. We use intentional asymmetry—aligning data-heavy modules to a strict left-axis while allowing "Status Indicators" to float as rhythmic punctuation. The visual interest comes not from decoration, but from the surgical precision of the layout.

## 2. Colors & Surface Logic
The palette is rooted in absolute darkness to ensure the screen hardware disappears, leaving only the data visible.

*   **Primary Background:** `surface-container-lowest` (#000000). 
*   **The "No-Line" Rule:** Standard 1px solid borders are strictly prohibited for sectioning large areas of the UI. Instead, define boundaries through a shift from `surface` (#0e0e0e) to `surface-container-low` (#131313).
*   **Surface Hierarchy & Nesting:** Use a "Recessive Stacking" model. An outer container uses `surface-container`, while an inner data-well drops down to `surface-container-lowest` to create a sense of looking *into* the machine.
*   **The "Vanta" Accent:** The `primary` green (#00FF41/token `#00e639`) is a high-performance laser. It is never used for large surfaces. It is reserved for 2px x 2px status dots, active toggle pips, and "Live" execution strings.
*   **The "Glass" Rule:** For floating overlays (modals or context menus), use `surface-container-high` at 85% opacity with a `20px` backdrop blur. This ensures the underlying "instrument" is still visible, maintaining the user's mental map of the system.

## 3. Typography: Weight as Architecture
In a monochromatic environment, font weight is your only structural tool. We use **Inter** for its technical, neutral geometric DNA.

*   **Display & Headlines:** Use `display-sm` or `headline-sm` in `Medium` (500) weight. Never use Bold; it feels too aggressive. The hierarchy is established by the contrast between `on-surface` (white) and `on-surface-variant` (gray).
*   **Data Strings:** ROM titles, FPS counters, and memory addresses should use `label-md` with `SemiBold` (600) weight to mimic the etched look of physical hardware labeling.
*   **Functional Body:** `body-md` in `Regular` (400) weight handles all descriptive text. Ensure a tight line-height (1.2–1.3) to maintain the "compact tool" feel.

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are banned. They create a "softness" that contradicts the precision requirement.

*   **The Layering Principle:** Depth is achieved by "carving" into the UI. Use `surface-container-highest` for elements that need to feel "closer" to the glass, and `surface-dim` for background processes.
*   **Ambient Shadows:** If an element must float (e.g., a critical alert), use an ultra-diffused shadow: `Y: 8px, Blur: 32px, Color: rgba(0,0,0,0.4)`. It should feel like a soft occlusion, not a shadow.
*   **The "Ghost Border" Fallback:** For interactive inputs, use a 0.5px `outline-variant` (#484848) at 40% opacity. This creates a "micro-etched" look that defines the tap target without adding visual weight.

## 5. Components: The Toolset

### Buttons (Tactile Triggers)
*   **Primary:** A 1px `outline` border (#757575) with `on-surface` text. No fill. On press, the background shifts to `surface-container-highest`.
*   **Active State:** When a toggle is "On," a single 4px circle of `primary` green appears next to the label.

### Lists & Library
*   **The Divider Rule:** Forbid the use of horizontal divider lines. Separate game titles using `spacing-4` (0.9rem) of vertical white space. Use a `surface-container-low` background on hover/focus to define the row.

### Inputs & Sliders
*   **Precision Sliders:** The track is a 1px line of `outline-variant`. The "thumb" is a 2px x 12px vertical bar of `on-surface` (white). No round "pills"—only sharp rectangles with `rounded-sm`.

### Performance Chips
*   **Status Indicators:** Small, rectangular chips using `surface-container-high`. Text is `label-sm` in `on-surface-variant`. If a status is critical (e.g., "Overheating"), the text color switches to `error`, but the background remains dark.

### Extra: The "Telemetry Module"
A unique component for this system: A small, high-density grid showing CPU/GPU load. Use `primary` green for the data points and `secondary` gray for the grid lines. 

## 6. Do's and Don'ts

### Do:
*   **Align to the Pixel:** Ensure all 0.5px borders are snapped to the sub-pixel grid to maintain the "Sharp" (犀利) feel.
*   **Use Mono-spacing:** For numerical data (FPS, Clock speed), use a mono-spaced variant of Inter or SF Pro to prevent layout jitter.
*   **Embrace the Dark:** Allow large areas of `#000000` to exist. It provides the "void" that makes the precision elements pop.

### Don't:
*   **No Glows/Blooms:** Never use `box-shadow` to create a "neon" effect with the green accent. The green must be matte and clinical.
*   **No Pill Shapes:** Avoid `rounded-full` for buttons. Stick to `rounded-md` (0.375rem) to maintain the architectural integrity of the "Instrument."
*   **No Motion Blurs:** All transitions should be fast (150ms–200ms) and linear or "Productive Lean-in" (ease-out). Avoid "bouncy" or "organic" animations.

---
*Note: This design system is optimized for the high-PPI displays of iOS 26 and HarmonyOS. Always test the 0.5px "Ghost Borders" on physical hardware to ensure visibility.*```