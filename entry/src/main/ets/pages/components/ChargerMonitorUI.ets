// 基础状态与用户主动查询的占用详情分层，滚动、筛选和排序均不发网络请求。
import { ChargerConfig, ConfigStationMember, OutletStatus, SORT_MODE } from '../ChargerModels';
import { StationLoadProgress, StationService, StationSnapshot, OutletLoadProgress } from '../services/StationService';
import { MonitorDetail, MonitorModel, MonitorOutletRow, MonitorStationRow, MonitorStats, MonitorTarget } from '../utils/MonitorModel';
import { RefreshGate } from '../utils/RefreshGate';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { ApiConfig } from '../ApiConfig';
import { MonitorBadge, MonitorPresentation } from '../utils/MonitorPresentation';

@ComponentV2
export struct ChargerMonitorUI {
  @Param stationConfig: Record<string, number> = {};
  @Param isActive: boolean = true;
  @Param configRevision: number = 0;
  @Param networkOnline: boolean = true;
  @Param networkRevision: number = 0;
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Event onManageConfig: (id: string) => void = () => {};
  @Event onAddStations: (config: ChargerConfig) => void = () => {};

  @Local configs: ChargerConfig[] = [];
  @Local currentConfig: ChargerConfig | null = null;
  @Local allRows: MonitorStationRow[] = [];
  @Local filteredRows: MonitorStationRow[] = [];
  @Local stats: MonitorStats = { active: 0, covered: 0, total: 0, free: 0, occupied: 0, broken: 0 };
  @Local searchText: string = '';
  @Local searchInputText: string = '';
  @Local sortMode: number = SORT_MODE.FREE_COUNT;
  @Local showSortMenu: boolean = false;
  @Local isFetching: boolean = false;
  @Local baseManual: boolean = false;
  @Local manualWaiting: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local refreshCooldown: number = 0;
  @Local baseCompleted: number = 0;
  @Local baseTotal: number = 0;
  @Local baseCacheHits: number = 0;
  @Local baseStartedAt: number = 0;
  @Local failedIds: number[] = [];
  @Local errorMessage: string = '';
  @Local configReadError: boolean = false;
  @Local now: number = Date.now();
  @Local detailsRunning: boolean = false;
  @Local detailStartedAt: number = 0;
  @Local detailTotal: number = 0;
  @Local detailCompleted: number = 0;
  @Local detailSucceeded: number = 0;
  @Local detailFailed: number = 0;
  @Local detailSkipped: number = 0;
  @Local detailMessage: string = '';
  @Local showProgressDialog: boolean = false;
  @Local progressKind: string = 'detail';
  @Local detailFailedTargets: MonitorTarget[] = [];

  @Local members: ConfigStationMember[] = [];
  @Local showStationInfo: boolean = false;
  @Local infoStationId: number = 0;
  private snapshots: Map<number, StationSnapshot> = new Map();
  private details: Map<string, MonitorDetail> = new Map();
  private retries: Map<number, number> = new Map();
  private manualRetries: Map<number, number> = new Map();
  private sortedRows: MonitorStationRow[] = [];
  private baseRequestedIds: number[] = [];
  private baseWaiters: (() => void)[] = [];
  private pendingIds: number[] = [];
  private missingIds: number[] = [];
  private snapshotSignature: string = '';
  private hasAppeared: boolean = false;
  private baseVersion: number = 0;
  private manualVersion: number = 0;
  private detailVersion: number = 0;
  private configLoadVersion: number = 0;
  private clockTimer: number = -1;
  private searchTimer: number = -1;
  private freshnessCheckedAt: number = 0;
  private refreshGate: RefreshGate = new RefreshGate(ApiConfig.MANUAL_REFRESH_COOLDOWN);

  aboutToAppear() {
    this.hasAppeared = true;
    this.loadConfigs();
    this.startTimers();
  }

  aboutToDisappear() {
    this.hasAppeared = false;
    this.configLoadVersion++;
    this.showStationInfo = false;
    this.stopLoads();
    this.stopTimers();
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
  }

  @Monitor('isActive')
  onActivityChange() {
    if (this.isActive) {
      this.loadConfigs();
      this.startTimers();
    } else {
      this.stopLoads();
      this.stopTimers();
      this.showSortMenu = false;
    }
  }

  @Monitor('networkRevision')
  onNetworkChange() {
    if (!this.networkOnline) {
      this.stopLoads();
      this.syncSnapshots(true);
    } else if (this.isActive && this.hasAppeared) {
      this.now = Date.now();
      this.syncSnapshots(true);
      // 恢复网络可提前复核普通失败；服务端限流仍保持约束。
      const failed = this.manualFailedIds().filter(id => !this.missingIds.includes(id));
      const due = MonitorModel.dueIds(this.allRows, this.now);
      const ids = Array.from(new Set([...failed, ...due]));
      if (ids.length) this.fetchData(ids, failed.length > 0, false);
    }
  }

  @Monitor('stationConfig')
  onStationConfigChange() {
    this.showStationInfo = false;
    this.stopLoads();
    this.failedIds = [];
    this.missingIds = [];
    this.retries.clear();
    this.manualRetries.clear();
    this.details.clear();
    this.detailFailedTargets = [];
    this.detailTotal = 0;
    this.detailMessage = '';
    this.showProgressDialog = false;
    this.errorMessage = '';
    this.searchText = '';
    this.searchInputText = '';
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    this.currentConfig = null;
    this.members = MonitorModel.members(null, this.stationConfig);
    this.syncSnapshots(true);
    this.loadConfigs();
  }

