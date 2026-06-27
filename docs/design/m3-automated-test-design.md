# M3: 自动化测试脚本设计

**日期**: 2026-05-31  
**状态**: 📋 设计完成  
**关联任务**: M3 任务 42 - 实现自动化测试脚本

---

## 1. 设计目标

为 M3 核心兼容矩阵提供自动化测试能力，验证核心加载和 ROM 启动功能。

### 核心目标

1. **自动化核心加载测试**: 遍历所有核心 .so 文件，验证 dlopen/dlsym 成功
2. **自动化 ROM 启动测试**: 遍历测试 ROM 清单，验证 retro_load_game 成功
3. **结构化测试报告**: 输出 JSON 格式报告，支持 CI 集成
4. **手工验证流程**: 提供真机验证步骤，补充自动化测试无法覆盖的维度（画面/音频/输入）

---

## 2. 测试架构

### 2.1 测试层次

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Bash 测试脚本 (CI 环境)                        │
│  - 核心文件存在性检查                                     │
│  - ROM 文件存在性检查                                     │
│  - 生成测试清单                                          │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 2: ArkTS 测试脚本 (真机环境)                      │
│  - 调用 NAPI 接口 (refactoredLoadCore/refactoredLoadRom) │
│  - 收集测试结果                                          │
│  - 输出 JSON 报告                                        │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 3: 手工验证 (真机环境)                            │
│  - 画面输出验证 (目视)                                    │
│  - 音频输出验证 (耳机)                                    │
│  - 输入响应验证 (虚拟手柄)                                │
│  - 稳定性验证 (5 分钟运行)                                │
└─────────────────────────────────────────────────────────┘
```

### 2.2 测试范围

| 测试维度 | 自动化支持 | 验证方法 |
|---------|-----------|---------|
| **T1: 核心加载** | ✅ 完全自动化 | NAPI `refactoredLoadCore` 返回值 + 日志 |
| **T2: ROM 启动** | ✅ 完全自动化 | NAPI `refactoredLoadRom` 返回值 + 日志 |
| **T3: 画面输出** | ❌ 需手工验证 | 目视确认画面正常 |
| **T4: 音频输出** | ❌ 需手工验证 | 耳机确认音频正常 |
| **T5: 输入响应** | ❌ 需手工验证 | 虚拟手柄/物理按键有反馈 |
| **T6: 稳定性** | ❌ 需手工验证 | 运行 5 分钟无崩溃 |

---

## 3. Layer 1: Bash 测试脚本

### 3.1 脚本设计

**文件**: `scripts/test/check_core_compatibility.sh`

**功能**:
1. 扫描 `entry/build/default/intermediates/libs/default/arm64/*.so` 核心文件
2. 扫描本地测试 ROM 目录（默认 `build/test-roms/**/*`，可由 `M3_TEST_ROMS_DIR` 覆盖）
3. 生成测试清单 JSON
4. 验证核心文件与兼容矩阵一致性

**输出**: `build/test-manifest.json`

### 3.2 脚本伪代码

```bash
#!/bin/bash
# scripts/test/check_core_compatibility.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORES_DIR="$REPO_ROOT/entry/build/default/intermediates/libs/default/arm64"
ROMS_DIR="${M3_TEST_ROMS_DIR:-$REPO_ROOT/build/test-roms}"
OUTPUT_JSON="$REPO_ROOT/build/test-manifest.json"

# 1. 扫描核心文件
echo "=== Scanning libretro cores ==="
CORES=$(find "$CORES_DIR" -name "*_libretro*.so" -type f 2>/dev/null | sort)
CORE_COUNT=$(echo "$CORES" | wc -l)
echo "Found $CORE_COUNT cores"

# 2. 扫描 ROM 文件
echo "=== Scanning ROM files ==="
ROMS=$(find "$ROMS_DIR" -type f \
  \( -name "*.gb" -o -name "*.gbc" -o -name "*.gba" \
  -o -name "*.nes" -o -name "*.smc" -o -name "*.gen" \
  -o -name "*.zip" -o -name "*.ngp" \) 2>/dev/null | sort)
ROM_COUNT=$(echo "$ROMS" | wc -l)
echo "Found $ROM_COUNT ROMs"

# 3. 生成测试清单 JSON
echo "=== Generating test manifest ==="
mkdir -p "$(dirname "$OUTPUT_JSON")"

