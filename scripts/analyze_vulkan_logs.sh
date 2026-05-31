#!/bin/bash
# Vulkan 验证日志分析脚本
# 用法: bash scripts/analyze_vulkan_logs.sh <log_file>

LOG_FILE="$1"

if [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <log_file>"
    echo ""
    echo "示例:"
    echo "  hdc shell hilog -x > vulkan_test.log"
    echo "  bash scripts/analyze_vulkan_logs.sh vulkan_test.log"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "错误: 文件不存在: $LOG_FILE"
    exit 1
fi

echo "=== Vulkan 验证日志分析 ==="
echo "日志文件: $LOG_FILE"
echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. 初始化统计
echo "1. 初始化统计:"
INIT_SUCCESS=$(grep -c "Vulkan presenter initialized" "$LOG_FILE")
INIT_FAIL=$(grep -c "hw_vk_context_init_failed\|hw_vk_presenter_init_failed" "$LOG_FILE")
HW_RENDER_INIT=$(grep -c "\[Vulkan\] Hardware Renderer Initialized" "$LOG_FILE")
echo "  Presenter 初始化成功: $INIT_SUCCESS 次"
echo "  HW Renderer 初始化成功: $HW_RENDER_INIT 次"
echo "  初始化失败: $INIT_FAIL 次"

if [ $INIT_SUCCESS -gt 0 ]; then
    echo "  ✓ 初始化验证通过"
else
    echo "  ✗ 初始化验证失败"
fi
echo ""

# 2. Swapchain 重建统计
echo "2. Swapchain 重建统计:"
RECREATE_TOTAL=$(grep -c "Vulkan swapchain recreate" "$LOG_FILE")
RECREATE_OK=$(grep -c "hw_vk_recreate_ok\|hw_vk_resize_ok" "$LOG_FILE")
RECREATE_FAIL=$(grep -c "Vulkan swapchain recreate failed" "$LOG_FILE")
echo "  总重建次数: $RECREATE_TOTAL"
echo "  成功: $RECREATE_OK 次"
echo "  失败: $RECREATE_FAIL 次"

if [ $RECREATE_TOTAL -gt 0 ]; then
    SUCCESS_RATE=$((RECREATE_OK * 100 / RECREATE_TOTAL))
    echo "  成功率: $SUCCESS_RATE%"
    if [ $SUCCESS_RATE -ge 80 ]; then
        echo "  ✓ Swapchain 重建验证通过"
    else
        echo "  ⚠ Swapchain 重建成功率偏低"
    fi
fi
echo ""

# 3. Acquire/Present 错误统计
echo "3. Acquire/Present 错误统计:"
OUT_OF_DATE=$(grep -c "Vulkan acquire out of date" "$LOG_FILE")
ACQUIRE_FAIL=$(grep -c "Vulkan acquire failed" "$LOG_FILE")
PRESENT_FAIL=$(grep -c "Vulkan present failed" "$LOG_FILE")
ACQUIRE_OK=$(grep -c "hw_vk_acquire_ok" "$LOG_FILE")
PRESENT_OK=$(grep -c "hw_vk_present_ok" "$LOG_FILE")

echo "  OUT_OF_DATE 事件: $OUT_OF_DATE 次"
echo "  Acquire 失败: $ACQUIRE_FAIL 次"
echo "  Acquire 成功: $ACQUIRE_OK 次"
echo "  Present 失败: $PRESENT_FAIL 次"
echo "  Present 成功: $PRESENT_OK 次"

TOTAL_ERRORS=$((OUT_OF_DATE + ACQUIRE_FAIL + PRESENT_FAIL))
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo "  ✓ 无 Acquire/Present 错误"
elif [ $TOTAL_ERRORS -lt 10 ]; then
    echo "  ⚠ 有少量错误，但在可接受范围内"
else
    echo "  ✗ 错误次数过多，需要调查"
fi
echo ""

# 4. 降级事件统计
echo "4. 降级事件统计:"
DEGRADE=$(grep -c "Render degraded to software" "$LOG_FILE")
HW_FAILURE=$(grep -c "HW path failure" "$LOG_FILE")
RECOVERY=$(grep -c "Render recovery attempt" "$LOG_FILE")

echo "  降级次数: $DEGRADE"
echo "  HW 路径失败: $HW_FAILURE 次"
echo "  恢复尝试: $RECOVERY 次"

if [ $DEGRADE -gt 0 ]; then
    echo "  降级原因:"
    grep "Render degraded to software" "$LOG_FILE" | sed 's/.*reason=\([^ ]*\).*/    - \1/' | sort | uniq -c
    echo "  ⚠ 发生了降级事件，需要检查原因"
else
    echo "  ✓ 无降级事件"
fi
echo ""

# 5. 失败模式 Top 5
echo "5. 失败模式 Top 5:"
FAILURE_PATTERNS=$(grep -o "hw_vk_[a-z_]*_failed" "$LOG_FILE" | sort | uniq -c | sort -rn | head -5)
if [ -n "$FAILURE_PATTERNS" ]; then
    echo "$FAILURE_PATTERNS" | while read count pattern; do
        echo "  $count 次 - $pattern"
    done
else
    echo "  ✓ 无失败模式"
fi
echo ""

# 6. 窗口事件统计
echo "6. 窗口事件统计:"
WINDOW_RESIZE=$(grep -c "OnHardwareWindowResizedImpl\|hw_vk_resize" "$LOG_FILE")
WINDOW_DESTROY=$(grep -c "OnHardwareWindowDestroyedImpl" "$LOG_FILE")
echo "  窗口 Resize 事件: $WINDOW_RESIZE 次"
echo "  窗口销毁事件: $WINDOW_DESTROY 次"
echo ""

# 7. 时间线分析（前 20 条关键事件）
echo "7. 关键事件时间线（前 20 条）:"
grep -E "Vulkan presenter initialized|Hardware Renderer Initialized|Vulkan swapchain recreate|Render degraded|hw_vk_|OnHardwareWindow" "$LOG_FILE" | head -20 | while read line; do
    # 提取时间戳和关键信息
    timestamp=$(echo "$line" | grep -oP '\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+' | head -1)
    event=$(echo "$line" | grep -oP '(Vulkan presenter initialized|Hardware Renderer Initialized|Vulkan swapchain recreate|Render degraded|hw_vk_[a-z_]+|OnHardwareWindow[a-zA-Z]+)')
    if [ -n "$timestamp" ] && [ -n "$event" ]; then
        echo "  [$timestamp] $event"
    fi
done
echo ""

# 8. 性能指标
echo "8. 性能指标:"
SLOW_RECREATE=$(grep -c "Vulkan swapchain recreate.*[5-9][0-9][0-9]ms\|[1-9][0-9][0-9][0-9]ms" "$LOG_FILE")
if [ $SLOW_RECREATE -gt 0 ]; then
    echo "  ⚠ 检测到 $SLOW_RECREATE 次慢速 Swapchain 重建（>500ms）"
else
    echo "  ✓ Swapchain 重建性能正常"
fi
echo ""

# 9. 总体评估
echo "=== 总体评估 ==="
PASS_COUNT=0
TOTAL_CHECKS=5

# Check 1: 初始化
if [ $INIT_SUCCESS -gt 0 ] && [ $INIT_FAIL -eq 0 ]; then
    echo "✓ 初始化验证通过"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "✗ 初始化验证失败"
fi

# Check 2: Swapchain 重建
if [ $RECREATE_TOTAL -eq 0 ] || [ $RECREATE_OK -gt 0 ]; then
    echo "✓ Swapchain 重建验证通过"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "✗ Swapchain 重建验证失败"
fi

# Check 3: 错误恢复
if [ $TOTAL_ERRORS -lt 10 ]; then
    echo "✓ 错误恢复验证通过"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "✗ 错误恢复验证失败"
fi

# Check 4: 降级控制
if [ $DEGRADE -le 1 ]; then
    echo "✓ 降级控制验证通过"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "⚠ 降级次数偏多"
fi

# Check 5: 无 FATAL 错误
FATAL_COUNT=$(grep -c "LOG_FATAL\|FATAL" "$LOG_FILE")
if [ $FATAL_COUNT -eq 0 ]; then
    echo "✓ 无 FATAL 错误"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "✗ 检测到 $FATAL_COUNT 个 FATAL 错误"
fi

echo ""
echo "通过率: $PASS_COUNT/$TOTAL_CHECKS"

if [ $PASS_COUNT -eq $TOTAL_CHECKS ]; then
    echo "结论: ✓ 验证通过"
    exit 0
elif [ $PASS_COUNT -ge 3 ]; then
    echo "结论: ⚠ 有条件通过（需修复部分问题）"
    exit 0
else
    echo "结论: ✗ 验证不通过"
    exit 1
fi