  @Monitor('configRevision')
  onConfigRevisionChange() { this.loadConfigs(); }

  async loadConfigs() {
    const version = ++this.configLoadVersion;
    try {
      const storage = await ConfigService.loadConfigs();
      if (version !== this.configLoadVersion || !this.hasAppeared) return;
      this.configReadError = false;
      this.configs = storage.configs;
      this.currentConfig = storage.configs.find(config => config.id === storage.currentConfigId) || null;
      this.members = MonitorModel.members(this.currentConfig, this.stationConfig);
      const activeIds = this.members.filter(member => !member.paused).map(member => member.stationId);
      this.failedIds = this.failedIds.filter(id => activeIds.includes(id));
      this.syncSnapshots(true);
      if (this.isActive) this.fetchDue();
    } catch (error) {
      if (version !== this.configLoadVersion || !this.hasAppeared) return;
      this.configReadError = true;
      ErrorHandler.handle(error, 'ChargerMonitorUI.loadConfigs');
    }
  }

  private startTimers() {
    if (!this.isActive || !this.hasAppeared) return;
    if (this.clockTimer === -1) this.clockTimer = setInterval(() => {
      this.now = Date.now();
      this.refreshCooldown = this.refreshGate.remaining(this.now);
      if (this.now < this.freshnessCheckedAt || this.now - this.freshnessCheckedAt >= 1000) {
        this.freshnessCheckedAt = this.now;
        this.syncSnapshots();
        this.fetchDue();
      }
    }, 250);
  }

  private stopTimers() {
    if (this.clockTimer !== -1) clearInterval(this.clockTimer);
    this.clockTimer = -1;
  }

  private stopLoads() {
    this.baseVersion++;
    this.manualVersion++;
    this.manualWaiting = false;
    this.notifyBaseWaiters();
    this.isFetching = false;
    this.isRefreshing = false;
    this.pendingIds = [];
    this.refreshGate.finish();
    this.stopDetails(false);
    this.showProgressDialog = false;
  }

  private syncSnapshots(force: boolean = false) {
    const snapshots = new Map<number, StationSnapshot>();
    const signatures: string[] = [];
    this.members.forEach((member: ConfigStationMember) => {
      const reading = StationService.getSnapshot(member.stationId, member.alias || member.originalName, Date.now());
      const snapshot: StationSnapshot | null = reading ? { station: reading.station, fetchedAt: reading.fetchedAt,
        generation: reading.generation, fromDisk: reading.fromDisk, confirmed: reading.confirmed && this.networkOnline } : null;
      if (snapshot) snapshots.set(member.stationId, snapshot);
      signatures.push(`${member.stationId}/${snapshot?.generation}/${snapshot?.confirmed}/${snapshot?.fetchedAt}/${snapshot?.fromDisk}`);
    });
    this.snapshots = snapshots;
    const signature = signatures.join('|');
    if (!force && signature === this.snapshotSignature) return;
    this.snapshotSignature = signature;
    MonitorModel.retainDetails(this.members, snapshots, this.details);
    this.rebuildRows();
  }

  private rebuildRows() {
    this.allRows = MonitorModel.rows(this.members, this.snapshots, this.details, this.pendingIds, this.failedIds, this.retries, this.manualRetries, this.missingIds);
    this.stats = MonitorModel.stats(this.allRows);
    this.sortedRows = MonitorModel.sorted(this.allRows, this.sortMode);
    this.filteredRows = MonitorModel.filter(this.sortedRows, this.searchText);
  }

  @Monitor('searchText')
  onFilterChange() { this.filteredRows = MonitorModel.filter(this.sortedRows, this.searchText); }

  @Monitor('sortMode')
  onSortChange() { this.sortedRows = MonitorModel.sorted(this.allRows, this.sortMode); this.onFilterChange(); }

