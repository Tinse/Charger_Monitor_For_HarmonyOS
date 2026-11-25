// StationPickerUI.ets - 站点选择器组件
import { StationBrief } from '../ChargerModels';
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

  @Monitor('isActive')
  onVisibilityChange() {
    if (this.hasAppeared && this.isActive && !this.isLoading && this.allStations.length === 0) {
      this.fetchAllStations();
    }
  }

  aboutToAppear() {
    this.hasAppeared = true;
    if (this.isActive) {
      this.fetchAllStations();
    }
    this.setupLocationServiceListener();
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
          if (state && this.isActive && this.allStations.length === 0 && !this.isLoading) {
            this.fetchAllStations();
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
    this.isLoading = true;
    this.errorMessage = '';
    this.loadingMessage = "正在获取位置信息…";

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await StationService.fetchNearbyStations(context);
      this.allStations = result.stations;
      this.locationStatus = result.locationStatus;

      if (result.needOpenLocationService) {
        this.showLocationServiceDialog();
      }

      if (this.allStations.length === 0 && !result.needOpenLocationService) {
        this.loadingMessage = "未找到附近充电站";
      }

      this.updateFilteredStations();
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.fetchAllStations');
      this.errorMessage = "加载失败，请检查网络连接";
    }
    this.isLoading = false;
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
    if (this.selectedIds.length === 0) return;
    this.isSaving = true;
    const stations: Record<string, number> = {};
    this.allStations.filter(station => this.selectedIds.includes(station.stationId))
      .forEach(station => { stations[station.stationName] = station.stationId; });
    try {
      await ConfigService.addConfig(this.configName.trim(), stations);
      ErrorHandler.showToast(this.getUIContext(), '配置已保存，可在监控页切换');
      this.onSaved();
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.saveConfig');
      ErrorHandler.showToast(this.getUIContext(), '保存失败，请重试');
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
        Button('取消结果').height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.theme.textSecondary)
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
                  Text(`${row.item.formattedDistance || ''} · 空闲 ${row.item.freeNum}`)
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
      Row() {
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
