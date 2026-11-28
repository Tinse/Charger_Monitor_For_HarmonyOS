// StationPickerUI.ets - 站点选择器组件
import { ChargerConfig, StationBrief } from '../ChargerModels';
import { ConfigManager } from '../ConfigManager';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { StationService } from '../services/StationService';
import { NearbyLoadPhase } from '../api/ChargerApi';
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
  @Param mode: string = 'create';
  @Param replaceStationId: number = 0;
  @Event onBusyChange: (busy: boolean) => void = () => {};
  private existingIds: number[] = [];
  private displayNames: Record<string, string> = {};
  private originalNames: Record<string, string> = {};
  private catalogIds: number[] = [];
  @Local fetchedIds: number[] = [];
  @Event onDirtyChange: (dirty: boolean) => void = () => {};
  private originalName: string = '';
  private originalIds: number[] = [];
  private lastLocationStatus: string = '';

  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onSaved: (openCreatedId?: string) => void = () => {};
  @Local configName: string = '';
  @Local isSaving: boolean = false;
  @Local showSelectedOnly: boolean = false;

  @Local allStations: StationBrief[] = [];
  @Local searchText: string = "";
  @Local searchInputText: string = "";
  private searchTimer: number = -1;
  @Local selectedIds: number[] = [];
  @Local isLoading: boolean = false;
  @Local locationStatus: string = "";

  @Local filteredStations: StationBrief[] = [];

  private locationServiceStateCallback?: (state: boolean) => void;
  private hasAppeared: boolean = false;
  private hasFetched: boolean = false;
  private nearbySource: 'device' | 'campus' = 'campus';
  private requestedNearby: boolean = false;
  @Local nameError: string = '';
  private fetchSequence: number = 0;
  private needsLocationService: boolean = false;

  @Monitor('isActive')
  onVisibilityChange() {
    if (!this.hasAppeared || !this.requestedNearby) return;
    if (!this.isActive) {
      if (this.isLoading) {
        this.fetchSequence++;
        this.hasFetched = false;
        this.isLoading = false;
        this.locationStatus = this.lastLocationStatus;
      }
      return;
    }
    const retryLocation = this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限');
    if (!this.isLoading && (!this.hasFetched || this.needsLocationService || this.allStations.length === 0 || retryLocation)) {
      this.fetchAllStations(this.hasFetched && (this.needsLocationService || retryLocation));
    }
  }

  aboutToAppear() {
    this.hasAppeared = true;
    const initial = this.initialConfig;
    const catalog = StationSelection.campusCatalog();
    this.catalogIds = catalog.map(station => station.stationId);
    this.existingIds = initial?.members?.map(member => member.stationId) || (initial ? Object.values(initial.stations) : []);
    this.displayNames = StationSelection.displayNames(initial);
    this.originalNames = initial?.stationNames || {};
    const saved = initial ? StationSelection.savedStations(initial) : [];
    if (initial && (this.mode === 'copy' || this.mode === 'create')) {
      this.configName = ConfigManager.copyName(initial.name, []);
      this.loadCopyName(initial);
      this.selectedIds = [...this.existingIds];
    }
    this.allStations = StationSelection.mergeAvailable(catalog, saved, this.existingIds);
    this.locationStatus = '可先使用校园预设，联网后可查询附近站点';
    this.originalName = this.configName;
    this.originalIds = [...this.selectedIds];
    this.onDirtyChange(this.hasChanges());
    this.updateFilteredStations();
    this.setupLocationServiceListener();
  }

  private async loadCopyName(initial: ChargerConfig) {
    const previous = this.configName;
    try {
      const storage = await ConfigService.loadConfigs();
      if (!this.hasAppeared || this.configName !== previous) return;
      this.configName = ConfigManager.copyName(initial.name, storage.configs);
      this.originalName = this.configName;
    } catch (error) { ErrorHandler.handle(error, 'StationPickerUI.copyName'); }
  }

  hasChanges(): boolean {
    return this.configName !== this.originalName || this.selectedIds.length !== this.originalIds.length ||
      this.selectedIds.some(id => !this.originalIds.includes(id));
  }

  @Monitor('configName', 'selectedIds')
  onDraftChange() { this.onDirtyChange(this.hasChanges()); }

  async refreshLocation(source: 'device' | 'campus' = this.nearbySource, force: boolean = true) {
    if (this.isLoading) return;
    this.nearbySource = source;
    this.requestedNearby = true;
    await this.fetchAllStations(force);
  }

  async chooseLocation() {
    if (this.isLoading || this.isSaving) return;
    try {
      const decision = await this.getUIContext().getPromptAction().showDialog({
        title: '查找附近站点', message: '校园位置使用清水河校区坐标，设备位置使用本机定位。',
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '校园位置', color: this.theme.accent },
          { text: '设备位置', color: this.theme.accent }]
      });
      if (this.hasAppeared && (decision.index === 1 || decision.index === 2)) {
        const source = decision.index === 1 ? 'campus' : 'device';
        await this.refreshLocation(source, this.requestedNearby && source === this.nearbySource);
      }
    } catch (error) { ErrorHandler.handle(error, 'StationPickerUI.chooseLocation'); }
  }

  updateFilteredStations() {
    const available = StationSelection.candidates(this.allStations, this.mode, this.existingIds);
    const aliases: Record<string, string> = this.mode === 'copy' ? this.displayNames : {};
    const matches = StationSelection.filter(available, this.searchText, aliases);
    this.filteredStations = this.showSelectedOnly ? matches.filter(station => this.selectedIds.includes(station.stationId)) : matches;
  }

  applyKeyword(keyword: string) {
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    this.searchTimer = -1;
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
          if (state && this.requestedNearby && this.nearbySource === 'device' && this.isActive && (this.needsLocationService || this.allStations.length === 0 || this.lastLocationStatus.includes('默认位置') || this.lastLocationStatus.includes('权限')) && !this.isLoading) {
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

  async fetchAllStations(forceRefresh: boolean = false) {
    if (this.isLoading || !this.isActive || !this.hasAppeared) return;
    this.hasFetched = true;
    const request = ++this.fetchSequence;
    this.isLoading = true;

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await StationService.fetchNearbyStations(context, (phase: NearbyLoadPhase) => {
        if (this.hasAppeared && this.isActive && request === this.fetchSequence) {
          this.locationStatus = phase === NearbyLoadPhase.LOCATING ? '正在获取位置' : '正在查询附近站点';
        }
      }, forceRefresh, this.nearbySource);
      if (!this.hasAppeared || !this.isActive || request !== this.fetchSequence) return;
      this.fetchedIds = result.stations.map(station => station.stationId);
      this.allStations = StationSelection.mergeAvailable(result.stations, this.allStations,
        [...this.catalogIds, ...this.existingIds, ...this.selectedIds]);
      this.locationStatus = result.locationStatus;
      this.lastLocationStatus = result.locationStatus;
      this.needsLocationService = result.needOpenLocationService === true;

      if (result.needOpenLocationService && this.isActive && !this.isSaving) {
        this.showLocationServiceDialog();
      }

      this.updateFilteredStations();
    } catch (error) {
      if (this.hasAppeared && request === this.fetchSequence) {
        ErrorHandler.handle(error, 'StationPickerUI.fetchAllStations');
        this.locationStatus = '附近查询失败，可使用已加载站点或重新定位';
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
    if (this.isSaving || !StationSelection.canSelect(stationId, this.mode, this.existingIds)) return;
    const selected = this.selectedIds.includes(stationId);
    if (selected === checked) {
      return;
    }
    this.selectedIds = StationSelection.setSelected(this.selectedIds, stationId, checked, this.mode, this.existingIds);
    if (this.showSelectedOnly) this.updateFilteredStations();
  }

  selectAllStations() {
    if (this.isSaving || this.mode === 'replace') return;
    const matches = this.filteredStations.filter(station => StationSelection.canSelect(station.stationId, this.mode, this.existingIds));
    this.selectedIds = StationSelection.selectMatches(this.selectedIds, matches);
  }

  deselectAllStations() {
    this.selectedIds = StationSelection.clearMatches(this.selectedIds, this.filteredStations);
    this.updateFilteredStations();
  }

  stationDisplayName(station: StationBrief): string {
    return this.mode === 'copy' ? this.displayNames[station.stationId.toString()] || station.stationName : station.stationName;
  }

  isJoined(station: StationBrief): boolean { return this.mode === 'add' && this.existingIds.includes(station.stationId); }

  hasAvailableCandidates(): boolean {
    return StationSelection.candidates(this.allStations, this.mode, this.existingIds).length > 0;
  }

  emptyTitle(): string {
    if (this.mode === 'replace' && !this.hasAvailableCandidates()) return '没有可替换的站点';
    return this.hasAvailableCandidates() ? '没有匹配的站点' : '暂未获取到可选站点';
  }

  emptyDescription(): string {
    if (this.mode === 'replace' && !this.hasAvailableCandidates()) {
      return '已排除当前配置中的站点，可重新定位查询更多候选站点';
    }
    return this.hasAvailableCandidates() ? '试试其他关键词，或清除筛选查看全部站点' : this.locationStatus;
  }

  stationSummary(station: StationBrief): string {
    if (!this.fetchedIds.includes(station.stationId)) {
      return `${this.catalogIds.includes(station.stationId) ? '校园预设' : '已保存站点'} · 状态待查询`;
    }
    const distance = station.formattedDistance || '距离未知';
    return `${distance} · ${station.freeNum < 0 ? '空闲数量未知' : `空闲 ${station.freeNum}`}`;
  }

  async saveConfig() {
    if (this.isSaving) return;
    const manageExisting = this.mode === 'add' || this.mode === 'replace';
    if (!manageExisting && !this.configName.trim()) {
      ErrorHandler.showToast(this.getUIContext(), '请填写配置名称'); return;
    }
    if (manageExisting && this.selectedIds.length === 0) {
      ErrorHandler.showToast(this.getUIContext(), this.mode === 'replace' ? '请选择一个替代站点' : '请至少选择一个站点'); return;
    }
    this.isSaving = true;
    this.onBusyChange(true);
    try {
      let openCreatedId: string | undefined = undefined;
      const selected = this.selectedIds.map(id => this.allStations.find(station => station.stationId === id));
      if (selected.some(station => !station)) throw new Error('已选站点信息缺失，请重新查询');
      const stations = selected as StationBrief[];
      if (this.mode === 'add') {
        if (!this.initialConfig) throw new Error('目标配置不存在');
        await ConfigService.addStations(this.initialConfig.id, stations);
      } else if (this.mode === 'replace') {
        const initial = this.initialConfig;
        if (!initial || stations.length !== 1) throw new Error('请选择一个替代站点');
        const oldName = Object.keys(initial.stations).find(name => initial.stations[name] === this.replaceStationId);
        if (!oldName) throw new Error('原站点不存在，请返回后重试');
        const replacement = stations[0];
        const oldNote = initial.members?.find(member => member.stationId === this.replaceStationId)?.note || '';
        const choices: promptAction.Button[] = [
          { text: '取消', color: this.theme.textSecondary }, { text: '确认替换', color: this.theme.accent }
        ];
        if (oldNote) choices.push({ text: '替换并保留备注', color: this.theme.accent });
        const confirmation = await this.getUIContext().getPromptAction().showDialog({
          title: '确认替换站点？',
          message: `将“${oldName}”（ID ${this.replaceStationId}）替换为“${replacement.stationName}”（ID ${replacement.stationId}）。保留别名、顺序和暂停状态。${oldNote ? '默认清除原站备注。' : ''}`,
          buttons: choices
        });
        if ((confirmation.index !== 1 && confirmation.index !== 2) || !this.hasAppeared) return;
        await ConfigService.replaceStation(initial.id, this.replaceStationId, replacement, confirmation.index === 2);
      } else {
        const names: Record<string, string> = this.mode === 'copy' ? this.displayNames : {};
        const originalNames: Record<string, string> = this.mode === 'copy' ? this.originalNames : {};
        const created = await ConfigService.addConfig(this.configName.trim(),
          StationSelection.toStationMap(this.allStations, this.selectedIds, names),
          StationSelection.toStationNames(this.allStations, this.selectedIds, originalNames),
          this.mode === 'copy' ? this.initialConfig?.members : undefined);
        if (!this.hasAppeared) return;
        try {
          const next = await this.getUIContext().getPromptAction().showDialog({
            title: '配置已保存', message: created.name,
            buttons: [{ text: '完成', color: this.theme.textSecondary }, { text: '查看配置', color: this.theme.accent }]
          });
          if (next.index === 1) openCreatedId = created.id;
        } catch (error) { ErrorHandler.handle(error, 'StationPickerUI.savedDialog'); }
      }
      if (!this.hasAppeared) return;
      this.onDirtyChange(false);
      ErrorHandler.showToast(this.getUIContext(), this.mode === 'replace' ? '站点已替换' : this.mode === 'add' ? '站点已添加' : '配置已保存，可在监控页切换');
      this.onSaved(openCreatedId);
    } catch (error) {
      if (!this.hasAppeared) return;
      if ((this.mode === 'copy' || this.mode === 'create') && (error as Error).message.includes('名称')) this.nameError = (error as Error).message;
      ErrorHandler.handle(error, 'StationPickerUI.saveConfig');
      ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '保存失败，请重试');
    } finally {
      this.isSaving = false;
      this.onBusyChange(false);
    }
  }

  saveLabel(): string {
    if (this.isSaving) return '正在处理…';
    if (this.mode === 'replace') return '替换为所选站点';
    if (this.mode === 'add') return `添加 ${this.selectedIds.length} 个站点`;
    if (!this.selectedIds.length) return this.mode === 'copy' ? '保存为空配置' : '创建空配置';
    return `保存配置 · ${this.selectedIds.length} 个站点`;
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
      if (this.mode === 'add' || this.mode === 'replace') {
        Text(this.mode === 'replace' ? `为“${this.initialConfig?.name || ''}”选择一个替代站点` : `为“${this.initialConfig?.name || ''}”添加站点`)
          .fontSize(14).fontColor(this.theme.textSecondary).width('100%')
      } else {
        TextInput({ placeholder: '配置名称，如：下课后的充电站', text: this.configName })
          .onChange((value: string) => { this.configName = value; this.nameError = ''; })
          .enabled(!this.isSaving).maxLength(24).height(44).width('100%').borderRadius(16)
          .backgroundColor(this.theme.cardBackground).fontColor(this.theme.textPrimary)
          .id('configNameInput')
        if (this.nameError) { Text(this.nameError).fontSize(13).fontColor(this.theme.error) }
      }
      SearchBar({ placeholder: '搜索名称、地址或站点ID', value: this.searchInputText, theme: this.theme,
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
        if (this.mode !== 'replace') {
          Button('勾选结果').height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
            .enabled(!this.isSaving && this.filteredStations.some(station => StationSelection.canSelect(station.stationId, this.mode, this.existingIds)))
            .onClick(() => this.selectAllStations())
          Button('取消结果').height(36).fontSize(13).backgroundColor(Color.Transparent).fontColor(this.theme.textSecondary)
            .enabled(!this.isSaving && this.filteredStations.some(station => this.selectedIds.includes(station.stationId)))
            .onClick(() => this.deselectAllStations())
        }
      }.width('100%')
      if (this.isLoading && this.allStations.length === 0) {
        Column({ space: 12 }) {
          LoadingProgress().width(32).height(32)
          Text('正在查找附近站点').fontSize(14).fontColor(this.theme.textSecondary)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.filteredStations.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([this.theme.textSecondary])
          Text(this.emptyTitle()).fontColor(this.theme.textPrimary)
          Text(this.emptyDescription()).fontSize(13).fontColor(this.theme.textSecondary)
          Button(this.hasAvailableCandidates() ? '清除筛选' : '重新查询候选站点').enabled(!this.isSaving && (this.hasAvailableCandidates() || !this.isLoading)).onClick(() => {
            if (this.hasAvailableCandidates()) this.applyKeyword('');
            else this.chooseLocation();
          })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        List({ space: 8 }) {
          Repeat<StationBrief>(this.filteredStations).each((row: RepeatItem<StationBrief>) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text(this.stationDisplayName(row.item)).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.textPrimary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.stationDisplayName(row.item) !== row.item.stationName) {
                    Text(`原站名：${row.item.stationName}`).fontSize(12).fontColor(this.theme.textSecondary)
                  }
                  Text(`ID ${row.item.stationId} · ${row.item.address}`).fontSize(12).fontColor(this.theme.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.stationSummary(row.item))
                    .fontSize(12).fontColor(this.theme.textSecondary)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  .enabled(!this.isSaving && !this.isJoined(row.item))
                  .onClick(() => this.setStationSelected(row.item.stationId, this.mode === 'replace' ? true : !this.selectedIds.includes(row.item.stationId)))
                if (this.isJoined(row.item)) {
                  Text('已加入').fontSize(13).fontColor(this.theme.textSecondary)
                } else if (this.mode === 'replace') {
                  Radio({ value: row.item.stationId.toString(), group: 'replacement' })
                    .checked(this.selectedIds.includes(row.item.stationId)).enabled(!this.isSaving)
                    .accessibilityText(`选择替代站点：${row.item.stationName}，ID ${row.item.stationId}`)
                    .width(22).height(22).onChange((checked: boolean) => this.setStationSelected(row.item.stationId, checked))
                } else {
                  Checkbox({ name: row.item.stationName }).select(this.selectedIds.includes(row.item.stationId))
                    .enabled(!this.isSaving).selectedColor(this.theme.accent).width(22).height(22)
                    .accessibilityText(`选择站点：${this.stationDisplayName(row.item)}，ID ${row.item.stationId}`)
                    .onChange((checked: boolean) => this.setStationSelected(row.item.stationId, checked))
                }
              }.padding(16).width('100%').borderRadius(20).backgroundColor(this.theme.cardBackground)
            }
          }).key((station: StationBrief) => JSON.stringify(station)).virtualScroll()
        }.layoutWeight(1).cachedCount(3).width('100%')
      }
      Text('附近查询将设备或默认校区坐标发送至 wemp.issks.com，仅用于查找附近站点。')
        .fontSize(11).fontColor(this.theme.textSecondary).width('100%')
      Row() {
        if (this.isLoading) {
          LoadingProgress().width(18).height(18).margin({ right: 6 })
        } else {
          Button('查找附近').fontSize(12).height(32)
            .backgroundColor(Color.Transparent).fontColor(this.theme.accent)
            .onClick(() => this.chooseLocation())
        }
        Text(this.locationStatus).id('nearbyLoadStatus').fontSize(12).fontColor(this.theme.textSecondary).layoutWeight(1).maxLines(2)
        Button(this.showSelectedOnly ? '查看全部' : `已选 ${this.selectedIds.length}`)
          .backgroundColor(Color.Transparent).fontColor(this.theme.accent).fontSize(13).height(32)
          .onClick(() => {
            const showSelected = !this.showSelectedOnly;
            this.applyKeyword('');
            this.showSelectedOnly = showSelected;
            this.updateFilteredStations();
          })
      }.width('100%')
      Button(this.saveLabel())
        .enabled(!this.isSaving && ((this.mode === 'add' || this.mode === 'replace') ?
          this.selectedIds.length > 0 : this.configName.trim().length > 0))
        .height(48).width('100%').backgroundColor(this.theme.accent).fontColor('#ffffff')
        .onClick(() => this.saveConfig()).margin({ bottom: 12 })
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.theme.background)
  }
}
