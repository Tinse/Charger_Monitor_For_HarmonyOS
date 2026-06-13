# UESTC_Charger_Monitor_CC 工程架构文档

## 项目概述

**项目名称**：UESTC_Charger_Monitor_CC（电子科技大学充电桩监控应用）  
**项目类型**：HarmonyOS 应用  
**开发语言**：ArkTS  
**目标平台**：手机、平板  
**SDK 版本**：目标 SDK 6.1.0(23)，兼容 SDK 6.0.2(22)  
**Bundle 名称**：`com.example.uestc_charger_monitor`

## 目录结构

```
UESTC_Charger_Monitor_CC/
├── AppScope/                    # 应用级配置
│   ├── app.json5               # 应用配置信息
│   └── resources/              # 应用级资源
├── entry/                       # 主模块
│   ├── src/
│   │   ├── main/
│   │   │   ├── ets/           # ArkTS 源代码
│   │   │   │   ├── entryability/    # 应用入口能力
│   │   │   │   ├── entrybackupability/ # 备份能力
│   │   │   │   └── pages/          # 页面和业务逻辑
│   │   │   ├── module.json5   # 模块配置
│   │   │   └── resources/     # 模块资源
│   │   ├── mock/              # 模拟数据
│   │   ├── ohosTest/          # HarmonyOS 测试
│   │   └── test/              # 单元测试
│   ├── build-profile.json5    # 模块构建配置
│   └── oh-package.json5       # 模块依赖配置
├── build-profile.json5        # 项目构建配置
├── oh-package.json5           # 项目依赖配置
└── hvigorfile.ts              # 构建脚本
```

## 核心模块

### 1. EntryAbility（应用入口）
- **文件**：`entry/src/main/ets/entryability/EntryAbility.ets`
- **职责**：
  - 应用生命周期管理（onCreate、onDestroy、onForeground、onBackground）
  - 系统主题状态同步（通过 AppStorage）
  - 定位权限检查（不自动申请，遵循最小权限原则）
  - 主窗口加载（加载 `pages/Index`）

### 2. Index.ets（主页面）
- **文件**：`entry/src/main/ets/pages/Index.ets`
- **职责**：
  - 作为应用主界面，包含三个 Tab 页签
  - 管理全局状态（配置、主题）
  - 协调子组件间的数据交互
- **子组件**：
  - `ChargerMonitorUI`：监控页面组件
  - `StationPickerUI`：站点选择器组件
  - `MapViewerUI`：地图查看组件

### 3. ChargerApi（充电站 API）
- **文件**：`entry/src/main/ets/pages/ChargerApi.ets`
- **职责**：
  - 封装所有网络请求（HTTP 客户端）
  - 获取充电站数据（单个站点、附近站点）
  - 获取插座详情（功率、费用、时长）
  - 位置服务集成（获取当前位置、计算距离）
  - 权限管理（位置权限检查与申请）
- **主要方法**：
  - `fetchStation()`：获取单个站点数据
  - `fetchNearbyStations()`：获取附近站点列表
  - `fetchOutletDetail()`：获取插座详情
  - `getCurrentLocation()`：获取当前位置
  - `requestLocationPermissions()`：请求位置权限

### 4. ChargerModels（数据模型）
- **文件**：`entry/src/main/ets/pages/ChargerModels.ets`
- **职责**：
  - 定义所有数据接口和类型
  - 提供数据验证工具类
  - 定义排序模式常量
- **主要接口**：
  - `OutletDetail`：插座详情（序列号、状态、功率、费用、时长）
  - `StationData`：站点数据（ID、名称、插座列表）
  - `StationBrief`：站点简要信息（用于列表显示）
  - `ChargerConfig`：充电站配置（ID、名称、站点映射）
  - `ConfigStorage`：配置存储结构

### 5. ConfigManager（配置管理）
- **文件**：`entry/src/main/ets/pages/ConfigManager.ets`
- **职责**：
  - 管理用户配置的充电站列表
  - 使用 Preferences 进行持久化存储
  - 支持多配置管理（添加、更新、删除、切换）
  - 提供默认配置
- **主要方法**：
  - `getConfigs()`：获取所有配置
  - `addConfig()`：添加新配置
  - `updateConfig()`：更新配置
  - `deleteConfig()`：删除配置
  - `setCurrentConfig()`：设置当前配置

