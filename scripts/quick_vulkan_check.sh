#!/bin/bash
# Vulkan 快速验证脚本
#
# 用途: 快速检查 Vulkan 是否正常工作（15 秒验证）
#
# 用法:
#   bash scripts/quick_vulkan_check.sh
#
# 前置条件:
#   1. 设备已连接并开启 USB 调试（hdc list targets 可见）
#   2. 应用已安装（com.libretro.emulator）
#   3. 已加载支持 Vulkan 的核心（如 ParaLLEl N64）
#
# 验证流程:
#   1. 检查设备连接
#   2. 检查设备 Vulkan 支持（vulkaninfo）
#   3. 清空旧日志
#   4. 检查应用状态（未运行则提示启动）
#   5. 等待 Vulkan 初始化（15 秒）
#   6. 导出日志到 vulkan_quick_check_<timestamp>.log
#   7. 检查 Vulkan 初始化（Presenter + HW Renderer）
#   8. 检查错误（初始化/Acquire/Present/Swapchain）
#   9. 检查降级事件
#   10. 总结（通过/有问题/失败）
#
# 退出码:
#   0 = 验证通过或有条件通过
#   1 = 验证失败
#
# 示例:
#   # 快速验证
#   bash scripts/quick_vulkan_check.sh
#
#   # 验证失败后分析详细日志
#   bash scripts/analyze_vulkan_logs.sh vulkan_quick_check_*.log

set -euo pipefail

echo "=== Vulkan 快速验证 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. 检查 hdc 连接
echo "1. 检查设备连接..."
if ! hdc list targets | grep -q "^[0-9A-Za-z]"; then
    print_error "未检测到设备，请确保设备已连接并开启 USB 调试"
    exit 1
fi
print_success "设备已连接"
echo ""

# 2. 检查设备 Vulkan 支持
echo "2. 检查设备 Vulkan 支持..."
VULKAN_CHECK=$(hdc shell "command -v vulkaninfo" 2>/dev/null || echo "")
if [ -n "$VULKAN_CHECK" ]; then
    print_success "设备支持 Vulkan（vulkaninfo 可用）"

    # 尝试获取 Vulkan 版本
    VULKAN_VERSION=$(hdc shell vulkaninfo 2>/dev/null | grep "apiVersion" | head -1 || echo "")
    if [ -n "$VULKAN_VERSION" ]; then
        echo "  版本信息: $VULKAN_VERSION"
    fi
else
    print_warning "vulkaninfo 不可用，无法确认 Vulkan 支持"
    echo "  继续验证..."
fi
echo ""

# 3. 清空日志
echo "3. 清空旧日志..."
hdc shell hilog -r > /dev/null 2>&1
print_success "日志已清空"
echo ""

# 4. 检查应用是否运行
echo "4. 检查应用状态..."
APP_RUNNING=$(hdc shell ps -ef | grep "com.libretro" | grep -v grep || echo "")
if [ -n "$APP_RUNNING" ]; then
    print_success "应用正在运行"
else
    print_warning "应用未运行"
    echo ""
    echo "请手动启动应用并加载 Vulkan 核心（如 ParaLLEl N64）"
    echo "启动后按回车继续..."
    read
fi
echo ""

# 5. 等待初始化
echo "5. 等待 Vulkan 初始化（15 秒）..."
for i in {15..1}; do
    echo -ne "  倒计时: $i 秒\r"
    sleep 1
done
echo ""
print_success "等待完成"
echo ""

# 6. 导出日志
echo "6. 导出日志..."
LOG_FILE="vulkan_quick_check_$(date +%Y%m%d_%H%M%S).log"
hdc shell hilog -x > "$LOG_FILE" 2>&1
print_success "日志已导出到: $LOG_FILE"
echo ""

# 7. 检查初始化日志
echo "7. 检查 Vulkan 初始化..."
PRESENTER_INIT=$(grep -c "Vulkan presenter initialized" "$LOG_FILE" || true)
HW_RENDER_INIT=$(grep -c "\[Vulkan\] Hardware Renderer Initialized" "$LOG_FILE" || true)
PRESENTER_INIT=${PRESENTER_INIT:-0}
HW_RENDER_INIT=${HW_RENDER_INIT:-0}

if [ "$PRESENTER_INIT" -gt 0 ] && [ "$HW_RENDER_INIT" -gt 0 ]; then
    print_success "Vulkan 初始化成功"
    grep "Vulkan presenter initialized" "$LOG_FILE" | tail -1 | sed 's/^/  /'
    grep "\[Vulkan\] Hardware Renderer Initialized" "$LOG_FILE" | tail -1 | sed 's/^/  /'