cat > "$OUTPUT_JSON" <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cores": [
$(echo "$CORES" | while read -r core; do
  basename=$(basename "$core")
  echo "    {\"file\": \"$basename\", \"path\": \"$core\"},"
done | sed '$ s/,$//')
  ],
  "roms": [
$(echo "$ROMS" | while read -r rom; do
  basename=$(basename "$rom")
  relpath="${rom#$ROMS_DIR/}"
  echo "    {\"file\": \"$basename\", \"path\": \"$relpath\"},"
done | sed '$ s/,$//')
  ]
}
EOF

echo "Test manifest written to: $OUTPUT_JSON"
echo "=== Check complete ==="
```

### 3.3 CI 集成

在 `.github/workflows/harmonyos-pr-ci.yml` 中添加：

```yaml
- name: Generate test manifest
  run: bash scripts/test/check_core_compatibility.sh

- name: Upload test manifest
  uses: actions/upload-artifact@v3
  with:
    name: test-manifest
    path: build/test-manifest.json
```

---

## 4. Layer 2: ArkTS 测试脚本

### 4.1 脚本设计

**文件**: `entry/src/main/ets/test/CoreCompatibilityTest.ets`

**功能**:
1. 读取测试清单 JSON
2. 遍历核心列表，调用 `refactoredLoadCore`
3. 遍历 ROM 列表，调用 `refactoredLoadRom`
4. 收集测试结果，输出 JSON 报告

**输出**: `files/test-results.json`

### 4.2 脚本伪代码

```typescript
// entry/src/main/ets/test/CoreCompatibilityTest.ets

import libentry from 'libentry.so'
import resourceManager from '@ohos.resourceManager'
import fs from '@ohos.file.fs'

interface TestResult {
  core_id: string
  core_file: string
  load_success: boolean
  error_message?: string
  rom_tests?: RomTestResult[]
}

interface RomTestResult {
  rom_file: string
  load_success: boolean
  error_message?: string
}

export class CoreCompatibilityTest {
  private resMgr: resourceManager.ResourceManager
  private filesDir: string
  private results: TestResult[] = []

  constructor(resMgr: resourceManager.ResourceManager, filesDir: string) {
    this.resMgr = resMgr
    this.filesDir = filesDir
  }

  /**
   * 测试单个核心加载
   */
  async testCoreLoad(coreFile: string): Promise<boolean> {
    console.info(`[Test] Testing core: ${coreFile}`)
    
    try {
      // 1. 启动引擎
      const started = libentry.refactoredStartEngine()
      if (!started) {
        console.error(`[Test] Failed to start engine for ${coreFile}`)
        return false
      }

      // 2. 加载核心
      const corePath = `${this.filesDir}/../libs/arm64/${coreFile}`
      const loaded = libentry.refactoredLoadCore(corePath)
      
      // 3. 停止引擎
      await libentry.refactoredStopEngineAsync()
      libentry.refactoredResetEngine()

      return loaded
    } catch (err) {
      console.error(`[Test] Exception testing ${coreFile}: ${err}`)
      return false
    }
  }

  /**
   * 测试单个 ROM 启动
   */
  async testRomLoad(coreFile: string, romPath: string): Promise<boolean> {
    console.info(`[Test] Testing ROM: ${romPath} with core: ${coreFile}`)
    
    try {
      // 1. 启动引擎
      const started = libentry.refactoredStartEngine()
      if (!started) {
        return false
      }

      // 2. 加载核心
      const corePath = `${this.filesDir}/../libs/arm64/${coreFile}`
      const coreLoaded = libentry.refactoredLoadCore(corePath)
      if (!coreLoaded) {
        await libentry.refactoredStopEngineAsync()
        libentry.refactoredResetEngine()
        return false
      }

      // 3. 加载 ROM (rawfile 路径)
      const romLoaded = libentry.refactoredLoadRom(romPath, this.resMgr)
      
      // 4. 停止引擎
      await libentry.refactoredStopEngineAsync()
      libentry.refactoredResetEngine()

      return romLoaded
    } catch (err) {
      console.error(`[Test] Exception testing ROM ${romPath}: ${err}`)
      return false
    }
  }

