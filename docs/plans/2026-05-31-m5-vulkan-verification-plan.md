# M5 Vulkan 实机验证方案

**文档版本**: v1.0
**创建日期**: 2026-05-31
**状态**: Draft
**目标**: 验证 Vulkan Transfer-only 渲染路径在真机上的稳定性与可恢复性

---

## 1. 验证目标

验证 Vulkan HW_RENDER 路径在以下场景下的稳定性：
- Swapchain 生命周期管理（创建/重建/销毁）
- 窗口状态变化（旋转/分屏/前后台切换）
- 错误恢复机制（OUT_OF_DATE/SUBOPTIMAL/失败降级）
- 多核心切换场景下的资源复用

**验收标准**：
- 所有场景无崩溃、无黑屏超过 3 秒
- 错误恢复后画面可正常显示
- 日志中无 FATAL 级别错误

---

## 2. 验证场景清单

### 场景 1: 基础渲染稳定性
**触发条件**: 启动支持 Vulkan 的核心（如 ParaLLEl N64）并加载 ROM
**预期行为**:
- VulkanContext 初始化成功（LOG_DOMAIN 0xD00C）
- VulkanPresenter 初始化成功（LOG_DOMAIN 0xD00B）
- 画面正常显示，无闪烁/撕裂

**PASS 标准**:
```
✓ hilog 出现 "Vulkan presenter initialized: gfx_family=X present_family=Y"
✓ hilog 出现 "[Vulkan] Hardware Renderer Initialized"
✓ 画面连续显示 60 秒无黑屏
✓ 无 "hw_vk_context_init_failed" / "hw_vk_presenter_init_failed" 日志
```

**FAIL 标志**:
```
✗ 黑屏超过 3 秒
✗ hilog 出现 "HW path failure: reason=hw_vk_*"
✗ 应用崩溃或 ANR
```

---

### 场景 2: 屏幕旋转（Swapchain 重建）
**触发条件**: 游戏运行中旋转设备（竖屏 ↔ 横屏）
**预期行为**:
- `OnHardwareWindowResizedImpl` 触发
- `RecreateVulkanSwapchain` 执行（200ms 去抖后）
- Swapchain 重建成功，画面适配新尺寸

**PASS 标准**:
```
✓ hilog 出现 "Vulkan swapchain recreate recovered" 或 "hw_vk_resize_ok"
✓ 旋转后 1 秒内画面恢复显示
✓ 画面比例正确（无拉伸/黑边异常）
✓ 连续旋转 5 次无崩溃
```

**FAIL 标志**:
```
✗ hilog 出现 "Vulkan swapchain recreate failed" 且画面持续黑屏
✗ hilog 出现 "hw_vk_resize_recreate_failed" 且未降级到 SW
✗ 旋转后应用崩溃
```

---

### 场景 3: 前后台切换（Surface 生命周期）
**触发条件**: 游戏运行中按 Home 键切后台，再切回前台
**预期行为**:
- 切后台时 `OnHardwareWindowDestroyedImpl` 触发
- 切回前台时 `InitializeHardwareRendererImpl` 重新初始化
- Vulkan 上下文重建成功

**PASS 标准**:
```
✓ 切后台时无崩溃
✓ 切回前台后 2 秒内画面恢复
✓ hilog 出现 "hw_vk_initialized" 或 "hw_vk_same_window_ready"
✓ 连续切换 3 次无黑屏
```

**FAIL 标志**:
```
✗ 切回前台后黑屏超过 5 秒
✗ hilog 出现 "hw_vk_context_init_failed" 且未降级
✗ 应用无响应或崩溃
```

---

### 场景 4: 分屏模式（窗口尺寸动态变化）
**触发条件**: 进入分屏模式，拖动分割线调整窗口大小
**预期行为**:
- 每次尺寸变化触发 `OnHardwareWindowResizedImpl`
- 200ms 去抖机制生效，避免频繁重建
- 最终尺寸稳定后 Swapchain 重建成功

**PASS 标准**:
```
✓ 拖动过程中画面可能短暂黑屏，但最终恢复
✓ hilog 中 "Vulkan swapchain recreate" 日志间隔 ≥200ms
✓ 最终画面适配新窗口尺寸
✓ 退出分屏后画面恢复全屏
```

**FAIL 标志**:
```
✗ 分屏后画面永久黑屏
✗ hilog 出现大量 "Vulkan swapchain recreate failed"（>5 次/秒）
✗ 应用崩溃
```

---

### 场景 5: Acquire 失败恢复（OUT_OF_DATE）
**触发条件**: 快速旋转设备或快速进出分屏
**预期行为**:
- `HandleVulkanAcquireImpl` 返回 `VK_ERROR_OUT_OF_DATE_KHR`
- 自动触发 `RecreateVulkanSwapchain(force=true)`
- 重建后继续渲染

**PASS 标准**:
```
✓ hilog 出现 "Vulkan acquire out of date: -1000000001"
✓ 紧接着出现 "hw_vk_acquire_recreate_failed" 或 "hw_vk_acquire_ok"
✓ 画面在 2 秒内恢复
✓ 无连续失败超过 3 次
```

**FAIL 标志**:
```
✗ hilog 出现 "hw_vk_acquire_out_of_date" 后无恢复日志
✗ 画面永久黑屏
✗ 降级到 SW 模式（除非连续失败 ≥3 次）
```