elif [ "$PRESENTER_INIT" -gt 0 ]; then
    print_warning "Presenter 初始化成功，但 HW Renderer 未初始化"
    echo "  可能原因: 核心未启用 Vulkan 或初始化失败"
elif [ "$HW_RENDER_INIT" -gt 0 ]; then
    print_warning "HW Renderer 初始化成功，但 Presenter 未初始化"
    echo "  可能原因: Presenter 初始化失败"
else
    print_error "Vulkan 初始化失败或未检测到"
    echo "  请检查:"
    echo "    1. 是否加载了支持 Vulkan 的核心"
    echo "    2. 核心是否正确配置 HW_RENDER"
    echo "    3. 查看完整日志: cat $LOG_FILE | grep -E 'VulkanContext|VulkanPresenter'"
    exit 1
fi
echo ""

# 8. 检查错误日志
echo "8. 检查错误..."
INIT_FAIL=$(grep -c "hw_vk_context_init_failed\|hw_vk_presenter_init_failed" "$LOG_FILE" || true)
ACQUIRE_FAIL=$(grep -c "hw_vk_acquire_failed" "$LOG_FILE" || true)
PRESENT_FAIL=$(grep -c "hw_vk_present_failed" "$LOG_FILE" || true)
RECREATE_FAIL=$(grep -c "Vulkan swapchain recreate failed" "$LOG_FILE" || true)
INIT_FAIL=${INIT_FAIL:-0}
ACQUIRE_FAIL=${ACQUIRE_FAIL:-0}
PRESENT_FAIL=${PRESENT_FAIL:-0}
RECREATE_FAIL=${RECREATE_FAIL:-0}

TOTAL_ERRORS=$((INIT_FAIL + ACQUIRE_FAIL + PRESENT_FAIL + RECREATE_FAIL))

if [ $TOTAL_ERRORS -eq 0 ]; then
    print_success "无 Vulkan 错误"
else
    print_warning "检测到 $TOTAL_ERRORS 个 Vulkan 错误"
    if [ $INIT_FAIL -gt 0 ]; then
        echo "  - 初始化失败: $INIT_FAIL 次"
    fi
    if [ $ACQUIRE_FAIL -gt 0 ]; then
        echo "  - Acquire 失败: $ACQUIRE_FAIL 次"
    fi
    if [ $PRESENT_FAIL -gt 0 ]; then
        echo "  - Present 失败: $PRESENT_FAIL 次"
    fi
    if [ $RECREATE_FAIL -gt 0 ]; then
        echo "  - Swapchain 重建失败: $RECREATE_FAIL 次"
    fi
    echo "  查看详细日志: cat $LOG_FILE | grep hw_vk_"
fi
echo ""

# 9. 检查降级事件
echo "9. 检查降级事件..."
DEGRADE=$(grep -c "Render degraded to software" "$LOG_FILE" || true)
DEGRADE=${DEGRADE:-0}
if [ $DEGRADE -eq 0 ]; then
    print_success "无降级事件"
else
    print_warning "检测到 $DEGRADE 次降级事件"
    echo "  降级原因:"
    grep "Render degraded to software" "$LOG_FILE" | sed 's/.*reason=\([^ ]*\).*/    - \1/' | sort | uniq -c
fi
echo ""

# 10. 总结
echo "=== 验证总结 ==="
if [ "$PRESENTER_INIT" -gt 0 ] && [ "$HW_RENDER_INIT" -gt 0 ] && [ $TOTAL_ERRORS -eq 0 ] && [ $DEGRADE -eq 0 ]; then
    print_success "快速验证通过"
    echo ""
    echo "建议:"
    echo "  1. 继续进行完整验证（旋转/前后台切换/分屏等）"
    echo "  2. 参考文档: docs/plans/2026-05-31-m5-vulkan-verification-plan.md"
    exit 0
elif [ "$PRESENTER_INIT" -gt 0 ] && [ "$HW_RENDER_INIT" -gt 0 ]; then
    print_warning "基础功能正常，但有部分问题"
    echo ""
    echo "建议:"
    echo "  1. 查看详细日志: cat $LOG_FILE"
    echo "  2. 分析日志: bash scripts/analyze_vulkan_logs.sh $LOG_FILE"
    echo "  3. 继续进行完整验证"
    exit 0
else
    print_error "快速验证失败"
    echo ""
    echo "建议:"
    echo "  1. 确认核心是否支持 Vulkan HW_RENDER"
    echo "  2. 查看详细日志: cat $LOG_FILE | grep -E 'VulkanContext|VulkanPresenter|VideoPipeline'"
    echo "  3. 检查设备 Vulkan 驱动是否正常"
    exit 1
fi
