import { ChargerConfig } from '../ChargerModels';
import { PresetConfigs } from '../PresetConfigs';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from '../theme/ThemeManager';
import { SegmentedControl } from './SegmentedControl';
import { StationSelection } from '../utils/StationSelection';
import { SearchBar } from './SearchBar';
import { ErrorHandler } from '../utils/ErrorHandler';

@ComponentV2
export struct SettingsUI {
  @Param isActive: boolean = false;
  @Param revision: number = 0;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Param themeMode: ThemeMode = ThemeMode.SYSTEM;
  @Param hdsImmersiveEnabled: boolean = true;
  @Param appearanceBusy: boolean = false;
  @Event onAdd: () => void = () => {};
  @Event onOpen: (id: string) => void = (_id: string) => {};
  @Event onThemeChange: (mode: ThemeMode) => void = () => {};
  @Event onImmersiveChange: (enabled: boolean) => void = () => {};
  @Local configs: ChargerConfig[] = [];
  @Local restoring: boolean = false;
  @Local query: string = '';
  @Local currentId: string = '';
  @Local hasLoadedConfigs: boolean = false;
  @Local configReadError: boolean = false;
  private configReadVersion: number = 0;

  aboutToAppear() { this.loadConfigs(); }
  @Monitor('isActive', 'revision')
  onVisibilityChange() { if (this.isActive) this.loadConfigs(); }

  async loadConfigs() {
    const version = ++this.configReadVersion;
    this.configReadError = false;
    try {
      const storage = await ConfigService.loadConfigs();
      if (version !== this.configReadVersion) return;
      this.configs = storage.configs;
      this.currentId = storage.currentConfigId || '';
      this.hasLoadedConfigs = true;
    } catch (error) {
      if (version === this.configReadVersion) this.configReadError = true;
      ErrorHandler.handle(error, 'SettingsUI.loadConfigs');
    }
  }

  aboutToDisappear() { this.configReadVersion++; }