  onSearchInput(value: string) {
    this.searchInputText = value;
    if (this.searchTimer !== -1) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => { this.searchText = value; this.searchTimer = -1; }, ApiConfig.DEBOUNCE_DELAY);
  }

  private fetchDue(): void {
    if (!this.isActive || !this.networkOnline || this.isFetching || !this.hasAppeared) return;
    this.syncSnapshots();
    const ids = MonitorModel.dueIds(this.allRows, Date.now());
    if (ids.length) this.fetchData(ids, false);
  }

  async fetchData(ids: number[], forceNetwork: boolean, manualIntent: boolean = forceNetwork): Promise<boolean> {
    if (this.isFetching || !this.networkOnline || !this.isActive || !this.hasAppeared) return false;
    const target: Record<string, number> = {};
    Object.keys(this.stationConfig).forEach((name: string) => {
      if (ids.includes(this.stationConfig[name])) target[name] = this.stationConfig[name];
    });
    const requested = Object.values(target);
    if (!requested.length) return false;
    const version = ++this.baseVersion;
    this.pendingIds = requested;
    this.baseRequestedIds = requested;
    this.baseManual = manualIntent;
    this.baseTotal = requested.length;
    this.baseCompleted = 0;
    this.baseCacheHits = 0;
    this.baseStartedAt = Date.now();
    this.isFetching = true;
    this.errorMessage = '';
    this.syncSnapshots(true);
    try {
      await StationService.fetchStationsForConfig(target, (step: StationLoadProgress) => {
        if (version !== this.baseVersion || !this.hasAppeared || !this.isActive || !this.networkOnline) return;
        this.baseCompleted = step.completed;
        if (step.fromCache) this.baseCacheHits++;
        this.pendingIds = this.pendingIds.filter(id => id !== step.stationId);
        this.failedIds = this.failedIds.filter(id => id !== step.stationId);
        if (!step.station) this.failedIds = [...this.failedIds, step.stationId];
        this.missingIds = this.missingIds.filter(id => id !== step.stationId);
        if (step.missing) this.missingIds = [...this.missingIds, step.stationId];
        if (step.retryAt !== undefined) this.retries.set(step.stationId, step.retryAt);
        else this.retries.delete(step.stationId);
        if (step.manualRetryAt !== undefined) this.manualRetries.set(step.stationId, step.manualRetryAt);
        else this.manualRetries.delete(step.stationId);
        this.syncSnapshots(true);
      }, forceNetwork, () => version === this.baseVersion && this.hasAppeared && this.isActive && this.networkOnline);
      if (version !== this.baseVersion) return false;
      return !requested.some(id => this.failedIds.includes(id));
    } catch (error) {
      if (version === this.baseVersion) {
        this.failedIds = Array.from(new Set([...this.failedIds, ...this.pendingIds]));
        this.errorMessage = '基础状态查询失败，可单站重试或仅重试失败站';
      }
      ErrorHandler.handle(error, 'ChargerMonitorUI.fetchData');
      return false;
    } finally {
      if (version === this.baseVersion) {
        this.isFetching = false;
        this.pendingIds = [];
        this.syncSnapshots(true);
        this.notifyBaseWaiters();
      }
    }
  }

  private notifyBaseWaiters(): void {
    const waiting = this.baseWaiters;
    this.baseWaiters = [];
    waiting.forEach((done: () => void) => done());
  }

  async manualRefresh(source: string = 'button', ids: number[] = Object.values(this.stationConfig)) {
    if (!ids.length || !this.isActive || !this.networkOnline) { this.isRefreshing = false; return; }
    if ((this.isFetching && this.baseManual) || !this.refreshGate.tryStart(Date.now())) {
      this.isRefreshing = false;
      ErrorHandler.showToast(this.getUIContext(), this.isFetching ? '正在查询基础状态' : '请稍候再刷新');
      return;
    }
    this.progressKind = 'base';
    this.showProgressDialog = true;
    const version = ++this.manualVersion;
    this.refreshCooldown = this.refreshGate.remaining(Date.now());
    try {
      let remaining = ids;
      if (this.isFetching) {
        // 重用当前自动轮次覆盖的请求，随后仅补未覆盖的启用站点。
        remaining = ids.filter(id => !this.baseRequestedIds.includes(id));
        this.manualWaiting = true;
        await new Promise<void>((resolve: () => void) => { this.baseWaiters.push(resolve); });
        if (version !== this.manualVersion || !this.isActive || !this.networkOnline) return;
        this.manualWaiting = false;
      }
      const success = remaining.length ? await this.fetchData(remaining, true) : !ids.some(id => this.failedIds.includes(id));
      if (success && this.hasAppeared && this.isActive) ErrorHandler.showToast(this.getUIContext(), '基础状态已更新');
      console.info(`[MonitorRefresh] ${source}: ${success}`);
    } finally {
      if (version === this.manualVersion) {
        this.manualWaiting = false;
        if (this.progressKind === 'base') this.showProgressDialog = false;
        this.refreshGate.finish();
        this.isRefreshing = false;
        this.refreshCooldown = this.refreshGate.remaining(Date.now());
      }
    }
  }

  private manualFailedIds(at: number = this.now): number[] {
    return this.allRows.filter(row => row.failed && !row.paused && (!row.manualRetryAt || row.manualRetryAt <= at)).map(row => row.id);
  }

  private retryFailedStations() {
    const ids = this.manualFailedIds();
    if (ids.length) this.manualRefresh('failed', ids);
  }

  private stopDetails(showMessage: boolean = true) {
    this.detailVersion++;
    if (this.detailsRunning) {
      this.detailsRunning = false;
      for (const detail of Array.from(this.details.values())) {
        if (detail.state === 'pending') this.details.set(MonitorModel.key(detail.stationId, detail.outletNo, detail.generation), MonitorModel.withState({ stationId: detail.stationId, outletNo: detail.outletNo, generation: detail.generation }, 'stopped', detail));
      }
      this.detailMessage = MonitorPresentation.detailSummary(this.detailCompleted, this.detailSucceeded, this.detailFailed, this.detailSkipped, true);
      if (!showMessage) this.showProgressDialog = false;
      this.rebuildRows();
    }
  }

  private retryableDetailTargets(rows: MonitorStationRow[] = this.allRows): MonitorTarget[] {
    return MonitorModel.targets(rows).filter(target => this.detailFailedTargets.some(failed =>
      failed.stationId === target.stationId && failed.outletNo === target.outletNo));
  }

  async fetchDetails(retryFailed: boolean = false) {
    if (this.detailsRunning || !this.networkOnline || !this.isActive || !this.hasAppeared) return;
    this.syncSnapshots();
    // 此处冻结整配置清单；后续搜索、滚动、排序或新增占用不扩充本轮。
    const targets = retryFailed ? this.retryableDetailTargets() : MonitorModel.targets(this.allRows);
    if (!targets.length) return;
    const version = ++this.detailVersion;
    const readings: StationSnapshot[] = [];
    const wantedIds = Array.from(new Set(targets.map(target => target.stationId)));
    wantedIds.forEach((id: number) => {
      const reading = this.snapshots.get(id);
      if (!reading?.confirmed) return;
      // 使用同一轮快照，边界过期由服务计入已失效；同时按站限定目标，避免重号插座扩充重试范围。
      const frozen: StationSnapshot = { fetchedAt: reading.fetchedAt, generation: reading.generation,
        confirmed: reading.confirmed, fromDisk: reading.fromDisk,
        station: { id: reading.station.id, name: reading.station.name,
          outlets: reading.station.outlets.filter(outlet => targets.some(target => target.stationId === id &&
            target.generation === reading.generation && target.outletNo === outlet.outletNo)) } };
      readings.push(frozen);
    });
    this.detailTotal = targets.length;
    this.detailCompleted = 0;
    this.detailSucceeded = 0;
    this.detailFailed = 0;
    this.detailSkipped = 0;
    this.detailFailedTargets = [];
    this.detailMessage = '';
    this.showProgressDialog = false;
    this.detailStartedAt = Date.now();
    this.detailsRunning = true;
    this.progressKind = 'detail';
    this.showProgressDialog = true;
    targets.forEach((target: MonitorTarget) => this.details.set(MonitorModel.key(target.stationId, target.outletNo, target.generation),
      MonitorModel.withState(target, 'pending', this.details.get(MonitorModel.key(target.stationId, target.outletNo, target.generation)))));
    this.rebuildRows();
    try {
      await StationService.fetchOccupiedDetails(readings, (step: OutletLoadProgress) => {
        if (version !== this.detailVersion || !this.hasAppeared || !this.isActive || !this.networkOnline) return;
        this.detailCompleted = step.completed;
        this.detailSucceeded = step.succeeded;
        this.detailFailed = step.failed;
        this.detailSkipped = step.skipped;
        const target = targets.find(item => item.stationId === step.stationId && item.outletNo === step.outletNo && item.generation === step.generation);
        if (!target) return;
        this.syncSnapshots();
        if (!MonitorModel.validTarget(target, this.allRows)) return;
        const key = MonitorModel.key(target.stationId, target.outletNo, target.generation);
        const detail: MonitorDetail = { stationId: target.stationId, outletNo: target.outletNo, generation: target.generation,
          state: step.detail ? 'success' : 'failed', fetchedAt: step.detail ? Date.now() : undefined,
          power_w: step.detail?.power_w, fee: step.detail?.fee, used_min: step.detail?.used_min };
        this.details.set(key, step.detail ? detail : MonitorModel.withState(target, 'failed', this.details.get(key)));
        if (!step.detail) this.detailFailedTargets = [...this.detailFailedTargets, target];
        this.rebuildRows();
      }, () => version === this.detailVersion && this.hasAppeared && this.isActive && this.networkOnline,
      targets.map(target => target.outletNo));
      if (version === this.detailVersion) this.detailMessage = MonitorPresentation.detailSummary(this.detailCompleted, this.detailSucceeded, this.detailFailed, this.detailSkipped);
    } catch (error) {
      if (version === this.detailVersion) {
        this.detailMessage = '详情查询中断，可重试失败项';
        targets.forEach((target: MonitorTarget) => {
          const key = MonitorModel.key(target.stationId, target.outletNo, target.generation);
          if (this.details.get(key)?.state === 'pending' && MonitorModel.validTarget(target, this.allRows)) {
            this.details.set(key, MonitorModel.withState(target, 'failed', this.details.get(key)));
            this.detailFailedTargets = [...this.detailFailedTargets, target];
          }
        });
      }
      if (version === this.detailVersion) {
        this.detailFailed = this.detailFailedTargets.length;
        this.detailCompleted = this.detailSucceeded + this.detailFailed + this.detailSkipped;
      }
      ErrorHandler.handle(error, 'ChargerMonitorUI.fetchDetails');
    } finally {
      if (version === this.detailVersion) {
        this.detailsRunning = false;
        // 保留弹窗结果，由用户关闭或重试。
        this.rebuildRows();
      }
    }
  }

  @Computed
  get infoRow(): MonitorStationRow | null { return this.allRows.find(row => row.id === this.infoStationId) || null; }

  @Monitor('allRows')
  onInfoRowsChange(): void { if (this.showStationInfo && !this.infoRow) this.showStationInfo = false; }

  private openStationInfo(id: number): void {
    if (!this.allRows.some(row => row.id === id)) return;
    this.infoStationId = id;
    this.showStationInfo = true;
  }

  private elapsed(start: number, at: number = this.now): number { return Math.max(0, Math.floor((at - start) / 1000)); }

  private rowStatus(row: MonitorStationRow): string { return MonitorPresentation.rowStatus(row); }

  private sortLabel(mode: number): string {
    if (mode === SORT_MODE.CONFIG_ORDER) return '配置顺序';
    if (mode === SORT_MODE.SERIAL) return '插座编号';
    if (mode === SORT_MODE.POWER) return '功率';
    if (mode === SORT_MODE.FEE) return '费用';
    if (mode === SORT_MODE.DURATION) return '时长';
    return '空闲数量';
  }

  @Builder
  sortItem(label: string, mode: number) {
    Button(label).height(44).width('100%').fontSize(14).backgroundColor(Color.Transparent)
      .fontColor(this.sortMode === mode ? this.theme.accent : this.theme.textPrimary)
      .onClick(() => { this.sortMode = mode; this.showSortMenu = false; })
  }

  @Builder
  sortMenu() {
    Column() {
      this.sortItem('空闲数量', SORT_MODE.FREE_COUNT)
      this.sortItem('配置顺序', SORT_MODE.CONFIG_ORDER)
      this.sortItem('插座编号', SORT_MODE.SERIAL)
      this.sortItem('功率（已查询详情）', SORT_MODE.POWER)
      this.sortItem('费用（已查询详情）', SORT_MODE.FEE)
      this.sortItem('时长（已查询详情）', SORT_MODE.DURATION)
    }.width(210).padding(4)
  }

  @Builder
  stationInfo() {
    Scroll() {
      Column({ space: 14 }) {
        Text('站点信息').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
        if (this.infoRow) {
        Text(this.infoRow!.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary).width('100%')
        Text(`原站名：${this.infoRow!.originalName}`).fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        Text(`站点 ID：${this.infoRow!.id}`).fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        Text(`基础状态：${MonitorPresentation.rowStatus(this.infoRow!) || '已确认'}`).fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        Text(`获取时间：${MonitorPresentation.clock(this.infoRow!.fetchedAt, true)}`).fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        if (this.infoRow!.note) Text(`备注：${this.infoRow!.note}`).fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        ForEach(this.infoRow!.outlets.filter(outlet => outlet.detailState === 'success'), (outlet: MonitorOutletRow) => {
          Text(`插座${outlet.serial} 详情：${MonitorPresentation.clock(outlet.detailFetchedAt, true)}`).fontSize(12).fontColor(this.theme.textSecondary).width('100%')
        }, (outlet: MonitorOutletRow) => outlet.renderKey)
        Text('这里只展示已有记录，打开面板不会刷新或查询详情。').fontSize(12).fontColor(this.theme.textTertiary).width('100%')
        Button('管理配置').height(40).fontSize(14).onClick(() => { this.showStationInfo = false; this.onManageConfig(this.currentConfig?.id || ''); })
        }
      }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: 36 }).alignItems(HorizontalAlign.Start)
    }.width('100%').scrollBar(BarState.Off)
  }

  @Builder
  overview() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Circle({ width: 8, height: 8 }).foregroundColor(!this.networkOnline || !this.stats.covered ? this.theme.textTertiary : this.stats.free > 0 ? this.theme.success : this.theme.error)
        Text(MonitorPresentation.title(this.stats, this.isFetching, this.networkOnline, this.members.length))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary).layoutWeight(1).maxLines(2)
        Button(this.isFetching && this.baseManual || this.manualWaiting ? '刷新中' : this.refreshCooldown > 0 ? `${Math.ceil(this.refreshCooldown / 1000)}s` : '刷新')
          .id('monitorRefreshButton').width(72).height(40).fontSize(12).padding({ left: 8, right: 8 })
          .backgroundColor(this.theme.accent).fontColor(this.theme.onAccent)
          .enabled(this.isFetching && this.baseManual || this.manualWaiting || this.stats.active > 0 && this.networkOnline && this.refreshCooldown === 0)
          .accessibilityText('刷新当前配置基础状态').onClick(() => {
            if (this.isFetching && this.baseManual || this.manualWaiting) {
              this.progressKind = 'base'; this.showProgressDialog = true;
            } else this.manualRefresh();
          })
      }.width('100%')
      Row() {
        Column({ space: 2 }) {
          Text(this.stats.covered > 0 ? this.stats.free.toString() : '—').id('monitorFreeCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.success)
          Text('空闲').fontSize(12).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Divider().vertical(true).height(26).color(this.theme.border)
        Column({ space: 2 }) {
          Text(this.stats.covered > 0 ? this.stats.occupied.toString() : '—').id('monitorOccupiedCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.error)
          Text('占用').fontSize(12).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Divider().vertical(true).height(26).color(this.theme.border)
        Column({ space: 2 }) {
          Text(this.stats.covered > 0 ? this.stats.broken.toString() : '—').id('monitorBrokenCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.warning)
          Text('故障').fontSize(12).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Divider().vertical(true).height(26).color(this.theme.border)
        Column({ space: 2 }) {
          Text(this.stats.covered > 0 ? this.stats.total.toString() : '—').id('monitorTotalCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text('总计').fontSize(12).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
      }.width('100%')
      Text(MonitorPresentation.coverage(this.stats, this.allRows)).id('monitorLoadSummary').fontSize(12).fontColor(this.theme.textSecondary).width('100%')
      if (!this.networkOnline) Text('网络未连接，恢复后自动核实历史数据').fontSize(12).fontColor(this.theme.warningText).width('100%')
      if (this.failedIds.length > 0) {
        Row({ space: 8 }) {
          Text(`${this.failedIds.length} 站更新失败`).fontSize(12).fontColor(this.theme.errorText).layoutWeight(1)
          Button('重试失败站').id('monitorRetryFailedButton').height(40).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.infoText)
            .enabled(this.networkOnline && !this.isFetching && this.refreshCooldown === 0 && this.manualFailedIds(this.now).length > 0)
            .onClick(() => this.retryFailedStations())
        }.width('100%')
      }
      if (this.errorMessage) Text(this.errorMessage).fontSize(12).fontColor(this.theme.errorText).width('100%')
      if (this.configReadError) {
        Row({ space: 8 }) {
          Text('配置读取失败').fontSize(12).fontColor(this.theme.errorText).layoutWeight(1)
          Button('重新读取').height(40).fontSize(12).onClick(() => this.loadConfigs())
        }.width('100%')
      }
    }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: 10 }).backgroundColor(this.theme.cardBackground).borderRadius(16)
  }

  @Builder
  progressOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor(this.theme.overlay)
        .onClick(() => { this.showProgressDialog = false; })
      Scroll() {
        this.progressDialog()
      }.width('90%').constraintSize({ maxWidth: 360, maxHeight: '85%' })
        .backgroundColor(this.theme.cardBackground).borderRadius(24).scrollBar(BarState.Auto)
    }.width('100%').height('100%')
  }

  @Builder
  progressDialog() {
    Column({ space: 16 }) {
      Text(this.progressKind === 'base' ? '正在刷新站点' : this.detailsRunning ? '正在获取占用信息' : '占用信息获取结果')
        .id('progressDialogTitle').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).width('100%')
      if (this.progressKind === 'base') {
        Text(this.manualWaiting ? '正在等待本轮站点更新' : `已处理 ${this.baseCompleted}/${this.baseTotal} 站`)
          .id('monitorLoadProgress').fontSize(14).fontColor(this.theme.textSecondary).width('100%')
        Progress({ value: this.baseCompleted, total: Math.max(1, this.baseTotal), type: ProgressType.Linear })
          .id('monitorLoadProgressBar').width('100%').color(this.theme.accent)
        Text(`已等待 ${this.elapsed(this.baseStartedAt, this.now)} 秒 · 已获取的站点会先显示`)
          .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
      } else {
        Text(this.detailsRunning ? `已处理 ${this.detailCompleted}/${this.detailTotal} 个占用插座` : this.detailMessage)
          .id('detailLoadProgress').fontSize(14).fontColor(this.theme.textPrimary).width('100%')
        Progress({ value: this.detailCompleted, total: Math.max(1, this.detailTotal), type: ProgressType.Linear })
          .id('detailLoadProgressBar').width('100%').color(this.theme.accent)
        Text(`${this.detailSucceeded} 项成功 · ${this.detailFailed} 项失败${this.detailSkipped ? ' · ' + this.detailSkipped + ' 项状态已变化' : ''}`)
          .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
        if (this.detailsRunning) {
          Text(this.elapsed(this.detailStartedAt, this.now) >= 10 ? `已等待 ${this.elapsed(this.detailStartedAt, this.now)} 秒，响应较慢，可继续等待或停止` : `已等待 ${this.elapsed(this.detailStartedAt, this.now)} 秒`)
            .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
        }
        Text('基础刷新保留已获取的信息，功率、费用、时长仅在主动获取时更新。')
          .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
      }
      Row({ space: 12 }) {
        if (this.progressKind === 'detail' && this.detailsRunning) {
          Button('停止获取').id('detailStopButton').height(40).fontSize(14).layoutWeight(1)
            .backgroundColor(this.theme.secondaryBackground).fontColor(this.theme.textPrimary).onClick(() => this.stopDetails())
        } else if (this.progressKind === 'detail' && this.retryableDetailTargets(this.allRows).length > 0) {
          Button('重试失败项').id('detailRetryButton').height(40).fontSize(14).layoutWeight(1)
            .backgroundColor(this.theme.secondaryBackground).fontColor(this.theme.infoText)
            .enabled(this.networkOnline).onClick(() => this.fetchDetails(true))
        }
        Button(this.progressKind === 'base' || this.detailsRunning ? '收起' : '完成')
          .id('progressDialogClose').height(40).fontSize(14).layoutWeight(1)
          .backgroundColor(this.theme.accent).fontColor(this.theme.onAccent).onClick(() => { this.showProgressDialog = false; })
      }.width('100%')
    }.padding({ left: 24, right: 24, top: 28, bottom: 24 }).width('100%')
  }

  @Builder
  configurationChips() {
    Row({ space: 4 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.configs, (config: ChargerConfig) => {
            Button(config.name).height(40).fontSize(12).padding({ left: 14, right: 14 })
              .fontColor(this.currentConfig?.id === config.id ? this.theme.onAccent : this.theme.textPrimary)
              .backgroundColor(this.currentConfig?.id === config.id ? this.theme.accent : this.theme.secondaryBackground)
              .onClick(async () => {
                if (this.currentConfig?.id === config.id) return;
                try { await ConfigService.switchConfig(config.id); await this.loadConfigs(); }
                catch (error) { ErrorHandler.handle(error, 'ChargerMonitorUI.switchConfig'); ErrorHandler.showToast(this.getUIContext(), '切换配置失败'); }
              })
          }, (config: ChargerConfig) => `${config.id}/${config.name}/${this.currentConfig?.id === config.id}`)
        }
      }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Button('管理').height(40).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.infoText)
        .accessibilityText('管理当前站点配置').onClick(() => this.onManageConfig(this.currentConfig?.id || ''))
    }.width('100%')
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.isRefreshing }) {
        List({ space: 8 }) {
          ListItem() {
            Column({ space: 8 }) {
              this.overview()
              this.configurationChips()
              Row({ space: 6 }) {
                TextInput({ placeholder: '搜索站点', text: this.searchInputText }).id('monitorSearchInput')
                  .layoutWeight(1).height(40).fontSize(13).borderRadius(10).fontColor(this.theme.textPrimary).backgroundColor(this.theme.secondaryBackground)
                  .placeholderColor(this.theme.textSecondary).onChange((value: string) => this.onSearchInput(value))
                  .accessibilityText('搜索别名、原站名、备注或站点ID')
                  .onSubmit(() => { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchText = this.searchInputText; })
                Button() { SymbolGlyph($r('sys.symbol.sort')).fontSize(18).fontColor([this.theme.textSecondary]) }
                  .id('monitorSortButton').width(40).height(40).type(ButtonType.Normal).borderRadius(10).backgroundColor(this.theme.secondaryBackground)
                  .accessibilityText(`排序：${this.sortLabel(this.sortMode)}`)
                  .bindMenu(this.showSortMenu, this.sortMenu(), { placement: Placement.BottomRight, onDisappear: () => { this.showSortMenu = false; } })
                  .onClick(() => { this.showSortMenu = !this.showSortMenu; })
              }.width('100%')
              if (this.stats.active > 0) {
                Row({ space: 8 }) {
                  Text('功率 · 费用 · 时长').fontSize(12).fontColor(this.theme.textSecondary).layoutWeight(1)
                  Button(this.detailsRunning ? '查看获取进度' : '获取占用信息').id('detailFetchButton').height(40).fontSize(12).padding({ left: 14, right: 14 })
                    .backgroundColor(this.theme.accent).fontColor(this.theme.onAccent)
                    .enabled(this.detailsRunning || this.stats.occupied > 0 && this.networkOnline)
                    .accessibilityText(`获取当前配置 ${this.stats.occupied} 个已确认占用插座的功率、费用和时长`)
                    .onClick(() => {
                      if (this.detailsRunning) { this.progressKind = 'detail'; this.showProgressDialog = true; }
                      else this.fetchDetails();
                    })
                }.width('100%')
              }
              if (this.members.length === 0) {
                Column({ space: 8 }) {
                  Text(this.currentConfig ? '本配置还没有站点' : '暂无配置').fontColor(this.theme.textPrimary)
                  Button(this.currentConfig ? '添加站点' : '增加配置').height(40).fontSize(14).onClick(() => {
                    if (this.currentConfig) this.onAddStations(this.currentConfig);
                    else this.onManageConfig('');
                  })
                }.width('100%').padding(20)
              } else if (this.stats.active === 0) {
                Column({ space: 8 }) {
                  Text('本配置的站点已全部暂停').fontColor(this.theme.textPrimary)
                  Button('管理站点').height(40).fontSize(14).onClick(() => this.onManageConfig(this.currentConfig?.id || ''))
                }.width('100%').padding(16)
              }
              if (this.members.length > 0 && this.filteredRows.length === 0) {
                Column({ space: 8 }) {
                  Text('没有匹配的站点').fontColor(this.theme.textSecondary)
                  Button('清除搜索').height(40).fontSize(14).onClick(() => { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchInputText = ''; this.searchText = ''; })
                }.width('100%').padding(16)
              }
            }.width('100%')
          }
          Repeat<MonitorStationRow>(this.filteredRows).each((row: RepeatItem<MonitorStationRow>) => {
            ListItem() {
              MonitorStationCardUI({ row: row.item, theme: this.theme, now: this.now, isFetching: this.isFetching,
                networkOnline: this.networkOnline, refreshCooldown: this.refreshCooldown,
                onRetry: (id: number) => { this.manualRefresh('station', [id]); },
                onInfo: (id: number) => { this.openStationInfo(id); },
                onManage: () => { this.onManageConfig(this.currentConfig?.id || ''); } })
            }
          }).key((row: MonitorStationRow) => row.renderKey).virtualScroll()
          ListItem() { Column().height(100).width('100%') }
        }.width('100%').height('100%').padding({ left: 16, right: 16, top: 8 })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
      }.width('100%').layoutWeight(1).pullToRefresh(true).onRefreshing(() => this.manualRefresh('pull'))
        .bindContentCover($$this.showProgressDialog, this.progressOverlay(), { modalTransition: ModalTransition.NONE, backgroundColor: Color.Transparent })
    }.width('100%').height('100%').backgroundColor(this.theme.background)
      .bindSheet($$this.showStationInfo, this.stationInfo(), { height: SheetSize.MEDIUM, showClose: true, dragBar: true, backgroundColor: this.theme.cardBackground })
  }
}

