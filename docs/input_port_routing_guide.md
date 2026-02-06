# 多端口输入路由与来源分配开发指引

## 背景与目标
- 现状：InputSnapshot 已支持 4 端口，但 ArkTS 虚拟手柄只能在当前页面驱动单一端口；外设多端口映射链路尚未完整。
- 目标：建立“每端口唯一来源”的输入规则，并补齐 ArkTS 与 Native 侧的路由、分配与写入链路。

## 核心规则（必须遵守）
1. 每个玩家端口（P1~P4）只能绑定一个输入来源。
2. 虚拟手柄只向其被分配的端口写入。
3. 外设设备只能绑定一个端口；绑定后只写入该端口。
4. 多设备可同时在线，但必须保证设备与端口一一对应。

## 术语
- 端口：玩家输入通道，P1~P4（端口索引为 0~3，P1=0）。
- 输入来源：虚拟手柄或外设设备。
- 端口映射：端口与来源的绑定关系。
- InputSnapshot：Native 侧用于 libretro 读取的输入快照结构（已有 4 端口）。
- 外设范围：键盘、鼠标、手柄、蓝牙手柄。

## ArkTS 侧设计
### 状态模型
- `PortAssignState`
  - `portId: number` (0~3，对应 P1~P4)
  - `sourceType: 'virtual' | 'device' | 'none'`
  - `deviceId?: string`
  - `isActive: boolean`

### UI 与交互
- 每个端口可选输入来源（虚拟/外设）。
- 虚拟手柄仅控制被分配端口；当未分配端口时，虚拟手柄不产生输入。
- 端口被切换后立即生效；旧端口不再接收虚拟手柄输入。

### 事件与协议
- `assignPortSource(portId, sourceType, deviceId?)`：端口绑定。
- `unassignPort(portId)`：解除绑定。
- `queryDevices()`：获取外设列表与能力信息。
- `onDeviceConnected/Disconnected`：更新设备列表与映射状态。

## Native 侧设计
### 端口映射表
- `DevicePortMap` 维护：`deviceId -> portId`。
- `PortSourceMap` 维护：`portId -> sourceType`。
- 规则：
  - 绑定时检查冲突（端口已占用或设备已绑定）。
  - 解绑时清理映射并清空对应端口输入状态。

### 输入写入路径
- 外设输入：设备回调 -> 设备路由 -> 目标端口 -> 写入 `InputSnapshot`。
- 虚拟手柄输入：ArkTS 事件 -> NAPI -> 目标端口 -> 写入 `InputSnapshot`。

### 多设备同时在线
- 多设备可并行产生输入，但写入必须遵循设备绑定的端口。
- 同一端口只接受来自其绑定来源的输入，忽略其他来源。

## 端口切换策略
- 虚拟手柄切换端口时：
  - 先解绑旧端口的 `sourceType='virtual'`。
  - 再绑定新端口为 `sourceType='virtual'`。
- 外设插拔：
  - 插入时如果策略是“自动分配”，需在 ArkTS 或 Native 侧选择空闲端口。
  - 拔出时立即解绑端口，并清空端口输入状态。

## 冲突处理
- 端口已被占用：拒绝绑定，返回错误码或提示。
- 设备已绑定到其他端口：拒绝绑定或提示用户先解绑。
- 端口未分配来源时：对该端口保持空输入（所有键位为未按下）。

## 日志与可观测性
- 关键日志点：
  - 绑定/解绑成功与失败原因。
  - 设备连接/断开事件。
  - 端口切换与当前映射表快照。
- 日志域需在 `0xD000-0xFFFF` 范围内，并遵循当前项目日志规范。

## 验收标准
- 可在 ArkTS 中为 P1~P4 分配输入来源。
- 虚拟手柄只影响其绑定端口，其他端口不受影响。
- 两个及以上外设同时在线时，各自输入只写入自身端口。
- 解绑端口后该端口输入立即清空。

## 落地实施清单（按模块）
### 1) ArkTS 状态与 UI
- 新增路由状态定义（显式 `interface`），避免匿名对象：
  - `entry/src/main/ets/common/InputPortRouting.ts`
  - 推荐字段：`portId(0~3) / sourceType / deviceId / isActive`
- 在页面里加入端口来源选择与设备绑定 UI：
  - `entry/src/main/ets/pages/LibretroGamePage.ets`
  - `entry/src/main/ets/pages/LibretroNewArchTestPage.ets`
- 虚拟手柄发送入口统一走“当前绑定端口”，未绑定时不发送：
  - `setButton()` / `setAnalog()` 处增加端口来源校验

### 2) NAPI 接口与类型声明
- 新增端口映射接口（命名可按现有风格调整）：
  - `refactoredAssignPortSource(port: number, sourceType: number, deviceId?: string): boolean`
  - `refactoredUnassignPort(port: number): boolean`
  - `refactoredListInputDevices(): DeviceInfo[]`
- 更新类型声明：
  - `entry/src/main/cpp/types/libentry/index.d.ts`
- ArkTS 侧接口定义同步更新（`LibretroGamePage.ets` / `LibretroNewArchTestPage.ets`）

### 3) Native 侧端口路由与映射表
- 新增路由管理类（建议新增文件）：
  - `entry/src/main/cpp/core/engine/input_port_router.h`
  - `entry/src/main/cpp/core/engine/input_port_router.cpp`
- 维护映射关系：
  - `deviceId -> portId`
  - `portId -> sourceType`
- 规则处理：
  - 端口占用或设备已绑定时拒绝
  - 解绑时清空 `InputSnapshot` 对应端口
- 线程同步：
  - 共享状态统一 `std::mutex + std::lock_guard`

### 4) Native 输入入口改造（路由绑定）
- XComponent 输入回调不再硬编码 `port=0`：
  - `entry/src/main/cpp/app/framework/plugin_manager.cpp`
  - 键盘/鼠标/触控输入均通过路由器选择端口
- NAPI 输入路径增加端口来源校验：
  - `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
  - 虚拟手柄输入仅允许写入 `sourceType='virtual'` 的端口

### 5) Controller 设备类型同步（可选但推荐）
- 绑定端口后按需调用 `retro_set_controller_port_device`：
  - `entry/src/main/cpp/core/engine/libretro_engine.cpp`
  - NAPI 已有 `refactoredSetControllerPortDevice` 可复用

### 6) 日志与可观测性
- 绑定/解绑、冲突、设备插拔关键路径打点
- 日志域遵循 `0xD000-0xFFFF`，数值日志 `%{public}d/%{public}u/%{public}X`

## 未来扩展
- 支持“端口合并/共享”模式（当前不启用）。
- 支持多虚拟手柄实例（当前仅单实例）。
