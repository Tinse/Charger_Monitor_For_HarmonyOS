import { ChargerConfig } from '../ChargerModels';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';

@ComponentV2
export struct ConfigStationUI {
  @Param configId: string = '';
  @Param stationId: number = 0;
  @Param revision: number = 0;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onReplace: (config: ChargerConfig, id: number) => void = () => {};
  @Event onChanged: () => void = () => {};
  @Event onRemoved: () => void = () => {};
  @Event onDirtyChange: (dirty: boolean) => void = () => {};
  @Event onBusyChange: (busy: boolean) => void = () => {};
  @Local config: ChargerConfig | null = null;
  @Local displayName: string = '';
  @Local originalName: string = '';
  @Local savedAlias: string = '';
  @Local draftAlias: string = '';
  @Local savedNote: string = '';
  @Local draftNote: string = '';
  @Local savedPaused: boolean = false;
  @Local draftPaused: boolean = false;
  @Local loadError: string = '';
  @Local loading: boolean = true;
  @Local busy: boolean = false;
  private loadSequence: number = 0;
  private present: boolean = false;

  aboutToAppear() { this.present = true; this.loadStation(); }
  aboutToDisappear() { this.present = false; this.loadSequence++; }
  @Monitor('revision')
  onRevisionChange() { this.loadStation(); }

  @Computed
  get dirty(): boolean {
    return this.draftAlias.trim() !== this.savedAlias || this.draftNote.trim() !== this.savedNote || this.draftPaused !== this.savedPaused;
  }

  private setDraft(value: string) {
    this.draftAlias = value;
    this.reportDraft();
  }

  private reportDraft() {
    this.onDirtyChange(this.draftAlias.trim() !== this.savedAlias || this.draftNote.trim() !== this.savedNote ||
      this.draftPaused !== this.savedPaused);
  }

  private resetDraft() {
    this.draftNote = this.savedNote;
    this.draftPaused = this.savedPaused;
    this.setDraft(this.savedAlias);
  }

