// 基础状态与用户主动查询的占用详情分层，滚动、筛选和排序均不发网络请求。
import { ChargerConfig, ConfigStationMember, OutletStatus, SORT_MODE } from '../ChargerModels';
import { StationLoadProgress, StationService, StationSnapshot, OutletLoadProgress } from '../services/StationService';
import { MonitorDetail, MonitorModel, MonitorOutletRow, MonitorStationRow, MonitorStats, MonitorTarget } from '../utils/MonitorModel';
import { RefreshGate } from '../utils/RefreshGate';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { ApiConfig } from '../ApiConfig';

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
  @Local detailFailedTargets: MonitorTarget[] = [];

  @Local members: ConfigStationMember[] = [];
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
    this.stopLoads();
    this.failedIds = [];
    this.missingIds = [];
    this.retries.clear();
    this.manualRetries.clear();
    this.details.clear();
    this.detailFailedTargets = [];
    this.detailTotal = 0;
    this.detailMessage = '';
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
    for (const key of Array.from(this.details.keys())) {
      const detail = this.details.get(key)!;
      const snapshot = snapshots.get(detail.stationId);
      const member = this.members.find(item => item.stationId === detail.stationId);
      if (!snapshot?.confirmed || snapshot.generation !== detail.generation || member?.paused ||
        !snapshot.station.outlets.some(outlet => outlet.outletNo === detail.outletNo && outlet.status === OutletStatus.OCCUPIED)) this.details.delete(key);
    }
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
        if (detail.state === 'pending') this.details.set(MonitorModel.key(detail.stationId, detail.outletNo, detail.generation), { stationId: detail.stationId, outletNo: detail.outletNo, generation: detail.generation, state: 'stopped' });
      }
      this.detailMessage = showMessage ? '详情查询已停止；已获取且仍有效的详情仍保留' : '离开监控或网络中断，详情查询已停止';
      this.rebuildRows();
    }
  }

  private retryableDetailTargets(rows: MonitorStationRow[] = this.allRows): MonitorTarget[] {
    return this.detailFailedTargets.filter(target => MonitorModel.validTarget(target, rows));
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
    this.detailStartedAt = Date.now();
    this.detailsRunning = true;
    targets.forEach((target: MonitorTarget) => this.details.set(MonitorModel.key(target.stationId, target.outletNo, target.generation),
      { stationId: target.stationId, outletNo: target.outletNo, generation: target.generation, state: 'pending' }));
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
        this.details.set(key, detail);
        if (!step.detail) this.detailFailedTargets = [...this.detailFailedTargets, target];
        this.rebuildRows();
      }, () => version === this.detailVersion && this.hasAppeared && this.isActive && this.networkOnline,
      targets.map(target => target.outletNo));
      if (version === this.detailVersion) this.detailMessage = '本轮详情查询已结束；站点状态更新后请重新查询详情';
    } catch (error) {
      if (version === this.detailVersion) {
        this.detailMessage = '详情查询中断，可重试失败项';
        targets.forEach((target: MonitorTarget) => {
          const key = MonitorModel.key(target.stationId, target.outletNo, target.generation);
          if (this.details.get(key)?.state === 'pending' && MonitorModel.validTarget(target, this.allRows)) {
            this.details.set(key, { stationId: target.stationId, outletNo: target.outletNo, generation: target.generation, state: 'failed' });
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
        this.rebuildRows();
      }
    }
  }

  private timestamp(time: number | undefined): string {
    if (time === undefined) return '尚无成功记录';
    const date = new Date(time);
    return `${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  private elapsed(start: number, at: number = this.now): number { return Math.max(0, Math.floor((at - start) / 1000)); }

  private rowStatus(row: MonitorStationRow): string {
    if (row.paused) return '已暂停监控';
    if (row.missing && !row.pending) return '站点不存在，请检查配置或手动重新核实';
    const state = row.confirmed ? '已确认' : row.fetchedAt !== undefined ? (row.fromDisk ? '上次保存的历史记录' : '历史数据 · 不计入当前统计') : '状态未知';
    return `${row.pending ? '查询中 · ' : row.failed ? '查询失败 · ' : ''}${state}`;
  }

  private detailStatus(outlet: MonitorOutletRow): string {
    if (outlet.detailState === 'pending') return '详情查询中';
    if (outlet.detailState === 'failed') return '详情查询失败';
    if (outlet.detailState === 'stopped') return '详情查询已停止';
    if (outlet.detailState === 'history') return '历史占用状态，详情未知';
    if (outlet.detailState === 'success') return `详情获取于 ${this.timestamp(outlet.detailFetchedAt)}`;
    return '详情未查询';
  }

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
  overview() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('基础状态').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary).layoutWeight(1)
        Button(this.refreshCooldown > 0 ? `${Math.ceil(this.refreshCooldown / 1000)}s` : this.isFetching ? '查询中' : '刷新')
          .id('monitorRefreshButton').height(36).fontSize(13).backgroundColor(this.theme.accent).fontColor(Color.White)
          .enabled(this.stats.active > 0 && this.networkOnline && (!this.isFetching || !this.baseManual) && !this.manualWaiting && this.refreshCooldown === 0)
          .onClick(() => this.manualRefresh())
      }.width('100%')
      Text(`已确认 ${this.stats.covered}/${this.stats.active} 站 · 当前统计${this.baseCacheHits ? ` · 本轮 ${this.baseCacheHits} 站使用缓存` : ''}`).id('monitorLoadSummary')
        .fontSize(13).fontColor(this.theme.textSecondary).width('100%')
      Row() {
        Column({ space: 3 }) {
          Text(this.stats.covered > 0 ? this.stats.free.toString() : '—').id('monitorFreeCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.success)
          Text('空闲').fontSize(11).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Column({ space: 3 }) {
          Text(this.stats.covered > 0 ? this.stats.occupied.toString() : '—').id('monitorOccupiedCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.error)
          Text('占用').fontSize(11).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Column({ space: 3 }) {
          Text(this.stats.covered > 0 ? this.stats.broken.toString() : '—').id('monitorBrokenCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.textSecondary)
          Text('故障').fontSize(11).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
        Column({ space: 3 }) {
          Text(this.stats.covered > 0 ? this.stats.total.toString() : '—').id('monitorTotalCount').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text('插座总数').fontSize(11).fontColor(this.theme.textSecondary)
        }.layoutWeight(1)
      }.width('100%')
      if (!this.networkOnline) {
        Text('网络不可用，已停止查询；恢复连接后补查到期或失败站点').fontSize(13).fontColor(this.theme.error).width('100%')
      }
      if (this.isFetching) {
        Text(`基础状态已处理 ${this.baseCompleted}/${this.baseTotal} 站`).id('monitorLoadProgress').fontSize(13).fontColor(this.theme.textPrimary).width('100%')
        Progress({ value: this.baseCompleted, total: Math.max(1, this.baseTotal), type: ProgressType.Linear })
          .id('monitorLoadProgressBar').width('100%').color(this.theme.accent)
        if (this.elapsed(this.baseStartedAt, this.now) >= 3) {
          Text(this.elapsed(this.baseStartedAt, this.now) >= 10 ? `已等待 ${this.elapsed(this.baseStartedAt, this.now)} 秒；当前请求仍在等待网络响应` : '网络响应较慢，已获取站点会先显示')
            .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
        }
      }
      if (this.failedIds.length) {
        Row({ space: 8 }) {
          Text(`${this.failedIds.length} 站查询失败，历史数据保留至 10 分钟`).fontSize(12).fontColor(this.theme.error).layoutWeight(1)
          Button('重试失败站').id('monitorRetryFailedButton').height(36).fontSize(12)
            .enabled(this.networkOnline && !this.isFetching && this.refreshCooldown === 0 && this.manualFailedIds(this.now).length > 0)
            .onClick(() => this.retryFailedStations())
        }.width('100%')
      }
      if (this.errorMessage) Text(this.errorMessage).fontSize(13).fontColor(this.theme.error).width('100%')
      if (this.configReadError) {
        Row({ space: 8 }) {
          Text('配置读取失败，已有配置仍保留').fontSize(13).fontColor(this.theme.error).layoutWeight(1)
          Button('重试读取').height(36).onClick(() => this.loadConfigs())
        }.width('100%')
      }
    }.width('100%').padding(12).backgroundColor(this.theme.cardBackground).borderRadius(20)
  }

  @Builder
  detailOverview() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('占用详情').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary).layoutWeight(1)
        Button(`查询占用详情（${this.stats.occupied}）`).id('detailFetchButton').height(36).fontSize(12)
          .backgroundColor(this.theme.secondaryBackground).fontColor(this.theme.accent)
          .enabled(this.stats.occupied > 0 && !this.detailsRunning && this.networkOnline)
          .onClick(() => this.fetchDetails())
      }.width('100%')
      if (this.detailsRunning) Text('查询当前配置的已确认占用插座，基础状态仍会自动刷新').fontSize(12).fontColor(this.theme.textSecondary).width('100%')
      if (this.detailTotal > 0) {
        Text(`详情已处理 ${this.detailCompleted}/${this.detailTotal} · 成功 ${this.detailSucceeded} · 失败 ${this.detailFailed} · 已失效 ${this.detailSkipped}`)
          .id('detailLoadProgress').fontSize(13).fontColor(this.theme.textPrimary).width('100%')
        Progress({ value: this.detailCompleted, total: Math.max(1, this.detailTotal), type: ProgressType.Linear })
          .id('detailLoadProgressBar').width('100%').color(this.theme.accent)
      }
      if (this.detailsRunning) {
        Row({ space: 8 }) {
          Text(this.elapsed(this.detailStartedAt, this.now) >= 10 ? `已等待 ${this.elapsed(this.detailStartedAt, this.now)} 秒，可停止本轮查询` :
            this.elapsed(this.detailStartedAt, this.now) >= 3 ? '详情响应较慢，可继续等待或停止' : '正在查询本轮占用详情')
            .fontSize(12).fontColor(this.theme.textSecondary).layoutWeight(1)
          Button('停止查询').id('detailStopButton').height(36).fontSize(12).onClick(() => this.stopDetails())
        }.width('100%')
      }
      if (this.retryableDetailTargets(this.allRows).length > 0 && !this.detailsRunning) {
        Button(`重试失败详情（${this.retryableDetailTargets(this.allRows).length}）`).id('detailRetryButton').height(36).fontSize(12)
          .enabled(this.networkOnline).onClick(() => this.fetchDetails(true))
      }
      if (this.detailMessage) Text(this.detailMessage).fontSize(12).fontColor(this.theme.textSecondary).width('100%')
    }.width('100%').padding(12).backgroundColor(this.theme.cardBackground).borderRadius(20)
  }

  @Builder
  configurationChips() {
    Row({ space: 4 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.configs, (config: ChargerConfig) => {
            Button(config.name).height(34).fontSize(12)
              .fontColor(this.currentConfig?.id === config.id ? Color.White : this.theme.textPrimary)
              .backgroundColor(this.currentConfig?.id === config.id ? this.theme.accent : this.theme.secondaryBackground)
              .onClick(async () => {
                if (this.currentConfig?.id === config.id) return;
                try { await ConfigService.switchConfig(config.id); await this.loadConfigs(); }
                catch (error) { ErrorHandler.handle(error, 'ChargerMonitorUI.switchConfig'); ErrorHandler.showToast(this.getUIContext(), '切换配置失败'); }
              })
          }, (config: ChargerConfig) => `${config.id}/${config.name}/${this.currentConfig?.id === config.id}`)
        }
      }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Button('管理').height(34).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
        .accessibilityText('管理当前站点配置').onClick(() => this.onManageConfig(this.currentConfig?.id || ''))
    }.width('100%')
  }


  build() {
    Column() {
      Refresh({ refreshing: $$this.isRefreshing }) {
        List({ space: 10 }) {
          ListItem() {
            Column({ space: 10 }) {
              this.overview()
              this.configurationChips()
              if (this.stats.active > 0) this.detailOverview()
              Row({ space: 8 }) {
                TextInput({ placeholder: '搜索别名、原站名、备注或 ID', text: this.searchInputText })
                  .layoutWeight(1).height(40).fontColor(this.theme.textPrimary).backgroundColor(this.theme.secondaryBackground)
                  .placeholderColor(this.theme.textSecondary).onChange((value: string) => this.onSearchInput(value))
                  .onSubmit(() => { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchText = this.searchInputText; })
                Button(this.sortLabel(this.sortMode)).height(40).fontSize(12).fontColor(this.theme.textPrimary).backgroundColor(this.theme.secondaryBackground)
                  .bindMenu(this.showSortMenu, this.sortMenu(), { placement: Placement.BottomRight, onDisappear: () => { this.showSortMenu = false; } })
                  .onClick(() => { this.showSortMenu = !this.showSortMenu; })
              }.width('100%')
              if (this.members.length === 0) {
                Column({ space: 12 }) {
                  Text(this.currentConfig ? '本配置还没有站点' : '暂无配置').fontColor(this.theme.textPrimary)
                  Button(this.currentConfig ? '添加站点' : '增加配置').onClick(() => {
                    if (this.currentConfig) this.onAddStations(this.currentConfig);
                    else this.onManageConfig('');
                  })
                }.width('100%').padding(24)
              } else if (this.stats.active === 0) {
                Column({ space: 10 }) {
                  Text('本配置的站点已全部暂停').fontColor(this.theme.textPrimary)
                  Text('暂停期间不查询基础状态或占用详情').fontSize(13).fontColor(this.theme.textSecondary)
                  Button('管理站点').onClick(() => this.onManageConfig(this.currentConfig?.id || ''))
                }.width('100%').padding(16)
              }
              if (this.members.length > 0 && this.filteredRows.length === 0) {
                Column({ space: 10 }) {
                  Text('没有匹配的站点').fontColor(this.theme.textSecondary)
                  Button('清除搜索').onClick(() => { if (this.searchTimer !== -1) clearTimeout(this.searchTimer); this.searchInputText = ''; this.searchText = ''; })
                }.width('100%').padding(16)
              }
            }.width('100%')
          }
          Repeat<MonitorStationRow>(this.filteredRows).each((row: RepeatItem<MonitorStationRow>) => {
            ListItem() {
              MonitorStationCardUI({ row: row.item, theme: this.theme, now: this.now, isFetching: this.isFetching,
                networkOnline: this.networkOnline, refreshCooldown: this.refreshCooldown,
                onRetry: (id: number) => { this.manualRefresh('station', [id]); },
                onManage: () => { this.onManageConfig(this.currentConfig?.id || ''); } })
            }
          }).key((row: MonitorStationRow) => row.renderKey).virtualScroll()
          ListItem() { Column().height(100).width('100%') }
        }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12 })
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
      }.width('100%').layoutWeight(1).pullToRefresh(true).onRefreshing(() => this.manualRefresh('pull'))
    }.width('100%').height('100%').backgroundColor(this.theme.background)
  }
}

// 虚拟列表复用时通过 @Param 接收最新整行，避免 Builder 按值参数捕获初次快照。
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

  private timestamp(time: number | undefined): string {
    if (time === undefined) return '尚无成功记录';
    const date = new Date(time);
    return `${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  private rowStatus(row: MonitorStationRow): string {
    if (row.paused) return '已暂停监控';
    if (row.missing && !row.pending) return '站点不存在，请检查配置或手动重新核实';
    const state = row.confirmed ? '已确认' : row.fetchedAt !== undefined ? (row.fromDisk ? '上次保存的历史记录' : '历史数据 · 不计入当前统计') : '状态未知';
    return `${row.pending ? '查询中 · ' : row.failed ? '查询失败 · ' : ''}${state}`;
  }

  private detailStatus(outlet: MonitorOutletRow): string {
    if (outlet.detailState === 'pending') return '详情查询中';
    if (outlet.detailState === 'failed') return '详情查询失败';
    if (outlet.detailState === 'stopped') return '详情查询已停止';
    if (outlet.detailState === 'history') return '历史占用状态，详情未知';
    if (outlet.detailState === 'success') return `详情获取于 ${this.timestamp(outlet.detailFetchedAt)}`;
    return '详情未查询';
  }

  @Builder
  outletRow(outlet: MonitorOutletRow) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Circle({ width: 8, height: 8 }).foregroundColor(outlet.status === OutletStatus.FREE ? this.theme.success : outlet.status === OutletStatus.OCCUPIED ? this.theme.error : this.theme.textTertiary)
        Text(`插座${outlet.serial}`).fontSize(14).fontColor(this.theme.textPrimary).layoutWeight(1)
        Text(outlet.status === OutletStatus.FREE ? '空闲' : outlet.status === OutletStatus.OCCUPIED ? '占用' : '故障')
          .fontSize(13).fontColor(outlet.status === OutletStatus.FREE ? this.theme.success : this.theme.textSecondary)
      }.width('100%')
      if (outlet.status === OutletStatus.OCCUPIED) {
        Text(`功率 ${outlet.power_w === undefined ? '—' : outlet.power_w + 'W'} · 费用 ${outlet.fee === undefined ? '—' : '¥' + outlet.fee.toFixed(2)} · 时长 ${outlet.used_min === undefined ? '—' : outlet.used_min + '分钟'}`)
          .fontSize(12).fontColor(this.theme.textSecondary).width('100%')
        Text(this.detailStatus(outlet)).fontSize(11).fontColor(outlet.detailState === 'failed' ? this.theme.error : this.theme.textTertiary).width('100%')
      }
    }.padding({ left: 16, right: 16, top: 8, bottom: 8 }).width('100%')
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.row.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
          Text(`ID ${this.row.id}${this.row.name !== this.row.originalName ? ' · ' + this.row.originalName : ''}`).fontSize(11).fontColor(this.theme.textTertiary)
          if (this.row.note) Text(this.row.note).fontSize(12).fontColor(this.theme.textSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (!this.row.paused) {
          Button(this.row.pending ? '查询中' : this.row.manualRetryAt && this.row.manualRetryAt > this.now ? `限流等待 ${Math.ceil((this.row.manualRetryAt - this.now) / 1000)}s` : this.row.missing ? '重新核实' : this.row.failed ? '重试' : '刷新')
            .id(`stationRetry-${this.row.id}`).height(36).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
            .enabled(!this.isFetching && this.networkOnline && this.refreshCooldown === 0 && (!this.row.manualRetryAt || this.row.manualRetryAt <= this.now))
            .onClick(() => this.onRetry(this.row.id))
        }
      }.width('100%').padding({ left: 16, right: 16, top: 16 })
      Text(this.rowStatus(this.row)).fontSize(12).fontColor(this.row.confirmed ? this.theme.success : this.row.failed ? this.theme.error : this.theme.textSecondary)
        .width('100%').padding({ left: 16, right: 16 })
      if (this.row.missing) {
        Button('管理此配置的站点').height(32).fontSize(12).backgroundColor(Color.Transparent).fontColor(this.theme.accent)
          .onClick(() => this.onManage())
      }
      if (!this.row.paused) {
        Text(this.row.fetchedAt === undefined ? '从未成功获取：空闲 — / 总数 —' :
          `${this.row.confirmed ? '状态获取于' : '历史记录于'} ${this.timestamp(this.row.fetchedAt)} · 空闲 ${this.row.freeCount ?? '—'} / 总数 ${this.row.outlets.length}`)
          .fontSize(11).fontColor(this.theme.textTertiary).width('100%').padding({ left: 16, right: 16 })
        if (this.row.outlets.length > 0) {
          Divider().color(this.theme.border).margin({ left: 16, right: 16 })
          ForEach(this.row.outlets, (outlet: MonitorOutletRow) => { this.outletRow(outlet) }, (outlet: MonitorOutletRow) => outlet.renderKey)
        }
      }
    }.id(`stationCard-${this.row.id}`).width('100%').padding({ bottom: 12 }).backgroundColor(this.theme.cardBackground).borderRadius(20)
  }
}