---

### 场景 6: Present 失败恢复（SUBOPTIMAL）
**触发条件**: 旋转过程中或窗口尺寸变化时
**预期行为**:
- `Present()` 返回 `VK_SUBOPTIMAL_KHR`
- `ShouldRecreateSwapchain()` 返回 true
- 下一帧自动重建 Swapchain

**PASS 标准**:
```
✓ hilog 出现 "Vulkan present failed" 或 "Vulkan swapchain recreate failed (present)"
✓ 紧接着出现 "hw_vk_recreate_ok" 或 "hw_vk_present_ok"
✓ 画面短暂闪烁后恢复
✓ 无连续失败超过 5 次
```

**FAIL 标志**:
```
✗ hilog 出现 "hw_vk_present_failed" 后无恢复
✗ 画面持续黑屏或闪烁
✗ 应用崩溃
```

---

### 场景 7: 核心切换（资源复用）
**触发条件**: 从 Vulkan 核心 A 切换到 Vulkan 核心 B
**预期行为**:
- 旧核心 `DestroyHardwareRendererImpl` 清理资源
- 新核心 `InitializeHardwareRendererImpl` 重新初始化
- Vulkan 上下文可能复用（取决于 `cache_context`）

**PASS 标准**:
```
✓ 切换过程无崩溃
✓ 新核心画面正常显示
✓ hilog 出现 "hw_vk_initialized" 或 "hw_vk_same_window_ready"
✓ 内存无明显泄漏（通过 DevEco Profiler 验证）
```

**FAIL 标志**:
```
✗ 切换后黑屏超过 5 秒
✗ hilog 出现 "hw_vk_context_init_failed"
✗ 内存持续增长（>50MB/次切换）
```

---

### 场景 8: 降级到 SW 模式（失败兜底）
**触发条件**: 连续 3 次 Vulkan 初始化失败或 Present 失败
**预期行为**:
- `MarkHardwarePathFailure` 累计失败次数
- `hw_failure_streak_ >= 3` 触发 `EnterDegradedMode`
- 自动切换到 SOFTWARE_SCALING 模式

**PASS 标准**:
```
✓ hilog 出现 "HW path failure: reason=hw_vk_* streak=3"
✓ hilog 出现 "Render degraded to software: reason=hw_path_failed source=2"
✓ 画面切换到 CPU 渲染路径，继续显示
✓ RenderModeState 变为 DEGRADED_TO_SW
```

**FAIL 标志**:
```
✗ 连续失败后画面永久黑屏
✗ 应用崩溃而非降级
✗ 降级后仍然黑屏
```

---

## 3. 验证步骤

### 3.1 准备工作
1. **设备要求**:
   - HarmonyOS 真机（非模拟器）
   - 支持 Vulkan 1.1+（通过 `vulkaninfo` 或设备规格确认）
   - 屏幕支持旋转

2. **核心准备**:
   - 使用支持 Vulkan HW_RENDER 的核心（推荐 ParaLLEl N64）
   - 准备测试 ROM（如 Super Mario 64）

3. **日志配置**:
   ```bash
   # 清空旧日志
   hdc shell hilog -r

   # 开始实时监控（新终端）
   hdc shell hilog -T LIBRETRO | grep -E "VulkanContext|VulkanPresenter|VideoPipeline|HW path"
   ```

### 3.2 执行验证

#### 场景 1-3: 基础稳定性验证
1. 启动应用，加载 Vulkan 核心 + ROM
2. 观察初始化日志，确认无错误
3. 游戏运行 60 秒，记录是否有黑屏/闪烁
4. 旋转设备 5 次（每次间隔 5 秒）
5. 切后台 → 等待 10 秒 → 切回前台（重复 3 次）

**记录内容**:
- 初始化耗时（从 "Initialize" 到 "Initialized" 的时间）
- 旋转恢复耗时（从旋转到画面稳定的时间）
- 前后台切换恢复耗时
- 任何错误日志

#### 场景 4: 分屏压力测试
1. 进入分屏模式（游戏占上半屏）
2. 缓慢拖动分割线 10 次
3. 快速拖动分割线 5 次
4. 退出分屏

**记录内容**:
- 拖动过程中黑屏次数和持续时间
- Swapchain 重建频率（通过日志统计）
- 是否触发降级

#### 场景 5-6: 错误注入测试
1. 快速连续旋转设备（1 秒内旋转 3 次）
2. 旋转过程中快速进出分屏
3. 观察 Acquire/Present 失败日志

**记录内容**:
- OUT_OF_DATE 触发次数
- SUBOPTIMAL 触发次数
- 恢复成功率

#### 场景 7: 核心切换测试
1. 加载核心 A（Vulkan）
2. 运行 30 秒
3. 切换到核心 B（Vulkan）
4. 运行 30 秒
5. 重复 3 次

**记录内容**:
- 切换耗时
- 内存占用变化（通过 DevEco Profiler）
- 任何资源泄漏迹象

#### 场景 8: 降级验证
1. 模拟连续失败（可通过修改代码强制返回失败）
2. 观察降级日志
3. 确认 CPU 渲染路径接管

**记录内容**:
- 降级触发条件
- 降级后画面质量
- 是否可手动切回 Vulkan

---

## 4. 日志收集方案