  async move(offset: number) {
    if (this.busy || this.dirty) return;
    this.setBusy(true);
    try {
      await ConfigService.moveStation(this.configId, this.stationId, offset);
      if (!this.present) return;
      this.onChanged();
      await this.loadStation();
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '移动失败，请重试');
    } finally { if (this.present) this.setBusy(false); }
  }

  private setBusy(value: boolean) {
    this.busy = value;
    this.onBusyChange(value);
  }

  async loadStation() {
    const request = ++this.loadSequence;
    this.loading = !this.config;
    this.loadError = '';
    try {
      const storage = await ConfigService.loadConfigs();
      if (!this.present || request !== this.loadSequence) return;
      const config = storage.configs.find(item => item.id === this.configId) || null;
      const name = config ? Object.keys(config.stations).find(label => config.stations[label] === this.stationId) : undefined;
      const original = config?.stationNames?.[String(this.stationId)] || name || '';
      const keepAlias = !!name && this.draftAlias.trim() !== this.savedAlias;
      const keepNote = !!name && this.draftNote.trim() !== this.savedNote;
      const keepPaused = !!name && this.draftPaused !== this.savedPaused;
      this.config = config;
      this.displayName = name || '';
      this.originalName = original;
      const member = config?.members?.find(row => row.stationId === this.stationId);
      this.savedAlias = member?.alias || '';
      this.savedNote = member?.note || '';
      this.savedPaused = member?.paused || false;
      if (!keepAlias) this.draftAlias = this.savedAlias;
      if (!keepNote) this.draftNote = this.savedNote;
      if (!keepPaused) this.draftPaused = this.savedPaused;
      this.reportDraft();
    } catch (error) {
      if (this.present && request === this.loadSequence) this.loadError = (error as Error).message || '站点读取失败，请重试';
    } finally { if (request === this.loadSequence) this.loading = false; }
  }

  async saveAlias() {
    if (this.busy || !this.dirty || !this.displayName) return;
    const alias = this.draftAlias.trim();
    this.setBusy(true);
    try {
      await ConfigService.editStation(this.configId, this.stationId,
        alias === this.savedAlias ? undefined : alias,
        this.draftNote.trim() === this.savedNote ? undefined : this.draftNote,
        this.draftPaused === this.savedPaused ? undefined : this.draftPaused);
      if (!this.present) return;
      this.savedAlias = alias;
      this.savedNote = this.draftNote.trim();
      this.savedPaused = this.draftPaused;
      this.resetDraft();
      this.onChanged();
      await this.loadStation();
      if (this.present) ErrorHandler.showToast(this.getUIContext(), '站点设置已保存');
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '保存失败，请重试');
    } finally { if (this.present) this.setBusy(false); }
  }

  async removeStation() {
    const config = this.config;
    if (!config || this.busy || this.dirty || !this.displayName) return;
    this.setBusy(true);
    try {
      const lastStation = Object.keys(config.stations).length === 1;
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '从此配置移除站点？',
        message: `将从“${config.name}”移除“${this.displayName}”。${lastStation ? '移除后会保留这套空配置。' : '其他配置仍可使用此站点。'}`,
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '移除站点', color: this.theme.error }]
      });
      if (!this.present || result.index !== 1) return;
      await ConfigService.removeStation(this.configId, this.stationId);
      if (!this.present) return;
      ErrorHandler.showToast(this.getUIContext(), '站点已从此配置移除');
      this.onRemoved();
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '移除失败，请重试');
    } finally { if (this.present) this.setBusy(false); }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.loading) {
          LoadingProgress().width(32).height(32)
        } else if (this.loadError) {
          Text(this.loadError).fontColor(this.theme.textSecondary)
          Button('重新读取').onClick(() => this.loadStation())
        } else if (!this.config) {
          Text('配置不存在或已被删除').fontColor(this.theme.textSecondary)
        } else if (!this.displayName) {
          Text('此站点已从配置移除').fontColor(this.theme.textSecondary)
        } else {
          Column({ space: 6 }) {
            Text(this.config.name).fontSize(14).fontColor(this.theme.textSecondary)
            Text(this.displayName).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            Text(`原站名 · ${this.originalName}`).fontSize(14).fontColor(this.theme.textSecondary)
            Text(`站点 ID · ${this.stationId}`).fontSize(13).fontColor(this.theme.textSecondary)
          }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
            .backgroundColor(this.theme.cardBackground).borderRadius(18)
          Column({ space: 10 }) {
            Text('配置内显示名').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
            TextInput({ placeholder: this.originalName, text: this.draftAlias }).id('stationAliasInput')
              .maxLength(40).height(44).fontColor(this.theme.textPrimary)
              .backgroundColor(this.theme.secondaryBackground).enabled(!this.busy).onChange((value: string) => this.setDraft(value))
            Text('留空可恢复原站名').fontSize(13).fontColor(this.theme.textSecondary)
            Text('备注').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
            TextArea({ placeholder: '例如：从西侧车棚进入', text: this.draftNote }).id('stationNoteInput')
              .maxLength(200).height(68).fontColor(this.theme.textPrimary).enabled(!this.busy)
              .onChange((value: string) => { this.draftNote = value; this.reportDraft(); })
            Row() {
              Text('暂停此站监控').layoutWeight(1).fontColor(this.theme.textPrimary)
              Toggle({ type: ToggleType.Switch, isOn: this.draftPaused }).accessibilityText('暂停此站监控')
                .enabled(!this.busy).onChange((value: boolean) => { this.draftPaused = value; this.reportDraft(); })
            }.width('100%')
            Row({ space: 10 }) {
              if (this.dirty) {
                Button('取消修改').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
                  .enabled(!this.busy).onClick(() => this.resetDraft())
              }
              Button('保存站点设置').fontSize(14).backgroundColor(this.theme.accent).fontColor('#ffffff')
                .enabled(!this.busy && this.dirty).onClick(() => this.saveAlias())
            }.width('100%').justifyContent(FlexAlign.End)
          }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
            .backgroundColor(this.theme.cardBackground).borderRadius(18)
          if (this.dirty) {
            Text('请先保存或取消修改，再调整顺序、替换或移除。').fontSize(13).fontColor(this.theme.textSecondary)
          }
          Row({ space: 8 }) {
            Text(`配置顺序 ${(this.config.members || []).findIndex(item => item.stationId === this.stationId) + 1} / ${this.config.members?.length || 0}`)
              .layoutWeight(1).fontColor(this.theme.textSecondary)
            Button('上移').height(36).enabled(!this.busy && !this.dirty && (this.config.members || [])[0]?.stationId !== this.stationId)
              .onClick(() => this.move(-1))
            Button('下移').height(36).enabled(!this.busy && !this.dirty && (this.config.members || []).findIndex(item =>
              item.stationId === this.stationId) < (this.config.members?.length || 0) - 1).onClick(() => this.move(1))
          }.width('100%')
          Button('替换站点').width('100%').height(44).backgroundColor(this.theme.cardBackground).fontColor(this.theme.accent)
            .enabled(!this.busy && !this.dirty).onClick(() => { if (this.config) this.onReplace(this.config, this.stationId); })
          Button('从此配置移除').width('100%').height(44).backgroundColor(this.theme.cardBackground).fontColor(this.theme.error)
            .enabled(!this.busy && !this.dirty).onClick(() => this.removeStation())
        }
      }.padding({ left: 16, right: 16, top: 8, bottom: 18 }).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
