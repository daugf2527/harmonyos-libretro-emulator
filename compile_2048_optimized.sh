#!/bin/bash

# Libretro 2048 核心编译脚本 (鸿蒙优化版)
# 完全适配鸿蒙 NDK,包含所有优化和验证
# 更新时间: 2025-12-08 13:01

set -e  # 遇到错误立即退出

echo "========================================="
echo "编译 Libretro 2048 核心 (鸿蒙 ARM64)"
echo "========================================="

# ========================================
# 配置路径
# ========================================
CORES_DIR="/Users/asd/libretro-cores"
CORE_NAME="libretro-2048"
PROJECT_DIR="/Users/asd/drawing-to-xcomponent"
OHOS_NDK="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"

# ========================================
# 设置环境变量
# ========================================
export OHOS_NDK_HOME="$OHOS_NDK"
export PATH="$OHOS_NDK/llvm/bin:$PATH"
export PATH="$OHOS_NDK/build-tools/cmake/bin:$PATH"

# ========================================
# 步骤 1: 验证环境
# ========================================
echo ""
echo "步骤 1: 验证环境..."
echo "----------------------------------------"

# 检查 NDK
if [ ! -d "$OHOS_NDK_HOME" ]; then
    echo "❌ 错误: 鸿蒙 NDK 不存在: $OHOS_NDK_HOME"
    exit 1
fi
echo "✅ NDK 路径: $OHOS_NDK_HOME"

# 检查工具链文件
if [ ! -f "$OHOS_NDK/build/cmake/ohos.toolchain.cmake" ]; then
    echo "❌ 错误: 找不到工具链文件!"
    exit 1
fi
echo "✅ 工具链文件存在"

# 检查 CMake
if ! command -v cmake &> /dev/null; then
    echo "❌ 错误: 找不到 CMake!"
    exit 1
fi
echo "✅ CMake 版本: $(cmake --version | head -1)"

# 检查源码目录
if [ ! -d "$CORES_DIR/$CORE_NAME" ]; then
    echo "❌ 错误: 源码目录不存在: $CORES_DIR/$CORE_NAME"
    echo "请先下载源码:"
    echo "  cd $CORES_DIR"
    echo "  git clone https://github.com/libretro/libretro-2048.git"
    exit 1
fi
echo "✅ 源码目录: $CORES_DIR/$CORE_NAME"

# ========================================
# 步骤 2: 准备优化的 CMakeLists.txt
# ========================================
echo ""
echo "步骤 2: 准备优化的 CMakeLists.txt..."
echo "----------------------------------------"

if [ -f "$PROJECT_DIR/CMakeLists_libretro_2048_harmonyos.txt" ]; then
    echo "✅ 找到优化的 CMakeLists.txt"
    cp "$PROJECT_DIR/CMakeLists_libretro_2048_harmonyos.txt" "$CORES_DIR/$CORE_NAME/CMakeLists.txt"
    echo "✅ 已替换为优化版本"
else
    echo "⚠️  未找到优化版本,使用原始 CMakeLists.txt"
fi

# ========================================
# 步骤 3: 进入源码目录
# ========================================
echo ""
echo "步骤 3: 进入源码目录..."
echo "----------------------------------------"
cd "$CORES_DIR/$CORE_NAME"
echo "当前目录: $(pwd)"

# ========================================
# 步骤 4: 清理旧构建
# ========================================
echo ""
echo "步骤 4: 清理旧构建..."
echo "----------------------------------------"
rm -rf build
mkdir build
cd build
echo "✅ 构建目录已创建"

# ========================================
# 步骤 5: 配置 CMake
# ========================================
echo ""
echo "步骤 5: 配置 CMake (鸿蒙工具链)..."
echo "----------------------------------------"
cmake .. \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK/build/cmake/ohos.toolchain.cmake" \
    -DOHOS_ARCH=arm64-v8a \
    -DOHOS_PLATFORM=OHOS \
    -DOHOS_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON

if [ $? -ne 0 ]; then
    echo "❌ CMake 配置失败!"
    exit 1
fi
echo "✅ CMake 配置成功"

# ========================================
# 步骤 6: 编译
# ========================================
echo ""
echo "步骤 6: 编译..."
echo "----------------------------------------"
cmake --build . -j8

if [ $? -ne 0 ]; then
    echo "❌ 编译失败!"
    exit 1
fi
echo "✅ 编译成功"

