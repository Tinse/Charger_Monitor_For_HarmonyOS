// ChargerMonitorUI.ets - 充电站监控页面组件
import { StationData, OutletDetail, SORT_MODE, ChargerConfig, OutletStatus } from '../ChargerModels';
import { StationSelection } from '../utils/StationSelection';
import { RefreshGate } from '../utils/RefreshGate';
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

@ComponentV2
export struct ChargerMonitorUI {
  @Param stationConfig: Record<string, number> = {};
  @Param isActive: boolean = true;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();

  @Local stations: StationData[] = [];
  @Local searchText: string = "";
  @Local searchInputText: string = "";
  private searchTimer: number = -1;
  @Local sortMode: number = SORT_MODE.FREE_COUNT;
  @Local filteredStations: StationWithFreeCount[] = [];
  @Local showSortMenu: boolean = false;
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';
  @Local isRefreshing: boolean = false;
  @Local isFetching: boolean = false;
  @Local lastUpdated: string = '';
  @Event onManageConfig: (id: string) => void = () => {};
  @Local refreshCooldown: number = 0;

  // 配置相关状态
  @Local configs: ChargerConfig[] = [];
  @Local currentConfig: ChargerConfig | null = null;


  private refreshInterval: number = -1;
  private cooldownInterval: number = -1;
  private fetchVersion: number = 0;
  private refreshGate: RefreshGate = new RefreshGate(ApiConfig.MANUAL_REFRESH_COOLDOWN);

  aboutToAppear() {
    this.loadConfigs();
    if (this.isActive) this.fetchData();
    this.startAutoRefresh();
  }