### 4.1 关键日志域
```
0xD009 - VideoPipeline (渲染管线主控)
0xD00B - VulkanPresenter (Present 逻辑)
0xD00C - VulkanContext (Swapchain 管理)
0xD010 - LibretroEngine (引擎状态)
```

### 4.2 日志过滤命令

**实时监控（推荐）**:
```bash
hdc shell hilog -T LIBRETRO | grep -E "VulkanContext|VulkanPresenter|VideoPipeline|HW path|Render degraded|swapchain"
```

**完整日志导出**:
```bash
# 开始测试前清空
hdc shell hilog -r

# 执行测试...

# 导出日志
hdc shell hilog -x > vulkan_verification_$(date +%Y%m%d_%H%M%S).log
```

**关键模式匹配**:
```bash
# 初始化成功
grep "Vulkan presenter initialized" vulkan_verification.log
grep "Hardware Renderer Initialized" vulkan_verification.log

# Swapchain 重建
grep "Vulkan swapchain recreate" vulkan_verification.log

# 错误恢复
grep "hw_vk_.*_ok" vulkan_verification.log
grep "hw_vk_.*_failed" vulkan_verification.log

# 降级事件
grep "Render degraded to software" vulkan_verification.log
grep "HW path failure" vulkan_verification.log

# OUT_OF_DATE 事件
grep "VK_ERROR_OUT_OF_DATE\|VK_SUBOPTIMAL" vulkan_verification.log
```

### 4.3 日志分析脚本

创建 `scripts/analyze_vulkan_logs.sh`:
```bash
#!/bin/bash
LOG_FILE="$1"

if [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

echo "=== Vulkan 验证日志分析 ==="
echo ""

echo "1. 初始化统计:"
INIT_SUCCESS=$(grep -c "Vulkan presenter initialized" "$LOG_FILE")
INIT_FAIL=$(grep -c "hw_vk_context_init_failed\|hw_vk_presenter_init_failed" "$LOG_FILE")
echo "  成功: $INIT_SUCCESS 次"
echo "  失败: $INIT_FAIL 次"
echo ""

echo "2. Swapchain 重建统计:"
RECREATE_TOTAL=$(grep -c "Vulkan swapchain recreate" "$LOG_FILE")
RECREATE_OK=$(grep -c "hw_vk_recreate_ok\|hw_vk_resize_ok" "$LOG_FILE")
RECREATE_FAIL=$(grep -c "Vulkan swapchain recreate failed" "$LOG_FILE")
echo "  总次数: $RECREATE_TOTAL"
echo "  成功: $RECREATE_OK 次"
echo "  失败: $RECREATE_FAIL 次"
echo ""

echo "3. Acquire/Present 错误:"
OUT_OF_DATE=$(grep -c "Vulkan acquire out of date" "$LOG_FILE")
PRESENT_FAIL=$(grep -c "Vulkan present failed" "$LOG_FILE")
echo "  OUT_OF_DATE: $OUT_OF_DATE 次"
echo "  Present 失败: $PRESENT_FAIL 次"
echo ""

echo "4. 降级事件:"
DEGRADE=$(grep -c "Render degraded to software" "$LOG_FILE")
echo "  降级次数: $DEGRADE"
if [ $DEGRADE -gt 0 ]; then
    echo "  降级原因:"
    grep "Render degraded to software" "$LOG_FILE" | sed 's/.*reason=\([^ ]*\).*/    - \1/'
fi
echo ""

echo "5. 失败模式 Top 5:"
grep "hw_vk_.*_failed" "$LOG_FILE" | sed 's/.*reason=\([^ ]*\).*/\1/' | sort | uniq -c | sort -rn | head -5
echo ""

echo "6. 时间线（前 10 条关键事件）:"
grep -E "Vulkan presenter initialized|Hardware Renderer Initialized|Vulkan swapchain recreate|Render degraded|hw_vk_" "$LOG_FILE" | head -10
```

---

## 5. 已知风险点

### 5.1 Swapchain 重建频率
**风险**: 连续 Resize 事件可能导致 Swapchain 频繁重建
**缓解**: 200ms 去抖机制（`last_vk_swapchain_recreate_time_`）
**验证**: 分屏拖动时观察日志，确认重建间隔 ≥200ms

### 5.2 Surface 生命周期不一致
**风险**: 前后台切换时 Surface 可能先于 Vulkan 上下文销毁
**缓解**: `OnHardwareWindowDestroyedImpl` 中先 `device_wait_idle`
**验证**: 前后台切换时无崩溃，日志无 "use-after-free" 迹象

### 5.3 Queue Family 不匹配
**风险**: Graphics Queue 和 Present Queue 可能属于不同 Family
**缓解**: `VulkanPresenter` 分别存储 `queue_family_index_` 和 `present_queue_family_index_`
**验证**: 初始化日志中确认两个 Family Index，Present 无 `VK_ERROR_DEVICE_LOST`

### 5.4 Image Layout 转换
**风险**: Transfer-only 模式下 Layout 转换可能不正确
**缓解**: `RecordPresenterCommands` 中显式转换 Layout
**验证**: 画面无花屏/撕裂，日志无 Validation Layer 错误

### 5.5 Semaphore 同步
**风险**: Acquire/Present Semaphore 可能死锁或泄漏
**缓解**: `SwapAcquireSemaphores` 处理 Index 不匹配情况
**验证**: 长时间运行无卡顿，内存无持续增长

