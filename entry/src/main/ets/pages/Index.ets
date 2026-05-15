// Index.ets
import { ChargerApi } from './ChargerApi';
import { StationData, OutletDetail, SORT_MODE, StationBrief, ChargerConfig } from './ChargerModels';
import { ConfigManager } from './ConfigManager';
import { ThemeManager, ThemeMode, ThemeColors } from './ThemeManager';
import { APP_STORAGE_KEY_SYSTEM_DARK_MODE } from '../entryability/EntryAbility';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import display from '@ohos.display';
import { geoLocationManager } from '@kit.LocationKit';
import { Want, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

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
  // 辅助方法：显示Toast消息（API 18+兼容）
  private showToast(message: string, duration: number = 2000): void {
    try {
      this.getUIContext().getPromptAction().openToast({
        message: message,
        duration: duration
      });
    } catch (error) {
      console.error('Failed to show toast:', error);
    }
  }
  // 全局共享的站点配置
  @State stationConfig: Record<string, number> = ConfigManager.getDefaultConfig();
  @State configs: ChargerConfig[] = [];
  @State currentConfig: ChargerConfig | null = null;
  @State showConfigDialog: boolean = false;
  @State configDialogText: string = "";
  @State showConfigList: boolean = false;
  @State pendingConfig: Record<string, number> = {}; // 待保存的配置

  // 主题相关状态
  @State themeMode: ThemeMode = ThemeMode.SYSTEM; // 主题模式设置
  @StorageLink(APP_STORAGE_KEY_SYSTEM_DARK_MODE) @Watch('onSystemDarkModeChange') systemDarkMode: boolean = true; // 系统深色模式状态
  @State theme: ThemeColors = ThemeManager.getDarkColors(); // 当前主题颜色

  // 系统深色模式变化回调
  onSystemDarkModeChange(): void {
    console.log('System dark mode changed:', this.systemDarkMode);
    this.updateThemeColors();
  }

  // 获取当前是否为深色模式
  getIsDark(): boolean {
    if (this.themeMode === ThemeMode.SYSTEM) {
      return this.systemDarkMode;
    }
    return this.themeMode === ThemeMode.DARK;
  }

  // 更新主题颜色
  updateThemeColors(): void {
    this.theme = ThemeManager.getColors(this.getIsDark());
  }

  // 切换主题模式
  async setThemeMode(mode: ThemeMode): Promise<void> {
    this.themeMode = mode;
    this.updateThemeColors();
    const context = getContext(this) as common.UIAbilityContext;
    await ThemeManager.saveThemeMode(context, mode);

    // 设置应用颜色模式，确保 onConfigurationUpdate 能正确触发
    try {
      const applicationContext = context.getApplicationContext();
      if (mode === ThemeMode.SYSTEM) {
        // 跟随系统
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } else if (mode === ThemeMode.DARK) {
        // 深色模式
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        // 浅色模式
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      }
    } catch (error) {
      console.error('Failed to set color mode:', error);
    }
  }

  aboutToAppear() {
    console.log('MainApp aboutToAppear - loading configs');
    this.loadConfigs();
    this.initTheme();
  }

  // 初始化主题
  async initTheme() {
    // 获取 context
    const context = getContext(this) as common.UIAbilityContext;

    // 加载保存的主题模式
    this.themeMode = await ThemeManager.loadThemeMode(context);

    // 恢复应用颜色模式设置
    try {
      const applicationContext = context.getApplicationContext();
      if (this.themeMode === ThemeMode.SYSTEM) {
        // 跟随系统
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } else if (this.themeMode === ThemeMode.DARK) {
        // 深色模式
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        // 浅色模式
        applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      }
    } catch (error) {
      console.error('Failed to set color mode on init:', error);
    }

    // 更新主题颜色（系统主题状态已由 EntryAbility 通过 AppStorage 提供）
    this.updateThemeColors();
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
        this.showToast('配置名称不能为空', 2000);
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
        this.showToast('配置已保存', 2000);
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
    } else if (this.currentConfig) {
      // 更新现有配置
      console.log('Updating existing config:', this.currentConfig.name);
      await ConfigManager.updateConfig(this.currentConfig.id, name, configToSave);
      await this.loadConfigs();
      try {
        this.showToast('配置已更新', 2000);
      } catch (error) {
        console.error('Failed to show toast:', error);
      }
    } else {
      // 没有当前配置，也创建新配置
      console.log('Creating new config (no current config):', name);
      await ConfigManager.addConfig(name, configToSave);
      await this.loadConfigs();
      try {
        this.showToast('配置已保存', 2000);
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
      this.showToast('配置已删除', 2000);
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
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Column() {
            // 配置选择器
            if (this.configs.length > 0) {
              Row() {
                Text("当前配置:").fontColor(this.theme.textPrimary).fontSize(14)

                Button(this.currentConfig?.name || '请选择配置')
                  .onClick(() => { this.showConfigList = !this.showConfigList; })
                  .layoutWeight(1)
                  .margin({ left: 10 })
              }
              .width('90%')
              .padding(10)
              .backgroundColor(this.theme.cardBackground)
              .borderRadius(8)
              .margin({ top: 10 })

              // 配置列表
              if (this.showConfigList) {
                Column() {
                  ForEach(this.configs, (config: ChargerConfig) => {
                    Row() {
                      Text(config.name).fontColor(this.theme.textPrimary).fontSize(14)
                      Blank()
                      if (this.currentConfig?.id === config.id) {
                        Text("当前").fontColor(this.theme.success).fontSize(12)
                      }
                      Button("选择")
                        .onClick(async () => {
                          try {
                            await this.switchConfig(config.id);
                          } catch (error) {
                            console.error('Failed to switch config:', error);
                            try {
                              this.showToast('切换配置失败', 2000);
                            } catch (toastError) {
                              console.error('Failed to show error toast:', toastError);
                            }
                          }
                          this.showConfigList = false;
                        })
                        .fontSize(10)
                        .margin({ left: 10 })
                      Button("删除")
                        .onClick(async () => {
                          try {
                            await this.deleteConfig(config.id);
                          } catch (error) {
                            console.error('Failed to delete config:', error);
                            try {
                              this.showToast('删除配置失败', 2000);
                            } catch (toastError) {
                              console.error('Failed to show error toast:', toastError);
                            }
                          }
                        })
                        .fontSize(10)
                        .backgroundColor(this.theme.error)
                        .margin({ left: 5 })
                    }
                    .width('100%')
                    .padding(8)
                    .backgroundColor(this.theme.secondaryBackground)
                    .borderRadius(6)
                    .margin({ bottom: 5 })
                  })
                }
                .width('90%')
                .padding(10)
                .backgroundColor(this.theme.cardBackground)
                .borderRadius(8)
                .margin({ top: 5 })
              }
            }

            // 监控列表
            ChargerMonitorUI({
              stationConfig: $stationConfig,
              configs: $configs,
              currentConfig: $currentConfig,
              theme: this.theme
            })
          }
          .width('100%')
          .height('100%')
        }.tabBar("监控")

        TabContent() {
          MapViewerUI({ theme: this.theme })
        }.tabBar("地图")

        TabContent() {
          StationPickerUI({
            stationConfig: $stationConfig,
            theme: this.theme,
            themeMode: this.themeMode,
            onThemeChange: (mode: ThemeMode) => {
              this.setThemeMode(mode);
            },
            onSaveConfig: (newConfig: Record<string, number>) => {
              this.handleSaveConfigRequest(newConfig);
            }
          })
        }.tabBar("设置")
      }
      .layoutWeight(1)
      .scrollable(false)  // 禁用左右滑动切换，避免与地图手势冲突

      // 配置命名对话框
      if (this.showConfigDialog) {
        Column() {
          Text("配置名称").fontColor(this.theme.textPrimary).fontSize(16).fontWeight(FontWeight.Bold)
          TextInput({ placeholder: '输入配置名称', text: this.configDialogText })
            .onChange((value) => { this.configDialogText = value; })
            .width('100%')
            .height(40)
            .backgroundColor(this.theme.secondaryBackground)
            .fontColor(this.theme.textPrimary)
            .margin({ top: 10, bottom: 10 })

          Row() {
            Button("取消")
              .onClick(() => {
                this.showConfigDialog = false;
                this.configDialogText = "";
                this.pendingConfig = {};
              })
              .backgroundColor(this.theme.tertiaryBackground)
              .layoutWeight(1)
              .margin({ right: 10 })

            Button("保存")
              .onClick(async () => {
                try {
                  await this.saveCurrentConfig(this.configDialogText);
                } catch (error) {
                  console.error('Failed to save config:', error);
                  try {
                    this.showToast('保存配置失败', 2000);
                  } catch (toastError) {
                    console.error('Failed to show error toast:', toastError);
                  }
                }
              })
              .backgroundColor(this.theme.accent)
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width(300)
        .padding(20)
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(12)
        .alignItems(HorizontalAlign.Center)
        .position({ x: '50%', y: '40%' })
        .translate({ x: -150, y: -100 })
      }
    }
    .width('100%').layoutWeight(1).backgroundColor(this.theme.background)
  }
}

