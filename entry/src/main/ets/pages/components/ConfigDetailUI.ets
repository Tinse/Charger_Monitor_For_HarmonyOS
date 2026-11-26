import { ChargerConfig } from '../ChargerModels';
import { PresetConfigs } from '../PresetConfigs';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';

@ComponentV2
export struct ConfigDetailUI {
  @Param configId: string = '';
  @Param revision: number = 0;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onEdit: (config: ChargerConfig, copy: boolean) => void = () => {};
  @Event onDeleted: () => void = () => {};
  @Local config: ChargerConfig | null = null;
  @Local loading: boolean = true;
  @Local deleting: boolean = false;
  @Local loadError: string = '';
  private loadSequence: number = 0;
  private present: boolean = false;

  aboutToAppear() { this.present = true; this.loadConfig(); }
  aboutToDisappear() { this.present = false; this.loadSequence++; }
  @Monitor('revision')
  onRevisionChange() { this.loadConfig(); }

  async loadConfig() {
    const sequence = ++this.loadSequence;
    this.loading = true;
    this.loadError = '';
    try {
      const storage = await ConfigService.loadConfigs();
      if (sequence === this.loadSequence && this.present) this.config = storage.configs.find(config => config.id === this.configId) || null;
    } catch (error) {
      if (sequence === this.loadSequence && this.present) this.loadError = (error as Error).message || '配置读取失败，请重试';
    } finally {
      if (sequence === this.loadSequence) this.loading = false;
    }
  }

  async deleteConfig() {
    if (this.deleting || !this.config) return;
    const config = this.config;
    this.deleting = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除配置', message: PresetConfigs.isPreset(config.id) ? `删除“${config.name}”？删除后不会自动恢复，可在设置中恢复默认配置。` : `删除“${config.name}”？此操作不可恢复，站点本身不会被删除。`,
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '删除', color: this.theme.error }]
      });
      if (result.index !== 1) return;
      const removed = await ConfigService.deleteConfig(config.id);
      if (!removed) throw new Error('配置不存在或已被删除');
      if (!this.present) return;
      ErrorHandler.showToast(this.getUIContext(), '配置已删除');
      this.onDeleted();
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), '删除未完成，请重试');
    } finally { this.deleting = false; }
  }

  build() {
    Column({ space: 12 }) {
      if (this.loading) {
        LoadingProgress().width(32).height(32)
      } else if (this.loadError) {
        Text(this.loadError).fontColor(this.theme.textSecondary)
        Button('重新读取').onClick(() => this.loadConfig())
      } else if (!this.config) {
        Text('配置不存在或已被删除').fontColor(this.theme.textSecondary)
      } else {
        Column({ space: 8 }) {
          Text(this.config.name).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text(`${Object.keys(this.config.stations).length} 个站点 · ${PresetConfigs.isPreset(this.config.id) ? '默认配置' : '自定义配置'}`)
            .fontSize(13).fontColor(this.theme.textSecondary)
          Text(PresetConfigs.isPreset(this.config.id) ? '可删除此默认配置，或复制后自由修改名称、增减站点。删除后仅通过设置中的恢复入口恢复。' : '在这里编辑名称与站点，或删除整套配置。监控页负责切换当前配置。')
            .fontSize(13).fontColor(this.theme.textSecondary)
        }.alignItems(HorizontalAlign.Start).width('100%').padding(16).borderRadius(20).backgroundColor(this.theme.cardBackground)
        List({ space: 8 }) {
          ForEach(Object.keys(this.config.stations), (name: string) => {
            ListItem() {
              Text(name).fontSize(15).fontColor(this.theme.textPrimary).width('100%')
                .padding(16).borderRadius(16).backgroundColor(this.theme.cardBackground)
            }
          }, (name: string) => name)
        }.layoutWeight(1).width('100%')
        Button(PresetConfigs.isPreset(this.config.id) ? '复制为自定义配置' : '编辑名称与站点')
          .width('100%').height(48).backgroundColor(this.theme.accent).fontColor('#ffffff')
          .enabled(!this.deleting).onClick(() => {
            if (this.config) this.onEdit(this.config, PresetConfigs.isPreset(this.config.id));
          })
        Button(this.deleting ? '正在删除…' : '删除配置').width('100%').height(44)
          .backgroundColor(this.theme.cardBackground).fontColor(this.theme.error)
          .enabled(!this.deleting).onClick(() => this.deleteConfig())
      }
    }.padding({ left: 16, right: 16, top: 8, bottom: 20 }).width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