### 5.6 降级后无法恢复
**风险**: 降级到 SW 后可能无法自动恢复到 Vulkan
**缓解**: `MaybeRecoverDegradedMode` 在冷却期后尝试恢复
**验证**: 降级后等待 3-5 秒，观察是否尝试恢复（日志中出现 "Render recovery attempt"）

---

## 6. 验证清单

### 6.1 功能验证
- [ ] 场景 1: 基础渲染稳定性（60 秒无黑屏）
- [ ] 场景 2: 屏幕旋转（5 次旋转无崩溃）
- [ ] 场景 3: 前后台切换（3 次切换画面恢复）
- [ ] 场景 4: 分屏模式（拖动 15 次无崩溃）
- [ ] 场景 5: Acquire 失败恢复（OUT_OF_DATE 自动恢复）
- [ ] 场景 6: Present 失败恢复（SUBOPTIMAL 自动恢复）
- [ ] 场景 7: 核心切换（3 次切换无泄漏）
- [ ] 场景 8: 降级到 SW 模式（连续失败后降级成功）

### 6.2 性能验证
- [ ] 初始化耗时 <2 秒
- [ ] Swapchain 重建耗时 <500ms
- [ ] 旋转恢复耗时 <1 秒
- [ ] 前后台切换恢复耗时 <2 秒
- [ ] 帧率稳定（无明显掉帧）

### 6.3 日志验证
- [ ] 无 FATAL 级别错误
- [ ] 无连续失败 >5 次（除非触发降级）
- [ ] 降级事件有明确原因
- [ ] 恢复事件与失败事件成对出现

### 6.4 内存验证
- [ ] 初始内存占用 <200MB
- [ ] 运行 10 分钟内存增长 <50MB
- [ ] 核心切换无明显泄漏（<10MB/次）
- [ ] 降级后内存释放正常

---

## 7. 问题上报模板

如果验证失败，请按以下格式上报：

```markdown
### 问题描述
[简要描述问题现象，如"旋转后黑屏超过 5 秒"]

### 复现步骤
1. [步骤 1]
2. [步骤 2]
3. [步骤 3]

### 预期行为
[描述预期应该发生什么]

### 实际行为
[描述实际发生了什么]

### 设备信息
- 设备型号: [如 Mate 60 Pro]
- HarmonyOS 版本: [如 4.2.0]
- Vulkan 版本: [通过 vulkaninfo 获取]

### 日志片段
```
[粘贴关键日志，包含时间戳]
```

### 截图/录屏
[如有，附上截图或录屏链接]

### 严重程度
- [ ] P0 - 应用崩溃/无法使用
- [ ] P1 - 功能不可用但有降级
- [ ] P2 - 体验问题但不影响使用
```

---

## 8. 验证结论模板

验证完成后填写：

```markdown
### 验证环境
- 设备: [型号]
- HarmonyOS: [版本]
- 核心: [核心名称 + 版本]
- ROM: [测试 ROM 名称]
- 验证日期: [YYYY-MM-DD]

### 验证结果
- 功能验证: [X/8] 通过
- 性能验证: [X/4] 通过
- 日志验证: [X/4] 通过
- 内存验证: [X/4] 通过

### 关键发现
1. [发现 1]
2. [发现 2]
3. [发现 3]

### 遗留问题
1. [问题 1 - 严重程度 PX]
2. [问题 2 - 严重程度 PX]

### 建议
1. [建议 1]
2. [建议 2]

### 结论
- [ ] 通过 - 可进入下一阶段
- [ ] 有条件通过 - 需修复 P0/P1 问题
- [ ] 不通过 - 需重新验证
```

---

## 9. 参考资料

### 9.1 代码位置
- Vulkan 上下文管理: `entry/src/main/cpp/platform/graphics/vulkan_context.cpp`
- Vulkan 呈现逻辑: `entry/src/main/cpp/platform/graphics/vulkan_presenter.cpp`
- 渲染管线主控: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- HW_RENDER 接口: `entry/src/main/cpp/core/libretro/libretro_vulkan.h`

### 9.2 关键函数
- `VulkanContext::Initialize` - Vulkan 初始化
- `VulkanContext::RecreateSwapchain` - Swapchain 重建
- `VulkanPresenter::Present` - 帧呈现
- `VideoPipeline::HandleVulkanAcquireImpl` - Acquire 逻辑
- `VideoPipeline::MarkHardwarePathFailure` - 失败计数
- `VideoPipeline::EnterDegradedMode` - 降级逻辑

### 9.3 相关文档
- `docs/plans/2026-02-06-new-arch-technical-whitepaper.md` - 架构白皮书
- `docs/reference/known-issues.md` - 已知问题清单（Vulkan Swapchain Resize 风险）
- `Roadmap.md` - M5 里程碑定义

---

## 附录 A: 快速验证脚本

