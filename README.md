# 充电不愁 · HarmonyOS 7

当前版本 **1.8.0**（versionCode `1008000`）。[下载未签名 HAP](https://github.com/Tinse/Charger_Monitor_For_HarmonyOS/releases/tag/v1.8.0)

面向电子科技大学充电场景的原生 ArkTS / ArkUI 应用。查看充电站插座状态、寻找附近站点、保存常用站点组合，并浏览内置校园地图。

**当前开发基线：HarmonyOS 7，API 26.0.0 Release。编译、目标和最低兼容 API 均为 `26.0.0`，不再支持 HarmonyOS 6 / API 22。**

## 核心功能

| 页面 | 功能 | 实现入口 |
| --- | --- | --- |
| 监控 | 空闲 / 占用 / 故障 / 总数统计；查看占用插座的功率、费用和时长；按名称搜索；按序号、空闲数、功率、费用、时长排序 | [ChargerMonitorUI.ets](entry/src/main/ets/pages/components/ChargerMonitorUI.ets) |
| 配置 | 监控页切换配置；设置页进入详情；自定义配置可编辑名称与站点；默认配置可复制后修改；两类配置均可确认删除，并可恢复默认配置 | [ConfigDetailUI.ets](entry/src/main/ets/pages/components/ConfigDetailUI.ets)、[StationPickerUI.ets](entry/src/main/ets/pages/components/StationPickerUI.ets)、[ConfigService.ets](entry/src/main/ets/pages/services/ConfigService.ets) |
| 地图 | 内置静态校园地图；双指缩放、单指拖动、缩放按钮和复位；缩放范围 50%～500% | [MapViewerUI.ets](entry/src/main/ets/pages/components/MapViewerUI.ets) |
| 外观 | 跟随系统 / 深色 / 浅色，主题设置保存在本地；底部 HDS 浮动导航栏，支持切换沉浸材质效果 | [Index.ets](entry/src/main/ets/pages/Index.ets)、[ThemeManager.ets](entry/src/main/ets/pages/theme/ThemeManager.ets) |

内置两套配置：主楼 C 区（3 站）、商业街（19 站）。首次启动默认使用主楼 C 区；旧的 D 区预设移除，原先选中 D 区时迁移到剩余可用配置，已有自定义配置保留。监控页的配置标签用于切换；设置页点击配置进入详情，不改变当前监控配置。默认配置保持原始站点，可复制为自定义配置；自定义配置可编辑名称、增加或移除站点。默认和自定义配置均可经过确认后删除。站点 ID、名称与坐标见 [核对记录](docs/stations.md)。

设置页点击「增加配置」进入独立的二级页面，底部页签自动隐藏。填写名称后，可搜索站点名称或地址，也可点击「主楼C区」「商业街」快捷词，再点「勾选结果」。批量勾选采用累加方式，保留其他关键词下的选择；「取消结果」仅移除当前结果，「已选」用于复查组合。搜索忽略空格和英文大小写。配置至少保留一个站点，名称不能为空或与已有配置重名。

在配置详情中点击「编辑名称与站点」可增减站点或改名。重新定位后，原先勾选但已超出查询范围的站点仍保留在草稿中。不同站点重名或已选站点资料缺失时，保存按钮会提示调整选择或重新加载。保存后返回详情，带着修改返回时可选择继续编辑或放弃修改。

删除默认配置后会保存删除记录（`deletedPresetIds`），重新读取或重启不会自动恢复。删除当前配置时切换到剩余配置；删除最后一套配置后保留空列表，监控页引导增加配置，不自动补回预设。设置中的「恢复默认配置」仅在明确点击后恢复两套预设，保留自定义配置和仍有效的当前选择；如自定义名称与预设冲突，会提示先重命名，不覆盖已有内容。删除弹窗展示期间锁定重复操作，取消后恢复可操作状态。

首次读取配置出错时，监控页提供「重新读取配置」。设置页会保留最近一次成功读出的列表。存储格式损坏时会阻止写入，避免用默认配置覆盖个人配置。

地图使用内置校园图片。双指缩放以两指中心为焦点，放大后可单指拖动到地图边缘，点击复位可恢复到居中的 100% 视图。

## 软件架构

工程采用 Stage 模型，只有一个 `entry` 模块和一个 `EntryAbility`。主页面和地图沿用 ArkUI 状态管理 V1；监控页、设置首页、配置详情、站点选择页、搜索栏和分段控件使用 V2（`@ComponentV2`、`@Local`、`@Param`、`@Event`），明确输入、局部状态和事件契约。没有 WebView、应用自建后端或第三方运行时依赖。

```mermaid
flowchart TD
    Ability[EntryAbility<br/>生命周期、Context、窗口] --> Root[Index / MainApp<br/>三页签、主题、共享配置]
    Root --> Monitor[ChargerMonitorUI]
    Root --> Settings[SettingsUI]
    Settings -->|配置详情 / 增加配置| Nav[Navigation / NavDestination]
    Monitor -->|管理配置| Nav
    Nav --> Detail[ConfigDetailUI]
    Detail -->|编辑 / 复制| Picker[StationPickerUI]
    Nav --> Picker
    Root --> Map[MapViewerUI<br/>本地地图图片]
    Monitor --> Config[ConfigService<br/>配置变更通知]
    Picker --> Config
    Detail --> Config
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
2. **站点监控**：页面将 `{站点名称: 站点 ID}` 交给 `StationService`；服务先读缓存，再通过 `ChargerApi` 读取插座列表，并补充占用插座的功率、费用和时长。每批最多并发 4 个站点；返回成功站点及失败站点名称。部分失败会提示缺失站点，全部失败时保留同一配置的上次数据并提示重试。
3. **附近站点**：`StationService` 检查附近列表缓存；未命中时，`ChargerApi` 委托 `LocationService` 处理定位能力、系统定位开关和授权，然后使用坐标查询站点并计算直线距离。此处是直线距离，不是步行或骑行距离。
4. `ConfigManager` 按顺序完成配置的读取、修改和写入。写盘失败时会尝试恢复写入前的值，回滚也失败时提示重新打开应用核对。配置变化后，`ConfigService` 使用一致的当前配置快照通知页面，单个监听回调异常不会阻止其余回调。
5. **界面派生状态**：监控列表的过滤、排序由 V2 `@Monitor` 更新；主题由 `ThemeManager` 映射颜色并保存偏好，窗口状态通过 `AppStateKeys` 共享。

### 刷新、缓存与资源释放

- 应用在前台、当前页签为监控且没有二级页面覆盖时，每 30 秒检查一次站点数据。切换页签、打开详情或进入后台会停止自动刷新。返回监控时重新检查。
- 站点选择二级页只在可见时主动获取定位；从系统位置设置返回且尚未查询、列表为空或此前使用默认位置时重新查询，避免在后台发起仅允许使用期间的定位请求。
- 站点和附近列表使用 60 秒的进程内缓存。附近列表会保留上次的定位来源，例如使用设备位置或因缺少权限而使用校区默认位置。再次使用缓存时，页面会标明来源和缓存状态。
- 顶部按钮、下拉刷新和错误页重试共用同一刷新流程：清缓存、执行请求、反馈结果，并在结束时释放刷新状态。
- 3 秒冷却从触发刷新时开始，以绝对时间计算剩余秒数；界面显示倒计时。请求尚未结束时仍禁止重复刷新，冷却结束不代表慢请求已完成；页面返回前台时按当前时间校正倒计时。
- 切换配置后会清空旧列表与搜索条件，显示当前配置中的站点名称。清除缓存前发出的慢请求随后返回时，其结果也无法写回已清除的缓存。
- 「数据获取于」显示当前已加载站点中，客户端最早一次从接口成功取回数据的月日、时分秒。再次命中缓存会保留原时间。部分失败会列出未加载的站点，全部失败会保留同一配置上次的数据和时间。
- 占用插座的功率统一按 W 展示，保留小数，并将 kW 转换为 W。缺失的功率、费用、时长保持未知。遇到重复插座或未知状态，所在站点会计入加载失败，以免误报故障或重复计数。
- 启动时仅读取外观偏好。修改主题或沉浸光感时若写盘失败，会提示重试并尝试恢复原选择。
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
│       ├── PresetConfigs.ets     已核对的两套校园预设
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
scripts/test-core.cjs              使用 SDK 编译器的配置与选择回归
scripts/test-refresh.cjs           冷却、请求互斥与失败处理回归
docs/function-audit.md             按钮与操作审查、验证状态及待办
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

- 系统定位开关关闭：提示打开设置；未查询时不宣称已使用默认位置。
- 用户拒绝授权、设备不支持定位或定位超时：显示回退状态，按 `ApiConfig` 中的清水河校区附近默认坐标查询。
- 缺少有效坐标的站点显示「距离未知」，不显示成 0 米；有效距离按直线距离排序。
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

逻辑回归使用 SDK 自带的 TypeScript 编译器加载当前 ArkTS 模块。`test-core` 通过内存 Preferences 验证配置增删改、默认配置迁移与恢复、并发写入、配置损坏保护、写盘失败回滚、监听回调异常、选择站点完整性和外观设置回滚。

```powershell
node scripts/test-core.cjs
node scripts/test-refresh.cjs
```

刷新脚本用可控时钟、站点服务替身和模拟 HTTP 响应，覆盖冷却与慢请求互斥、全部或部分失败、并发上限、缓存清除后的旧响应、定位来源与实际获取时间，以及功率单位和缺失字段的解析。

逐按钮的源码审查、逻辑测试覆盖和模拟器验证状态记录在 [功能审查报告](docs/function-audit.md)。本轮模拟器状态应按实际执行证据回填，不沿用上一版本的通过结果。设备回归时至少核对：

1. HAP 元数据的 Release SDK 与编译 / 目标 / 最低 API；构建成功后设备上仍存在应用进程和可见页面。
2. 默认监控数据、搜索和排序、手动刷新、隐藏页面暂停自动刷新。
3. 地图缩放、拖动和复位；主题切换及重新启动后恢复。
4. 附近站点获取、权限拒绝 / 模糊授权 / 定位开关关闭的处理。
5. 配置创建、切换、编辑、默认与自定义删除、重启后不复活、删除最后配置后的空态，以及恢复默认与同名冲突；检查本次运行的崩溃记录。

本地验证日志和截图写入 `.deveco/harmony7-validation/`，该目录不提交 Git。模拟器验证不等同于真机性能测量或应用市场发布验收。

## 界面设计参考

导航使用透明背景的单色系统 Symbol，当前页签以蓝色强调。设置采用浅灰画布、圆角分组卡片与分级文字；配置详情、新增与编辑通过 Navigation / NavDestination 提供系统返回和二级页面转场，保存操作避让系统导航条。深色模式使用独立配色。

参考华为官方：[HarmonyOS Symbol](https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962/)、[工具栏与安全区域](https://developer.huawei.com/consumer/cn/doc/design-guides/toolbar-0000001929683232/)、[HDS 浮动页签](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-hds-tabs-bar-floating/)、[Navigation](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-navigation-navigation/)。此前界面改版的模拟器截图位于 `.deveco/settings-redesign/`；本轮功能修复的验证状态以 [功能审查报告](docs/function-audit.md) 为准。

## 公开仓库与本机配置

仓库仅维护可公开的源码、资源、构建基线和文档。SDK 安装位置通过环境变量指定；设备实例、签名证书、私钥、凭据、本地日志和调试产物保存在 Git 忽略的本机文件中。请勿在构建配置或文档中写入开发者目录、私人邮箱或真实签名参数。