// 虚拟列表复用时通过 @Param 接收最新整行，信息面板只读取此刻的展示快照。
@ComponentV2
struct MonitorStationCardUI {
  @Param row: MonitorStationRow = { id: 0, name: '', originalName: '', note: '', order: 0,
    paused: false, pending: false, failed: false, missing: false, confirmed: false, fromDisk: false, outlets: [], renderKey: '' };
  @Param theme: ThemeColors = ThemeManager.getDarkColors();
  @Param now: number = Date.now();
  @Param isFetching: boolean = false;
  @Param networkOnline: boolean = true;
  @Param refreshCooldown: number = 0;
  @Event onRetry: (id: number) => void = () => {};
  @Event onManage: () => void = () => {};
  @Event onInfo: (id: number) => void = () => {};
  @Local showMenu: boolean = false;
  private menuStationId: number = 0;

  @Monitor('row')
  onRowChange() { if (this.showMenu && this.menuStationId !== this.row.id) this.showMenu = false; }
  aboutToDisappear() { this.showMenu = false; }

  private showMore(): void { this.menuStationId = this.row.id; this.showMenu = true; }

  private selectMore(action: string): void {
    this.showMenu = false;
    if (this.menuStationId !== this.row.id) return;
    if (action === 'info') this.onInfo(this.row.id);
    else if (action === 'refresh' && this.canRetry(this.row, this.now)) this.onRetry(this.row.id);
    else if (action === 'manage') this.onManage();
  }