创建 `scripts/quick_vulkan_check.sh`:
```bash
#!/bin/bash
# 快速验证 Vulkan 是否正常工作

echo "=== Vulkan 快速验证 ==="
echo ""

# 1. 检查设备 Vulkan 支持
echo "1. 检查设备 Vulkan 支持..."
hdc shell vulkaninfo > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ 设备支持 Vulkan"
else
    echo "  ✗ 设备不支持 Vulkan 或 vulkaninfo 不可用"
    exit 1
fi

# 2. 清空日志
echo ""
echo "2. 清空旧日志..."
hdc shell hilog -r
echo "  ✓ 日志已清空"

# 3. 启动应用（需要手动操作）
echo ""
echo "3. 请手动启动应用并加载 Vulkan 核心..."
echo "   按回车继续..."
read

# 4. 等待初始化
echo ""
echo "4. 等待 Vulkan 初始化（10 秒）..."
sleep 10

# 5. 检查初始化日志
echo ""
echo "5. 检查初始化结果..."
INIT_LOG=$(hdc shell hilog -x | grep "Vulkan presenter initialized")
if [ -n "$INIT_LOG" ]; then
    echo "  ✓ Vulkan 初始化成功"
    echo "    $INIT_LOG"
else
    echo "  ✗ Vulkan 初始化失败或未检测到"
    echo "    请检查完整日志: hdc shell hilog -x | grep VulkanContext"
    exit 1
fi

# 6. 检查是否有错误
echo ""
echo "6. 检查错误日志..."
ERROR_COUNT=$(hdc shell hilog -x | grep -c "hw_vk_.*_failed")
if [ $ERROR_COUNT -eq 0 ]; then
    echo "  ✓ 无 Vulkan 错误"
else
    echo "  ⚠ 检测到 $ERROR_COUNT 个 Vulkan 错误"
    echo "    请查看详细日志"
fi

echo ""
echo "=== 快速验证完成 ==="
echo "如需完整验证，请参考 docs/plans/2026-05-31-m5-vulkan-verification-plan.md"
```

---

## 10. 常见问题排查

### 10.1 Swapchain 重建失败

**症状**:
- 旋转或分屏后画面持续黑屏超过 3 秒
- hilog 出现 `Vulkan swapchain recreate failed` 或 `hw_vk_resize_recreate_failed`
- 应用未崩溃但画面无法恢复

**可能原因**:
1. **Surface 尺寸不匹配**: `OH_NativeWindow_GetBufferGeometry` 返回的尺寸与实际窗口不一致
2. **Swapchain 资源未释放**: 旧 Swapchain 销毁前仍有未完成的 Present 操作
3. **设备丢失**: GPU 驱动崩溃或设备进入低功耗模式
4. **内存不足**: 新 Swapchain 所需内存无法分配

**解决方案**:
```bash
# 1. 检查 Surface 尺寸日志
hdc shell hilog -x | grep "NativeWindow geometry"

# 2. 确认 device_wait_idle 是否执行
hdc shell hilog -x | grep "vkDeviceWaitIdle"

# 3. 检查是否触发降级
hdc shell hilog -x | grep "Render degraded"

# 4. 查看内存占用
hdc shell hidumper -s MemoryManagerService | grep "com.libretro.emulator"
```

**预防措施**:
- 确保 `RecreateSwapchain` 前调用 `vkDeviceWaitIdle()`
- 检查 200ms 去抖机制是否生效（避免频繁重建）
- 监控内存占用，及时释放不必要的资源

---

### 10.2 图像格式不支持

**症状**:
- 初始化时 hilog 出现 `VK_ERROR_FORMAT_NOT_SUPPORTED` 或 `hw_vk_context_init_failed`
- 画面完全黑屏，无任何渲染输出
- 降级到 SW 模式后画面正常

**可能原因**:
1. **Surface 格式不匹配**: `OH_NativeWindow` 的格式与 Vulkan Swapchain 支持的格式不一致
2. **色彩空间不支持**: 请求的色彩空间（如 sRGB）设备不支持
3. **Present Mode 不支持**: 请求的 Present Mode（如 MAILBOX）设备不支持

**解决方案**:
```bash
# 1. 查看设备支持的格式
hdc shell vulkaninfo | grep -A 20 "VkSurfaceFormatKHR"

# 2. 检查初始化日志中的格式选择
hdc shell hilog -x | grep "Selected surface format"

# 3. 查看 Present Mode 选择
hdc shell hilog -x | grep "Present mode"
```

**代码检查点**:
- `VulkanContext::ChooseSurfaceFormat()` 是否有 fallback 逻辑
- `VulkanContext::ChoosePresentMode()` 是否优先选择 FIFO（必定支持）
- `OH_NativeWindow_SetBufferGeometry()` 设置的格式是否与 Vulkan 一致

**预防措施**:
- 优先使用 `VK_FORMAT_R8G8B8A8_UNORM` 或 `VK_FORMAT_B8G8R8A8_UNORM`（广泛支持）
- Present Mode 优先级: `MAILBOX` > `IMMEDIATE` > `FIFO`（FIFO 必定支持）
- 添加格式兼容性检查，不支持时提前降级

---

### 10.3 内存分配失败

**症状**:
- hilog 出现 `VK_ERROR_OUT_OF_DEVICE_MEMORY` 或 `VK_ERROR_OUT_OF_HOST_MEMORY`
- 应用崩溃或自动降级到 SW 模式
- 核心切换或长时间运行后出现

**可能原因**:
1. **内存泄漏**: Swapchain Image、Semaphore、CommandBuffer 未正确释放
2. **峰值内存过高**: 同时存在多个大尺寸 Swapchain（如分屏时）
3. **碎片化**: 频繁创建/销毁资源导致内存碎片
4. **设备限制**: 设备 Vulkan 可用内存本身较小