  async restoreDefaults() {
    if (this.restoring) return;
    this.restoring = true;
    try {
      const missing = PresetConfigs.create().filter(preset => !this.configs.some(config => config.id === preset.id));
      const conflict = this.configs.find(config => missing.some(preset => preset.name.trim().toLowerCase() === config.name.trim().toLowerCase()));
      if (conflict) {
        const decision = await this.getUIContext().getPromptAction().showDialog({
          title: '需要先修改配置名称', message: `自定义配置“${conflict.name}”与要恢复的预设同名，可到配置详情修改名称。`,
          buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '去修改', color: this.theme.accent }]
        });
        if (decision.index === 1) this.onOpen(conflict.id);
        return;
      }
      const decision = await this.getUIContext().getPromptAction().showDialog({
        title: '恢复默认配置？', message: `将恢复出厂站点：${missing.map(preset => preset.name).join('、')}。其他配置会保留。`,
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '恢复', color: this.theme.accent }]
      });
      if (decision.index !== 1) return;
      await ConfigService.restoreDefaultConfigs();
      await this.loadConfigs();
      ErrorHandler.showToast(this.getUIContext(), '默认配置已恢复');
    } catch (error) {
      ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '恢复失败，请重试');
    } finally { this.restoring = false; }
  }

  private matchedStation(config: ChargerConfig): string {
    const keyword = StationSelection.normalize(this.query);
    if (!keyword) return '';
    const display = StationSelection.displayNames(config);
    const member = config.members?.find(item =>
      [display[String(item.stationId)], item.originalName, item.note, String(item.stationId)]
        .some(field => StationSelection.normalize(field).includes(keyword)));
    return member ? display[String(member.stationId)] : '';
  }

  @Computed
  get results(): ChargerConfig[] {
    const keyword = StationSelection.normalize(this.query);
    return this.configs.filter(config => StationSelection.normalize(config.name).includes(keyword) || this.matchedStation(config).length > 0);
  }

  @Builder
  configRow(config: ChargerConfig) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(config.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        if (this.matchedStation(config)) {
          Text(`匹配站点 · ${this.matchedStation(config)}`).fontSize(12).fontColor(this.theme.textSecondary)
        }
        Text(`${Object.keys(config.stations).length} 个站点`)
          .fontSize(12).fontColor(this.theme.textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (config.id === this.currentId) {
        Text('监控中').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.theme.infoText)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(8).backgroundColor(this.theme.infoSurface)
      }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([this.theme.textSecondary])
    }.padding(16).width('100%').constraintSize({ minHeight: 64 })
      .backgroundColor(this.theme.cardBackground).borderRadius(16)
      .onClick(() => this.onOpen(config.id))
  }

  @Builder
  settingsScroll() {
    Scroll() {
      Column({ space: 12 }) {
        Text('设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          .width('100%').margin({ top: 12 })
        SearchBar({ placeholder: '搜索配置、站名、ID 或备注', value: this.query, theme: this.theme,
          onChangeCallback: (value: string) => { this.query = value; } })
        if (this.query && this.results.length === 0) {
          Row() {
            Text('没有匹配的配置').layoutWeight(1).fontColor(this.theme.textSecondary)
            Button('清除搜索').constraintSize({ minHeight: 40 }).fontSize(14).onClick(() => { this.query = ''; })
          }.width('100%')
        }
        Row() {
          Text('默认配置').layoutWeight(1).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
          if (this.hasLoadedConfigs && !this.configReadError && this.configs.filter(config => PresetConfigs.isPreset(config.id)).length < 2) {
            Button(this.restoring ? '正在恢复…' : '恢复默认配置').constraintSize({ minHeight: 40 }).fontSize(14)
              .backgroundColor(Color.Transparent).fontColor(this.theme.accent).enabled(!this.restoring)
              .onClick(() => this.restoreDefaults())
          }
        }.width('100%')
        if (this.configReadError) {
          Row({ space: 12 }) {
            Text('站点配置读取失败').fontSize(14).fontColor(this.theme.textSecondary).layoutWeight(1)
            Button('重新读取配置').constraintSize({ minHeight: 40 }).fontSize(14).onClick(() => this.loadConfigs())
          }.width('100%')
        } else if (!this.hasLoadedConfigs) {
          Text('正在读取配置…').fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        } else if (this.configs.length === 0) {
          Text('暂无配置，可增加自定义配置或恢复默认配置。').fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        }
        ForEach(this.results.filter(config => PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          this.configRow(config)
        }, (config: ChargerConfig) => JSON.stringify(config) + String(this.currentId === config.id) + this.matchedStation(config))
        Text('我的配置').width('100%').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
          .margin({ top: 4 })
        ForEach(this.results.filter(config => !PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          this.configRow(config)
        }, (config: ChargerConfig) => JSON.stringify(config) + String(this.currentId === config.id) + this.matchedStation(config))
        Button() {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([this.theme.accent])
            Text('增加配置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.accent).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([this.theme.textSecondary])
          }.width('100%').padding(16)
        }.width('100%').constraintSize({ minHeight: 52 }).type(ButtonType.Normal).borderRadius(16)
          .backgroundColor(this.theme.cardBackground).onClick(() => this.onAdd())
        Text('外观').width('100%').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary).margin({ top: 4 })
        Column({ space: 16 }) {
          Text('主题模式').fontSize(15).fontColor(this.theme.textPrimary).width('100%')
          SegmentedControl({
            segments: [{ label: '跟随系统', value: ThemeMode.SYSTEM }, { label: '浅色', value: ThemeMode.LIGHT }, { label: '深色', value: ThemeMode.DARK }],
            selectedIndex: this.themeMode === ThemeMode.SYSTEM ? 0 : this.themeMode === ThemeMode.LIGHT ? 1 : 2,
            theme: this.theme, onChangeCallback: (_: number, value: number) => this.onThemeChange(value as ThemeMode)
          }).enabled(!this.appearanceBusy)
          Divider().color(this.theme.border)
          Row() {
            Column({ space: 5 }) {
              Text('沉浸光感').fontSize(15).fontColor(this.theme.textPrimary)
              Text('柔和通透的底部导航').fontSize(12).fontColor(this.theme.textSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.hdsImmersiveEnabled })
              .responseRegion({ x: 0, y: -5, width: '100%', height: 42 }).accessibilityText('沉浸光感').enabled(!this.appearanceBusy)
              .selectedColor(this.theme.accent).onChange((enabled: boolean) => this.onImmersiveChange(enabled))
          }.width('100%')
        }.padding(16).backgroundColor(this.theme.cardBackground).borderRadius(16)
      }.padding({ left: 16, right: 16, bottom: 4 }).width('100%')
    }.layoutWeight(1).width('100%').clip(true).scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.settingsScroll()
    }.width('100%').height('100%').backgroundColor(this.theme.background)
      // Reserve the 56 vp floating bar, its 28 vp bottom margin and a 12 vp gap outside the scroll hit area.
      .padding({ bottom: 96 })
  }
}
