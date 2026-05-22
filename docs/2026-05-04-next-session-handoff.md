# 新窗口交接

> 日期：2026-05-04
> 仓库：`D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator`
> 分支：`feat/design-pages-visual-closure`
> 当前 HEAD：`d2f3af6`

## 当前约束

- 默认中文沟通。
- 不编译、不真机、不跑测试脚本；用户自己执行运行验证。
- 代理可做静态检查，且必须明确“未编译 / 未真机”。
- 旧架构 `deprecated/legacy/` 不参与后续检索和编辑，除非用户明确要求。
- 做 UI 页面收口时，先看 `screen.png + code.html + 当前 ETS`，不要凭经验猜页面归属。

## 本轮已完成

- 新增 `截图验证/README.md`：为 2026-05-04 的 11 张运行截图 / 验收截图建立索引。
- 新增 `docs/2026-05-04-arkts-ui-static-scan.md`：记录固定布局扫描命令、当前命中和复查优先级。
- 新增本文件：用于新窗口短交接。
- 追加 2026-05-21 ETS 页面切换性能排障结论：`Canvas` 不是设置页 / 手柄页切入钝感的主因，底部顶级导航使用 `pushUrl` 叠栈才是主因；改为平级 `replaceUrl` 后，切页明显恢复。

## 当前工作区状态提醒

本轮只新增文档，不处理已有脏改动。后续提交前不要使用 `git add .`，需要按文件显式 stage。

已看到的既有修改 / 未跟踪项：

- 已修改：`entry/src/main/ets/pages/ImportTaskOverlayPage.ets`
- 已修改：`entry/src/main/ets/pages/MultiplayerInputPage.ets`
- 未跟踪目录 / 文件包括：`.appanalyzer/`、`.claude/`、`.codex`、`.firecrawl/`、`CLAUDE.md`、`codex*`、`nul`、`stitch_game_emulator_design_plan/`、`截图验证/`

本轮新增文件：

- `截图验证/README.md`
- `docs/2026-05-04-arkts-ui-static-scan.md`
- `docs/2026-05-04-next-session-handoff.md`

## 下一步建议

1. 如果用户继续做验收文档：把 `截图验证/README.md` 与 `docs/2026-04-30-design-page-acceptance-matrix.md` 逐页回写，不要只按截图文件名判断完成度。
2. 如果用户继续做 UI 静态收口：优先复查 `ImportEntryPage.ets` 粒子定位、`RuntimeVirtualControllerLayer.ets` Quick Save rail、`ShaderPreviewPage.ets` 固定宽度。
3. 如果用户要求提交：先 `git status --short`，只 stage 本轮文档和用户确认要提交的 ETS 文件，避免混入未跟踪工具目录。
4. 如果用户继续查“页面切换慢”：先看底部 tab 是否误用 `pushUrl`，再看是否有共享 `blur`、`aboutToAppear()` 同步 native 调用、来源页未在切路由前停掉定时器 / 刷新任务；不要优先怀疑 `Canvas`。

## 2026-05-21 性能排障结论

- 现象：
  - `SettingsPage`、`MultiplayerInputPage`、`InputLayoutPage` 切入和返回时有明显钝感，游戏库页相对正常。
- 已做排除：
  - 临时移除设置页、手柄页、布局编辑页中的 `Canvas` 网格 / 柱状图后，只是“略好”，没有根治，因此 `Canvas` 不是主因。
  - 恢复 `Canvas` 后，在保留路由修正的前提下，页面切换仍然很快，再次证实 `Canvas` 不是主因。
- 已验证有效的策略：
  - 将底部导航的顶级 tab 切换统一改为 `replaceUrl`，不再对平级页面使用 `pushUrl` 叠栈。
  - `LibraryPage` 在切换路由前先 suspend 当前页面活动状态，避免搜索、刷新、长按等状态拖累转场。
  - 调试期曾移除共享 `EmuHeaderBar` / `EmuBottomNav` 的 `backdropBlur` 与部分 `monospace`，它们可能是放大器，但本轮未做最终归因。
  - 调试期曾把 `MultiplayerInputPage.aboutToAppear()` 里的设备枚举摘掉，以排除同步 native 调用干扰；该项属于辅助手段，不是最终根因结论。
- UI 文案结论：
  - 底部导航现已收口为“中文主文案 + 英文装饰副文案”，符合仓库“中文为主、英文作技术副标签”的约定。

## 验证边界

- 已做：截图目录文件核对、固定布局静态扫描、`git diff --check`。
- 未做：`hvigor` 编译、预览器验证、真机验证、测试脚本。