**解决方案**:
```bash
# 1. 使用 DevEco Profiler 监控内存
# 打开 DevEco Studio -> Profiler -> Memory

# 2. 检查 Vulkan 内存使用
hdc shell hilog -x | grep "vkAllocateMemory\|vkFreeMemory"

# 3. 统计资源创建/销毁次数
hdc shell hilog -x | grep "vkCreateSwapchain\|vkDestroySwapchain" | wc -l

# 4. 查看设备内存限制
hdc shell vulkaninfo | grep -A 10 "VkPhysicalDeviceMemoryProperties"
```

**代码检查点**:
- `VulkanContext::Cleanup()` 是否正确释放所有资源
- `VulkanPresenter::~VulkanPresenter()` 是否调用 `vkDestroySemaphore`
- 核心切换时是否调用 `DestroyHardwareRendererImpl`

**预防措施**:
- 使用 RAII 封装 Vulkan 资源（如 `VulkanSwapchainRAII`）
- 限制 Swapchain Image 数量（2-3 个足够）
- 核心切换时强制 `vkDeviceWaitIdle()` 后再释放资源
- 添加内存使用监控，接近阈值时主动降级

---

### 10.4 Semaphore 同步问题

**症状**:
- 画面卡顿或完全冻结
- hilog 出现 `VK_TIMEOUT` 或 `VK_ERROR_DEVICE_LOST`
- CPU 占用正常但画面不更新

**可能原因**:
1. **Semaphore 死锁**: Acquire 和 Present Semaphore 配对错误
2. **Fence 未重置**: 重复使用 Fence 但未调用 `vkResetFences`
3. **Queue 提交顺序错误**: Present 在 Acquire 之前提交

**解决方案**:
```bash
# 1. 检查 Semaphore 创建/销毁日志
hdc shell hilog -x | grep "vkCreateSemaphore\|vkDestroySemaphore"

# 2. 查看 Acquire/Present 配对
hdc shell hilog -x | grep "vkAcquireNextImageKHR\|vkQueuePresentKHR"

# 3. 检查 Fence 状态
hdc shell hilog -x | grep "vkWaitForFences\|vkResetFences"
```

**代码检查点**:
- `VulkanPresenter::Present()` 中 Semaphore Index 是否与 Image Index 匹配
- `SwapAcquireSemaphores()` 是否正确处理 Index 不匹配情况
- `vkQueueSubmit` 的 `waitSemaphores` 和 `signalSemaphores` 是否正确

**预防措施**:
- 使用 Per-Frame Semaphore（每个 Swapchain Image 一对）
- 添加 Validation Layer 检查同步错误
- Fence 使用后立即重置，避免状态混乱

---

### 10.5 Layout 转换错误

**症状**:
- 画面花屏、撕裂或颜色异常
- hilog 出现 Validation Layer 错误（如 `VUID-vkQueuePresentKHR-pImageIndices-01296`）
- 画面偶尔正常，偶尔异常

**可能原因**:
1. **Layout 不匹配**: Present 时 Image Layout 不是 `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR`
2. **Pipeline Barrier 缺失**: Transfer 后未正确转换 Layout
3. **多 Queue 同步问题**: Graphics Queue 和 Present Queue 不同时未同步

**解决方案**:
```bash
# 1. 启用 Validation Layer（需重新编译）
# 在 CMakeLists.txt 中添加: add_definitions(-DENABLE_VULKAN_VALIDATION)

# 2. 检查 Layout 转换日志
hdc shell hilog -x | grep "vkCmdPipelineBarrier\|ImageMemoryBarrier"

# 3. 查看 Present 时的 Layout
hdc shell hilog -x | grep "vkQueuePresentKHR" -B 5
```

**代码检查点**:
- `VulkanPresenter::RecordPresenterCommands()` 中是否有 Layout 转换
- `vkCmdPipelineBarrier` 的 `srcStageMask` 和 `dstStageMask` 是否正确
- `oldLayout` 和`newLayout` 是否匹配实际使用

**预防措施**:
- Transfer 后显式转换 Layout: `TRANSFER_DST_OPTIMAL` → `PRESENT_SRC_KHR`
- 使用 `VK_IMAGE_LAYOUT_UNDEFINED` 作为初始 Layout（避免假设）
- 多 Queue 时添加 Queue Family Ownership Transfer

---

## 11. 快速验证步骤（5 分钟版本）

适合快速检查 Vulkan 基础功能是否正常，不包含压力测试。

### 11.1 前置条件
- HarmonyOS 真机已连接（`hdc list targets` 有输出）
- 应用已安装
- 准备一个支持 Vulkan 的核心（如 ParaLLEl N64）和测试 ROM

### 11.2 验证步骤

**Step 1: 清空日志（10 秒）**
```bash
hdc shell hilog -r
```

**Step 2: 启动应用并加载核心（60 秒）**
1. 打开应用
2. 选择 Vulkan 核心（如 ParaLLEl N64）
3. 加载测试 ROM
4. 等待游戏画面出现

**Step 3: 检查初始化日志（20 秒）**
```bash
# 检查 Vulkan 初始化成功
hdc shell hilog -x | grep "Vulkan presenter initialized"

# 预期输出示例:
# 05-31 14:23:45.678  1234  5678 I D00B/VulkanPresenter: Vulkan presenter initialized: gfx_family=0 present_family=0

# 检查是否有初始化失败
hdc shell hilog -x | grep "hw_vk_.*_failed"

# 预期: 无输出（或仅有偶发的 acquire/present 失败，但有恢复日志）
```