  aboutToDisappear() {
    this.fetchVersion++;
    this.isFetching = false;
    this.stopAutoRefresh();
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.cooldownInterval !== -1) {
      clearInterval(this.cooldownInterval);
      this.cooldownInterval = -1;
    }
  }

  @Monitor('isActive')
  onActivityChange() {
    if (this.isActive) {
      this.loadConfigs();
      this.fetchData();
      this.startAutoRefresh();
      this.startCooldownTicker();
    } else {
      this.showSortMenu = false;
      this.stopAutoRefresh();
      this.stopCooldownTicker();
    }
  }

  @Monitor('stationConfig')
  onStationConfigChange() {
    this.loadConfigs();
    this.fetchVersion++;
    this.stations = [];
    this.isFetching = false;
    this.isLoading = true;
    this.errorMessage = '';
    this.lastUpdated = '';
    this.searchInputText = '';
    this.searchText = '';
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    if (this.isActive) this.fetchData(true);
  }

  onSearchInput(value: string) {
    this.searchInputText = value;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchText = value;
      this.searchTimer = -1;
    }, ApiConfig.DEBOUNCE_DELAY);
  }

  private startAutoRefresh() {
    if (this.isActive && this.refreshInterval === -1) {
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
    try {
      const configStorage = await ConfigService.loadConfigs();
      this.configs = configStorage.configs;
      this.currentConfig = configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
    } catch (error) {
      this.errorMessage = '配置读取失败，请重试；已有数据仍保留';
      ErrorHandler.handle(error, 'ChargerMonitorUI.loadConfigs');
      ErrorHandler.showToast(this.getUIContext(), '配置读取失败，请重试');
    }
  }

  async switchConfig(configId: string) {
    await ConfigService.switchConfig(configId);
    await this.loadConfigs();
  }

  private stopCooldownTicker() {
    if (this.cooldownInterval !== -1) clearInterval(this.cooldownInterval);
    this.cooldownInterval = -1;
  }

  private startCooldownTicker() {
    this.stopCooldownTicker();
    this.refreshCooldown = this.refreshGate.remaining(Date.now());
    if (this.refreshCooldown === 0) return;
    this.cooldownInterval = setInterval(() => {
      this.refreshCooldown = this.refreshGate.remaining(Date.now());
      if (this.refreshCooldown === 0) this.stopCooldownTicker();
    }, 100);
  }

  async manualRefresh(source: string = 'button') {
    if (this.isFetching || !this.refreshGate.tryStart(Date.now())) {
      this.isRefreshing = false;
      ErrorHandler.showToast(this.getUIContext(), this.isFetching ? '正在刷新，请稍候' : '刷新过快，请稍后重试');
      return;
    }
    this.startCooldownTicker();
    console.info(`[MonitorRefresh] start ${source}`);
    try {
      StationService.clearCache();
      const success = await this.fetchData();
      if (success) ErrorHandler.showToast(this.getUIContext(), '数据已更新');
      console.info(`[MonitorRefresh] complete ${source}: ${success}`);
    } finally {
      this.refreshGate.finish();
      this.isRefreshing = false;
      this.refreshCooldown = this.refreshGate.remaining(Date.now());
    }
  }

  async fetchData(force: boolean = false): Promise<boolean> {
    if (this.isFetching && !force) return false;
    const version = ++this.fetchVersion;
    if (Object.keys(this.stationConfig).length === 0) {
      this.stations = [];
      this.lastUpdated = '';
      this.errorMessage = '';
      this.isFetching = false;
      this.isLoading = false;
      return false;
    }
    this.isFetching = true;
    this.errorMessage = '';
    try {
      const result = await StationService.fetchStationsForConfig(this.stationConfig);
      if (version !== this.fetchVersion) return false;
      if (result.stations.length === 0) {
        this.errorMessage = this.stations.length ? '刷新失败，保留上次数据；请检查网络后重试' : '站点加载失败，请检查网络后重试';
        return false;
      }
      this.stations = result.stations;
      if (result.oldestFetchedAt !== undefined) {
        const fetched = new Date(result.oldestFetchedAt);
        this.lastUpdated = `数据获取于 ${(fetched.getMonth() + 1).toString().padStart(2, '0')}-${fetched.getDate().toString().padStart(2, '0')} ${fetched.getHours().toString().padStart(2, '0')}:${fetched.getMinutes().toString().padStart(2, '0')}:${fetched.getSeconds().toString().padStart(2, '0')}（已加载站点中最早）`;
      } else {
        this.lastUpdated = '';
      }
      if (result.failedNames.length) {
        this.errorMessage = `有 ${result.failedNames.length} 个站点未能加载：${result.failedNames.join('、')}`;
      }
      return result.failedNames.length === 0;
    } catch (error) {
      if (version === this.fetchVersion) this.errorMessage = '加载失败，请检查网络连接后重试';
      ErrorHandler.handle(error, 'ChargerMonitorUI.fetchData');
      return false;
    } finally {
      if (version === this.fetchVersion) {
        this.isFetching = false;
        this.isLoading = false;
      }
    }
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
  @Monitor('stations', 'searchText', 'sortMode')
  onFilterChange() {
    this.filteredStations = this.stations
      .filter(s => StationSelection.normalize(s.name).includes(StationSelection.normalize(this.searchText)))
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
      Refresh({ refreshing: $$this.isRefreshing }) {
        List({ space: 12 }) {
          ListItem() {
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
                  .foregroundColor(this.getStats().anyFree ? this.theme.success : this.theme.error)
                  .margin({ right: 8 })

                Text(this.stations.length === 0 ? "尚未获取数据" : this.getStats().anyFree ? "有空闲插座" : "暂无空闲插座")
                  .fontColor(this.theme.textPrimary)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)

                Blank()

                Button() {
                  Text(this.refreshCooldown > 0 ? `${Math.ceil(this.refreshCooldown / 1000)}s` : this.isFetching ? '刷新中' : '刷新')
                    .fontSize(12).fontColor('#ffffff')
                }.id('monitorRefreshButton')
                  .onClick(async () => {
                    try {
                      await this.manualRefresh();
                    } catch (error) {
                      ErrorHandler.handle(error, 'ChargerMonitorUI.manualRefresh');
                      ErrorHandler.showToast(this.getUIContext(), '刷新失败');
                    }
                  })
                  .enabled(Object.keys(this.stationConfig).length > 0 && !this.isFetching && this.refreshCooldown === 0)
                  .fontSize(12)
                  .backgroundColor(!this.isFetching && this.refreshCooldown === 0 ? this.theme.accent : this.theme.tertiaryBackground)
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
          .onChange((value: string) => { this.onSearchInput(value); })
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

            Button('管理配置')
              .fontSize(12).height(36).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
              .onClick(() => { if (this.currentConfig) this.onManageConfig(this.currentConfig.id); })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 6 })

          Scroll() {
            Row({ space: 8 }) {
              Repeat<ChargerConfig>(this.configs).each((configRow: RepeatItem<ChargerConfig>) => {
                Text(configRow.item.name)
                  .fontSize(13)
                  .fontColor(this.currentConfig?.id === configRow.item.id ? '#ffffff' : this.theme.textPrimary)
                  .fontWeight(this.currentConfig?.id === configRow.item.id ? FontWeight.Medium : FontWeight.Normal)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.currentConfig?.id === configRow.item.id ? this.theme.accent : this.theme.secondaryBackground)
                  .borderRadius(16)
                  .onClick(async () => {
                    if (this.currentConfig?.id !== configRow.item.id) {
                      try {
                        await this.switchConfig(configRow.item.id);
                      } catch (error) {
                        ErrorHandler.handle(error, 'ChargerMonitorUI.switchConfig');
                        ErrorHandler.showToast(this.getUIContext(), '切换配置失败');
                      }
                    }
                  })
              }).key((config: ChargerConfig) => config.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

              if (this.lastUpdated) {
                Text(this.lastUpdated).fontSize(12).fontColor(this.theme.textSecondary).width('100%').padding(16)
              }
              if (this.errorMessage && this.stations.length) {
                Text(this.errorMessage).fontSize(13).fontColor(this.theme.error).width('100%').padding(16)
              }
            }.width('100%')
          }
      // 4. 站点列表
      if (this.isLoading && this.stations.length === 0) {
        ListItem() { Column() {
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
        .height(200).justifyContent(FlexAlign.Center) }
      } else if (this.stations.length === 0) {
        // 空状态 / 错误状态
        ListItem() { Column({ space: 12 }) {
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
            Text(Object.keys(this.stationConfig).length === 0 ? '暂无配置' : '暂无充电站数据')
              .fontColor(this.theme.textPrimary)
              .fontSize(16)
            Text(Object.keys(this.stationConfig).length === 0 ? '到设置中增加配置或恢复默认配置' : '请检查配置是否正确')
              .fontColor(this.theme.textSecondary)
              .fontSize(14)
          }
          Button(Object.keys(this.stationConfig).length === 0 ? '增加配置' : this.errorMessage ? '重试' : '刷新')
            .onClick(() => {
              if (Object.keys(this.stationConfig).length === 0) this.onManageConfig('');
              else this.manualRefresh('retry');
            })
            .backgroundColor(this.theme.accent)
            .fontColor('#ffffff')
        }
        .width('100%')
        .layoutWeight(1)
        .height(200).justifyContent(FlexAlign.Center) }
      } else if (this.filteredStations.length === 0) {
        ListItem() { Column({ space: 12 }) {
          Text('没有匹配的站点').fontColor(this.theme.textPrimary)
          Button('清除搜索').onClick(() => {
            if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
            this.searchInputText = '';
            this.searchText = '';
          })
        }.height(200).width('100%').justifyContent(FlexAlign.Center) }
      } else {
        // 站点列表
          Repeat<StationWithFreeCount>(this.filteredStations).each((stationRow: RepeatItem<StationWithFreeCount>) => {
            ListItem() {
              Column() {
                // 站点头部
                Row() {
                  Column() {
                    Text(stationRow.item.station.name)
                      .fontColor(this.theme.textPrimary)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                    Text(`${stationRow.item.station.outlets.length} 个插座`)
                      .fontColor(this.theme.textSecondary)
                      .fontSize(12)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 空闲/总数徽章
                  Row() {
                    Circle({ width: 8, height: 8 })
                      .foregroundColor(stationRow.item.freeCount > 0 ? this.theme.success : this.theme.error)
                      .margin({ right: 6 })
                    Text(`${stationRow.item.freeCount}/${stationRow.item.station.outlets.length}`)
                      .fontColor(stationRow.item.freeCount > 0 ? this.theme.success : this.theme.error)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                  }
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(stationRow.item.freeCount > 0 ? 'rgba(48,209,88,0.15)' : 'rgba(255,69,58,0.15)')
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
                  ForEach(stationRow.item.station.outlets, (outlet: OutletDetail) => {
                    Row() {
                      // 状态指示灯
                      Circle({ width: 10, height: 10 })
                        .foregroundColor(outlet.status === OutletStatus.FREE ? this.theme.success : (outlet.status === OutletStatus.OCCUPIED ? this.theme.error : '#ffd60a'))
                        .margin({ right: 10 })

                      // 插座名称
                      Text(`插座${outlet.serial}`)
                        .fontColor(this.theme.textPrimary)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)

                      Blank()

                      // 状态信息
                      if (outlet.status === OutletStatus.OCCUPIED) {
                        if (outlet.power_w === undefined && outlet.fee === undefined && outlet.used_min === undefined) {
                          Text('占用 · 详情暂不可用').fontSize(12).fontColor(this.theme.textSecondary)
                        }
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
                            .fontColor('#252525')
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
                  }, (outlet: OutletDetail) => JSON.stringify(outlet))
                }
                .padding({ top: 8, bottom: 12 })
              }
              .backgroundColor(this.theme.cardBackground)
              .borderRadius(12)
            }
          }).key((item: StationWithFreeCount) => item.station.id.toString()).virtualScroll()

      }
          // 底部安全区域占位
          ListItem() {
            Divider()
              .color('transparent')
              .height(100)
          }
        }
        .width('100%').height('100%')
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Auto)
      }.width('100%').layoutWeight(1).pullToRefresh(true)
        .onRefreshing(() => { this.manualRefresh('pull'); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }
}