  /**
   * 运行完整测试套件
   */
  async runFullTest(): Promise<void> {
    console.info('[Test] === Starting Core Compatibility Test ===')

    // P0 核心测试清单
    const p0Cores = [
      { id: 'gambatte', file: 'gambatte_libretro.ohos-arm64.so', roms: ['roms/gb_gbc/snake_v0.1.gb'] },
      { id: 'mgba', file: 'mgba_libretro.ohos-arm64.so', roms: ['roms/gba/Anguna.gba'] },
      { id: 'fceumm', file: 'fceumm_libretro.ohos-arm64.so', roms: ['roms/nes/Alter_Ego.nes'] },
      { id: 'nestopia', file: 'nestopia_libretro.ohos-arm64.so', roms: ['roms/nes/Alter_Ego.nes'] },
      { id: 'snes9x', file: 'snes9x_libretro.ohos-arm64.so', roms: ['roms/snes/Classic_Kong.smc'] },
      { id: 'genesis_plus_gx', file: 'genesis_plus_gx_libretro.ohos-arm64.so', roms: ['roms/md/30years.gen'] },
    ]

    for (const core of p0Cores) {
      const result: TestResult = {
        core_id: core.id,
        core_file: core.file,
        load_success: false,
        rom_tests: []
      }

      // 测试核心加载
      result.load_success = await this.testCoreLoad(core.file)
      
      if (result.load_success) {
        console.info(`[Test] ✅ Core ${core.id} loaded successfully`)
        
        // 测试 ROM 加载
        for (const romPath of core.roms) {
          const romResult: RomTestResult = {
            rom_file: romPath,
            load_success: false
          }
          
          romResult.load_success = await this.testRomLoad(core.file, romPath)
          
          if (romResult.load_success) {
            console.info(`[Test] ✅ ROM ${romPath} loaded successfully`)
          } else {
            console.error(`[Test] ❌ ROM ${romPath} failed to load`)
          }
          
          result.rom_tests!.push(romResult)
        }
      } else {
        console.error(`[Test] ❌ Core ${core.id} failed to load`)
      }

      this.results.push(result)
    }

    // 输出测试报告
    await this.writeReport()
    console.info('[Test] === Core Compatibility Test Complete ===')
  }

  /**
   * 写入测试报告
   */
  private async writeReport(): Promise<void> {
    const report = {
      generated_at: new Date().toISOString(),
      summary: {
        total_cores: this.results.length,
        passed_cores: this.results.filter(r => r.load_success).length,
        total_roms: this.results.reduce((sum, r) => sum + (r.rom_tests?.length || 0), 0),
        passed_roms: this.results.reduce((sum, r) => 
          sum + (r.rom_tests?.filter(rt => rt.load_success).length || 0), 0)
      },
      results: this.results
    }

    const reportPath = `${this.filesDir}/test-results.json`
    const file = fs.openSync(reportPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
    fs.writeSync(file.fd, JSON.stringify(report, null, 2))
    fs.closeSync(file)

    console.info(`[Test] Report written to: ${reportPath}`)
  }
}
```

### 4.3 测试页面集成

在 `entry/src/main/ets/pages/TestPage.ets` 中添加测试入口：

```typescript
import { CoreCompatibilityTest } from '../test/CoreCompatibilityTest'

@Entry
@Component
struct TestPage {
  @State testRunning: boolean = false
  @State testResults: string = ''

  async runTest() {
    this.testRunning = true
    this.testResults = 'Running tests...'

    try {
      const resMgr = getContext(this).resourceManager
      const filesDir = getContext(this).filesDir
      
      const test = new CoreCompatibilityTest(resMgr, filesDir)
      await test.runFullTest()
      
      this.testResults = 'Test complete! Check hilog for details.'
    } catch (err) {
      this.testResults = `Test failed: ${err}`
    } finally {
      this.testRunning = false
    }
  }