**Step 4: 旋转测试（60 秒）**
1. 旋转设备 2 次（竖屏 → 横屏 → 竖屏）
2. 每次旋转后观察画面是否在 2 秒内恢复

**Step 5: 检查 Swapchain 重建（20 秒）**
```bash
# 检查重建成功
hdc shell hilog -x | grep "hw_vk_resize_ok\|hw_vk_recreate_ok"

# 预期: 至少 2 条日志（对应 2 次旋转）

# 检查是否有重建失败
hdc shell hilog -x | grep "Vulkan swapchain recreate failed"

# 预期: 无输出（或有输出但紧接着有恢复日志）
```

**Step 6: 前后台切换（60 秒）**
1. 按 Home 键切到后台
2. 等待 5 秒
3. 切回应用
4. 观察画面是否在 2 秒内恢复

**Step 7: 检查降级（10 秒）**
```bash
# 检查是否意外降级
hdc shell hilog -x | grep "Render degraded to software"

# 预期: 无输出（正常情况下不应降级）
```

### 11.3 快速判定标准

**✓ PASS（可进入完整验证）**:
- Step 3 有 "Vulkan presenter initialized" 日志
- Step 4 旋转后画面正常恢复
- Step 5 有 "hw_vk_resize_ok" 日志
- Step 6 前后台切换后画面恢复
- Step 7 无降级日志

**✗ FAIL（需排查问题）**:
- Step 3 无初始化日志或有 "hw_vk_context_init_failed"
- Step 4 旋转后黑屏超过 3 秒
- Step 5 有 "Vulkan swapchain recreate failed" 且无恢复
- Step 6 切回前台后黑屏超过 5 秒
- Step 7 有降级日志

**⚠ 需进一步观察**:
- 偶发的 "hw_vk_acquire_out_of_date" 或 "hw_vk_present_failed"（但有恢复日志）
- 旋转恢复时间 2-3 秒（可接受但需优化）
- 前后台切换恢复时间 3-5 秒（可接受但需优化）

### 11.4 失败后的下一步

如果快速验证失败，按以下顺序排查：

