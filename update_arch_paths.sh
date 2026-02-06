#!/bin/bash

# 批量更新文档中的架构路径
# 将 libs/arm64 替换为 libs/arm64-v8a

echo "========================================="
echo "更新文档中的架构路径"
echo "arm64 → arm64-v8a"
echo "========================================="

# 需要更新的文档列表
files=(
    "LIBRETRO_CORE_COMPILE_GUIDE.md"
    "PHASE3_1_DOWNLOAD_GUIDE.md"
    "PHASE3_1_FINAL_TEST.md"
    "PHASE3_1_PACKAGING_FIX.md"
    "PHASE3_1_CORELOADER.md"
    "PHASE3_TECH_VERIFICATION.md"
)

# 备份并替换
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "处理: $file"
        
        # 备份
        cp "$file" "$file.bak"
        
        # 替换 libs/arm64 为 libs/arm64-v8a
        sed -i '' 's|libs/arm64/|libs/arm64-v8a/|g' "$file"
        sed -i '' 's|libs/arm64\b|libs/arm64-v8a|g' "$file"
        
        echo "  ✅ 已更新"
    else
        echo "  ⚠️  文件不存在: $file"
    fi
done

echo "========================================="
echo "✅ 更新完成!"
echo "========================================="
echo ""
echo "备份文件: *.bak"
echo "如需恢复,运行: for f in *.bak; do mv \"\$f\" \"\${f%.bak}\"; done"
