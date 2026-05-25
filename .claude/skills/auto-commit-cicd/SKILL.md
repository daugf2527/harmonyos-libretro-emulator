---
name: auto-commit-cicd
description: 自动化代码提交 → 推送 → 创建 PR → CI 监控 → 合并 main 的完整工作流。如果 CI 失败，自动分析错误并修复，最多重试 3 次。
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
model: sonnet
metadata:
  short-description: 自动化 Git 提交、推送、创建 PR、CI 监控与合并工作流
---

# auto-commit-cicd

## TRIGGER
当用户说以下任一内容时调用本 skill：
- "提交代码" / "提交并推送" / "commit and push"
- "自动提交" / "auto commit" / "auto-commit"
- "提交到 master" / "合并到 master" / "merge to master"
- "运行 CI" / "run CI" / "触发 CI"
- "/auto-commit-cicd" (slash command)

## 工作流

### Step 1: 检查工作区

```
cd "D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator"
git status --short
```

- 如果有未提交改动 → 继续 Step 2
- 如果工作区干净 → 提示用户"没有需要提交的改动"，退出

### Step 2: 本地预检

在提交前运行本地 CI 脚本，确保代码符合项目规范：

```bash
cd "D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator"
bash scripts/ci/check_repo_hygiene.sh
bash scripts/ci/check_regression_guards.sh
```

- 如果任一脚本失败 → 根据错误信息修复代码，修复后重新运行预检
- 两次预检均通过 → 继续 Step 3

**常见预检错误修复指引：**
- `merge conflict markers` (冲突标记 `<<<<<<<`, `=======`, `>>>>>>>`) → 检查并移除残留的合并冲突标记
- `build cache directories` (构建缓存目录) → 检查 `.gitignore` 中是否已排除
- `NativeBuffer` 使用违规 → 确保使用 `FromNativeWindowBuffer + Map/Unmap`，不要用 `mmap`/`munmap`
- `LOG_DOMAIN` 缺失 → 在源文件中添加 `#define LOG_DOMAIN`
- `TODO/FIXME` 残留 → 替换为实现代码或移除

### Step 3: 提交改动

1. 确认当前分支名：
```bash
git branch --show-current
```

2. `git add` 相关文件（排除 secrets、.env、二进制文件）：
```bash
# 查看所有改动文件
git diff --name-only
git ls-files --others --exclude-standard
# 逐个 add，排除 .env、credentials、*.p12、*.keystore 等敏感文件
```

3. 生成符合项目规范的 commit message：
   - 格式：`type(scope): 中文描述`
   - type: feat / fix / refactor / perf / ci / docs / chore
   - 参考 `git log --oneline -5` 查看最近的提交风格
   - 示例：`fix(perf): 提取 setInterval 动画组件避免全量 build() 重渲染`

4. 创建提交：
```bash
git commit -m "$(cat <<'EOF'
type(scope): 简要描述改动内容

更详细的说明（如有需要）。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Step 4: 推送并创建 PR

1. 推送当前分支到远端：
```bash
git push origin <current-branch>
```
如果分支尚未推送（no upstream），使用：
```bash
git push -u origin <current-branch>
```

2. 创建 PR（合并到 master）：
```bash
gh pr create \
  --base master \
  --head <current-branch> \
  --title "<简洁的 PR 标题（≤70 字符）>" \
  --body "$(cat <<'EOF'
## Summary
- <改动点 1>
- <改动点 2>

## Test Plan
- [ ] CI 通过（harmonyos-pr-ci.yml）
- [ ] 本地仓库卫生检查和回归守卫检查通过

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

3. 记录 PR URL（后续步骤会用到）：
```bash
gh pr view --json url,number,state
```

### Step 5: 监控 CI

PR 创建后会自动触发 `harmonyos-pr-ci.yml`。监控 CI 状态：

```bash
# 查看 PR 的 CI checks 状态
gh pr checks
```

轮询策略：
- 每 60-90 秒检查一次 CI 状态（不超过 5 分钟的 prompt cache TTL）
- 如果所有 checks 状态为 `pass` → Step 6
- 如果任一 check 状态为 `fail` → Step 7（修复循环）
- 如果状态为 `pending` / `in_progress` → 继续等待

最大等待时间：30 分钟（`harmonyos-pr-ci.yml` 的 timeout 为 120 分钟，但通常 15-25 分钟完成）。

### Step 6: 合并 PR

CI 全部通过后，合并 PR 到 master：

```bash
gh pr merge <PR_URL> --merge
```

- `--merge` 创建 merge commit（保持提交历史完整）
- 如果合并冲突 → 提示用户手动解决冲突，退出 skill

报告最终状态：
- ✅ PR URL
- ✅ CI 通过
- ✅ 已合并到 master

### Step 7: 修复循环（最多 3 次迭代）

CI 失败时执行修复循环：

**迭代计数器**：从 1 开始，每次修复后递增。超过 3 次则退出并报告用户。

**每次迭代的步骤：**

1. 获取 CI 失败的详细日志：
```bash
# 找到失败的 run ID
gh run list --branch <current-branch> --limit 1 --json databaseId,status,conclusion
# 查看失败日志
gh run view <run-id> --log --job <job-id> 2>&1 | tail -200
```

2. 分析错误原因：
   - 编译错误 → 检查语法、类型、导入
   - codelinter 错误 → 按照 codelinter 报告修复
   - 签名错误 → 检查 secrets 配置（无法自动修复，报告用户）
   - HAP 构建错误 → 检查 build 脚本和配置
   - 仓库卫生/回归守卫错误 → 参考 Step 2 的修复指引

3. 修复代码后提交：
```bash
git add <修复的文件>
git commit -m "$(cat <<'EOF'
fix(ci): 修复 CI 错误 — <简要描述>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin <current-branch>
```

4. 回到 Step 5 重新监控 CI

**无法自动修复的情况（报告中止）：**
- GitHub secrets 或环境变量缺失
- 第三方服务不可用
- 分支保护规则阻止合并
- 3 次迭代后仍失败

## 安全约束

- **绝对不提交**：`.env`、`credentials.json`、`*.p12`、`*.keystore`、`secrets.*`
- **不 force push** master 分支
- **不跳过 Git hooks**（不使用 `--no-verify`、`--no-gpg-sign`）
- **修复循环上限**：最多 3 次迭代，防止无限循环
- **合并前确认**：CI 必须全部通过才能合并

## 项目信息

- **仓库**：`https://github.com/daugf2527/harmonyos-libretro-emulator.git`
- **base 分支**：`master`
- **CI 工作流**：`harmonyos-pr-ci.yml`（PR 触发）、`ci.yml`（push 到 master 触发）
- **提交格式**：`type(scope): 中文描述`（Conventional Commits）

## 本地 CI 脚本

| 脚本 | 作用 |
|------|------|
| `bash scripts/ci/check_repo_hygiene.sh` | 仓库卫生检查（冲突标记、缓存目录、shell 语法） |
| `bash scripts/ci/check_regression_guards.sh` | 回归守卫（NativeBuffer、LOG_DOMAIN、硬编码超时、TODO/FIXME） |