# ========================================
# 步骤 7: 验证编译结果
# ========================================
echo ""
echo "步骤 7: 验证编译结果..."
echo "----------------------------------------"

if [ ! -f "lib2048_libretro.so" ]; then
    echo "❌ 错误: 找不到编译输出 lib2048_libretro.so!"
    echo "查找所有 .so 文件:"
    find . -name "*.so"
    exit 1
fi

echo "✅ 找到编译产物"
echo ""
echo "文件信息:"
ls -lh lib2048_libretro.so
echo ""
echo "文件类型:"
file lib2048_libretro.so

# ========================================
# 步骤 8: 检查符号导出
# ========================================
echo ""
echo "步骤 8: 检查符号导出..."
echo "----------------------------------------"
echo "导出的 Libretro API 函数:"
nm -D lib2048_libretro.so 2>/dev/null | grep " T retro_" | head -15 || {
    echo "⚠️  nm 命令失败,尝试使用 llvm-nm..."
    "$OHOS_NDK/llvm/bin/llvm-nm" -D lib2048_libretro.so 2>/dev/null | grep " T retro_" | head -15 || echo "⚠️  无法读取符号"
}

# ========================================
# 步骤 9: 创建备份目录
# ========================================
echo ""
echo "步骤 9: 创建备份..."
echo "----------------------------------------"
mkdir -p "$CORES_DIR/compiled/arm64-v8a"
cp lib2048_libretro.so "$CORES_DIR/compiled/arm64-v8a/"
echo "✅ 已备份到: $CORES_DIR/compiled/arm64-v8a/"

# ========================================
# 步骤 10: 复制到鸿蒙项目
# ========================================
echo ""
echo "步骤 10: 复制到鸿蒙项目..."
echo "----------------------------------------"
mkdir -p "$PROJECT_DIR/entry/libs/arm64-v8a"
cp lib2048_libretro.so "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

if [ $? -ne 0 ]; then
    echo "❌ 复制失败!"
    exit 1
fi
echo "✅ 已复制到: $PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

# ========================================
# 步骤 11: 最终验证
# ========================================
echo ""
echo "步骤 11: 最终验证..."
echo "----------------------------------------"

TARGET_FILE="$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

echo "文件信息:"
ls -lh "$TARGET_FILE"
echo ""
echo "文件类型:"
file "$TARGET_FILE"
echo ""
echo "MD5 校验:"
md5 "$TARGET_FILE" || md5sum "$TARGET_FILE" 2>/dev/null || echo "⚠️  无法计算 MD5"

# ========================================
# 步骤 12: 检查依赖
# ========================================
echo ""
echo "步骤 12: 检查依赖库..."
echo "----------------------------------------"

# 尝试使用 readelf
if command -v readelf &> /dev/null; then
    echo "依赖的动态库:"
    readelf -d "$TARGET_FILE" 2>/dev/null | grep NEEDED || echo "✅ 无外部依赖 (只依赖系统库)"
else
    # 尝试使用 llvm-readelf
    if [ -f "$OHOS_NDK/llvm/bin/llvm-readelf" ]; then
        echo "依赖的动态库:"
        "$OHOS_NDK/llvm/bin/llvm-readelf" -d "$TARGET_FILE" 2>/dev/null | grep NEEDED || echo "✅ 无外部依赖"
    else
        echo "⚠️  无法检查依赖 (readelf 不可用)"
    fi
fi

# ========================================
# 完成
# ========================================
echo ""
echo "========================================="
echo "✅ 编译完成!"
echo "========================================="
echo ""
echo "📦 输出文件:"
echo "  - 备份: $CORES_DIR/compiled/arm64-v8a/lib2048_libretro.so"
echo "  - 项目: $PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"
echo ""
echo "📊 文件信息:"
ls -lh "$TARGET_FILE"
echo ""
echo "🚀 下一步:"
echo "  1. 在 DevEco Studio 中 Clean Project"
echo "  2. Rebuild Project"
echo "  3. 运行应用,测试 CoreLoader"
echo ""
echo "🔍 预期日志:"
echo "  [CoreLoader] Loading Libretro core: /data/storage/el1/bundle/libs/arm64-v8a/libretro_2048.so"
echo "  [CoreLoader] dlopen succeeded! ✅"
echo "  [CoreLoader] Core loaded successfully!"
echo "  [CoreLoader] Name: 2048"
echo "  [CoreLoader] Version: v1.0"
echo ""
echo "========================================="
