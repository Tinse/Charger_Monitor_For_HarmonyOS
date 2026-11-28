import { ChargerConfig } from '../ChargerModels';
import { PresetConfigs } from '../PresetConfigs';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { StationSelection } from '../utils/StationSelection';
import { SearchBar } from './SearchBar';

interface ConfigStationRow {
  id: number;
  displayName: string;
  originalName: string;
  note: string;
  paused: boolean;
}

@ComponentV2
export struct ConfigDetailUI {
  @Param configId: string = '';
  @Param revision: number = 0;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onAddStations: (config: ChargerConfig) => void = () => {};
  @Event onOpenStation: (config: ChargerConfig, id: number) => void = () => {};
  @Event onCopy: (config: ChargerConfig) => void = () => {};
  @Event onChanged: () => void = () => {};
  @Event onDeleted: () => void = () => {};
  @Event onDirtyChange: (dirty: boolean) => void = () => {};
  @Event onBusyChange: (busy: boolean) => void = () => {};
  @Local config: ChargerConfig | null = null;
  @Local loading: boolean = true;
  @Local busy: boolean = false;
  @Local loadError: string = '';
  @Local query: string = '';
  @Local editingName: boolean = false;
  @Local nameDraft: string = '';
  @Local nameError: string = '';
  @Local mode: string = 'browse';
  @Local selectedIds: number[] = [];
  @Local selectedOnly: boolean = false;
  private loadSequence: number = 0;
  private present: boolean = false;

  aboutToAppear() { this.present = true; this.loadConfig(); }
  aboutToDisappear() { this.present = false; this.loadSequence++; }
  @Monitor('revision')
  onRevisionChange() { this.loadConfig(); }

  async loadConfig() {
    const sequence = ++this.loadSequence;
    this.loading = !this.config;
    this.loadError = '';
    try {
      const storage = await ConfigService.loadConfigs();
      if (sequence !== this.loadSequence || !this.present) return;
      this.config = storage.configs.find(item => item.id === this.configId) || null;
      if (!this.config) this.finishRename();
      else {
        const ids = Object.values(this.config.stations);
        this.selectedIds = this.selectedIds.filter(id => ids.includes(id));
        if (this.mode === 'select') this.onDirtyChange(this.selectedIds.length > 0);
      }
    } catch (error) {
      if (sequence === this.loadSequence && this.present) this.loadError = (error as Error).message || '配置读取失败，请重试';
    } finally {
      if (sequence === this.loadSequence) this.loading = false;
    }
  }

  @Computed
  get rows(): ConfigStationRow[] {
    const config = this.config;
    if (!config) return [];
    const displays = StationSelection.displayNames(config);
    return (config.members || []).map((member): ConfigStationRow => {
      return { id: member.stationId, displayName: displays[String(member.stationId)], originalName: member.originalName,
        note: member.note, paused: member.paused };
    });
  }

  @Computed
  get matches(): ConfigStationRow[] {
    const query = StationSelection.normalize(this.query);
    if (this.mode === 'reorder') return this.rows;
    if (this.selectedOnly) return this.rows.filter(row => this.selectedIds.includes(row.id));
    return this.rows.filter(row => StationSelection.normalize(row.displayName).includes(query) ||
      StationSelection.normalize(row.originalName).includes(query) || StationSelection.normalize(row.note).includes(query) ||
      String(row.id).includes(query));
  }

  private setBusy(value: boolean) {
    this.busy = value;
    this.onBusyChange(value);
  }

  private finishRename() {
    this.editingName = false;
    this.nameDraft = '';
    this.nameError = '';
    this.onDirtyChange(false);
  }

  private menuItems(): MenuElement[] {
    const config = this.config;
    if (!config) return [];
    const actions: MenuElement[] = [];
    actions.push({ value: '复制为自定义配置', action: () => { if (!this.busy) this.onCopy(config); } });
    if (this.rows.length > 1) actions.push({ value: '调整站点顺序', action: () => { this.mode = 'reorder'; } });
    if (!PresetConfigs.isPreset(config.id)) {
      actions.push({ value: '修改配置名称', action: () => {
        if (this.busy) return;
        this.nameDraft = config.name;
        this.editingName = true;
      } });
    }
    actions.push({ value: '删除整套配置', action: () => { this.deleteConfig(); } });
    return actions;
  }

  async saveName() {
    if (!this.config || this.busy) return;
    this.setBusy(true);
    try {
      await ConfigService.renameConfig(this.config.id, this.nameDraft.trim());
      if (!this.present) return;
      this.finishRename();
      this.onChanged();
      ErrorHandler.showToast(this.getUIContext(), '配置名称已保存');
    } catch (error) {
      if (this.present) this.nameError = (error as Error).message || '保存失败，请重试';
    } finally { if (this.present) this.setBusy(false); }
  }

