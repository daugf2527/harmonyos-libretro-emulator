#!/bin/bash

# 为鸿蒙编译 Libretro 2048 核心
# 使用鸿蒙 NDK 工具链
# 更新时间: 2025-12-08 13:01

set -e  # 遇到错误立即退出

echo "========================================="
echo "为鸿蒙编译 Libretro 2048 核心"
echo "========================================="

# 1. 设置环境变量
export OHOS_NDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
export PATH="$OHOS_NDK_HOME/llvm/bin:$PATH"
export PATH="$OHOS_NDK_HOME/build-tools/cmake/bin:$PATH"

# 2. 检查 NDK 是否存在
if [ ! -d "$OHOS_NDK_HOME" ]; then
    echo "❌ 错误: 鸿蒙 NDK 不存在: $OHOS_NDK_HOME"
    exit 1
fi

echo "✅ 鸿蒙 NDK 路径: $OHOS_NDK_HOME"

# 3. 设置路径
CORES_DIR="/Users/asd/libretro-cores"
CORE_2048_DIR="$CORES_DIR/libretro-2048"
PROJECT_DIR="/Users/asd/drawing-to-xcomponent"

# 4. 检查源码目录
if [ ! -d "$CORE_2048_DIR" ]; then
    echo "❌ 错误: 2048 核心源码不存在: $CORE_2048_DIR"
    echo "请先下载源码:"
    echo "  cd $CORES_DIR"
    echo "  git clone https://github.com/libretro/libretro-2048.git"
    exit 1
fi

echo "✅ 2048 核心源码: $CORE_2048_DIR"

# 5. 进入源码目录
cd "$CORE_2048_DIR"

# 6. 清理旧的构建
echo ""
echo "步骤 1: 清理旧的构建..."
rm -rf build
mkdir build
cd build

# 6.5. 复制优化的 CMakeLists.txt
echo ""
echo "步骤 1.5: 使用优化的 CMakeLists.txt..."
if [ -f "$PROJECT_DIR/CMakeLists_libretro_2048_harmonyos.txt" ]; then
    cp "$PROJECT_DIR/CMakeLists_libretro_2048_harmonyos.txt" "$CORE_2048_DIR/CMakeLists.txt"
    echo "✅ 已复制优化的 CMakeLists.txt"
else
    echo "⚠️  使用原始 CMakeLists.txt"
fi

# 7. 配置 CMake (使用鸿蒙工具链)
echo ""
echo "步骤 2: 配置 CMake (鸿蒙工具链)..."
cmake .. \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK_HOME/build/cmake/ohos.toolchain.cmake" \
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

# 8. 编译
echo ""
echo "步骤 3: 编译..."
cmake --build . -j8

if [ $? -ne 0 ]; then
    echo "❌ 编译失败!"
    exit 1
fi

echo "✅ 编译成功"

# 9. 检查生成的文件
if [ ! -f "lib2048_libretro.so" ]; then
    echo "❌ 错误: 编译产物不存在: lib2048_libretro.so"
    exit 1
fi

# 10. 显示文件信息
echo ""
echo "步骤 4: 检查编译产物..."
ls -lh lib2048_libretro.so
file lib2048_libretro.so

# 11. 复制到项目
echo ""
echo "步骤 5: 复制到鸿蒙项目..."
mkdir -p "$PROJECT_DIR/entry/libs/arm64-v8a"
cp lib2048_libretro.so "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

if [ $? -ne 0 ]; then
    echo "❌ 复制失败!"
    exit 1
fi

echo "✅ 已复制到: $PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

# 12. 验证
echo ""
echo "步骤 6: 验证..."
echo "文件信息:"
ls -lh "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"
echo ""
echo "文件类型:"
file "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"

# 13. 检查符号导出
echo ""
echo "步骤 7: 检查符号导出..."
echo "导出的 Libretro API 函数:"
nm -D "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so" 2>/dev/null | grep " T retro_" | head -15 || echo "⚠️  无法读取符号 (可能需要 llvm-nm)"

# 14. 使用 readelf 检查 (如果可用)
echo ""
echo "步骤 8: 检查依赖库..."
if command -v readelf &> /dev/null; then
    echo "依赖的动态库:"
    readelf -d "$PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so" 2>/dev/null | grep NEEDED || echo "无外部依赖"
else
    echo "⚠️  readelf 不可用,跳过依赖检查"
fi

echo ""
echo "========================================="
echo "✅ 编译完成!"
echo "========================================="
echo ""
echo "输出文件: $PROJECT_DIR/entry/libs/arm64-v8a/libretro_2048.so"
echo ""
echo "下一步:"
echo "1. 在 DevEco Studio 中 Clean Project"
echo "2. Rebuild Project"
echo "3. 运行测试"
echo ""