// ==========================================
// 1. 监控页面组件 (Tab 1)
// ==========================================
@Component
struct ChargerMonitorUI {
  // 辅助方法：显示Toast消息（API 18+兼容）
  private showToast(message: string, duration: number = 2000): void {
    try {
      this.getUIContext().getPromptAction().openToast({
        message: message,
        duration: duration
      });
    } catch (error) {
      console.error('Failed to show toast:', error);
    }
  }

  @Link @Watch('onStationConfigChange') stationConfig: Record<string, number>;
  @Link configs: ChargerConfig[];
  @Link currentConfig: ChargerConfig | null;
  // 主题参数
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();

  @State isExpanded: boolean = false;
  @State stations: StationData[] = [];
  @State searchText: string = "";          // 实际搜索值
  @State searchInputText: string = "";     // 输入框临时值
  @State sortMode: number = SORT_MODE.FREE_COUNT;
  @State showSortMenu: boolean = false;
  @State isLoading: boolean = true;
  @State showConfigList: boolean = false;
  @State canRefresh: boolean = true; // 是否可以刷新
  @State refreshCooldown: number = 0; // 刷新冷却时间
  @State screenHeight: number = 800; // 默认屏幕高度
  @State screenWidth: number = 400; // 默认屏幕宽度

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

  // 获取屏幕尺寸
  getScreenHeight() {
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      this.screenHeight = defaultDisplay.height;
      this.screenWidth = defaultDisplay.width;
      console.log('Screen size detected:', this.screenWidth, 'x', this.screenHeight);
    } catch (error) {
      console.error('Failed to get screen size, using default:', error);
      this.screenHeight = 800; // 默认高度
      this.screenWidth = 400; // 默认宽度
    }
  }

  // 计算自适应展开高度
  getExpandedHeight(): number {
    // 已弃用固定高度计算，改用 layoutWeight 自适应
    return 0;
  }

  aboutToDisappear() {
    // 清理所有定时器
    if (this.refreshInterval !== -1) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = -1;
    }
    if (this.cooldownInterval !== -1) {
      clearInterval(this.cooldownInterval);
      this.cooldownInterval = -1;
    }
    console.log('ChargerMonitorUI: All timers cleaned up');
  }

  // 监听stationConfig变化 - 防抖响应
  onStationConfigChange() {
    console.log('Config changed detected by @Watch, scheduling data refresh...');
    // 使用防抖机制，避免频繁刷新
    setTimeout(() => {
      this.fetchData();
    }, 300); // 300ms防抖延迟
  }

  // 手动刷新数据
  async manualRefresh() {
    if (!this.canRefresh) {
      const remainingTime = Math.ceil(this.refreshCooldown / 1000);
      try {
        this.showToast(`刷新过快，请等待${remainingTime}秒后重试`, 2000);
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

    // 使用Promise.all并行获取数据，提高效率
    const stationPromises = keys.map(async (name) => {
      const id = this.stationConfig[name];
      try {
        const data = await ChargerApi.fetchStation(id, name);
        // 验证数据有效性
        if (data && data.outlets && data.outlets.length > 0) {
          return data;
        }
      } catch (error) {
        console.error(`Failed to fetch station ${name}:`, error);
      }
      return null;
    });

    const results = await Promise.allSettled(stationPromises);

    results.forEach(result => {
      if (result.status === 'fulfilled' && result.value) {
        newStations.push(result.value);
      }
    });

    this.stations = newStations;
    this.isLoading = false;
    console.log(`Data fetch completed: ${newStations.length} stations loaded`);
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
  // 构建排序菜单项
  @Builder
  buildSortMenuItem(text: string, mode: number) {
    Row() {
      Text(text)
        .fontSize(14)
        .fontColor(this.sortMode === mode ? this.theme.accent : this.theme.textPrimary)
        .fontWeight(this.sortMode === mode ? FontWeight.Medium : FontWeight.Normal)
      
      if (this.sortMode === mode) {
        Blank()
        Text('✓')
          .fontSize(14)
          .fontColor(this.theme.accent)
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.sortMode === mode ? this.theme.overlay : 'transparent')
    .borderRadius(8)
    .onClick(() => {
      this.sortMode = mode;
      this.showSortMenu = false;
    })
  }

  // 构建排序下拉菜单
  @Builder
  SortMenuBuilder() {
    Column() {
      this.buildSortMenuItem('空闲插座数量', SORT_MODE.FREE_COUNT)
      this.buildSortMenuItem('插座编号', SORT_MODE.SERIAL)
      this.buildSortMenuItem('功率', SORT_MODE.POWER)
      this.buildSortMenuItem('费用', SORT_MODE.FEE)
      this.buildSortMenuItem('使用时长', SORT_MODE.DURATION)
    }
    .width(160)
    .padding(4)
  }

  build() {
    Column() {


      Column() {
        // 头部胶囊
        Row() {
          if (this.isLoading) {
            Text("正在获取数据…").fontColor(this.theme.textTertiary).fontSize(14)
          } else {
            Circle({ width: 12, height: 12 }).fill(this.getStats().anyFree ? this.theme.success : this.theme.error).margin({ right: 10 })
            Text(this.getStats().anyFree ? "有空闲插座" : "全部占用").fontColor(this.theme.textPrimary).fontSize(16).fontWeight(FontWeight.Medium)
            Blank()
            Text(`${this.getStats().free}/${this.getStats().total}`).fontColor(this.getStats().anyFree ? this.theme.success : this.theme.error).fontSize(16).fontWeight(FontWeight.Bold)
          }

          // 刷新按钮
          Button(this.canRefresh ? "刷新" : `冷却中(${Math.ceil(this.refreshCooldown / 1000)}s)`)
            .onClick(async () => {
              try {
                await this.manualRefresh();
              } catch (error) {
                console.error('Manual refresh failed:', error);
                try {
                  this.showToast('刷新失败', 2000);
                } catch (toastError) {
                  console.error('Failed to show error toast:', toastError);
                }
              }
            })
            .enabled(this.canRefresh)
            .fontSize(12)
            .backgroundColor(this.canRefresh ? this.theme.accent : this.theme.tertiaryBackground)
            .fontColor('#ffffff')
            .width(60)
            .height(28)
            .margin({ left: 10 })
        }
        .width('100%')
        .height(46)
        .padding({ left: 20, right: 20 })
        .onClick(() => { this.isExpanded = !this.isExpanded; })

        // 展开面板
        if (this.isExpanded) {
          Column() {
            // 搜索框 - 统一样式，带搜索按钮
            Row() {
              TextInput({ placeholder: '搜索站点名称…', text: this.searchInputText })
                .onChange((value) => { this.searchInputText = value; })
                .layoutWeight(1)
                .height(36)
                .backgroundColor(this.theme.secondaryBackground)
                .fontColor(this.theme.textPrimary)
                .placeholderColor(this.theme.textSecondary)
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
              
              Button('搜索')
                .fontSize(13)
                .fontColor('#ffffff')
                .backgroundColor(this.theme.accent)
                .borderRadius(8)
                .height(36)
                .margin({ left: 8 })
                .onClick(() => {
                  this.searchText = this.searchInputText;
                })
            }
            .width('100%')
            .margin({ top: 10, bottom: 10 })

            // 排序模式选择器 - 使用 bindMenu 实现下拉菜单
            Row() {
              Text("排序:")
                .fontColor(this.theme.textSecondary)
                .fontSize(13)
                .margin({ right: 8 })
              
              // 排序按钮 - 绑定下拉菜单
              Row() {
                Text(this.getSortModeText(this.sortMode))
                  .fontSize(13)
                  .fontColor(this.theme.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('▼')
                  .fontSize(10)
                  .fontColor(this.theme.textSecondary)
                  .margin({ left: 6 })
              }
              .padding({ left: 12, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.theme.tertiaryBackground)
              .borderRadius(8)
              .bindMenu(this.showSortMenu, this.SortMenuBuilder(), {
                placement: Placement.BottomLeft,
                onDisappear: () => {
                  this.showSortMenu = false;
                }
              })
              .onClick(() => {
                this.showSortMenu = !this.showSortMenu;
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .margin({ bottom: 10 })

            List({ space: 10 }) {
              ForEach(this.getFilteredStations(), (item: StationWithFreeCount, index: number) => {
                ListItem() {
                  Column() {
                    Row() {
                      Text(item.station.name).fontColor(this.theme.textPrimary).fontSize(14).fontWeight(FontWeight.Bold)
                      Blank()
                      Text(` ${item.freeCount}/${item.station.outlets.length} `)
                        .fontColor(item.freeCount > 0 ? this.theme.success : this.theme.error)
                        .backgroundColor(item.freeCount > 0 ? 'rgba(48,209,88,0.15)' : 'rgba(255,69,58,0.15)')
                        .borderRadius(10).fontSize(12).padding(4)
                    }
                    .width('100%').padding(12).border({ width: { bottom: 1 }, color: this.theme.border })

                    Column({ space: 6 }) {
                      ForEach(item.station.outlets, (outlet: OutletDetail) => {
                        Row() {
                          Rect({ width: 3, height: 20 }).fill(outlet.status === 1 ? this.theme.success : (outlet.status === 2 ? this.theme.error : '#ffd60a')).radius(1.5).margin({ right: 10 })
                          Text(`插座${outlet.serial}`).fontColor(this.theme.textPrimary).fontSize(13)
                          Blank()
                          if (outlet.status === 2) {
                            if (outlet.power_w !== undefined) Text(`${outlet.power_w}W`).chipStyle(this.theme.accent)
                            if (outlet.fee !== undefined) Text(`¥${outlet.fee.toFixed(2)}`).chipStyle(this.theme.success)
                            if (outlet.used_min !== undefined) Text(`${outlet.used_min}分钟`).chipStyle('#ffd60a')
                          } else {
                            Text(outlet.status === 1 ? '空闲' : '故障').chipStyle(outlet.status === 1 ? this.theme.success : this.theme.error)
                          }
                        }
                        .width('100%')
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      })
                    }
                  }
                  .backgroundColor(this.theme.cardBackground)
                  .borderRadius(8)
                  .padding(0)
                }
              })
            }
            .layoutWeight(1) // 自动填充剩余空间，支持滑动
            .backgroundColor(this.theme.background)
            .padding({ left: 10, right: 10 })
          }
          .width('100%')
          .layoutWeight(1) // 展开面板填充剩余空间，铺满到底部导航栏
          .backgroundColor(this.theme.background)
          .padding({ left: 10, right: 10 })
        }
      }
      .width('100%')
      .backgroundColor(this.theme.background)
      .borderRadius(12)
      .margin({ top: 10 })
    }
    .width('100%').layoutWeight(1).backgroundColor(this.theme.background)
  }
}

// ==========================================
// 2. 站点选择器组件 (Tab 2)
// ==========================================
@Component
struct StationPickerUI {
  // 辅助方法：显示Toast消息（API 18+兼容）
  private showToast(message: string, duration: number = 2000): void {
    try {
      this.getUIContext().getPromptAction().openToast({
        message: message,
        duration: duration
      });
    } catch (error) {
      console.error('Failed to show toast:', error);
    }
  }

  @Link stationConfig: Record<string, number>;
  // 保存配置的回调函数
  onSaveConfig?: (newConfig: Record<string, number>) => void;
  // 主题切换回调
  onThemeChange?: (mode: ThemeMode) => void;
  // 主题参数
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();
  @Prop themeMode: ThemeMode = ThemeMode.SYSTEM;

  @State allStations: StationBrief[] = [];
  @State searchText: string = "";          // 实际搜索值
  @State searchInputText: string = "";     // 输入框临时值
  @State selectedIds: number[] = [];
  @State isLoading: boolean = false;
  @State loadingMessage: string = "正在加载站点列表…";
  @State locationStatus: string = ""; // 位置状态提示

  // 定位服务状态监听回调
  private locationServiceStateCallback?: (state: boolean) => void;

  aboutToAppear() {
    this.loadSelectedStations();
    this.fetchAllStations();
    this.setupLocationServiceListener();
  }

  aboutToDisappear() {
    // 移除定位服务状态监听
    if (this.locationServiceStateCallback) {
      try {
        geoLocationManager.off('locationEnabledChange', this.locationServiceStateCallback);
      } catch (error) {
        console.error('Failed to remove location service listener:', error);
      }
    }
  }

  // 设置定位服务状态监听
  setupLocationServiceListener() {
    try {
      this.locationServiceStateCallback = (state: boolean) => {
        console.log('📍 Location service state changed:', state);
        
        // 如果定位服务开启且当前列表为空，自动刷新
        if (state && this.allStations.length === 0 && !this.isLoading) {
          console.log('🔄 Auto-refreshing stations after location service enabled');
          this.fetchAllStations();
        }
      };
      
      geoLocationManager.on('locationEnabledChange', this.locationServiceStateCallback);
      console.log('✅ Location service listener registered');
    } catch (error) {
      console.error('Failed to setup location service listener:', error);
    }
  }

  // 加载已选中的站点
  loadSelectedStations() {
    this.selectedIds = Object.values(this.stationConfig);
  }

  // 获取所有可用站点
  async fetchAllStations() {
    this.isLoading = true;
    this.loadingMessage = "正在获取位置信息…";
    try {
      // 获取UIAbilityContext并传递给API，以便在需要时请求权限
      const context = getContext(this) as common.UIAbilityContext;
      
      // 调用API获取站点，同时获取位置状态
      const result = await ChargerApi.fetchNearbyStations(context);
      this.allStations = result.stations;
      this.locationStatus = result.locationStatus;
      
      // 检查是否需要提示用户开启定位服务
      if (result.needOpenLocationService) {
        this.showLocationServiceDialog();
      }

      if (this.allStations.length === 0 && !result.needOpenLocationService) {
        this.loadingMessage = "未找到附近充电站";
        console.error('No stations found. Location status:', this.locationStatus);
      }
    } catch (error) {
      console.error('Failed to fetch all stations:', error);
      this.loadingMessage = "加载失败，请检查网络";
    }
    this.isLoading = false;
  }

  // 跳转到系统设置的位置服务页面
  openLocationSettings() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'location_manager_settings'
      };
      context.startAbility(want)
        .then(() => {
          console.log('✅ Opened location settings');
        })
        .catch((err: BusinessError) => {
          console.error(`Failed to open location settings: ${err.code}, ${err.message}`);
        });
    } catch (error) {
      console.error('Failed to open location settings:', error);
    }
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
      this.showToast('请至少选择一个站点', 2000);
      return;
    }

    // 构建新的配置对象
    const newConfig: Record<string, number> = {};
    this.allStations
      .filter(station => this.selectedIds.includes(station.stationId))
      .forEach(station => {
        newConfig[station.stationName] = station.stationId;
      });

    // 检查是否有有效的配置数据
    if (Object.keys(newConfig).length === 0) {
      this.showToast('站点列表加载失败，请检查网络和权限设置', 3000);
      console.error('No valid station data available. allStations:', this.allStations.length);
      return;
    }

    // 调用父组件传递的回调函数来保存配置
    if (this.onSaveConfig) {
      this.onSaveConfig(newConfig);
    } else {
      // 如果没有回调函数，显示提示
      this.showToast(`已选择${this.selectedIds.length}个站点，但无法保存配置`, 2000);
      console.error('onSaveConfig callback not provided');
    }
  }

  build() {
    Column() {
      // 主题设置区域
      Column() {
        Text('外观设置')
          .fontColor(this.theme.textPrimary)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width('90%')
          .margin({ top: 16, bottom: 8 })

        Row() {
          Button('跟随系统')
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.themeMode === ThemeMode.SYSTEM ? this.theme.accent : this.theme.secondaryBackground)
            .fontColor(this.themeMode === ThemeMode.SYSTEM ? '#ffffff' : this.theme.textPrimary)
            .borderRadius(8)
            .onClick(() => {
              if (this.onThemeChange) {
                this.onThemeChange(ThemeMode.SYSTEM);
              }
            })
          Button('深色模式')
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.themeMode === ThemeMode.DARK ? this.theme.accent : this.theme.secondaryBackground)
            .fontColor(this.themeMode === ThemeMode.DARK ? '#ffffff' : this.theme.textPrimary)
            .borderRadius(8)
            .margin({ left: 4, right: 4 })
            .onClick(() => {
              if (this.onThemeChange) {
                this.onThemeChange(ThemeMode.DARK);
              }
            })
          Button('浅色模式')
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.themeMode === ThemeMode.LIGHT ? this.theme.accent : this.theme.secondaryBackground)
            .fontColor(this.themeMode === ThemeMode.LIGHT ? '#ffffff' : this.theme.textPrimary)
            .borderRadius(8)
            .onClick(() => {
              if (this.onThemeChange) {
                this.onThemeChange(ThemeMode.LIGHT);
              }
            })
        }
        .width('90%')
        .margin({ bottom: 16 })
      }
      .width('100%')

      // 站点设置标题
      Text('站点配置')
        .fontColor(this.theme.textPrimary)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('90%')
        .margin({ bottom: 8 })

      // 搜索框 - 统一样式，带搜索按钮
      Row() {
        TextInput({ placeholder: '搜索站点名称…', text: this.searchInputText })
          .onChange((value) => { this.searchInputText = value; })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(this.theme.secondaryBackground)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textSecondary)
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
        
        Button('搜索')
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor(this.theme.accent)
          .borderRadius(8)
          .height(36)
          .margin({ left: 8 })
          .onClick(() => {
            this.searchText = this.searchInputText;
          })
      }
      .width('90%')
      .margin({ bottom: 8 })

      // 位置状态提示
      if (this.locationStatus) {
        Text(this.locationStatus)
          .fontColor(this.theme.textSecondary)
          .fontSize(12)
          .width('90%')
          .margin({ bottom: 8 })
      }

      // 加载状态
      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(24)
            .height(24)
          Text(this.loadingMessage).fontColor(this.theme.textPrimary).fontSize(14).margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(20)
      } else if (this.allStations.length === 0) {
        // 空状态提示
        Column({ space: 16 }) {
          Text('📭')
            .fontSize(48)
          Text('未找到附近充电站')
            .fontColor(this.theme.textPrimary)
            .fontSize(16)
          if (this.locationStatus.includes('默认位置')) {
            Text('请确保设备定位服务已开启')
              .fontColor(this.theme.textSecondary)
              .fontSize(14)
          }
          if (this.locationStatus.includes('网络')) {
            Text('请检查网络连接')
              .fontColor(this.theme.textSecondary)
              .fontSize(14)
          }
          // 刷新按钮
          Button('刷新')
            .backgroundColor(this.theme.success)
            .fontColor('#ffffff')
            .width(120)
            .height(40)
            .margin({ top: 16 })
            .onClick(() => {
              this.fetchAllStations();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
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
                    .fontColor(this.theme.textPrimary)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)

                  if (station.address) {
                    Text(station.address)
                      .fontColor(this.theme.textSecondary)
                      .fontSize(12)
                  }
                  
                  // 显示距离
                  if (station.formattedDistance) {
                    Text(`距离: ${station.formattedDistance}`)
                      .fontColor(this.theme.success)
                      .fontSize(11)
                  }
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding(16)
              .backgroundColor(this.theme.cardBackground)
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
        .backgroundColor(this.theme.success)
        .onClick(() => this.saveConfig())

    }
    .width('100%').height('100%').backgroundColor(this.theme.background)
  }

  // 显示开启定位服务弹窗
  showLocationServiceDialog() {
    promptAction.showDialog({
      title: '📍 需要开启定位服务',
      message: '请前往系统设置开启位置服务，以获取附近的充电站信息',
      buttons: [
        { text: '取消', color: '#8e8e93' },
        { text: '去设置', color: '#30d158' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        // 用户点击"去设置"
        this.openLocationSettings();
      }
    }).catch((err: BusinessError) => {
      console.error('showDialog error:', err);
    });
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

// ==========================================
// 3. 地图查看组件 (Tab 3)
// 支持双指缩放和单指移动
// ==========================================
@Component
struct MapViewerUI {
  @Prop theme: ThemeColors = ThemeManager.getDarkColors(); // 主题颜色
  // 缩放比例
  @State scaleValue: number = 1.0;
  // 上次缩放值（用于双指缩放计算）
  @State pinchValue: number = 1.0;
  // X轴偏移
  @State offsetX: number = 0;
  // Y轴偏移
  @State offsetY: number = 0;
  // 上次X偏移（用于单指移动计算）
  @State lastOffsetX: number = 0;
  // 上次Y偏移（用于单指移动计算）
  @State lastOffsetY: number = 0;
  // 缩放中心相对于图片的百分比位置
  private pinchCenterRatioX: number = 0.5;
  private pinchCenterRatioY: number = 0.5;
  // 最小缩放比例
  private minScale: number = 0.5;
  // 最大缩放比例
  private maxScale: number = 5.0;
  // 拖动灵敏度系数
  private dragSensitivity: number = 2.5;
  // 容器尺寸（用于计算缩放中心）
  private containerWidth: number = 0;
  private containerHeight: number = 0;

  build() {
    Column() {
      // 提示信息和重置按钮
      Row() {
        Text("双指缩放 | 单指拖动")
          .fontColor(this.theme.textSecondary)
          .fontSize(12)
        Blank()
        Text(`缩放: ${(this.scaleValue * 100).toFixed(0)}%`)
          .fontColor(this.theme.textSecondary)
          .fontSize(12)
          .margin({ right: 15 })
        // 重置按钮
        Button("重置")
          .fontSize(12)
          .height(28)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.theme.tertiaryBackground)
          .fontColor(this.theme.textPrimary)
          .onClick(() => {
            this.resetView();
          })
      }
      .width('95%')
      .padding({ top: 10, bottom: 10 })

      // 地图显示区域
      Stack() {
        Image($r('app.media.map'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              // 双指缩放手势
              PinchGesture({ fingers: 2 })
                .onActionStart((event: GestureEvent) => {
                  this.pinchValue = this.scaleValue;
                  // 计算缩放中心相对于图片的百分比位置
                  this.calculatePinchCenterRatio(event.pinchCenterX, event.pinchCenterY);
                })
                .onActionUpdate((event: GestureEvent) => {
                  const oldScale = this.scaleValue;
                  let newScale = this.pinchValue * event.scale;
                  // 限制缩放范围
                  newScale = Math.max(this.minScale, Math.min(this.maxScale, newScale));
                  this.scaleValue = newScale;
                  // 以双指中点为中心调整偏移量
                  this.adjustOffsetOnPinchScale(oldScale, newScale);
                })
                .onActionEnd(() => {
                  this.pinchValue = this.scaleValue;
                }),
              // 单指拖动手势（放大时生效）
              PanGesture({ fingers: 1, direction: PanDirection.All })
                .onActionStart(() => {
                  this.lastOffsetX = this.offsetX;
                  this.lastOffsetY = this.offsetY;
                })
                .onActionUpdate((event: GestureEvent) => {
                  // 只有放大状态下才允许拖动
                  if (this.scaleValue > 1.0) {
                    // 提高灵敏度：乘以灵敏度系数
                    this.offsetX = this.lastOffsetX + event.offsetX * this.dragSensitivity;
                    this.offsetY = this.lastOffsetY + event.offsetY * this.dragSensitivity;
                    // 限制偏移范围
                    this.clampOffset();
                  }
                })
                .onActionEnd(() => {
                  this.lastOffsetX = this.offsetX;
                  this.lastOffsetY = this.offsetY;
                })
            )
          )
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        // 更新容器尺寸
        this.containerWidth = Number(newValue.width);
        this.containerHeight = Number(newValue.height);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  // 计算缩放中心相对于图片的百分比位置
  private calculatePinchCenterRatio(centerX: number, centerY: number) {
    // 图片当前显示尺寸
    const displayWidth = this.containerWidth * this.scaleValue;
    const displayHeight = this.containerHeight * this.scaleValue;
    // 图片左上角位置（居中显示 + 偏移）
    const imgLeft = (this.containerWidth - displayWidth) / 2 + this.offsetX;
    const imgTop = (this.containerHeight - displayHeight) / 2 + this.offsetY;
    // 计算百分比位置
    this.pinchCenterRatioX = (centerX - imgLeft) / displayWidth;
    this.pinchCenterRatioY = (centerY - imgTop) / displayHeight;
    // 限制在 0-1 范围内
    this.pinchCenterRatioX = Math.max(0, Math.min(1, this.pinchCenterRatioX));
    this.pinchCenterRatioY = Math.max(0, Math.min(1, this.pinchCenterRatioY));
  }

  // 以双指中点为中心调整偏移量
  private adjustOffsetOnPinchScale(oldScale: number, newScale: number) {
    if (newScale <= 1.0) {
      // 缩放到小于等于1时，重置偏移
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    // 计算缩放前后图片尺寸变化
    const oldDisplayWidth = this.containerWidth * oldScale;
    const oldDisplayHeight = this.containerHeight * oldScale;
    const newDisplayWidth = this.containerWidth * newScale;
    const newDisplayHeight = this.containerHeight * newScale;
    // 缩放中心在旧图片中的位置
    const centerInOldImgX = oldDisplayWidth * this.pinchCenterRatioX;
    const centerInOldImgY = oldDisplayHeight * this.pinchCenterRatioY;
    // 缩放中心在新图片中的位置
    const centerInNewImgX = newDisplayWidth * this.pinchCenterRatioX;
    const centerInNewImgY = newDisplayHeight * this.pinchCenterRatioY;
    // 计算新的偏移量，使缩放中心点位置保持不变
    // 旧图片左上角位置
    const oldImgLeft = (this.containerWidth - oldDisplayWidth) / 2 + this.offsetX;
    const oldImgTop = (this.containerHeight - oldDisplayHeight) / 2 + this.offsetY;
    // 缩放中心在屏幕上的位置
    const centerScreenX = oldImgLeft + centerInOldImgX;
    const centerScreenY = oldImgTop + centerInOldImgY;
    // 新图片左上角位置（使缩放中心保持不变）
    const newImgLeft = centerScreenX - centerInNewImgX;
    const newImgTop = centerScreenY - centerInNewImgY;
    // 计算新偏移量
    this.offsetX = newImgLeft - (this.containerWidth - newDisplayWidth) / 2;
    this.offsetY = newImgTop - (this.containerHeight - newDisplayHeight) / 2;
    // 限制偏移范围
    this.clampOffset();
  }

  // 重置视图
  private resetView() {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.scaleValue = 1.0;
      this.pinchValue = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
      this.lastOffsetX = 0;
      this.lastOffsetY = 0;
    });
  }

  // 限制偏移范围
  private clampOffset() {
    // 计算最大允许偏移量（根据缩放比例动态计算）
    const maxOffset = (this.scaleValue - 1) * 300;
    this.offsetX = Math.max(-maxOffset, Math.min(maxOffset, this.offsetX));
    this.offsetY = Math.max(-maxOffset, Math.min(maxOffset, this.offsetY));
  }
}