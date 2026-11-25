# 充电不愁 · HarmonyOS 7

当前版本：**1.7.0**（versionCode `1007000`）。

面向电子科技大学充电场景的原生 ArkTS / ArkUI 应用。查看充电站插座状态、寻找附近站点、保存常用站点组合，并浏览内置校园地图。

**当前开发基线：HarmonyOS 7，API 26.0.0 Release。编译、目标和最低兼容 API 均为 `26.0.0`，不再支持 HarmonyOS 6 / API 22。**

## 核心功能

| 页面 | 功能 | 实现入口 |
| --- | --- | --- |
| 监控 | 空闲 / 占用 / 故障 / 总数统计；查看占用插座的功率、费用和时长；按名称搜索；按序号、空闲数、功率、费用、时长排序 | [ChargerMonitorUI.ets](entry/src/main/ets/pages/components/ChargerMonitorUI.ets) |
| 配置 | 根据设备位置查询附近站点并显示距离；搜索、多选和命名保存；在监控页切换、编辑、删除站点组合 | [StationPickerUI.ets](entry/src/main/ets/pages/components/StationPickerUI.ets)、[ConfigService.ets](entry/src/main/ets/pages/services/ConfigService.ets) |
| 地图 | 内置静态校园地图；双指缩放、单指拖动、缩放按钮和复位；缩放范围 50%～500% | [MapViewerUI.ets](entry/src/main/ets/pages/components/MapViewerUI.ets) |
| 外观 | 跟随系统 / 深色 / 浅色，主题设置保存在本地；底部 HDS 浮动导航栏，支持切换沉浸材质效果 | [Index.ets](entry/src/main/ets/pages/Index.ets)、[ThemeManager.ets](entry/src/main/ets/pages/theme/ThemeManager.ets) |

内置三套配置：D 区（3 站）、主楼 C 区（3 站）、商业街（19 站）。首次启动默认使用 D 区；旧自定义配置和当前选择会保留。默认配置只读，自定义配置可以创建、编辑和删除；在监控页或设置页点击配置切换。站点 ID、名称与坐标见 [核对记录](docs/stations.md)。

设置页点击「增加配置」进入独立的二级页面，底部页签自动隐藏。填写名称后，可搜索站点名称或地址，也可点击「主楼C区」「商业街」快捷词，再点「勾选结果」。批量勾选采用累加方式，保留其他关键词下的选择；「取消结果」仅移除当前结果，「已选」用于复查组合。搜索忽略空格和英文大小写。

地图是应用内置图片，不提供实时定位标记、站点叠加或路线导航。应用当前提供状态查询，不包含扫码启动充电、支付或账户登录流程。

## 软件架构

工程采用 Stage 模型，只有一个 `entry` 模块和一个 `EntryAbility`。主页面和地图沿用 ArkUI 状态管理 V1；监控页、设置首页、站点选择页、搜索栏和分段控件使用 V2（`@ComponentV2`、`@Local`、`@Param`、`@Event`），明确输入、局部状态和事件契约。没有 WebView、应用自建后端或第三方运行时依赖。

```mermaid
flowchart TD
    Ability[EntryAbility<br/>生命周期、Context、窗口] --> Root[Index / MainApp<br/>三页签、主题、共享配置]
    Root --> Monitor[ChargerMonitorUI]
    Root --> Settings[SettingsUI]
    Settings -->|增加配置| Nav[Navigation / NavDestination]
    Nav --> Picker[StationPickerUI]
    Root --> Map[MapViewerUI<br/>本地地图图片]
    Monitor --> Config[ConfigService<br/>配置变更通知]
    Picker --> Config
    Config --> Store[ConfigManager]
    Store --> Prefs[ArkData Preferences]
    Config -->|配置变化时清缓存| Stations[StationService]
    Monitor --> Stations
    Picker --> Stations
    Stations --> Cache[DataCache<br/>进程内缓存]
    Stations --> API[ChargerApi<br/>HTTP 接口适配]
    API --> Location[LocationService<br/>权限、系统定位、回退]
    API --> Remote[充电站服务]
    Root --> Theme[ThemeManager]
    Theme --> Prefs
```