1. **初始化失败** → 查看 [10.2 图像格式不支持](#102-图像格式不支持)
2. **旋转黑屏** → 查看 [10.1 Swapchain 重建失败](#101-swapchain-重建失败)
3. **前后台黑屏** → 检查 Surface 生命周期（参考 [5.2 已知风险点](#52-surface-生命周期不一致)）
4. **意外降级** → 查看完整日志，定位失败原因

---

## 12. 验证结果模板

### 12.1 基础信息

```markdown
## Vulkan 验证报告

**验证日期**: YYYY-MM-DD
**验证人**: [姓名/ID]
**验证类型**: [ ] 快速验证（5 分钟） [ ] 完整验证（30 分钟）

---

### 测试环境

| 项目 | 信息 |
|------|------|
| 设备型号 | [如 Mate 60 Pro / P60 Pro] |
| HarmonyOS 版本 | [如 4.2.0 / 5.0.0] |
| Vulkan 版本 | [通过 `hdc shell vulkaninfo \| grep apiVersion` 获取] |
| 应用版本 | [如 v1.0.0-beta.5] |
| 核心名称 | [如 ParaLLEl N64 v2.0] |
| 测试 ROM | [如 Super Mario 64 (USA)] |

---

### 测试核心列表

| 核心名称 | 版本 | HW_RENDER 支持 | 测试状态 |
|---------|------|----------------|---------|
| ParaLLEl N64 | v2.0 | Vulkan | [ ] 通过 [ ] 失败 [ ] 未测试 |
| Beetle PSX HW | v0.9.44 | Vulkan | [ ] 通过 [ ] 失败 [ ] 未测试 |
| Flycast | v2.3 | Vulkan | [ ] 通过 [ ] 失败 [ ] 未测试 |
| [其他核心] | - | - | [ ] 通过 [ ] 失败 [ ] 未测试 |

---

### 验证结果汇总

#### 功能验证（8 项）

| 场景 | 状态 | 备注 |
|------|------|------|
| 1. 基础渲染稳定性 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 60 秒无黑屏] |
| 2. 屏幕旋转 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 5 次旋转，恢复时间 <1s] |
| 3. 前后台切换 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 3 次切换，恢复时间 <2s] |
| 4. 分屏模式 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 15 次拖动无崩溃] |
| 5. Acquire 失败恢复 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: OUT_OF_DATE 自动恢复] |
| 6. Present 失败恢复 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: SUBOPTIMAL 自动恢复] |
| 7. 核心切换 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 3 次切换无泄漏] |
| 8. 降级到 SW 模式 | [ ] ✓ [ ] ✗ [ ] ⚠ | [如: 连续失败后降级成功] |

**通过率**: X/8 (XX%)

#### 性能验证（5 项）

| 指标 | 目标 | 实际 | 状态 |
|------|------|------|------|
| 初始化耗时 | <2s | [实际值] | [ ] ✓ [ ] ✗ |
| Swapchain 重建耗时 | <500ms | [实际值] | [ ] ✓ [ ] ✗ |
| 旋转恢复耗时 | <1s | [实际值] | [ ] ✓ [ ] ✗ |
| 前后台切换恢复耗时 | <2s | [实际值] | [ ] ✓ [ ] ✗ |
| 帧率稳定性 | 无明显掉帧 | [如: 稳定 60fps / 偶尔掉到 55fps] | [ ] ✓ [ ] ✗ |

**通过率**: X/5 (XX%)

#### 日志验证（4 项）

| 检查项 | 状态 | 备注 |
|--------|------|------|
| 无 FATAL 级别错误 | [ ] ✓ [ ] ✗ | [如有，列出错误] |
| 无连续失败 >5 次 | [ ] ✓ [ ] ✗ | [如有，列出失败类型] |
| 降级事件有明确原因 | [ ] ✓ [ ] ✗ [ ] N/A | [如: reason=hw_vk_resize_recreate_failed] |
| 恢复事件与失败事件成对 | [ ] ✓ [ ] ✗ | [如: 每个 _failed 后有 _ok] |

**通过率**: X/4 (XX%)

#### 内存验证（4 项）

| 指标 | 目标 | 实际 | 状态 |
|------|------|------|------|
| 初始内存占用 | <200MB | [实际值] | [ ] ✓ [ ] ✗ |
| 运行 10 分钟内存增长 | <50MB | [实际值] | [ ] ✓ [ ] ✗ |
| 核心切换内存泄漏 | <10MB/次 | [实际值] | [ ] ✓ [ ] ✗ |
| 降级后内存释放 | 正常 | [如: 释放 XXX MB] | [ ] ✓ [ ] ✗ [ ] N/A |

**通过率**: X/4 (XX%)

---

### 关键发现

#### 正面发现
1. [如: Swapchain 重建机制稳定，200ms 去抖有效]
2. [如: 前后台切换恢复速度快，用户体验良好]
3. [如: 降级机制工作正常，失败后自动切换到 SW 模式]

#### 问题发现
1. [如: 快速旋转时偶现 OUT_OF_DATE，但能自动恢复]
2. [如: 分屏拖动时 Swapchain 重建频率较高]
3. [如: 核心切换后内存占用略有增长]

---

### 遗留问题

| 问题 ID | 描述 | 严重程度 | 复现率 | 状态 |
|---------|------|----------|--------|------|
| VK-001 | [如: 快速旋转时偶现黑屏 1-2 秒] | [ ] P0 [ ] P1 [✓] P2 | [如: 20%] | [ ] 待修复 [ ] 已知问题 [ ] 可接受 |
| VK-002 | [如: 分屏拖动时 Swapchain 重建频率高] | [ ] P0 [✓] P1 [ ] P2 | [如: 100%] | [ ] 待修复 [ ] 已知问题 [ ] 可接受 |
| VK-003 | [如: 核心切换后内存增长 15MB] | [ ] P0 [ ] P1 [✓] P2 | [如: 100%] | [ ] 待修复 [ ] 已知问题 [ ] 可接受 |

**严重程度定义**:
- **P0**: 应用崩溃/无法使用，必须修复
- **P1**: 功能不可用但有降级，建议修复
- **P2**: 体验问题但不影响使用，可延后

---

### 建议

#### 短期建议（本版本）
1. [如: 优化 Swapchain 重建去抖时间，从 200ms 调整到 300ms]
2. [如: 添加内存监控，接近阈值时主动降级]
3. [如: 完善日志输出，增加更多调试信息]

#### 长期建议（后续版本）
1. [如: 支持 Vulkan 1.3 Dynamic Rendering，减少 Swapchain 重建开销]
2. [如: 实现 Swapchain Image 复用机制，降低内存占用]
3. [如: 添加性能监控面板，实时显示 FPS/内存/GPU 占用]

---

### 验证结论

**总体通过率**: XX/21 (XX%)

**结论**:
- [ ] **通过** - 所有关键场景正常，可进入下一阶段（如发布 Beta）
- [ ] **有条件通过** - 存在 P1 问题但有降级机制，可发布但需在 Release Notes 中说明
- [ ] **不通过** - 存在 P0 问题或通过率 <70%，需修复后重新验证

**签字**:
- 验证人: ________________  日期: ________
- 审核人: ________________  日期: ________

---

### 附件

- [ ] 完整日志文件: `vulkan_verification_YYYYMMDD_HHMMSS.log`
- [ ] 截图/录屏: [链接或文件名]
- [ ] DevEco Profiler 报告: [文件名]
- [ ] 其他: [说明]
```

### 12.2 使用说明

1. **验证前**: 复制模板到新文件（如 `vulkan_verification_report_20260531.md`）
2. **验证中**: 实时填写测试结果，记录关键日志和截图
3. **验证后**: 完善"关键发现"和"建议"部分，得出结论
4. **归档**: 将报告和附件一起归档到 `docs/verification/` 目录

### 12.3 模板字段说明

- **测试状态**: ✓ 通过 / ✗ 失败 / ⚠ 需进一步观察 / N/A 不适用
- **通过率**: 通过项 / 总项数（百分比）
- **严重程度**: P0（阻塞）/ P1（重要）/ P2（次要）
- **复现率**: 问题出现的概率（如 20% 表示 5 次测试中出现 1 次）

---

**文档维护**:
- 验证过程中发现的新问题应及时更新到"已知风险点"
- 验证通过后更新 `Roadmap.md` M5 状态
- 遗留问题同步到 `docs/reference/known-issues.md`