  async deleteConfig() {
    const config = this.config;
    if (this.busy || !config) return;
    this.setBusy(true);
    try {
      const storage = await ConfigService.loadConfigs();
      if (!this.present) return;
      const next = storage.configs.find(item => item.id !== config.id);
      const destination = storage.currentConfigId === config.id ? (next ? `监控将切换到“${next.name}”。` : '删除后可新建配置或恢复默认配置。') : '';
      const message = PresetConfigs.isPreset(config.id) ? '可在设置中恢复默认配置。' : '其他配置中的站点仍会保留。';
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除整套配置？', message: `将删除“${config.name}”及其中 ${Object.keys(config.stations).length} 个站点的配置记录。${destination}${message}`,
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '删除配置', color: this.theme.error }]
      });
      if (result.index !== 1 || !this.present) return;
      if (!await ConfigService.deleteConfig(config.id)) throw new Error('配置不存在或已被删除');
      if (!this.present) return;
      ErrorHandler.showToast(this.getUIContext(), '配置已删除');
      this.onDeleted();
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '删除未完成，请重试');
    } finally { if (this.present) this.setBusy(false); }
  }

  private finishSelection() {
    this.mode = 'browse';
    this.selectedOnly = false;
    this.selectedIds = [];
    this.onDirtyChange(false);
  }

  private selectStation(id: number) {
    this.selectedIds = this.selectedIds.includes(id) ? this.selectedIds.filter(item => item !== id) : [...this.selectedIds, id];
    this.onDirtyChange(this.selectedIds.length > 0);
  }

  async removeSelected() {
    if (this.busy || !this.config || this.selectedIds.length === 0) return;
    const ids = [...this.selectedIds];
    this.setBusy(true);
    try {
      const decision = await this.getUIContext().getPromptAction().showDialog({
        title: `移除选中的 ${ids.length} 个站点？`,
        message: `只影响“${this.config.name}”。${ids.length === this.rows.length ? '移除后保留这套空配置。' : ''}`,
        buttons: [{ text: '取消', color: this.theme.textSecondary }, { text: '确认移除', color: this.theme.error }]
      });
      if (decision.index !== 1 || !this.present) return;
      await ConfigService.removeStations(this.configId, ids);
      if (!this.present) return;
      this.finishSelection();
      this.onChanged();
      ErrorHandler.showToast(this.getUIContext(), `已移除 ${ids.length} 个站点`);
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '移除失败，可重试');
    } finally { if (this.present) this.setBusy(false); }
  }

  async moveStation(id: number, offset: number) {
    if (this.busy) return;
    this.setBusy(true);
    try {
      await ConfigService.moveStation(this.configId, id, offset);
      if (this.present) this.onChanged();
    } catch (error) {
      if (this.present) ErrorHandler.showToast(this.getUIContext(), (error as Error).message || '调整顺序失败');
    } finally { if (this.present) this.setBusy(false); }
  }

  @Builder
  stationRow(row: ConfigStationRow) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(row.displayName).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        if (row.originalName !== row.displayName) {
          Text(`原站名 · ${row.originalName}`).fontSize(13).fontColor(this.theme.textSecondary)
        }
        if (row.note) { Text(row.note).fontSize(13).fontColor(this.theme.textSecondary).maxLines(2) }
        Text(`ID ${row.id}${row.paused ? ' · 已暂停' : ''}`).fontSize(12).fontColor(this.theme.textSecondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        .onClick(() => { if (this.mode === 'select' && !this.busy) this.selectStation(row.id);
          else if (this.mode === 'browse' && !this.editingName && this.config && !this.busy) this.onOpenStation(this.config, row.id); })
      if (this.mode === 'reorder') {
        Button('上移').height(32).fontSize(12).enabled(!this.busy && this.rows[0]?.id !== row.id)
          .onClick(() => this.moveStation(row.id, -1))
        Button('下移').height(32).fontSize(12).enabled(!this.busy && this.rows[this.rows.length - 1]?.id !== row.id)
          .onClick(() => this.moveStation(row.id, 1))
      } else if (this.mode === 'select') {
        Checkbox({ name: String(row.id) }).select(this.selectedIds.includes(row.id)).accessibilityText(`选择${row.displayName}`)
          .onChange((checked: boolean) => { if (!this.busy && this.selectedIds.includes(row.id) !== checked) this.selectStation(row.id); })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.theme.textSecondary])
          .onClick(() => { if (this.config && !this.editingName && !this.busy) this.onOpenStation(this.config, row.id); })
      }
    }.width('100%').constraintSize({ minHeight: 60 }).padding(14)
      .backgroundColor(this.theme.cardBackground).borderRadius(16)
      .enabled(!this.busy && !this.editingName)

  }

  build() {
    Column({ space: 10 }) {
      if (this.loading) {
        LoadingProgress().width(32).height(32)
      } else if (this.loadError) {
        Text(this.loadError).fontColor(this.theme.textSecondary)
        Button('重新读取').onClick(() => this.loadConfig())
      } else if (!this.config) {
        Text('配置不存在或已被删除').fontColor(this.theme.textSecondary)
      } else {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(this.config.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
            Text(`${this.rows.length} 个站点 · ${PresetConfigs.isPreset(this.configId) ? '默认配置' : '自定义配置'}`)
              .fontSize(13).fontColor(this.theme.textSecondary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          if (this.mode === 'browse') {
            if (this.rows.length > 0) {
              Button('多选').height(36).fontSize(14).enabled(!this.busy && !this.editingName)
                .onClick(() => { this.mode = 'select'; })
            }
            Button('更多').height(36).fontSize(14).fontColor(this.theme.accent)
              .backgroundColor(this.theme.cardBackground).enabled(!this.busy && !this.editingName)
              .bindMenu(this.menuItems())
          } else {
            Button(this.mode === 'reorder' ? '完成排序' : '退出多选').height(36).fontSize(14)
              .enabled(!this.busy).onClick(() => this.finishSelection())
          }
        }.width('100%')
        if (this.editingName) {
          TextInput({ placeholder: '配置名称', text: this.nameDraft }).id('renameConfigInput')
            .maxLength(24).fontColor(this.theme.textPrimary).enabled(!this.busy)
            .onChange((value: string) => {
              this.nameDraft = value;
              this.nameError = '';
              this.onDirtyChange(this.config !== null && value.trim() !== this.config.name);
            })
          if (this.nameError) { Text(this.nameError).fontColor(this.theme.error).fontSize(13) }
          Row({ space: 12 }) {
            Button('取消').enabled(!this.busy).onClick(() => this.finishRename())
            Button('保存配置名称').enabled(!this.busy && this.nameDraft.trim().length > 0 &&
              this.nameDraft.trim() !== this.config.name).onClick(() => this.saveName())
          }.width('100%').justifyContent(FlexAlign.End)
        }
        if (this.mode !== 'reorder' && !this.selectedOnly) {
        Row({ space: 8 }) {
          Column() {
            SearchBar({ placeholder: '搜索站名、ID 或备注', value: this.query, theme: this.theme,
              onChangeCallback: (value: string) => { this.query = value; } })
          }.layoutWeight(1)
          if (this.query.length) {
            Button('清除搜索').height(36).fontSize(13).fontColor(this.theme.accent)
              .backgroundColor(Color.Transparent).onClick(() => { this.query = ''; })
          }
        }.width('100%')
        if (this.query.trim().length) {
          Text(`找到 ${this.matches.length} 个站点`).fontSize(13).fontColor(this.theme.textSecondary).width('100%')
        }
        }
        if (!this.matches.length) {
          Column({ space: 6 }) {
            Text(this.selectedOnly ? '尚未选择站点' : this.rows.length ? '没有匹配的站点' : '配置中暂无站点').fontSize(16).fontColor(this.theme.textPrimary)
            Text(this.selectedOnly ? '返回筛选后勾选要移除的站点' : this.rows.length ? '试试其他名称或站点 ID' : '添加站点后即可查看插座状态')
              .fontSize(13).fontColor(this.theme.textSecondary)
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.matches, (row: ConfigStationRow) => {
              ListItem() { this.stationRow(row) }
            }, (row: ConfigStationRow) => JSON.stringify(row))
          }.layoutWeight(1).width('100%')
        }
        if (this.mode === 'select') {
          Row({ space: 8 }) {
            Button(this.selectedOnly ? '返回筛选' : `已选 ${this.selectedIds.length}`).height(42)
              .enabled(this.selectedIds.length > 0 || this.selectedOnly).onClick(() => { this.selectedOnly = !this.selectedOnly; })
            Button('勾选结果').height(42).enabled(!this.busy && !this.selectedOnly && this.matches.length > 0)
              .onClick(() => {
                const ids = new Set<number>(this.selectedIds);
                this.matches.forEach(row => ids.add(row.id));
                this.selectedIds = Array.from(ids);
                this.onDirtyChange(this.selectedIds.length > 0);
              })
            Button('移除所选').height(42).fontColor(this.theme.error).backgroundColor(this.theme.cardBackground)
              .enabled(!this.busy && this.selectedIds.length > 0).onClick(() => this.removeSelected())
          }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        } else if (this.mode === 'browse') {
          Button('添加站点').height(46).width('100%').backgroundColor(this.theme.accent).fontColor('#ffffff')
            .enabled(!this.busy && !this.editingName).onClick(() => { if (this.config) this.onAddStations(this.config); })
        }
      }
    }.padding({ left: 16, right: 16, top: 8, bottom: 16 }).width('100%').height('100%')
      .backgroundColor(this.theme.background)
  }
}