  private canRetry(row: MonitorStationRow, at: number): boolean {
    return !row.paused && !this.isFetching && this.networkOnline && this.refreshCooldown === 0 && (!row.manualRetryAt || row.manualRetryAt <= at);
  }

  private badgeSurface(tone: string): string { return tone === 'neutral' ? this.theme.secondaryBackground : tone === 'info' ? this.theme.accent : tone === 'success' ? this.theme.success : this.theme.warning; }
  private badgeText(tone: string): string { return tone === 'neutral' ? this.theme.textSecondary : '#ffffff'; }

  @Builder
  moreMenu() {
    Column() {
      Button('站点信息').height(44).width('100%').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.theme.textPrimary)
        .onClick(() => this.selectMore('info'))
      Button('刷新本站状态').id(`stationMenuRefresh-${this.row.id}`).height(44).width('100%').fontSize(14)
        .backgroundColor(Color.Transparent).fontColor(this.theme.infoText).enabled(this.canRetry(this.row, this.now))
        .onClick(() => this.selectMore('refresh'))
      Button('管理配置').height(44).width('100%').fontSize(14).backgroundColor(Color.Transparent).fontColor(this.theme.textPrimary)
        .onClick(() => this.selectMore('manage'))
    }.width(210).padding(4)
  }

  @Builder
  outletRow(outlet: MonitorOutletRow) {
    Row({ space: 8 }) {
      Circle({ width: 8, height: 8 }).foregroundColor(outlet.status === OutletStatus.FREE ? this.theme.success : outlet.status === OutletStatus.OCCUPIED ? this.theme.error : this.theme.warning)
        .opacity(this.row.confirmed ? 1 : 0.45)
      Text(`插座${outlet.serial}`).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End, alignItems: ItemAlign.Center }) {
        if (MonitorPresentation.badges(outlet).length > 0) {
          ForEach(MonitorPresentation.badges(outlet), (badge: MonitorBadge) => {
            Text(badge.text).fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.badgeText(badge.tone)).backgroundColor(this.badgeSurface(badge.tone))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(6).margin({ left: 4, top: 1, bottom: 1 })
          }, (badge: MonitorBadge) => badge.tone + badge.text)
        } else {
          Text(MonitorPresentation.outletStatus(outlet, this.row.confirmed)).fontSize(12)
            .fontColor(outlet.status === OutletStatus.FREE && this.row.confirmed ? '#ffffff' : outlet.detailState === 'failed' ? this.theme.warningText : this.theme.textSecondary)
            .backgroundColor(outlet.status === OutletStatus.FREE && this.row.confirmed ? this.theme.success : Color.Transparent)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 }).borderRadius(6)
        }
      }.layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: 30 }).padding({ left: 12, right: 12, top: 3, bottom: 3 })
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Text(this.row.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => this.onInfo(this.row.id)).accessibilityText(`站点信息，${this.row.name}`)
        Row({ space: 4 }) {
          Circle({ width: 6, height: 6 }).foregroundColor(!this.row.confirmed ? this.theme.textTertiary : (this.row.freeCount ?? 0) > 0 ? this.theme.success : this.theme.error)
          Text(this.row.confirmed ? `${this.row.freeCount}/${this.row.outlets.length}` : '—/—').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(!this.row.confirmed ? this.theme.textSecondary : (this.row.freeCount ?? 0) > 0 ? this.theme.successText : this.theme.errorText)
        }.padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(8)
          .backgroundColor(!this.row.confirmed ? this.theme.secondaryBackground : (this.row.freeCount ?? 0) > 0 ? this.theme.successSurface : this.theme.errorSurface)
          .accessibilityText(this.row.confirmed ? `空闲 ${this.row.freeCount} 个，共 ${this.row.outlets.length} 个插座` : '当前插座数未确认')
        if (this.row.failed || this.row.missing) {
          Button(this.row.manualRetryAt && this.row.manualRetryAt > this.now ? `${Math.ceil((this.row.manualRetryAt - this.now) / 1000)}s` : '重试')
            .id(`stationRetry-${this.row.id}`).height(40).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.infoText)
            .enabled(this.canRetry(this.row, this.now)).onClick(() => this.onRetry(this.row.id))
        }
        Button() { Text('⋯').fontSize(24).fontColor(this.theme.textSecondary) }
          .id(`stationMore-${this.row.id}`).type(ButtonType.Normal).width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText(`${this.row.name}，更多操作`).onClick(() => this.showMore())
          .bindMenu(this.showMenu, this.moreMenu(), { placement: Placement.BottomRight, onDisappear: () => { this.showMenu = false; } })
      }.width('100%').padding({ left: 12, right: 4, top: 6 })
      Text(MonitorPresentation.rowCaption(this.row)).fontSize(12).fontColor(this.theme.textSecondary).width('100%').padding({ left: 12, right: 12, bottom: 6 })
      if (MonitorPresentation.detailCaption(this.row)) Text(MonitorPresentation.detailCaption(this.row)).fontSize(11).fontColor(this.theme.textSecondary).width('100%').padding({ left: 12, right: 12, bottom: 6 })
      if (this.row.note) Text(this.row.note).fontSize(12).fontColor(this.theme.textSecondary).width('100%').padding({ left: 12, right: 12, bottom: 6 }).maxLines(2)
      if (MonitorPresentation.rowStatus(this.row)) {
        Text(MonitorPresentation.rowStatus(this.row)).fontSize(12).fontColor(this.row.failed || this.row.missing ? this.theme.warningText : this.theme.textSecondary)
          .width('100%').padding({ left: 12, right: 12, bottom: 6 })
      }
      if (this.row.outlets.length > 0) {
        Divider().color(this.theme.border).margin({ left: 12, right: 12, bottom: 3 })
        ForEach(this.row.outlets, (outlet: MonitorOutletRow) => { this.outletRow(outlet) }, (outlet: MonitorOutletRow) => outlet.renderKey)
      }
    }.id(`stationCard-${this.row.id}`).width('100%').padding({ bottom: 6 }).backgroundColor(this.theme.cardBackground).borderRadius(16)
  }
}
