#!/bin/bash

# Gambatte 测试 ROM 下载脚本
# 下载开源的 Game Boy ROM 用于测试

echo "=== Gambatte 测试 ROM 下载脚本 ==="
echo ""

# 创建临时目录
TEMP_DIR=$(mktemp -d)
echo "临时目录: $TEMP_DIR"

# 1. 下载 Snake ROM
echo ""
echo "1. 下载 Snake (贪吃蛇) ROM..."
echo "   项目: https://github.com/raph080/gbSnake"
echo "   许可: Apache-2.0"

# 尝试从 GitHub Releases 下载
if curl -L -o "$TEMP_DIR/snake.gb" "https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb" 2>/dev/null; then
    if [ -f "$TEMP_DIR/snake.gb" ] && [ -s "$TEMP_DIR/snake.gb" ]; then
        mv "$TEMP_DIR/snake.gb" ./snake.gb
        echo "   ✅ Snake ROM 下载成功"
    else
        echo "   ❌ Snake ROM 下载失败（文件为空）"
        echo "   请手动下载: https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb"
    fi
else
    echo "   ❌ Snake ROM 下载失败"
    echo "   请手动下载: https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb"
fi

# 2. 提示其他 ROM
echo ""
echo "2. 其他推荐的测试 ROM:"
echo ""
echo "   Tobu Tobu Girl (平台游戏):"
echo "   - 下载: https://tangramgames.itch.io/tobu-tobu-girl"
echo "   - 许可: MIT"
echo ""
echo "   Adjustris (俄罗斯方块克隆):"
echo "   - 项目: https://github.com/tbsp/simple-gb-asm-demo"
echo "   - 许可: MIT"
echo ""

# 清理
rm -rf "$TEMP_DIR"

# 检查结果
echo ""
echo "=== 下载完成 ==="
echo ""
echo "当前目录中的 ROM 文件:"
ls -lh *.gb 2>/dev/null || echo "  (无 ROM 文件)"
echo ""
echo "使用方法:"
echo "  1. 确保有 .gb 或 .gbc ROM 文件在此目录"
echo "  2. 运行 Gambatte 测试程序"
echo "  3. 测试程序会自动加载 ROM"
echo ""