### 数据流与职责

1. **启动**：`EntryAbility` 注入 `ApplicationContext`，初始化配置存储、共享主题状态和主窗口，再加载 `pages/Index`。配置初始化使用共享 Promise，页面读取会等待初始化完成，不依赖已废弃的全局 `getContext()`。
2. **站点监控**：页面将 `{站点名称: 站点 ID}` 交给 `StationService`；服务先读缓存，再通过 `ChargerApi` 读取插座列表，并补充占用插座的功率、费用和时长。每批最多并发 4 个站点，单站请求失败不会丢弃其他成功结果。
3. **附近站点**：`StationService` 检查附近列表缓存；未命中时，`ChargerApi` 委托 `LocationService` 处理定位能力、系统定位开关和授权，然后使用坐标查询站点并计算直线距离。此处是直线距离，不是步行或骑行距离。
4. **配置变更**：`ConfigService` 写入 `ConfigManager`，清除站点缓存，并通过 listener 通知 `Index` 更新共享状态；监控页监听配置变化重新加载。配置 ID 和站点 ID 用于列表稳定标识。
5. **界面派生状态**：监控列表的过滤、排序由 V2 `@Monitor` 更新；主题由 `ThemeManager` 映射颜色并保存偏好，窗口状态通过 `AppStateKeys` 共享。

### 刷新、缓存与资源释放

- 监控页可见时每 30 秒检查一次数据；`TabContent.onWillShow/onWillHide` 将 Tab 切换及前后台变化传递给监控组件，隐藏时停止自动刷新。
- 站点选择二级页只在可见时主动获取定位；从系统位置设置返回且列表仍为空时重新查询，避免在后台发起仅允许使用期间的定位请求。
- 站点和附近列表使用 60 秒的进程内缓存；因此自动检查不等于每 30 秒都重新发网络请求。退出进程后缓存消失。
- 手动刷新清缓存后获取数据，带 3 秒冷却；配置切换、更新和删除也会清缓存。
- 同时发生的刷新以较新结果为准，避免旧配置的慢响应覆盖当前页面。
- 监控站点和附近站点使用 `Repeat.virtualScroll()` 虚拟列表，只构建可见行及少量缓存行；二级页保存按钮固定在安全区域内，无需滚过整份站点列表。
- 两个站点搜索框使用 300 毫秒防抖，输入停顿后更新结果，不要求额外提交搜索。
- HTTP 实例在 `finally` 中销毁；组件销毁时清理定时器和定位开关监听。

## 目录

```text
AppScope/                         应用标识、名称
entry/src/main/
├── ets/
│   ├── entryability/             应用入口与窗口管理
│   └── pages/
│       ├── Index.ets             主界面和 HDS 页签
│       ├── ChargerModels.ets     插座、站点、配置等类型
│       ├── ApiConfig.ets         API 地址、坐标和时间参数
│       ├── ConfigManager.ets     Preferences 配置读写
│       ├── PresetConfigs.ets     已核对的三套校园预设
│       ├── AppState.ets          共享状态键
│       ├── api/                  充电站 HTTP 接口
│       ├── services/             配置、站点、定位服务
│       ├── components/           三个页面及实际使用的 UI 组件
│       ├── theme/                主题颜色和持久化
│       └── utils/                缓存、距离计算、错误提示
├── resources/                    地图、图标、字符串、路由
└── module.json5                  Ability、设备类型和权限
build-profile.json5               API 与产品构建配置
hvigor/hvigor-config.json5         Hvigor 开发态版本
oh-package.json5                  包配置（无外部依赖）
scripts/test-core.cjs              使用 SDK 编译器的核心逻辑回归
```

## 开发环境与运行

