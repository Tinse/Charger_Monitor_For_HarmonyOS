// StationPickerUI.ets - 站点选择器组件
import { ChargerConfig, StationBrief } from '../ChargerModels';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { StationService } from '../services/StationService';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { geoLocationManager } from '@kit.LocationKit';
import { StationSelection } from '../utils/StationSelection';
import { SearchBar } from './SearchBar';
import { ApiConfig } from '../ApiConfig';

@ComponentV2
export struct StationPickerUI {
  @Param isActive: boolean = false;
  @Param initialConfig: ChargerConfig | null = null;
  @Param editConfigId: string = '';
  @Event onDirtyChange: (dirty: boolean) => void = () => {};
  private originalName: string = '';
  private originalIds: number[] = [];
  private lastLocationStatus: string = '';

  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onSaved: () => void = () => {};
  @Local configName: string = '';
  @Local isSaving: boolean = false;
  @Local showSelectedOnly: boolean = false;

  @Local allStations: StationBrief[] = [];
  @Local searchText: string = "";
  @Local searchInputText: string = "";
  private searchTimer: number = -1;
  @Local selectedIds: number[] = [];
  @Local isLoading: boolean = false;
  @Local loadingMessage: string = "正在加载站点列表…";
  @Local errorMessage: string = '';
  @Local locationStatus: string = "";

  @Local filteredStations: StationBrief[] = [];

  private locationServiceStateCallback?: (state: boolean) => void;
  private hasAppeared: boolean = false;
  private hasFetched: boolean = false;
  private fetchSequence: number = 0;
  private needsLocationService: boolean = false;

