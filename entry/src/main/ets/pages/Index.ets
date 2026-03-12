// Index.ets
import { ChargerApi } from './ChargerApi';
import { StationData, OutletDetail, SORT_MODE, StationBrief, ChargerConfig } from './ChargerModels';
import { ConfigManager } from './ConfigManager';
// import common from '@ohos.app.ability.common'; // 暂时未使用
import promptAction from '@ohos.promptAction';
import display from '@ohos.display';

interface StatsResult {
  total: number;
  free: number;
  anyFree: boolean;
}

interface StationWithFreeCount {
  station: StationData;
  freeCount: number;
}

@Entry
@Component
struct MainApp {
  // 全局共享的站点配置
  @State stationConfig: Record<string, number> = ConfigManager.getDefaultConfig();
  @State configs: ChargerConfig[] = [];
  @State currentConfig: ChargerConfig | null = null;
  @State showConfigDialog: boolean = false;
  @State configDialogText: string = "";
  @State showConfigList: boolean = false;
  @State pendingConfig: Record<string, number> = {}; // 待保存的配置

  aboutToAppear() {
    console.log('MainApp aboutToAppear - loading configs');
    this.loadConfigs();
  }

  async loadConfigs() {
    console.log('Loading configs from storage...');
    const configStorage = await ConfigManager.getConfigs();
    console.log('Loaded config storage:', JSON.stringify(configStorage));

    this.configs = configStorage.configs;
    console.log('Configs loaded:', this.configs.length);

    if (configStorage.currentConfigId) {
      this.currentConfig = configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
      if (this.currentConfig) {
        // 创建一个新的对象来确保@Watch能够检测到变化
        try {
          this.stationConfig = JSON.parse(JSON.stringify(this.currentConfig.stations));
        } catch (error) {
          console.error('Failed to parse station config:', error);
          this.stationConfig = ConfigManager.getDefaultConfig();
        }
        console.log('Current config set:', this.currentConfig.name);
      }
    }
  }

