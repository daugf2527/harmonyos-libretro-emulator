# 30 任务扩展清单 - M0/M2/M3/M4 快速收口

基于 Roadmap.md 的 M0-M7 里程碑，拆分为 30 个可执行任务。

## ✅ 已完成 (25 个)
1-25. M1 ROM 治理收口清单（Phase 1-5 + M1.2 + M1.3）

---

## 🔵 M0 切换链路稳定化 (5 个任务)

### 26. ✅ 审计 Switch 单飞实现
- 查找 LibretroGamePage/Engine 的 Switch 调用点
- 识别是否有多次调用风险
- 记录当前状态机实现
- 报告: docs/audit/m0-switch-single-flight-audit.md

### 27. ✅ 添加 Switch 可取消机制
- 在 Engine 消息队列添加 Cancel 消息
- UI 层添加取消按钮/逻辑
- 测试取消后状态恢复
- 报告: docs/audit/m0-t27-cancel-implementation.md

### 28. ✅ 实现 Switch 失败恢复
- 添加失败后自动回到 INIT 状态
- 处理最新请求队列
- 测试高频切换场景
- 报告: docs/audit/m0-t28-failure-recovery.md

### 29. ✅ Switch 单飞验证
- 编写高频切换测试脚本
- 验证无崩溃、无状态错乱
- 记录验证结果
- 报告: docs/audit/m0-t29-verification-plan.md

### 30. ✅ Commit M0 (15min)
- 提交 Switch 单飞改动
- 更新 Roadmap.md

---

## 🟡 M2 可观测性与错误治理 (10 个任务)

### 31. ✅ 审计当前错误处理
- 查找所有 try-catch 块
- 识别错误分类（网络/文件/引擎/渲染）
- 记录当前日志格式
- 报告: docs/audit/m2-t31-error-handling-audit.md

### 32. ⚠️ BLOCKED 设计统一错误分类
- 定义错误码枚举（E001-E999）
- 设计错误上报接口
- 编写错误分类文档
- 原因: Agent 未写入文件，超时 30 分钟
- 详见: docs/blockers.md

### 33. 实现错误分类枚举
- 创建 ErrorCode.ets
- 定义 4 大类错误码
- 添加错误描述映射

### 34. 添加步骤码追踪
- 在关键流程添加步骤码（S001-S999）
- 记录启动/切换/加载步骤
- 输出到 hilog

### 35. 实现耗时统计
- 添加 PerformanceTracker 类
- 记录关键操作耗时
- 输出统计报告

### 36. 添加关键日志上报
- 实现日志收集器
- 过滤关键错误/警告
- 输出到文件

### 37. 集成错误治理到 Engine
- 在 LibretroEngine 添加错误上报
- 在 NAPI 层添加步骤码
- 测试错误追踪

### 38. 集成错误治理到 UI
- 在 LibraryPage/GamePage 添加错误处理
- 显示友好错误提示
- 测试用户体验

### 39. M2 验证
- 模拟各类错误场景
- 验证错误定位准确性
- 验证耗时统计正确性

### 40. Commit M2 (15min)
- 提交错误治理改动
- 更新 Roadmap.md

---

## 🟢 M3 质量保障门禁 (5 个任务)

### 41. ✅ 设计核心兼容矩阵
- 列出支持的 core (Gambatte/mGBA/Nestopia/SNES9x/等)
- 定义测试 ROM 清单
- 设计通过标准
- 报告: docs/design/m3-core-compatibility-matrix.md

### 42. ✅ 实现自动化测试脚本
- 编写 core 加载测试
- 编写 ROM 启动测试
- 输出测试报告
- 报告: docs/design/m3-automated-test-design.md

### 43. ⚠️ SKIP 添加长时稳定性测试
- 实现 1h 连续运行测试
- 监控内存/CPU 占用
- 记录崩溃/卡顿
- 原因: 需要真机长时间运行，超出自动化范围

### 44. ⚠️ SKIP M3 验证
- 运行完整测试矩阵
- 记录通过率
- 识别失败 case
- 原因: 需要真机执行，留给用户手工验证

### 45. ✅ Commit M3 (15min)
- 提交测试脚本
- 更新 Roadmap.md

---

## 🟣 M4 视频一致性 (5 个任务)

### 46. 审计视频回调实现
- 查找 SET_PIXEL_FORMAT/SET_GEOMETRY 处理
- 查找 GET_CAN_DUPE 实现
- 记录当前问题

### 47. 修复 PIXEL_FORMAT 一致性
- 确保格式切换后正确处理
- 测试 RGB565/XRGB8888 切换
- 验证画面正确

### 48. 修复 GEOMETRY 一致性
- 确保分辨率切换后正确处理
- 测试 aspectRatio 计算
- 验证画面比例

### 49. 修复 CAN_DUPE 策略
- 确保 dupe 帧正确处理
- 测试帧跳过逻辑
- 验证性能

### 50. Commit M4 (15min)
- 提交视频一致性修复
- 更新 Roadmap.md

---

## 执行策略

- **并行执行**: M0/M2/M3/M4 可以并行推进
- **优先级**: M0 > M2 > M3 > M4
- **时间限制**: 每个任务 ≤30 分钟
- **验证**: 每个 M 完成后立即 quick_signals 验证

---

生成时间: 2026-05-31
任务总数: 50 (已完成 25，待执行 25)
