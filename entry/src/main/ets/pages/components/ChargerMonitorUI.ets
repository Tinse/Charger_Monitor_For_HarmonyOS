// ChargerMonitorUI.ets - 充电站监控页面组件
import { StationData, OutletDetail, SORT_MODE, ChargerConfig, OutletStatus } from '../ChargerModels';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { StationService } from '../services/StationService';
import { ApiConfig } from '../ApiConfig';

export interface StatsResult {
  total: number;
  free: number;
  occupied: number;
  broken: number;
  anyFree: boolean;
}

export interface StationWithFreeCount {
  station: StationData;
  freeCount: number;
}

@Component
export struct ChargerMonitorUI {
  @Prop stationConfig: Record<string, number> = {};
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();

  @State @Watch('onFilterChange') stations: StationData[] = [];
  @State @Watch('onFilterChange') searchText: string = "";
  private searchInputText: string = "";
  @State @Watch('onFilterChange') sortMode: number = SORT_MODE.FREE_COUNT;
  @State filteredStations: StationWithFreeCount[] = [];
  @State showSortMenu: boolean = false;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State isRefreshing: boolean = false;
  @State canRefresh: boolean = true;
  @State refreshCooldown: number = 0;

  // 配置相关状态
  @State configs: ChargerConfig[] = [];
  @State currentConfig: ChargerConfig | null = null;


  // 编辑配置对话框状态
  @State showEditDialog: boolean = false;
  @State editingConfig: ChargerConfig | null = null;
  @State editingConfigName: string = "";
  @State editingStations: Record<string, number> = {};

  private refreshInterval: number = -1;
  private cooldownInterval: number = -1;

  aboutToAppear() {
    this.loadConfigs();
    this.fetchData();
    this.startAutoRefresh();
  }

  aboutToDisappear() {
    this.stopAutoRefresh();
    if (this.cooldownInterval !== -1) {
      clearInterval(this.cooldownInterval);
      this.cooldownInterval = -1;
    }
  }

  onPageShow() {
    this.startAutoRefresh();
  }

  onPageHide() {
    this.stopAutoRefresh();
  }

  private startAutoRefresh() {
    if (this.refreshInterval === -1) {
      this.refreshInterval = setInterval(() => {
        this.fetchData();
      }, ApiConfig.AUTO_REFRESH_INTERVAL);
    }
  }