### 6. ThemeManager（主题管理）
- **文件**：`entry/src/main/ets/pages/ThemeManager.ets`
- **职责**：
  - 管理应用主题（深色/浅色/跟随系统）
  - 定义主题颜色方案
  - 主题设置的持久化存储
  - 与系统主题状态同步
- **主要功能**：
  - 提供深色和浅色主题颜色定义
  - 主题模式的保存与加载
  - 根据系统主题自动切换

## 数据流

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ChargerApi    │    │  ConfigManager  │    │  ThemeManager   │
│  (网络请求)      │    │  (配置管理)      │    │  (主题管理)      │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │ 获取站点数据          │ 获取/保存配置          │ 获取/保存主题
         │                      │                      │
         ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Index.ets                               │
│                      (主页面状态管理)                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ ChargerMonitorUI │ │ StationPickerUI │ │ MapViewerUI │         │
│  │   (监控页面)  │    │  (设置页面)  │    │  (地图页面)  │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

1. **数据获取**：ChargerApi 从远程 API 获取充电站数据
2. **配置管理**：ConfigManager 管理用户配置的站点列表（持久化存储）
3. **主题管理**：ThemeManager 处理主题切换和持久化
4. **状态管理**：使用 ArkUI 状态管理装饰器（@State、@Link、@StorageLink）
5. **组件通信**：通过回调函数和状态链接实现父子组件通信

## 权限需求

在 `module.json5` 中声明以下权限：

1. **ohos.permission.INTERNET**：网络访问权限
2. **ohos.permission.LOCATION**：精确位置权限
3. **ohos.permission.APPROXIMATELY_LOCATION**：大概位置权限

**权限使用策略**：
- 应用启动时检查权限状态（不自动申请）
- 在用户操作时（如获取附近站点）按需申请权限
- 遵循最小权限原则

## 主要功能

### 1. 充电站监控（Tab 1）
- 实时显示充电站状态（空闲/占用/故障）
- 支持手动刷新（带冷却时间）和自动刷新（30秒间隔）
- 多种排序方式（空闲数量、功率、费用、使用时长、插座编号）
- 站点搜索功能
- 配置选择器（快速切换不同配置）

### 2. 地图查看（Tab 2）
- 显示充电站地图
- 支持双指缩放（0.5x - 5x）
- 支持单指拖动（放大状态下）
- 重置视图功能

### 3. 站点设置（Tab 3）
- **外观设置**：主题切换（跟随系统/深色/浅色）
- **站点配置**：
  - 获取附近充电站列表（基于位置服务）
  - 多选站点
  - 保存配置（支持命名）
  - 搜索站点

### 4. 配置管理
- 支持多配置存储
- 配置的增删改查
- 当前配置切换
- 配置数据持久化

### 5. 主题系统
- 深色模式
- 浅色模式
- 跟随系统主题
- 主题设置持久化

## 技术特点

1. **ArkUI 声明式 UI**：使用 ArkTS 声明式开发范式
2. **状态管理**：合理使用 @State、@Link、@StorageLink 等装饰器
3. **异步编程**：使用 async/await 处理异步操作
4. **错误处理**：完善的异常捕获和用户提示
5. **性能优化**：
   - 并行数据获取（Promise.allSettled）
   - 防抖机制（配置变化时延迟刷新）
   - 冷却时间（防止频繁刷新）
6. **用户体验**：
   - Toast 消息提示
   - 加载状态显示
   - 空状态提示
   - 响应式布局

## 构建与运行

**构建命令**：
```bash
# 调试模式构建
hvigor assembleHap

# 发布模式构建
hvigor assembleHap --mode release
```

**运行环境**：
- DevEco Studio 5.0+
- HarmonyOS SDK 6.0.2+
- 真机或模拟器

## 注意事项

1. **API 依赖**：应用依赖 `https://wemp.issks.com` 和 `https://api.issks.com` 的充电站 API
2. **位置服务**：需要设备开启位置服务才能获取附近站点
3. **网络环境**：需要网络连接才能获取实时数据
4. **权限授权**：首次使用需要授权位置权限

---

*文档生成时间：2026-06-12*  
*项目版本：1.0.0*