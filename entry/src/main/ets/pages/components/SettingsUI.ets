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
  @Event onAdd: () => void = () => {};
  @Event onThemeChange: (mode: ThemeMode) => void = () => {};
  @Event onImmersiveChange: (enabled: boolean) => void = () => {};
  @Local configs: ChargerConfig[] = [];
  @Local currentId: string = '';

  aboutToAppear() { this.loadConfigs(); }
  @Monitor('isActive', 'revision')
  onVisibilityChange() { if (this.isActive) this.loadConfigs(); }

  async loadConfigs() {
    const storage = await ConfigService.loadConfigs();
    this.configs = storage.configs;
    this.currentId = storage.currentConfigId || '';
  }

  async selectConfig(id: string) {
    try {
      await ConfigService.switchConfig(id);
      await this.loadConfigs();
    } catch (error) { ErrorHandler.showToast(this.getUIContext(), '切换失败，请重试'); }
  }

  async deleteConfig(config: ChargerConfig) {
    try {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除配置', message: `删除“${config.name}”？站点本身不会被删除。`,
      buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '删除', color: this.theme.error }]
    });
    if (result.index === 1) {
      await ConfigService.deleteConfig(config.id);
      await this.loadConfigs();
    }
    } catch (error) { ErrorHandler.showToast(this.getUIContext(), '操作未完成，请重试'); }
  }

  @Builder
  configRow(config: ChargerConfig) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(config.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        Text(`${Object.keys(config.stations).length} 个站点${PresetConfigs.isPreset(config.id) ? ' · 校园预设' : ' · 自定义'}`)
          .fontSize(12).fontColor(this.theme.textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.currentId === config.id) {
        Text('使用中').fontSize(12).fontColor(this.theme.accent)
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.theme.textSecondary])
      }
    }.padding(16).width('100%').constraintSize({ minHeight: 64 })
      .backgroundColor(this.theme.cardBackground).borderRadius(20)
      .onClick(() => this.selectConfig(config.id))
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 8 }) {
          Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text('把常去的充电站，放在一起').fontSize(14).fontColor(this.theme.textSecondary)
        }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 12, bottom: 12 })
        Text('默认配置').width('100%').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.textSecondary)
        ForEach(this.configs.filter(config => PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          this.configRow(config)
        }, (config: ChargerConfig) => config.id + this.currentId)
        Row() {
          Text('我的配置').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.textSecondary)
          Blank()
          Text('点击配置即可切换').fontSize(12).fontColor(this.theme.textSecondary)
        }.width('100%').margin({ top: 12 })
        ForEach(this.configs.filter(config => !PresetConfigs.isPreset(config.id)), (config: ChargerConfig) => {
          Row() {
            Row() { this.configRow(config) }.layoutWeight(1)
            Button('删除').fontSize(12).fontColor(this.theme.error).backgroundColor(Color.Transparent)
              .onClick(() => this.deleteConfig(config))
          }.borderRadius(20).backgroundColor(this.theme.cardBackground)
        }, (config: ChargerConfig) => JSON.stringify(config) + this.currentId)
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
          })
          Divider().color(this.theme.border)
          Row() {
            Column({ space: 5 }) {
              Text('沉浸光感').fontSize(16).fontColor(this.theme.textPrimary)
              Text('柔和通透的底部导航').fontSize(12).fontColor(this.theme.textSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.hdsImmersiveEnabled })
              .selectedColor(this.theme.accent).onChange((enabled: boolean) => this.onImmersiveChange(enabled))
          }.width('100%')
        }.padding(16).backgroundColor(this.theme.cardBackground).borderRadius(20)
        Text('充电不愁 · 清水河校区').fontSize(12).fontColor(this.theme.textSecondary).margin({ top: 12, bottom: 110 })
      }.padding({ left: 16, right: 16 }).width('100%')
    }.height('100%').width('100%').scrollBar(BarState.Off).backgroundColor(this.theme.background)
  }
}