  private stopAutoRefresh() {
    if (this.refreshInterval !== -1) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = -1;
    }
  }

  async loadConfigs() {
    const configStorage = await ConfigService.loadConfigs();
    this.configs = configStorage.configs;

    if (configStorage.currentConfigId) {
      this.currentConfig = configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
    }
  }

  async switchConfig(configId: string) {
    await ConfigService.switchConfig(configId);
    await this.loadConfigs();
    await this.fetchData();
  }

  async deleteConfig(configId: string) {
    await ConfigService.deleteConfig(configId);
    await this.loadConfigs();
    ErrorHandler.showToast(this.getUIContext(), '配置已删除');
  }

  // 打开编辑配置对话框
  openEditDialog(config: ChargerConfig) {
    this.editingConfig = config;
    this.editingConfigName = config.name;
    this.editingStations = JSON.parse(JSON.stringify(config.stations));
    this.showEditDialog = true;
  }

  // 保存编辑后的配置
  async saveEditedConfig() {
    if (!this.editingConfig) return;

    if (this.editingConfigName.trim() === '') {
      ErrorHandler.showToast(this.getUIContext(), '请输入配置名称');
      return;
    }

    if (Object.keys(this.editingStations).length === 0) {
      ErrorHandler.showToast(this.getUIContext(), '配置中至少需要一个站点');
      return;
    }

    try {
      await ConfigService.updateConfig(
        this.editingConfig.id,
        this.editingConfigName.trim(),
        this.editingStations
      );
      await this.loadConfigs();
      ErrorHandler.showToast(this.getUIContext(), '配置已更新');
      this.showEditDialog = false;
    } catch (error) {
      ErrorHandler.handle(error, 'ChargerMonitorUI.saveEditedConfig');
      ErrorHandler.showToast(this.getUIContext(), '保存配置失败');
    }
  }

  // 从编辑配置中移除站点
  removeStationFromEdit(stationName: string) {
    const newStations: Record<string, number> = {};
    Object.keys(this.editingStations).forEach(key => {
      if (key !== stationName) {
        newStations[key] = this.editingStations[key];
      }
    });
    this.editingStations = newStations;
  }

  async manualRefresh() {
    if (!this.canRefresh) {
      const remainingTime = Math.ceil(this.refreshCooldown / 1000);
      ErrorHandler.showToast(this.getUIContext(), `刷新过快，请等待${remainingTime}秒后重试`);
      return;
    }

    this.canRefresh = false;
    this.refreshCooldown = ApiConfig.MANUAL_REFRESH_COOLDOWN;

    await this.fetchData();

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
    this.errorMessage = '';
    try {
      this.stations = await StationService.fetchStationsForConfig(this.stationConfig);
    } catch (error) {
      ErrorHandler.handle(error, 'ChargerMonitorUI.fetchData');
      this.errorMessage = '加载失败，请检查网络连接';
    }
    this.isLoading = false;
  }

  getStats(): StatsResult {
    let total = 0;
    let free = 0;
    let occupied = 0;
    let broken = 0;
    this.stations.forEach(s => {
      total += s.outlets.length;
      free += s.outlets.filter(o => o.status === OutletStatus.FREE).length;
      occupied += s.outlets.filter(o => o.status === OutletStatus.OCCUPIED).length;
      broken += s.outlets.filter(o => o.status === OutletStatus.BROKEN).length;
    });
    return { total, free, occupied, broken, anyFree: free > 0 };
  }

  private getFreeCount(outlets: OutletDetail[]): number {
    let count = 0;
    for (let i = 0; i < outlets.length; i++) {
      if (outlets[i].status === OutletStatus.FREE) count++;
    }
    return count;
  }

  private compareOutlets(a: OutletDetail, b: OutletDetail): number {
    switch (this.sortMode) {
      case SORT_MODE.POWER:
        return (b.power_w || 0) - (a.power_w || 0);
      case SORT_MODE.FEE:
        return (b.fee || 0) - (a.fee || 0);
      case SORT_MODE.DURATION:
        return (b.used_min || 0) - (a.used_min || 0);
      default:
        return a.serial - b.serial;
    }
  }

  private compareStations(a: StationWithFreeCount, b: StationWithFreeCount): number {
    switch (this.sortMode) {
      case SORT_MODE.FREE_COUNT:
        return b.freeCount - a.freeCount;
      case SORT_MODE.POWER:
        return this.getMaxPower(b.station.outlets) - this.getMaxPower(a.station.outlets);
      case SORT_MODE.FEE:
        return this.getMaxFee(b.station.outlets) - this.getMaxFee(a.station.outlets);
      case SORT_MODE.DURATION:
        return this.getMaxDuration(b.station.outlets) - this.getMaxDuration(a.station.outlets);
      default:
        return a.station.name.localeCompare(b.station.name);
    }
  }

  getFilteredStations(): StationWithFreeCount[] {
    return this.filteredStations;
  }

  // 当 stations/searchText/sortMode 变化时重新计算
  onFilterChange() {
    this.filteredStations = this.stations
      .filter(s => s.name.toLowerCase().includes(this.searchText.toLowerCase()))
      .map(s => {
        const sortedOutlets = [...s.outlets].sort((a, b) => this.compareOutlets(a, b));
        const station: StationData = { name: s.name, id: s.id, outlets: sortedOutlets };
        return { station, freeCount: this.getFreeCount(sortedOutlets) } as StationWithFreeCount;
      })
      .sort((a, b) => this.compareStations(a, b));
  }

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

  private getSortModeText(mode: number): string {
    switch (mode) {
      case SORT_MODE.FREE_COUNT:
        return '空闲数量';
      case SORT_MODE.SERIAL:
        return '插座编号';
      case SORT_MODE.POWER:
        return '功率';
      case SORT_MODE.FEE:
        return '费用';
      case SORT_MODE.DURATION:
        return '时长';
      default:
        return '空闲数量';
    }
  }

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

  @Builder
  SortMenuBuilder() {
    Column() {
      this.buildSortMenuItem('空闲数量', SORT_MODE.FREE_COUNT)
      this.buildSortMenuItem('插座编号', SORT_MODE.SERIAL)
      this.buildSortMenuItem('功率', SORT_MODE.POWER)
      this.buildSortMenuItem('费用', SORT_MODE.FEE)
      this.buildSortMenuItem('时长', SORT_MODE.DURATION)
    }
    .width(160)
    .padding(4)
  }

  build() {
    Column() {
      Refresh({ refreshing: this.isRefreshing }) {
        Column() {
          // 1. 统计概览卡片
          Column() {
            // 状态行
            Row() {
              if (this.isLoading) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                Text("正在获取数据…")
                  .fontColor(this.theme.textTertiary)
                  .fontSize(14)
              } else {
                Circle({ width: 10, height: 10 })
                  .fill(this.getStats().anyFree ? this.theme.success : this.theme.error)
                  .margin({ right: 8 })

                Text(this.getStats().anyFree ? "有空闲插座" : "全部占用")
                  .fontColor(this.theme.textPrimary)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)

                Blank()

                Button(this.canRefresh ? "刷新" : `${Math.ceil(this.refreshCooldown / 1000)}s`)
                  .onClick(async () => {
                    try {
                      await this.manualRefresh();
                    } catch (error) {
                      ErrorHandler.handle(error, 'ChargerMonitorUI.manualRefresh');
                      ErrorHandler.showToast(this.getUIContext(), '刷新失败');
                    }
                  })
                  .enabled(this.canRefresh)
                  .fontSize(12)
                  .backgroundColor(this.canRefresh ? this.theme.accent : this.theme.tertiaryBackground)
                  .fontColor('#ffffff')
                  .width(56)
                  .height(28)
              }
            }
            .width('100%')

            // 统计数字行
            if (!this.isLoading) {
              Row() {
                // 空闲
                Column() {
                  Text(`${this.getStats().free}`)
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.success)
                  Text('空闲')
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Divider()
                  .vertical(true)
                  .height(40)
                  .color(this.theme.border)

                // 占用
                Column() {
                  Text(`${this.getStats().occupied}`)
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.error)
                  Text('占用')
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Divider()
                  .vertical(true)
                  .height(40)
                  .color(this.theme.border)

                // 故障
                Column() {
                  Text(`${this.getStats().broken}`)
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffd60a')
                  Text('故障')
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Divider()
                  .vertical(true)
                  .height(40)
                  .color(this.theme.border)

                // 总计
                Column() {
                  Text(`${this.getStats().total}`)
                    .fontSize(36)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.textPrimary)
                  Text('总计')
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 16 })

      // 2. 搜索和排序工具栏
      Row() {
        // 搜索框
        TextInput({ placeholder: '搜索站点…', text: this.searchInputText })
          .onChange((value) => { this.searchInputText = value; })
          .onSubmit(() => {
            this.searchText = this.searchInputText;
          })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(this.theme.secondaryBackground)
          .fontColor(this.theme.textPrimary)
          .placeholderColor(this.theme.textSecondary)
          .borderRadius(8)
          .padding({ left: 12, right: 12 })

        // 排序按钮
        Row() {
          Text(this.getSortModeText(this.sortMode))
            .fontSize(13)
            .fontColor(this.theme.textPrimary)
          Text('▼')
            .fontSize(10)
            .fontColor(this.theme.textSecondary)
            .margin({ left: 4 })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.theme.secondaryBackground)
        .borderRadius(8)
        .margin({ left: 8 })
        .bindMenu(this.showSortMenu, this.SortMenuBuilder(), {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.showSortMenu = false;
          }
        })
        .onClick(() => {
          this.showSortMenu = !this.showSortMenu;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      // 3. 配置选择器（水平 Chips）
      if (this.configs.length > 0) {
        Column() {
          Row() {
            Text('配置')
              .fontColor(this.theme.textSecondary)
              .fontSize(12)

            Blank()

            Text('编辑')
              .fontSize(12)
              .fontColor(this.theme.accent)
              .onClick(() => {
                if (this.currentConfig) {
                  this.openEditDialog(this.currentConfig);
                }
              })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 6 })

          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.configs, (config: ChargerConfig) => {
                Text(config.name)
                  .fontSize(13)
                  .fontColor(this.currentConfig?.id === config.id ? '#ffffff' : this.theme.textPrimary)
                  .fontWeight(this.currentConfig?.id === config.id ? FontWeight.Medium : FontWeight.Normal)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.currentConfig?.id === config.id ? this.theme.accent : this.theme.secondaryBackground)
                  .borderRadius(16)
                  .onClick(async () => {
                    if (this.currentConfig?.id !== config.id) {
                      try {
                        await this.switchConfig(config.id);
                      } catch (error) {
                        ErrorHandler.handle(error, 'ChargerMonitorUI.switchConfig');
                        ErrorHandler.showToast(this.getUIContext(), '切换配置失败');
                      }
                    }
                  })
              }, (config: ChargerConfig) => config.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      // 4. 站点列表
      if (this.isLoading && this.stations.length === 0) {
        // 加载状态
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text("加载中...")
            .fontColor(this.theme.textTertiary)
            .fontSize(14)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.stations.length === 0) {
        // 空状态 / 错误状态
        Column({ space: 12 }) {
          if (this.errorMessage) {
            // 错误状态
            Text('加载失败')
              .fontColor(this.theme.error)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Text(this.errorMessage)
              .fontColor(this.theme.textSecondary)
              .fontSize(14)
              .textAlign(TextAlign.Center)
          } else {
            // 空状态
            Text('暂无充电站数据')
              .fontColor(this.theme.textPrimary)
              .fontSize(16)
            Text('请检查配置是否正确')
              .fontColor(this.theme.textSecondary)
              .fontSize(14)
          }
          Button(this.errorMessage ? '重试' : '刷新')
            .onClick(() => {
              StationService.clearCache();
              this.fetchData();
            })
            .backgroundColor(this.theme.accent)
            .fontColor('#ffffff')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 站点列表
        List({ space: 12 }) {
          ForEach(this.getFilteredStations(), (item: StationWithFreeCount) => {
            ListItem() {
              Column() {
                // 站点头部
                Row() {
                  Column() {
                    Text(item.station.name)
                      .fontColor(this.theme.textPrimary)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                    Text(`${item.station.outlets.length} 个插座`)
                      .fontColor(this.theme.textSecondary)
                      .fontSize(12)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 空闲/总数徽章
                  Row() {
                    Circle({ width: 8, height: 8 })
                      .fill(item.freeCount > 0 ? this.theme.success : this.theme.error)
                      .margin({ right: 6 })
                    Text(`${item.freeCount}/${item.station.outlets.length}`)
                      .fontColor(item.freeCount > 0 ? this.theme.success : this.theme.error)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                  }
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(item.freeCount > 0 ? 'rgba(48,209,88,0.15)' : 'rgba(255,69,58,0.15)')
                  .borderRadius(10)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .alignItems(VerticalAlign.Center)

                // 分隔线
                Divider()
                  .color(this.theme.border)
                  .margin({ left: 16, right: 16 })

                // 插座列表
                Column({ space: 6 }) {
                  ForEach(item.station.outlets, (outlet: OutletDetail) => {
                    Row() {
                      // 状态指示灯
                      Circle({ width: 10, height: 10 })
                        .fill(outlet.status === OutletStatus.FREE ? this.theme.success : (outlet.status === OutletStatus.OCCUPIED ? this.theme.error : '#ffd60a'))
                        .margin({ right: 10 })

                      // 插座名称
                      Text(`插座${outlet.serial}`)
                        .fontColor(this.theme.textPrimary)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)

                      Blank()

                      // 状态信息
                      if (outlet.status === OutletStatus.OCCUPIED) {
                        // 占用状态 - 显示详情
                        if (outlet.power_w !== undefined) {
                          Text(`${outlet.power_w}W`)
                            .fontSize(11)
                            .fontColor(Color.White)
                            .backgroundColor(this.theme.accent)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .borderRadius(6)
                            .margin({ right: 4 })
                        }
                        if (outlet.fee !== undefined) {
                          Text(`¥${outlet.fee.toFixed(2)}`)
                            .fontSize(11)
                            .fontColor(Color.White)
                            .backgroundColor(this.theme.success)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .borderRadius(6)
                            .margin({ right: 4 })
                        }
                        if (outlet.used_min !== undefined) {
                          Text(`${outlet.used_min}分钟`)
                            .fontSize(11)
                            .fontColor(Color.White)
                            .backgroundColor('#ffd60a')
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .borderRadius(6)
                        }
                      } else {
                        // 空闲或故障状态 - 彩色徽章
                        Row() {
                          Text(outlet.status === OutletStatus.FREE ? '空闲' : '故障')
                            .fontSize(12)
                            .fontColor(Color.White)
                            .fontWeight(FontWeight.Medium)
                        }
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .backgroundColor(outlet.status === OutletStatus.FREE ? this.theme.success : this.theme.error)
                        .borderRadius(8)
                      }
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
                  }, (outlet: OutletDetail) => outlet.serial.toString())
                }
                .padding({ top: 8, bottom: 12 })
              }
              .backgroundColor(this.theme.cardBackground)
              .borderRadius(12)
            }
          }, (item: StationWithFreeCount) => item.station.id.toString())

          // 底部安全区域占位
          ListItem() {
            Divider()
              .color('transparent')
              .height(100)
          }
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12 })
        .backgroundColor(this.theme.background)
        }
      }
      }
      .onRefreshing(async () => {
        StationService.clearCache();
        await this.fetchData();
        this.isRefreshing = false;
      })

      // 编辑配置对话框
      if (this.showEditDialog && this.editingConfig) {
        Column() {
          // 标题
          Text('编辑配置')
            .fontColor(this.theme.textPrimary)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)

          // 配置名称输入
          TextInput({ placeholder: '配置名称', text: this.editingConfigName })
            .onChange((value) => { this.editingConfigName = value; })
            .width('100%')
            .height(44)
            .backgroundColor(this.theme.secondaryBackground)
            .fontColor(this.theme.textPrimary)
            .margin({ top: 16 })

          // 站点列表标题
          Text(`站点列表 (${Object.keys(this.editingStations).length})`)
            .fontColor(this.theme.textSecondary)
            .fontSize(14)
            .margin({ top: 16 })
            .alignSelf(ItemAlign.Start)

          // 站点列表
          List({ space: 8 }) {
            ForEach(Object.keys(this.editingStations), (stationName: string) => {
              ListItem() {
                Row() {
                  Text(stationName)
                    .fontColor(this.theme.textPrimary)
                    .fontSize(14)
                    .layoutWeight(1)

                  Text('删除')
                    .fontSize(12)
                    .fontColor(this.theme.error)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor('rgba(255,69,58,0.15)')
                    .borderRadius(6)
                    .onClick(() => {
                      this.removeStationFromEdit(stationName);
                    })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.theme.secondaryBackground)
                .borderRadius(8)
              }
            }, (stationName: string) => stationName)
          }
          .width('100%')
          .height(200)
          .margin({ top: 8 })

          // 按钮
          Column({ space: 12 }) {
            // 删除配置按钮
            Button('删除此配置')
              .width('100%')
              .height(40)
              .backgroundColor('rgba(255,69,58,0.15)')
              .fontColor(this.theme.error)
              .onClick(async () => {
                if (this.editingConfig) {
                  await this.deleteConfig(this.editingConfig.id);
                  this.showEditDialog = false;
                }
              })

            Row() {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .backgroundColor(this.theme.tertiaryBackground)
                .fontColor(this.theme.textPrimary)
                .onClick(() => {
                  this.showEditDialog = false;
                })

              Button('保存')
                .layoutWeight(1)
                .height(40)
                .backgroundColor(this.theme.accent)
                .fontColor('#ffffff')
                .margin({ left: 12 })
                .onClick(async () => {
                  await this.saveEditedConfig();
                })
            }
            .width('100%')
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('90%')
        .height('80%')
        .padding(20)
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(16)
        .position({ x: '50%', y: '50%' })
        .translate({ x: '-50%', y: '-50%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }
}