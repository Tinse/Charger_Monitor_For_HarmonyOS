import { ChargerConfig } from '../ChargerModels';
import { PresetConfigs } from '../PresetConfigs';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from '../theme/ThemeManager';
import { SegmentedControl } from './SegmentedControl';
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
      await ConfigService.restoreDefaultConfigs();
      await this.loadConfigs();
      ErrorHandler.showToast(this.getUIContext(), '默认配置已恢复');
    } catch (error) {
      ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '恢复失败，请重试');
    } finally { this.restoring = false; }
  }

  @Builder
  configRow(config: ChargerConfig) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(config.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        Text(`${Object.keys(config.stations).length} 个站点${PresetConfigs.isPreset(config.id) ? ' · 校园预设' : ' · 自定义'}`)
          .fontSize(12).fontColor(this.theme.textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.theme.textSecondary])
    }.padding(16).width('100%').constraintSize({ minHeight: 64 })
      .backgroundColor(this.theme.cardBackground).borderRadius(20)
      .onClick(() => this.onOpen(config.id))
  }

  @Builder
  settingsScroll() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 8 }) {
          Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text('把常去的充电站，放在一起').fontSize(14).fontColor(this.theme.textSecondary)
        }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 12, bottom: 12 })
        Row() {
          Text('默认配置').layoutWeight(1).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.textSecondary)
          if (this.hasLoadedConfigs && !this.configReadError && this.configs.filter(config => PresetConfigs.isPreset(config.id)).length < 2) {
            Button(this.restoring ? '正在恢复…' : '恢复默认配置').height(36).fontSize(13)
              .backgroundColor(Color.Transparent).fontColor(this.theme.accent).enabled(!this.restoring)
              .onClick(() => this.restoreDefaults())
          }
        }.width('100%')
        if (this.configReadError) {
          Row({ space: 12 }) {
            Text('站点配置读取失败').fontSize(14).fontColor(this.theme.textSecondary).layoutWeight(1)
            Button('重新读取配置').onClick(() => this.loadConfigs())
          }.width('100%')
        } else if (!this.hasLoadedConfigs) {
          Text('正在读取配置…').fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        } else if (this.configs.length === 0) {
          Text('暂无配置，可增加自定义配置或恢复默认配置。').fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        }
        ForEach(this.configs.filter(config => PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          this.configRow(config)
        }, (config: ChargerConfig) => JSON.stringify(config))
        Row() {
          Text('我的配置').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.textSecondary)
          Blank()
          Text('点击查看、编辑或删除').fontSize(12).fontColor(this.theme.textSecondary)
        }.width('100%').margin({ top: 12 })
        ForEach(this.configs.filter(config => !PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          this.configRow(config)
        }, (config: ChargerConfig) => JSON.stringify(config))
        Button() {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([this.theme.accent])
            Column({ space: 4 }) {
              Text('增加配置').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.accent)
              Text('按关键词选站点，自由组合').fontSize(12).fontColor(this.theme.textSecondary)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.theme.textSecondary])
          }.width('100%').padding(16)
        }.width('100%').height(76).type(ButtonType.Normal).borderRadius(20)
          .backgroundColor(this.theme.cardBackground).onClick(() => this.onAdd())
        Text('外观').width('100%').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.textSecondary).margin({ top: 12 })
        Column({ space: 16 }) {
          Text('主题模式').fontSize(16).fontColor(this.theme.textPrimary).width('100%')
          SegmentedControl({
            segments: [{ label: '跟随系统', value: ThemeMode.SYSTEM }, { label: '浅色', value: ThemeMode.LIGHT }, { label: '深色', value: ThemeMode.DARK }],
            selectedIndex: this.themeMode === ThemeMode.SYSTEM ? 0 : this.themeMode === ThemeMode.LIGHT ? 1 : 2,
            theme: this.theme, onChangeCallback: (_: number, value: number) => this.onThemeChange(value as ThemeMode)
          }).enabled(!this.appearanceBusy)
          Divider().color(this.theme.border)
          Row() {
            Column({ space: 5 }) {
              Text('沉浸光感').fontSize(16).fontColor(this.theme.textPrimary)
              Text('柔和通透的底部导航').fontSize(12).fontColor(this.theme.textSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.hdsImmersiveEnabled })
              .accessibilityText('沉浸光感').enabled(!this.appearanceBusy)
              .selectedColor(this.theme.accent).onChange((enabled: boolean) => this.onImmersiveChange(enabled))
          }.width('100%')
        }.padding(16).backgroundColor(this.theme.cardBackground).borderRadius(20)
        Text('充电不愁 · 清水河校区').fontSize(12).fontColor(this.theme.textSecondary).margin({ top: 12, bottom: 12 })
      }.padding({ left: 16, right: 16 }).width('100%')
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