| 项目 | 要求 |
| --- | --- |
| 系统版本 | HarmonyOS 7 / API 26.0.0 及以上 |
| SDK | HarmonyOS SDK 26.0.0 Release；本机验证的组件版本为 `26.0.0.105` |
| IDE | 配套的 DevEco Studio 26.0.0 Release |
| Node.js | DevEco 工具链使用配套 Node 24.14.1；DevEco CLI 要求 Node 22 及以上 |
| 设备 | phone、tablet；可使用本地 HarmonyOS 7 手机镜像 |
| Bundle | `com.example.uestc_charger_monitor` |

本机设备名称、SDK 安装路径和签名材料不属于仓库配置。安装 CLI 的官方命令为 `npm install -g @deveco/deveco-cli@stable`，可用 `devecocli --version` 检查；本次验证使用 `1.3.13-alpha`，它是 CLI 的预发布版本，不代表项目使用了 Beta SDK。

在工程根目录执行：

```powershell
# 在当前终端指定自己的 DevEco Studio 安装目录，不将路径保存进仓库。
$env:DEVECO_CLI_STUDIO_PATH = Read-Host 'DevEco Studio 安装目录'
$env:DEVECO_SDK_HOME = "$env:DEVECO_CLI_STUDIO_PATH\sdk"

# CLI 自动执行依赖安装、Hvigor 同步和 HAP 构建。
devecocli build

# 选择已有的 HarmonyOS 7 模拟器。
devecocli emulator list
$deviceName = Read-Host '模拟器实例名称'
devecocli emulator start $deviceName
devecocli device list
devecocli run --device $deviceName --debug-line
```

`$deviceName` 使用 `emulator list` 显示的实例名称。无窗口环境可给 `emulator start` 加 `--no-window`。

默认产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`，当前配置用于允许安装未签名调试包的本地模拟器。真机调试或发布前，使用 DevEco Studio 的 Signing Configs 或 `devecocli signature generate` 配置自己的证书、描述文件和签名；不要复用其他开发者的路径或将签名材料提交到仓库。

### 定位与调试

监控默认站点不要求位置权限。点击增加配置进入站点选择二级页时才查询位置；用户仅允许模糊定位也可继续使用附近查询。定位权限仅声明为使用期间访问。

- 系统定位开关关闭：提示打开设置，不将其误判为授权被拒绝。
- 用户拒绝授权、设备不支持定位或定位超时：显示回退状态，按 `ApiConfig` 中的清水河校区附近默认坐标查询。
- 模拟器没有真实 GPS；测试附近查询时可注入坐标，返回结果不能用于证明真实设备定位精度。

```powershell
devecocli emulator geolocation --target $deviceName --latitude 30.751 --longitude 103.925
devecocli ui layout --device $deviceName
devecocli ui screenshot --device $deviceName --path .deveco/screenshot.png
devecocli log --device $deviceName --bundle-name com.example.uestc_charger_monitor --tail 100
devecocli log --device $deviceName --bundle-name com.example.uestc_charger_monitor --crash --from 5m
```

若进入配置页仍显示定位未开启，需要先在模拟器系统设置中启用位置服务并授权。CLI 截图路径如已存在，请换用新文件名。

## 接口与数据边界

接口配置集中在 [ApiConfig.ets](entry/src/main/ets/pages/ApiConfig.ets)。当前向 `https://wemp.issks.com` 请求数据：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/charge/v1/outlet/station/outlets/{stationId}` | 站点插座与状态 |
| GET | `/charge/v1/charging/outlet/{outletNo}` | 占用插座详情 |
| POST | `/device/v1/near/station` | 坐标附近的站点 |

请求的 Origin / Referer 使用 `https://api.issks.com`。附近查询单次请求最多 200 个站点；页面展示的是接口结果，不保证覆盖整个区域。状态更新频率和可用性取决于第三方服务与本地缓存。设备坐标会随附近查询发送给该服务；常用站点组合和主题偏好保存在应用沙箱中的 Preferences，当前没有云同步和备份扩展。