  /**
   * @throws
   */
  async saveCurrentConfig(name: string) {
    if (name.trim() === '') {
      try {
        promptAction.showToast({ message: '配置名称不能为空', duration: 2000 });
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
      return;
    }

    // 使用待保存的配置数据
    const configToSave = Object.keys(this.pendingConfig).length > 0 ? this.pendingConfig : this.stationConfig;

    // 检查是否要更新现有配置还是创建新配置
    // 如果是从"设置站点"页面发起的保存请求（有pendingConfig），总是创建新配置
    // 如果是从监控页面的"保存配置"按钮发起的，更新当前配置
    const isNewConfig = Object.keys(this.pendingConfig).length > 0;

    if (isNewConfig) {
      // 创建新配置
      console.log('Creating new config:', name);
      await ConfigManager.addConfig(name, configToSave);
      await this.loadConfigs();
      try {
        promptAction.showToast({ message: '配置已保存', duration: 2000 });
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
    } else if (this.currentConfig) {
      // 更新现有配置
      console.log('Updating existing config:', this.currentConfig.name);
      await ConfigManager.updateConfig(this.currentConfig.id, name, configToSave);
      await this.loadConfigs();
      try {
        promptAction.showToast({ message: '配置已更新', duration: 2000 });
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
    } else {
      // 没有当前配置，也创建新配置
      console.log('Creating new config (no current config):', name);
      await ConfigManager.addConfig(name, configToSave);
      await this.loadConfigs();
      try {
        promptAction.showToast({ message: '配置已保存', duration: 2000 });
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
    }

    // 清空待保存配置
    this.pendingConfig = {};
    this.showConfigDialog = false;
    this.configDialogText = "";
  }

  async switchConfig(configId: string) {
    await ConfigManager.setCurrentConfig(configId);
    await this.loadConfigs();
  }

  async deleteConfig(configId: string) {
    await ConfigManager.deleteConfig(configId);
    await this.loadConfigs();
    try {
      promptAction.showToast({ message: '配置已删除', duration: 2000 });
    } catch (error) {
      console.error('Failed to show toast:', error);
    }
  }

  // 处理保存配置请求
  handleSaveConfigRequest(newConfig: Record<string, number>) {
    this.pendingConfig = newConfig;
    this.configDialogText = this.currentConfig?.name || '';
    this.showConfigDialog = true;
  }

  build() {
    Column() {
      // 配置选择器
      if (this.configs.length > 0) {
        Row() {
          Text("当前配置:").fontColor(Color.White).fontSize(14)

          Button(this.currentConfig?.name || '请选择配置')
            .onClick(() => { this.showConfigList = !this.showConfigList; })
            .layoutWeight(1)
            .margin({ left: 10 })


        }
        .width('90%')
        .padding(10)
        .backgroundColor('#1a1a1c')
        .borderRadius(8)
        .margin({ top: 10 })

        // 配置列表
        if (this.showConfigList) {
          Column() {
            ForEach(this.configs, (config: ChargerConfig) => {
              Row() {
                Text(config.name).fontColor(Color.White).fontSize(14)
                Blank()
                if (this.currentConfig?.id === config.id) {
                  Text("当前").fontColor('#30d158').fontSize(12)
                }
                Button("选择")
                  .onClick(() => {
                    this.switchConfig(config.id);
                    this.showConfigList = false;
                  })
                  .fontSize(10)
                  .margin({ left: 10 })
                Button("删除")
                  .onClick(() => this.deleteConfig(config.id))
                  .fontSize(10)
                  .backgroundColor('#ff453a')
                  .margin({ left: 5 })
              }
              .width('100%')
              .padding(8)
              .backgroundColor('#2c2c2e')
              .borderRadius(6)
              .margin({ bottom: 5 })
            })
          }
          .width('90%')
          .padding(10)
          .backgroundColor('#1a1a1c')
          .borderRadius(8)
          .margin({ top: 5 })
        }
      }

      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          ChargerMonitorUI({
            stationConfig: $stationConfig,
            configs: $configs,
            currentConfig: $currentConfig
          })
        }.tabBar("监控")

        TabContent() {
          StationPickerUI({
            stationConfig: $stationConfig
          })
        }.tabBar("设置站点")
      }
      .layoutWeight(1)

      // 配置命名对话框
      if (this.showConfigDialog) {
        Column() {
          Text("配置名称").fontColor(Color.White).fontSize(16).fontWeight(FontWeight.Bold)
          TextInput({ placeholder: '输入配置名称', text: this.configDialogText })
            .onChange((value) => { this.configDialogText = value; })
            .width('100%')
            .height(40)
            .backgroundColor('#2c2c2e')
            .fontColor(Color.White)
            .margin({ top: 10, bottom: 10 })

          Row() {
            Button("取消")
              .onClick(() => {
                this.showConfigDialog = false;
                this.configDialogText = "";
                this.pendingConfig = {};
              })
              .backgroundColor('#48484a')
              .layoutWeight(1)
              .margin({ right: 10 })

            Button("保存")
              .onClick(() => this.saveCurrentConfig(this.configDialogText))
              .backgroundColor('#0a84ff')
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width(300)
        .padding(20)
        .backgroundColor('#1c1c1e')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Center)
        .position({ x: '50%', y: '40%' })
        .translate({ x: -150, y: -100 })
      }
    }
    .width('100%').height('100%').backgroundColor('#000000')
  }
}

// ==========================================
// 1. 监控页面组件 (Tab 1)
// ==========================================
@Component
struct ChargerMonitorUI {
  @Link @Watch('onStationConfigChange') stationConfig: Record<string, number>;
  @Link configs: ChargerConfig[];
  @Link currentConfig: ChargerConfig | null;

  @State isExpanded: boolean = false;
  @State stations: StationData[] = [];
  @State searchText: string = "";
  @State sortMode: number = SORT_MODE.FREE_COUNT;
  @State showSortMenu: boolean = false;
  @State isLoading: boolean = true;
  @State showConfigList: boolean = false;
  @State canRefresh: boolean = true; // 是否可以刷新
  @State refreshCooldown: number = 0; // 刷新冷却时间
  @State screenHeight: number = 800; // 默认屏幕高度

  private refreshInterval: number = -1;
  private lastConfigHash: string = ""; // 用于检测配置变化
  private cooldownInterval: number = -1; // 冷却计时器

  aboutToAppear() {
    // 获取屏幕高度
    this.getScreenHeight();
    this.fetchData();
    // 定时刷新数据（30秒）
    this.refreshInterval = setInterval(() => {
      this.fetchData();
    }, 30000);
  }

  // 获取屏幕高度
  getScreenHeight() {
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      this.screenHeight = defaultDisplay.height;
      console.log('Screen height detected:', this.screenHeight);
    } catch (error) {
      console.error('Failed to get screen height, using default:', error);
      this.screenHeight = 800; // 默认高度
    }
  }

  // 计算自适应展开高度
  getExpandedHeight(): number {
    // 计算可用高度：屏幕高度 - 顶部间距 - 底部安全区域
    const topMargin = 20; // 顶部间距
    const bottomSafeArea = 60; // 底部安全区域（包含底部导航栏）
    const maxHeight = this.screenHeight - topMargin - bottomSafeArea;

    // 限制最小和最大高度
    const minHeight = 300; // 最小展开高度
    const calculatedHeight = Math.max(minHeight, Math.min(maxHeight, 600)); // 最大不超过600

    console.log('Calculated expanded height:', calculatedHeight);
    return calculatedHeight;
  }

  aboutToDisappear() {
    if (this.refreshInterval !== -1) {
      clearInterval(this.refreshInterval);
    }
    if (this.cooldownInterval !== -1) {
      clearInterval(this.cooldownInterval);
    }
  }

  // 监听stationConfig变化 - 立即响应
  onStationConfigChange() {
    console.log('Config changed detected by @Watch, refreshing data immediately...');
    this.fetchData();
  }

  // 手动刷新数据
  async manualRefresh() {
    if (!this.canRefresh) {
      const remainingTime = Math.ceil(this.refreshCooldown / 1000);
      try {
        promptAction.showToast({
          message: `刷新过快，请等待${remainingTime}秒后重试`,
          duration: 2000
        });
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
      return;
    }

    console.log('Manual refresh triggered');

    // 设置冷却时间（3秒）
    this.canRefresh = false;
    this.refreshCooldown = 3000;

    // 立即刷新数据
    await this.fetchData();

    // 启动冷却计时器
    if (this.cooldownInterval !== -1) {
      clearInterval(this.cooldownInterval);
    }
    this.cooldownInterval = setInterval(() => {
      this.refreshCooldown -= 100;
      if (this.refreshCooldown <= 0) {
        this.canRefresh = true;
        this.refreshCooldown = 0;
        if (this.cooldownInterval !== -1) {
          clearInterval(this.cooldownInterval);
          this.cooldownInterval = -1;
        }
      }
    }, 100);
  }

  async fetchData() {
    // 更新配置哈希
    this.lastConfigHash = JSON.stringify(this.stationConfig);

    let newStations: StationData[] = [];
    let keys = Object.keys(this.stationConfig);
    for (let i = 0; i < keys.length; i++) {
      let name = keys[i];
      let id = this.stationConfig[name];
      let data = await ChargerApi.fetchStation(id, name);
      if (data) {
        newStations.push(data);
      }
    }
    this.stations = newStations;
    this.isLoading = false;
  }

  getStats(): StatsResult {
    let total = 0;
    let free = 0;
    this.stations.forEach(s => {
      total += s.outlets.length;
      free += s.outlets.filter(o => o.status === 1).length;
    });
    return { total, free, anyFree: free > 0 };
  }

  private getFreeCount(outlets: OutletDetail[]): number {
    let count = 0;
    for (let i = 0; i < outlets.length; i++) {
      if (outlets[i].status === 1) count++;
    }
    return count;
  }

  getFilteredStations(): StationWithFreeCount[] {
    let result: StationWithFreeCount[] = [];
    for (let i = 0; i < this.stations.length; i++) {
      let s = this.stations[i];
      if (s.name.toLowerCase().includes(this.searchText.toLowerCase())) {
        let sortedOutlets = s.outlets.slice();
        for (let j = 0; j < sortedOutlets.length - 1; j++) {
          for (let k = j + 1; k < sortedOutlets.length; k++) {
            let a = sortedOutlets[j];
            let b = sortedOutlets[k];
            let shouldSwap = false;
            if (this.sortMode === SORT_MODE.POWER) shouldSwap = (b.power_w || 0) > (a.power_w || 0);
            else if (this.sortMode === SORT_MODE.FEE) shouldSwap = (b.fee || 0) > (a.fee || 0);
            else if (this.sortMode === SORT_MODE.DURATION) shouldSwap = (b.used_min || 0) > (a.used_min || 0);
            else shouldSwap = a.serial > b.serial;

            if (shouldSwap) {
              let temp = sortedOutlets[j];
              sortedOutlets[j] = sortedOutlets[k];
              sortedOutlets[k] = temp;
            }
          }
        }

        let station: StationData = { name: s.name, id: s.id, outlets: sortedOutlets };
        result.push({station, freeCount: this.getFreeCount(sortedOutlets)} as StationWithFreeCount);
      }
    }

    // 按照选择的排序模式进行排序
    if (this.sortMode === SORT_MODE.FREE_COUNT) {
      // 按照空闲插座数量降序排序（数量多的排在上面）
      result.sort((a, b) => b.freeCount - a.freeCount);
    } else {
      // 其他排序模式保持原有逻辑
      result.sort((a, b) => {
        if (this.sortMode === SORT_MODE.POWER) {
          return this.getMaxPower(b.station.outlets) - this.getMaxPower(a.station.outlets);
        } else if (this.sortMode === SORT_MODE.FEE) {
          return this.getMaxFee(b.station.outlets) - this.getMaxFee(a.station.outlets);
        } else if (this.sortMode === SORT_MODE.DURATION) {
          return this.getMaxDuration(b.station.outlets) - this.getMaxDuration(a.station.outlets);
        } else {
          // 默认按站点名称排序
          return a.station.name.localeCompare(b.station.name);
        }
      });
    }

    return result;
  }

  // 获取站点插座最大功率
  private getMaxPower(outlets: OutletDetail[]): number {
    let maxPower = 0;
    for (let i = 0; i < outlets.length; i++) {
      const power = outlets[i].power_w || 0;
      if (power > maxPower) {
        maxPower = power;
      }
    }
    return maxPower;
  }

  // 获取站点插座最大费用
  private getMaxFee(outlets: OutletDetail[]): number {
    let maxFee = 0;
    for (let i = 0; i < outlets.length; i++) {
      const fee = outlets[i].fee || 0;
      if (fee > maxFee) {
        maxFee = fee;
      }
    }
    return maxFee;
  }

  // 获取站点插座最大使用时长
  private getMaxDuration(outlets: OutletDetail[]): number {
    let maxDuration = 0;
    for (let i = 0; i < outlets.length; i++) {
      const duration = outlets[i].used_min || 0;
      if (duration > maxDuration) {
        maxDuration = duration;
      }
    }
    return maxDuration;
  }

  // 根据排序模式值获取显示文本
  private getSortModeText(mode: number): string {
    switch (mode) {
      case SORT_MODE.FREE_COUNT:
        return '空闲插座数量';
      case SORT_MODE.SERIAL:
        return '插座编号';
      case SORT_MODE.POWER:
        return '功率';
      case SORT_MODE.FEE:
        return '费用';
      case SORT_MODE.DURATION:
        return '使用时长';
      default:
        return '空闲插座数量';
    }
  }



  // 构建排序菜单项
  @Builder
  buildSortMenuItem(text: string, mode: number) {
    Text(text)
      .fontSize(10)
      .fontColor(this.sortMode === mode ? '#0a84ff' : Color.White)
      .backgroundColor(this.sortMode === mode ? '#1c1c1e' : 'transparent')
      .width('100%')
      .height(24)
      .textAlign(TextAlign.Start)
      .padding({ left: 10 })
      .onClick(() => {
        this.sortMode = mode;
        this.showSortMenu = false;
      })
  }

  build() {
    Column() {


      Column() {
        // 头部胶囊
        Row() {
          if (this.isLoading) {
            Text("正在获取数据…").fontColor('#b4b4b4').fontSize(14)
          } else {
            Circle({ width: 12, height: 12 }).fill(this.getStats().anyFree ? '#30d158' : '#ff453a').margin({ right: 10 })
            Text(this.getStats().anyFree ? "有空闲插座" : "全部占用").fontColor(Color.White).fontSize(16).fontWeight(FontWeight.Medium)
            Blank()
            Text(`${this.getStats().free}/${this.getStats().total}`).fontColor(this.getStats().anyFree ? '#30d158' : '#ff453a').fontSize(16).fontWeight(FontWeight.Bold)
          }

          // 刷新按钮
          Button(this.canRefresh ? "刷新" : `冷却中(${Math.ceil(this.refreshCooldown / 1000)}s)`)
            .onClick(() => this.manualRefresh())
            .enabled(this.canRefresh)
            .fontSize(12)
            .backgroundColor(this.canRefresh ? '#0a84ff' : '#48484a')
            .fontColor(Color.White)
            .width(60)
            .height(28)
            .margin({ left: 10 })
        }
        .width('100%')
        .height(46)
        .padding({ left: 20, right: 20 })
        .onClick(() => { animateTo({ duration: 300 }, () => { this.isExpanded = !this.isExpanded; }); })

        // 展开面板
        if (this.isExpanded) {
          Column() {
            TextInput({ placeholder: '搜索站点名称…', text: this.searchText })
              .onChange((value) => { this.searchText = value; })
              .height(36)
              .backgroundColor('rgba(0,0,0,0.5)')
              .fontColor(Color.White)
              .margin({ top: 10, bottom: 10 })

            // 排序模式选择器 - 使用简化按钮组（节省空间）
            Row() {
              Text("排序:").fontColor('#8e8e93').fontSize(12).margin({ right: 10 })
              Button(this.getSortModeText(this.sortMode))
                .onClick(() => {
                  this.showSortMenu = !this.showSortMenu;
                })
                .fontSize(10)
                .backgroundColor('#48484a')
                .fontColor(Color.White)
                .width(80)
                .height(24)
                .borderRadius(4)
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .margin({ bottom: 10 })

            // 排序菜单
            if (this.showSortMenu) {
              Column() {
                this.buildSortMenuItem('空闲插座数量', SORT_MODE.FREE_COUNT)
                this.buildSortMenuItem('插座编号', SORT_MODE.SERIAL)
                this.buildSortMenuItem('功率', SORT_MODE.POWER)
                this.buildSortMenuItem('费用', SORT_MODE.FEE)
                this.buildSortMenuItem('使用时长', SORT_MODE.DURATION)
              }
              .backgroundColor('#2c2c2e')
              .borderRadius(4)
              .width(100)
              .margin({ bottom: 10 })
            }

            List({ space: 10 }) {
              ForEach(this.getFilteredStations(), (item: StationWithFreeCount, index: number) => {
                ListItem() {
                  Column() {
                    Row() {
                      Text(item.station.name).fontColor(Color.White).fontSize(14).fontWeight(FontWeight.Bold)
                      Blank()
                      Text(` ${item.freeCount}/${item.station.outlets.length} `)
                        .fontColor(item.freeCount > 0 ? '#30d158' : '#ff453a')
                        .backgroundColor(item.freeCount > 0 ? 'rgba(48,209,88,0.15)' : 'rgba(255,69,58,0.15)')
                        .borderRadius(10).fontSize(12).padding(4)
                    }
                    .width('100%').padding(12).border({ width: { bottom: 1 }, color: 'rgba(255,255,255,0.05)' })

                    Column({ space: 6 }) {
                      ForEach(item.station.outlets, (outlet: OutletDetail) => {
                        Row() {
                          Rect({ width: 3, height: 20 }).fill(outlet.status === 1 ? '#30d158' : (outlet.status === 2 ? '#ff453a' : '#ffd60a')).radius(1.5).margin({ right: 10 })
                          Text(`插座${outlet.serial}`).fontColor(Color.White).fontSize(13)
                          Blank()
                          if (outlet.status === 2) {
                            if (outlet.power_w !== undefined) Text(`${outlet.power_w}W`).chipStyle('#0a84ff')
                            if (outlet.fee !== undefined) Text(`¥${outlet.fee.toFixed(2)}`).chipStyle('#30d158')
                            if (outlet.used_min !== undefined) Text(`${outlet.used_min}分钟`).chipStyle('#ffd60a')
                          } else {
                            Text(outlet.status === 1 ? '空闲' : '故障').chipStyle(outlet.status === 1 ? '#30d158' : '#ff453a')
                          }
                        }
                        .width('100%')
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      })
                    }
                  }
                  .backgroundColor('#1c1c1e')
                  .borderRadius(8)
                  .padding(0)
                }
              })
            }
            .height(this.getExpandedHeight() - 160) // 减去搜索框和排序控件的高度
            .backgroundColor('#000000')
            .padding({ left: 10, right: 10 })
          }
          .width('100%')
          .backgroundColor('#000000')
          .padding({ left: 10, right: 10 })
          .height(this.getExpandedHeight())
        }
      }
      .width('100%')
      .backgroundColor('#000000')
      .borderRadius(12)
      .margin({ top: 10 })
    }
    .width('100%').height('100%').backgroundColor('#000000')
  }
}

// ==========================================
// 2. 站点选择器组件 (Tab 2)
// ==========================================
@Component
struct StationPickerUI {
  @Link stationConfig: Record<string, number>;

  @State allStations: StationBrief[] = [];
  @State searchText: string = "";
  @State selectedIds: number[] = [];
  @State isLoading: boolean = false;

  aboutToAppear() {
    this.loadSelectedStations();
    this.fetchAllStations();
  }

  // 加载已选中的站点
  loadSelectedStations() {
    this.selectedIds = Object.values(this.stationConfig);
  }

  // 获取所有可用站点
  async fetchAllStations() {
    this.isLoading = true;
    try {
      this.allStations = await ChargerApi.fetchNearbyStations();
    } catch (error) {
      console.error('Failed to fetch all stations:', error);
    }
    this.isLoading = false;
  }

  // 切换站点选择状态
  toggleStation(stationId: number) {
    const index = this.selectedIds.indexOf(stationId);
    if (index > -1) {
      // 取消选择
      this.selectedIds.splice(index, 1);
    } else {
      // 选择站点
      this.selectedIds.push(stationId);
    }
  }

  // 获取过滤后的站点列表
  getFilteredStations(): StationBrief[] {
    if (!this.searchText.trim()) {
      return this.allStations;
    }
    return this.allStations.filter(station =>
      station.stationName.toLowerCase().includes(this.searchText.toLowerCase())
    );
  }

  // 保存配置
  saveConfig() {
    if (this.selectedIds.length === 0) {
      promptAction.showToast({ message: '请至少选择一个站点', duration: 2000 });
      return;
    }

    // 构建新的配置对象
    const newConfig: Record<string, number> = {};
    this.allStations
      .filter(station => this.selectedIds.includes(station.stationId))
      .forEach(station => {
        newConfig[station.stationName] = station.stationId;
      });

    // 通知父组件保存配置 - 通过自定义事件或回调
    // 这里需要父组件传递回调函数来处理配置保存
    // 暂时先显示保存对话框
    promptAction.showToast({
      message: `已选择${this.selectedIds.length}个站点，请在配置对话框输入名称`,
      duration: 2000
    });
  }

  build() {
    Column() {
      // 搜索框
      TextInput({ placeholder: '搜索站点名称…', text: this.searchText })
        .onChange((value) => { this.searchText = value; })
        .width('90%')
        .height(40)
        .backgroundColor('#2c2c2e')
        .fontColor(Color.White)
        .borderRadius(8)
        .margin({ top: 16, bottom: 16 })

      // 加载状态
      if (this.isLoading) {
        Row() {
          LoadingProgress()
          Text('正在加载站点列表…').fontColor(Color.White).fontSize(14).margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(20)
      } else {
        // 站点列表
        List({ space: 8 }) {
          ForEach(this.getFilteredStations(), (station: StationBrief) => {
            ListItem() {
              Row() {
                // 选择框
                Checkbox({
                  name: station.stationName,
                  group: 'stations'
                })
                .select(this.selectedIds.includes(station.stationId))
                .onChange((checked: boolean) => {
                  this.toggleStation(station.stationId);
                })
                .size({ width: 20, height: 20 })
                .margin({ right: 12 })

                // 站点信息
                Column({ space: 2 }) {
                  Text(station.stationName)
                    .fontColor(Color.White)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)

                  if (station.address) {
                    Text(station.address)
                      .fontColor('#8e8e93')
                      .fontSize(12)
                  }
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#1c1c1e')
              .borderRadius(8)
            }
          })
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }

      // 保存按钮
      Button(`保存选中站点 (${this.selectedIds.length})`)
        .width('90%')
        .margin(16)
        .backgroundColor('#30d158')
        .onClick(() => this.saveConfig())

    }
    .width('100%').height('100%').backgroundColor('#000000')
  }
}

@Extend(Text) function chipStyle(bgColor: string) {
  .fontSize(10)
  .fontColor(Color.White)
  .backgroundColor(bgColor)
  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
  .borderRadius(8)
  .margin({ right: 5 })
}