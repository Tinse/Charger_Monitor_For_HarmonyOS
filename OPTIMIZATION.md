# UESTC_Charger_Monitor_CC 优化清单

> 基于 v1.2.1 代码审阅，结合 appfreeze 日志分析。
> 更新时间：2026-06-13

---

## 已完成项

### v1.2.1 及之前

- [x] 文件拆分（Index.ets → 3 个 UI 组件）
- [x] DataCache 缓存层
- [x] ErrorHandler 统一错误处理
- [x] ApiConfig 集中配置管理
- [x] ThemeManager 主题持久化
- [x] ConfigManager 配置 CRUD
- [x] AppState 全局状态键名
- [x] selectedIdsMap @State → private（渲染卡死修复）

### v1.3 重构（2026-06-13）

- [x] **#4 API 层拆分**：ChargerApi（424→254行）拆为 api/ChargerApi（纯HTTP）+ services/LocationService（位置+权限）+ utils/DistanceCalc（距离计算）
- [x] **#1 Service 层引入**：新建 StationService（站点数据+缓存）、ConfigService（配置CRUD+变更通知）、LocationService（位置+权限）
- [x] **#2 数据流理清**：`@Link stationConfig` → `@Prop stationConfig`，子组件不再直接修改；ConfigService 通过 listener 通知 Index.ets 更新 @State
- [x] **#3 @State 聚合**：ChargerMonitorUI 14→13，StationPickerUI 11→8（searchInputText/configNameInput 降为 private）
- [x] **#5 消除重复逻辑**：两个 UI 组件的 fetchData/fetchAllStations 统一委托给 StationService
- [x] **#6 Index 瘦身**：主题逻辑整合到 ThemeManager（resolveIsDark/getColorModeConstant/applyThemeMode），Index 从 182→159 行
- [x] **#7 splice 修复**：`this.selectedIds.splice(index, 1)` → `this.selectedIds = this.selectedIds.filter(...)`，`push` → `[...this.selectedIds, id]`
- [x] **#8 OutletStatus 枚举**：`status === 1/2/3` → `OutletStatus.FREE/OCCUPIED/BROKEN`
- [x] **#10 getContext 替换**：`getContext(this)` → `this.getUIContext().getHostContext()`
- [x] **目录整理**：api/、services/、utils/、theme/ 四层分离

### v1.4 代码质量（2026-06-13）

- [x] **ForEach keyGenerator**：所有 5 处 ForEach 添加稳定 key（config.id / station.id / outlet.serial / stationName / stationId）
- [x] **getFilteredStations 缓存**：使用 `@Watch` + `@State filteredStations` 缓存排序+过滤结果，避免每次渲染重新计算
- [x] **自动刷新页面可见性控制**：`onPageShow()` 启动定时器，`onPageHide()` 暂停，避免后台无意义刷新
- [x] **HTTP 实例 destroy**：ChargerApi 三个方法均添加 `finally { httpRequest.destroy() }`，防止资源泄漏

### v1.5 用户体验（2026-06-13）

- [x] **下拉刷新**：ChargerMonitorUI 使用 `Refresh` 组件包裹内容，支持手势下拉刷新
- [x] **CustomDialogController**：StationPickerUI 保存对话框从手动定位改为 `CustomDialogController`，居中显示

### v1.6 UI 现代化重构（2026-06-13）

- [x] **基础组件库**：新建 6 个可复用组件
  - `SearchBar.ets` — 胶囊搜索栏（🔍图标 + 圆角输入框）
  - `SegmentedControl.ets` — iOS 风格分段控件
  - `Chip.ets` — 标签/芯片组件（支持选中状态）
  - `StatCard.ets` — 统计卡片组件
  - `SettingSection.ets` — 设置分组容器（标题 + 卡片）
  - `SettingRow.ets` — 设置行（图标 + 标题 + 副标题 + 尾部控件）
- [x] **设置页面重构**（StationPickerUI）：
  - 个人资料卡片（应用名 + 版本 + 已配置站点数）
  - 外观设置分组：主题模式 SegmentedControl + HDS 沉浸光感 Toggle
  - 站点配置分组：胶囊搜索栏 + 全选/全不选 + 站点列表
  - 保存对话框改用 CustomDialogController
- [x] **监控页面优化**（ChargerMonitorUI）：
  - 统计概览卡片重新设计（更大数字、颜色编码）
  - 配置选择器改为水平滚动 Chips
  - 站点卡片增加视觉层次
- [x] **地图页面优化**（MapViewerUI）：
  - 浮动工具栏卡片（底部右侧，垂直布局）
  - 缩放级别指示器（底部左侧百分比标签）
  - 按钮改为图标风格（+/-/O）

---

## 当前目录结构

```
pages/
  Index.ets              (159行, Tab容器+配置监听)
  ChargerModels.ets      (数据模型+OutletStatus枚举+DataValidator)
  ConfigManager.ets      (底层Preferences操作)
  ApiConfig.ets          (API配置)
  AppState.ets           (全局状态键名)
  api/
    ChargerApi.ets       (254行, 纯HTTP请求)
  services/
    LocationService.ets  (165行, 位置获取+权限管理)
    StationService.ets   (78行, 站点数据+缓存策略)
    ConfigService.ets    (104行, 配置CRUD+变更通知)
  theme/
    ThemeManager.ets     (140行, 主题颜色+系统颜色模式)
  utils/
    ErrorHandler.ets     (统一错误处理)
    DataCache.ets        (数据缓存)
    DistanceCalc.ets     (距离计算)
  components/
    ChargerMonitorUI.ets (监控Tab, 含下拉刷新)
    StationPickerUI.ets  (设置Tab, 含CustomDialog)
    MapViewerUI.ets      (地图Tab, 浮动工具栏)
    SearchBar.ets        (胶囊搜索栏)
    SegmentedControl.ets (分段控件)
    Chip.ets             (标签/芯片)
    StatCard.ets         (统计卡片)
    SettingSection.ets   (设置分组)
    SettingRow.ets       (设置行)
```

---

## 待优化项

### P2 — 用户体验

#### 1. 空状态与错误状态区分不足

**现状**：加载失败和无数据共用同一 UI。

**方案**：增加独立的错误状态 UI，附带重试按钮和具体错误描述。

### P3 — 安全与规范

#### 2. User-Agent 伪装 Chrome Mobile

**现状**：`ApiConfig.getHeaders()` 返回 Chrome Mobile 的 UA 字符串。

**问题**：依赖 UA 伪装获取 API 响应，API 升级时可能失效。

**方案**：确认 API 是否有官方 SDK 或文档化接口。

#### 3. 配置名称未做输入校验

**现状**：用户输入的配置名称直接存储，未校验长度和特殊字符。

**方案**：添加长度限制（≤50 字符）和特殊字符过滤。

#### 4. 缺少单元测试

**现状**：`entry/src/test/` 和 `entry/src/ohosTest/` 仅有模板文件。

**方案**：优先为以下模块添加单元测试：
- `DataValidator`（纯函数，最容易测试）
- `DistanceCalc`（距离计算）
- `ConfigService`（配置逻辑）

#### 5. SettingSection/SettingRow @BuilderParam 适配

**现状**：`SettingSection` 和 `SettingRow` 使用 `@Builder` 装饰器，无法通过内联 lambda 传递内容。当前 StationPickerUI 已内联实现等效布局。

**方案**：研究 ArkTS `@BuilderParam` 正确用法，实现组件级别的内容注入。

---

*更新时间：2026-06-13*
*基于代码版本：v1.6（UI 现代化重构完成）*