## HarmonyOS 7 适配

- `compileSdkVersion`、`targetSdkVersion`、`compatibleSdkVersion` 均设为 `26.0.0`，`modelVersion` 同步为 `26.0.0`。
- 使用 `@kit.NetworkKit`、`@kit.ArkData`、`@kit.ArkUI` 等 Kit 入口；偏好存储使用显式注入的 Context。
- 弹窗通过 `UIContext.getPromptAction()` 调用，地图复位动画通过 `UIContext.animateTo()` 调用。
- HDS 沉浸材质只用于底部 TabBar 的有效区域；移除了低版本底栏分支。
- 地图工具栏和保存按钮避让浮动底栏，复位操作不再被页签触摸区域遮挡。
- 搜索栏和分段控件使用 V2 `@Event` 声明对外事件，避免把普通或 `private` 字段当成受管理的事件接口。
- 清理空备份扩展、空测试模板与未引用组件，将过期架构说明和优化清单合并到本 README；`oh_modules`、构建产物、IDE 文件和本机路径不再作为源码维护。

截至 2026-11-25，官方 `26.0.0` 为 Release，`26.0.1` 为 Beta1。本项目选择正式版，不将营销系统版本 `7.0.0` 直接填入 SDK 配置。

参考：[26.0.0 Release 配套信息](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-2600/)、[26.0.1 Beta1 配套信息](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-2601/)、[向 API 26.0.0 升级指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/upgrade-adaptation/)、[API 26 行为变更](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/changelogs-overview-2600/)。

## 验证范围

核心逻辑回归使用 SDK 自带的 TypeScript 编译器，直接加载当前 ArkTS 源码，覆盖预设加载和旧配置保留、关键词匹配与批量勾选、CRUD / 切换 / 重新加载、缓存有效期边界、距离计算和数据校验；Preferences 使用内存适配器，不代表真实设备 SDK 测试。

```powershell
node scripts/test-core.cjs
```

此外通过真实构建、模拟器页面操作和日志检查验证，不将已删除的空测试模板当成测试覆盖。设备回归时至少核对：

1. HAP 元数据的 Release SDK 与编译 / 目标 / 最低 API；构建成功后设备上仍存在应用进程和可见页面。
2. 默认监控数据、搜索和排序、手动刷新、隐藏页面暂停自动刷新。
3. 地图缩放、拖动和复位；主题切换及重新启动后恢复。
4. 附近站点获取、权限拒绝 / 模糊授权 / 定位开关关闭的处理。
5. 配置创建、切换、编辑、删除及重启后的持久化；检查本次运行的崩溃记录。

本地验证日志和截图写入 `.deveco/harmony7-validation/`，该目录不提交 Git。模拟器验证不等同于真机性能测量或应用市场发布验收。

## 界面设计参考

导航使用透明背景的单色系统 Symbol，当前页签以蓝色强调。设置采用浅灰画布、圆角分组卡片与分级文字；新增配置通过 Navigation / NavDestination 提供系统返回和二级页面转场，保存操作避让系统导航条。深色模式使用独立配色。

参考华为官方：[HarmonyOS Symbol](https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962/)、[工具栏与安全区域](https://developer.huawei.com/consumer/cn/doc/design-guides/toolbar-0000001929683232/)、[HDS 浮动页签](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-hds-tabs-bar-floating/)、[Navigation](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-navigation-navigation/)。本次通过模拟器截图检查设置页、站点选择页、深浅主题及返回路径，验证材料位于 `.deveco/settings-redesign/`。

## 公开仓库与本机配置

仓库仅维护可公开的源码、资源、构建基线和文档。SDK 安装位置通过环境变量指定；设备实例、签名证书、私钥、凭据、本地日志和调试产物保存在 Git 忽略的本机文件中。请勿在构建配置或文档中写入开发者目录、私人邮箱或真实签名参数。