  @Monitor('isActive')
  onVisibilityChange() {
    if (this.hasAppeared && this.isActive && !this.isLoading && (!this.hasFetched || this.needsLocationService || this.allStations.length === 0 || this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限'))) {
      if (this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限')) StationService.clearCache();
      this.fetchAllStations();
    }
  }

  aboutToAppear() {
    this.hasAppeared = true;
    const initial = this.initialConfig;
    if (initial) {
      this.configName = this.editConfigId ? initial.name : `${initial.name} 副本`;
      this.selectedIds = Object.values(initial.stations);
      this.allStations = Object.keys(initial.stations).map(name => ({
        stationId: initial.stations[name], stationName: name,
        address: '已保存站点，附近查询后更新', freeNum: -1
      } as StationBrief));
    }
    this.originalName = this.editConfigId ? this.configName : '';
    this.originalIds = this.editConfigId ? [...this.selectedIds] : [];
    this.onDirtyChange(this.hasChanges());
    this.updateFilteredStations();
    if (this.isActive) {
      this.fetchAllStations();
    }
    this.setupLocationServiceListener();
  }

  hasChanges(): boolean {
    return this.configName !== this.originalName || this.selectedIds.length !== this.originalIds.length ||
      this.selectedIds.some(id => !this.originalIds.includes(id));
  }

  @Monitor('configName', 'selectedIds')
  onDraftChange() { this.onDirtyChange(this.hasChanges()); }

  async refreshLocation() {
    if (this.isLoading) return;
    StationService.clearCache();
    await this.fetchAllStations();
  }

  updateFilteredStations() {
    const matches = StationSelection.filter(this.allStations, this.searchText);
    this.filteredStations = this.showSelectedOnly ? matches.filter(station => this.selectedIds.includes(station.stationId)) : matches;
  }

  applyKeyword(keyword: string) {
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    this.searchInputText = keyword;
    this.searchText = keyword;
    this.showSelectedOnly = false;
    this.updateFilteredStations();
  }

  aboutToDisappear() {
    this.hasAppeared = false;
    this.fetchSequence++;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (canIUse('SystemCapability.Location.Location.Core')) {
      if (!this.locationServiceStateCallback) {
        return;
      }
      try {
        geoLocationManager.off('locationEnabledChange', this.locationServiceStateCallback);
      } catch (error) {
        ErrorHandler.handle(error, 'StationPickerUI.aboutToDisappear');
      }
    }
  }

  setupLocationServiceListener() {
    if (canIUse('SystemCapability.Location.Location.Core')) {
      try {
        this.locationServiceStateCallback = (state: boolean) => {
          if (state && this.isActive && (this.needsLocationService || this.allStations.length === 0 || this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限')) && !this.isLoading) {
            this.refreshLocation();
          }
        };
        geoLocationManager.on('locationEnabledChange', this.locationServiceStateCallback);
      } catch (error) {
        ErrorHandler.handle(error, 'StationPickerUI.setupLocationServiceListener');
      }
    }
  }

  onSearchInput(value: string) {
    this.searchInputText = value;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchText = value;
      this.updateFilteredStations();
      this.searchTimer = -1;
    }, ApiConfig.DEBOUNCE_DELAY);
  }

  async fetchAllStations() {
    if (this.isLoading) return;
    this.hasFetched = true;
    const request = ++this.fetchSequence;
    this.isLoading = true;
    this.errorMessage = '';
    this.loadingMessage = "正在获取位置信息…";

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await StationService.fetchNearbyStations(context);
      if (!this.hasAppeared || request !== this.fetchSequence) return;
      this.allStations = StationSelection.mergeAvailable(result.stations, this.allStations, this.selectedIds);
      this.locationStatus = result.locationStatus;
      this.lastLocationStatus = result.locationStatus;
      this.needsLocationService = result.needOpenLocationService === true;

      if (result.needOpenLocationService && this.isActive) {
        this.showLocationServiceDialog();
      }

      if ((this.needsLocationService || this.allStations.length === 0 || this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限')) && !result.needOpenLocationService) {
        this.loadingMessage = "未找到附近充电站";
      }

      this.updateFilteredStations();
    } catch (error) {
      if (this.hasAppeared && request === this.fetchSequence) {
        ErrorHandler.handle(error, 'StationPickerUI.fetchAllStations');
        this.errorMessage = '加载失败，请检查网络连接';
        this.locationStatus = this.errorMessage;
      }
    } finally {
      if (request === this.fetchSequence) this.isLoading = false;
    }
  }

  openLocationSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'location_manager_settings'
      };
      context.startAbility(want)
        .then(() => {
          console.log('Opened location settings');
        })
        .catch((err: BusinessError) => {
          ErrorHandler.handle(err, 'StationPickerUI.openLocationSettings');
        });
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.openLocationSettings');
    }
  }

  setStationSelected(stationId: number, checked: boolean) {
    const selected = this.selectedIds.includes(stationId);
    if (selected === checked) {
      return;
    }
    this.selectedIds = checked ? [...this.selectedIds, stationId] : this.selectedIds.filter(id => id !== stationId);
    if (this.showSelectedOnly) this.updateFilteredStations();
  }

  selectAllStations() {
    this.selectedIds = StationSelection.selectMatches(this.selectedIds, this.filteredStations);
  }

  deselectAllStations() {
    this.selectedIds = StationSelection.clearMatches(this.selectedIds, this.filteredStations);
    this.updateFilteredStations();
  }

  stationSummary(station: StationBrief): string {
    const distance = station.formattedDistance || '距离未知';
    return `${distance} · ${station.freeNum < 0 ? '空闲数量未知' : `空闲 ${station.freeNum}`}`;
  }

  isStationSelected(stationId: number): boolean {
    return this.selectedIds.includes(stationId);
  }

  getFilteredStations(): StationBrief[] {
    return this.filteredStations;
  }

  async saveConfig() {
    if (this.isSaving) return;
    if (!this.configName.trim()) {
      ErrorHandler.showToast(this.getUIContext(), '请填写配置名称');
      return;
    }
    if (this.selectedIds.length === 0) { ErrorHandler.showToast(this.getUIContext(), '请至少选择一个站点'); return; }
    this.isSaving = true;
    try {
      const stations = StationSelection.toStationMap(this.allStations, this.selectedIds);
      if (this.editConfigId) {
        const updated = await ConfigService.updateConfig(this.editConfigId, this.configName.trim(), stations);
        if (!updated) throw new Error('配置不存在或无法编辑');
      } else {
        await ConfigService.addConfig(this.configName.trim(), stations);
      }
      if (!this.hasAppeared) return;
      this.onDirtyChange(false);
      ErrorHandler.showToast(this.getUIContext(), '配置已保存，可在监控页切换');
      this.onSaved();
    } catch (error) {
      if (!this.hasAppeared) return;
      ErrorHandler.handle(error, 'StationPickerUI.saveConfig');
      ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '保存失败，请重试');
    } finally {
      this.isSaving = false;
    }
  }

  showLocationServiceDialog() {
    this.getUIContext().getPromptAction().showDialog({
      title: '需要开启定位服务',
      message: '请前往系统设置开启位置服务，以获取附近的充电站信息',
      buttons: [
        { text: '取消', color: '#8e8e93' },
        { text: '去设置', color: '#30d158' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        this.openLocationSettings();
      }
    }).catch((err: BusinessError) => {
      ErrorHandler.handle(err, 'StationPickerUI.showLocationServiceDialog');
    });
  }


  build() {
    Column({ space: 8 }) {
      Column({ space: 8 }) {
        TextInput({ placeholder: '配置名称，如：下课后的充电站', text: this.configName })
          .onChange((value: string) => { this.configName = value; })
          .maxLength(24).height(44).borderRadius(16)
          .backgroundColor(this.theme.cardBackground).fontColor(this.theme.textPrimary)
          .id('configNameInput')
      }.width('100%')
      SearchBar({ placeholder: '搜索站点名称或地址', value: this.searchInputText, theme: this.theme,
        onChangeCallback: (value: string) => { this.onSearchInput(value); },
        onSubmitCallback: () => { this.applyKeyword(this.searchInputText); }
      })
      Row({ space: 8 }) {
        ForEach(['全部', '主楼C区', '商业街'], (keyword: string) => {
          Button(keyword).height(32).fontSize(13)
            .backgroundColor(this.searchText === (keyword === '全部' ? '' : keyword) ? this.theme.accent : this.theme.cardBackground)
            .fontColor(this.searchText === (keyword === '全部' ? '' : keyword) ? '#ffffff' : this.theme.textPrimary)
            .onClick(() => { this.applyKeyword(keyword === '全部' ? '' : keyword); })
        })
      }.width('100%')
      Row() {
        Text(`${this.filteredStations.length} 个结果`).fontSize(13).fontColor(this.theme.textSecondary).layoutWeight(1)
        Button('勾选结果').height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
          .enabled(!this.isLoading && this.filteredStations.length > 0).onClick(() => this.selectAllStations())
        Button('取消结果').enabled(!this.isLoading && this.filteredStations.some(station => this.selectedIds.includes(station.stationId))).height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.theme.textSecondary)
          .onClick(() => this.deselectAllStations())
      }.width('100%')
      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(32).height(32)
          Text('正在查找附近站点').fontSize(14).fontColor(this.theme.textSecondary)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.filteredStations.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([this.theme.textSecondary])
          Text(this.allStations.length ? '没有匹配的站点' : '暂未获取到附近站点').fontColor(this.theme.textPrimary)
          Text(this.allStations.length ? '试试其他关键词，或查看全部站点' : this.locationStatus).fontSize(13).fontColor(this.theme.textSecondary)
          Button(this.allStations.length ? '查看全部' : '重新加载').onClick(() => {
            if (this.allStations.length) { this.applyKeyword(''); } else { StationService.clearCache(); this.fetchAllStations(); }
          })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        List({ space: 8 }) {
          Repeat<StationBrief>(this.filteredStations).each((row: RepeatItem<StationBrief>) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text(row.item.stationName).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.textPrimary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.item.address).fontSize(12).fontColor(this.theme.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.stationSummary(row.item))
                    .fontSize(12).fontColor(this.theme.textSecondary)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Checkbox({ name: row.item.stationName }).select(this.selectedIds.includes(row.item.stationId))
                  .selectedColor(this.theme.accent).width(22).height(22)
                  .onChange((checked: boolean) => this.setStationSelected(row.item.stationId, checked))
              }.padding(16).width('100%').borderRadius(20).backgroundColor(this.theme.cardBackground)
            }
          }).key((station: StationBrief) => station.stationId.toString()).virtualScroll()
        }.layoutWeight(1).cachedCount(3).width('100%')
      }
      Text('附近查询将设备或默认校区坐标发送至 wemp.issks.com，仅用于查找附近站点。')
        .fontSize(11).fontColor(this.theme.textSecondary).width('100%')
      Row() {
        Button(this.isLoading ? '定位中…' : '重新定位').fontSize(12).height(32)
          .backgroundColor(Color.Transparent).fontColor(this.theme.accent).enabled(!this.isLoading)
          .onClick(() => this.refreshLocation())
        Text(this.locationStatus).fontSize(11).fontColor(this.theme.textSecondary).layoutWeight(1).maxLines(1)
        Button(this.showSelectedOnly ? '查看全部' : `已选 ${this.selectedIds.length}`)
          .backgroundColor(Color.Transparent).fontColor(this.theme.accent).fontSize(13).height(32)
          .onClick(() => {
            const showSelected = !this.showSelectedOnly;
            this.applyKeyword('');
            this.showSelectedOnly = showSelected;
            this.updateFilteredStations();
          })
      }.width('100%')
      Button(this.isSaving ? '正在保存…' : `保存配置 · ${this.selectedIds.length} 个站点`)
        .enabled(!this.isSaving && this.selectedIds.length > 0 && this.configName.trim().length > 0)
        .height(48).width('100%').backgroundColor(this.theme.accent).fontColor('#ffffff')
        .onClick(() => this.saveConfig()).margin({ bottom: 12 })
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.theme.background)
  }
}