  build() {
    Column() {
      Text('Core Compatibility Test')
        .fontSize(24)
        .margin({ bottom: 20 })

      Button('Run Test')
        .enabled(!this.testRunning)
        .onClick(() => this.runTest())

      Text(this.testResults)
        .margin({ top: 20 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }
}
```

---

## 5. Layer 3: 手工验证流程

### 5.1 验证清单

对每个 P0 核心执行以下步骤：

#### 步骤 1: 准备环境

- [ ] 真机环境（HarmonyOS API 12+）
- [ ] 安装最新 HAP（Debug 或 Release）
- [ ] 准备测试 ROM（见兼容矩阵）
- [ ] 启用 hilog 过滤：`hdc shell hilog -x | grep -E "LibretroEngine|CoreLoader"`

#### 步骤 2: 核心加载验证（T1）

1. 启动应用 → 进入 LibraryPage
2. 选择对应平台的测试 ROM
3. 观察日志：
   ```
   [LibretroEngine] LoadCore: /data/storage/el1/bundle/libs/arm64/gambatte_libretro.ohos-arm64.so
   [CoreLoader] dlopen success
   [CoreLoader] All function pointers valid
   ```
4. 记录结果：✅ 通过 / ❌ 失败

#### 步骤 3: ROM 启动验证（T2）

1. 观察日志：
   ```
   [LibretroEngine] LoadGame: roms/gb_gbc/snake_v0.1.gb
   [LibretroEngine] retro_load_game: true
   [LibretroEngine] State: RUNNING
   ```
2. 记录结果：✅ 通过 / ❌ 失败

#### 步骤 4: 画面输出验证（T3）

1. 目视确认画面正常（不黑屏/花屏）
2. 截图保存到 `docs/test-screenshots/`
3. 记录结果：✅ 通过 / ❌ 失败

#### 步骤 5: 音频输出验证（T4）

1. 插入耳机
2. 确认音频正常（不静音/爆音）
3. 记录结果：✅ 通过 / ❌ 失败

#### 步骤 6: 输入响应验证（T5）

1. 按虚拟手柄按键
2. 观察游戏响应
3. 记录结果：✅ 通过 / ❌ 失败

#### 步骤 7: 稳定性验证（T6）

1. 运行 5 分钟
2. 观察日志无 crash
3. UI 无 ANR
4. 记录结果：✅ 通过 / ❌ 失败

### 5.2 验证矩阵模板

```markdown
| 核心 ID | T1 加载 | T2 启动 | T3 画面 | T4 音频 | T5 输入 | T6 稳定 | 通过标准 | 备注 |
|---------|---------|---------|---------|---------|---------|---------|----------|------|
| gambatte | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | P2 | 完全通过 |
| mgba | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | P1 | 5 分钟后偶现卡顿 |
| fceumm | ✅ | ✅ | ✅ | ❌ | ✅ | - | P0 | 音频爆音 |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |
```

---

## 6. 测试报告格式

### 6.1 JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "generated_at": {
      "type": "string",
      "format": "date-time",
      "description": "报告生成时间 (ISO 8601)"
    },
    "summary": {
      "type": "object",
      "properties": {
        "total_cores": { "type": "integer" },
        "passed_cores": { "type": "integer" },
        "total_roms": { "type": "integer" },
        "passed_roms": { "type": "integer" }
      },
      "required": ["total_cores", "passed_cores", "total_roms", "passed_roms"]
    },
    "results": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "core_id": { "type": "string" },
          "core_file": { "type": "string" },
          "load_success": { "type": "boolean" },
          "error_message": { "type": "string" },
          "rom_tests": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "rom_file": { "type": "string" },
                "load_success": { "type": "boolean" },
                "error_message": { "type": "string" }
              },
              "required": ["rom_file", "load_success"]
            }
          }
        },
        "required": ["core_id", "core_file", "load_success"]
      }
    }
  },
  "required": ["generated_at", "summary", "results"]
}
```

### 6.2 示例报告

```json
{
  "generated_at": "2026-05-31T10:30:00Z",
  "summary": {
    "total_cores": 8,
    "passed_cores": 7,
    "total_roms": 9,
    "passed_roms": 8
  },
  "results": [
    {
      "core_id": "gambatte",
      "core_file": "gambatte_libretro.ohos-arm64.so",
      "load_success": true,
      "rom_tests": [
        {
          "rom_file": "roms/gb_gbc/snake_v0.1.gb",
          "load_success": true
        }
      ]
    },
    {
      "core_id": "mgba",
      "core_file": "mgba_libretro.ohos-arm64.so",
      "load_success": true,
      "rom_tests": [
        {
          "rom_file": "roms/gba/Anguna.gba",
          "load_success": true
        }
      ]
    },
    {
      "core_id": "fceumm",
      "core_file": "fceumm_libretro.ohos-arm64.so",
      "load_success": false,
      "error_message": "dlopen failed: library not found"
    }
  ]
}
```

---

## 7. 使用指南

### 7.1 CI 环境（自动化）

```bash
# 1. 生成测试清单
bash scripts/test/check_core_compatibility.sh

# 2. 查看测试清单
cat build/test-manifest.json
```

### 7.2 真机环境（半自动化）

```bash
# 1. 安装 HAP
hdc install entry-default-signed.hap

# 2. 启动应用，进入 TestPage

# 3. 点击 "Run Test" 按钮

# 4. 查看 hilog 输出
hdc shell hilog -x | grep -E "\[Test\]"

# 5. 拉取测试报告
hdc file recv /data/storage/el2/base/haps/entry/files/test-results.json ./test-results.json

# 6. 查看报告
cat test-results.json | jq .
```

### 7.3 手工验证（完整）

按照 **5.1 验证清单** 逐项执行，填写 **5.2 验证矩阵模板**。

---

## 8. 已知限制

### 8.1 自动化测试限制

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **无法验证画面输出** | T3 维度缺失 | 手工验证 + 截图 |
| **无法验证音频输出** | T4 维度缺失 | 手工验证 + 耳机 |
| **无法验证输入响应** | T5 维度缺失 | 手工验证 + 虚拟手柄 |
| **无法验证长时稳定性** | T6 维度缺失 | 手工验证 + 5 分钟运行 |
| **依赖真机环境** | CI 无法运行 ArkTS 测试 | 本地真机执行 |

### 8.2 测试覆盖风险

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| **测试 ROM 不代表所有 ROM** | 高 | 用户报告兼容性问题 | 文档说明"测试覆盖有限" |
| **真机环境差异** | 中 | 不同设备表现不一致 | 多设备验证（至少 2 台） |
| **自动化测试假阳性** | 低 | 核心加载成功但实际不可用 | 手工验证补充 |

---

## 9. 后续优化方向

### 9.1 短期（M3 完成后）

- [ ] 补充 P1 核心的测试用例
- [ ] 多设备验证（至少 2 台真机）
- [ ] 记录每个核心的性能基线（FPS/内存）

### 9.2 中期（M4-M6）

- [ ] 截图对比自动化（基于 OpenCV）
- [ ] 音频波形对比自动化（基于 FFT）
- [ ] 扩展测试 ROM 清单（每平台 3+ ROM）

### 9.3 长期（M7+）

- [ ] CI 集成真机测试（通过 hdc 远程执行）
- [ ] 兼容性数据库（ROM 黑名单/白名单）
- [ ] 社区反馈收集（GitHub Issues）

---

## 10. 参考资料

### 10.1 内部文档

- `docs/design/m3-core-compatibility-matrix.md` - 核心兼容矩阵
- `entry/src/main/cpp/tests/unit/core_loader_test.cpp` - C++ 核心加载测试
- `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp` - NAPI 接口实现
- `entry/src/main/ets/common/LibretroCoreCatalog.ets` - 核心清单

### 10.2 外部资源

- [Libretro Docs](https://docs.libretro.com/) - 官方文档
- [HarmonyOS NAPI](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/napi-guidelines-V5) - NAPI 开发指南

---

## 附录 A: 快速验证命令

### A.1 日志过滤

```bash
# 核心加载日志
hdc shell hilog -x | grep -E "LoadCore|dlopen|dlsym"

# ROM 启动日志
hdc shell hilog -x | grep -E "LoadGame|retro_load_game"

# 画面输出日志
hdc shell hilog -x | grep -E "VideoPipeline|retro_video_refresh"

# 音频输出日志
hdc shell hilog -x | grep -E "AudioBridge|retro_audio_sample"

# 崩溃日志
hdc shell hilog -x | grep -E "FATAL|CRASH|SIGSEGV"
```

### A.2 性能监控

```bash
# CPU 使用率
hdc shell top -n 1 | grep com.libretro.harmonyos

# 内存使用
hdc shell dumpsys mem | grep com.libretro.harmonyos

# FPS 监控（从日志提取）
hdc shell hilog -x | grep "FPS:"
```

---

**文档版本**: v1.0  
**最后更新**: 2026-05-31  
**维护者**: Codex Bot
