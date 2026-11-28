// StationService.ets - 站点数据获取 + 缓存策略
import { ChargerApi, NearbyLoadPhase, NearbySource, StationHttpFailure } from '../api/ChargerApi';
import { ApiConfig } from '../ApiConfig';
import { OutletDetails, OutletLoadProgress, StationSnapshot } from './OutletDetails';
import { StationHistory } from './StationHistory';
import { StationData, StationBrief, StationQueryResult } from '../ChargerModels';
import { DataCache } from '../utils/DataCache';
import { ErrorHandler } from '../utils/ErrorHandler';
import { common } from '@kit.AbilityKit';

export { OutletLoadProgress, StationSnapshot } from './OutletDetails';

export interface StationLoadResult {
  stations: StationData[];
  failedNames: string[];
  // 当前成功加载站点中最早的实际获取时间，不是本次读取缓存的时间。
  oldestFetchedAt?: number;
}

export interface StationLoadProgress {
  completed: number;
  total: number;
  succeeded: number;
  failed: number;
  stationId: number;
  stationName: string;
  station: StationData | null;
  fetchedAt?: number;
  fromCache: boolean;
  generation?: number;
  retryAt?: number;
  manualRetryAt?: number;
  missing?: boolean;
}

interface StationReading {
  data: StationData;
  fetchedAt?: number;
  fromCache: boolean;
  generation?: number;
}

interface RetryState {
  failures: number;
  retryAt: number;
  missing: boolean;
}

type NearbyPhaseListener = (phase: NearbyLoadPhase) => void;
type NearbyScope = string | common.UIAbilityContext;

interface NearbyFlight {
  phase?: NearbyLoadPhase;
  listeners: Set<NearbyPhaseListener>;
  result: Promise<StationQueryResult>;
}

interface NearbyCacheOwner { scope: NearbyScope; status: string; }

export class StationService {
  private static readonly MAX_STATION_REQUESTS: number = 4;
  private static cacheEpoch: number = 0;
  private static inFlight: Map<string, Promise<StationReading | null>> = new Map();
  private static retries: Map<number, RetryState> = new Map();
  private static limitedUntil: number = 0;
  private static nearbyRequest: Map<NearbySource, number> = new Map();
  private static nearbyFlights: Map<NearbyScope, NearbyFlight> = new Map();
  private static nearbyCache: Map<NearbySource, NearbyCacheOwner> = new Map();

  static initSnapshots(context: common.Context): Promise<void> { return StationHistory.initialize(context); }

  static retainStationIds(ids: number[]): void {
    StationHistory.retain(ids);
    StationService.retries.forEach((_state, id) => {
      if (!StationHistory.referenced(id)) StationService.retries.delete(id);
    });
  }

  static getSnapshot(id: number, name: string, now: number = Date.now()): StationSnapshot | null {
    const entry = DataCache.getHistory(id, now);
    if (!entry) return null;
    return { station: { id, name, outlets: entry.data.outlets }, fetchedAt: entry.fetchedAt, generation: entry.generation,
      confirmed: !entry.fromDisk && !StationService.retries.has(id) && now - entry.fetchedAt < ApiConfig.STATION_CONFIRM_DURATION,
      fromDisk: entry.fromDisk };
  }

  static fetchOccupiedDetails(stations: StationSnapshot[], onProgress?: (step: OutletLoadProgress) => void,
    shouldContinue?: () => boolean, onlyOutletNos?: string[]): Promise<void> {
    return OutletDetails.fetch(stations, (id: number, generation: number): boolean => {
      const snapshot = StationService.getSnapshot(id, '');
      return !!snapshot && snapshot.generation === generation && snapshot.confirmed;
    }, onProgress, shouldContinue, onlyOutletNos);
  }

  private static async queryStation(id: number, name: string, epoch: number): Promise<StationReading | null> {
    let status = 0;
    let serverDeadline = 0;
    let missing = false;
    try {
      const data = await ChargerApi.fetchStation(id, name, 0, (failure: StationHttpFailure) => {
        status = failure.status;
        serverDeadline = failure.retryAt || 0;
        missing = failure.status === 410 || failure.missing === true;
      });
      if (data && data.outlets.length > 0) {
        const fetchedAt = Date.now();
        if (epoch === StationService.cacheEpoch && StationHistory.referenced(id)) {
          DataCache.setStation(id, data, fetchedAt);
          StationHistory.changed();
          StationService.retries.delete(id);
        }
        return { data, fetchedAt, fromCache: false, generation: DataCache.getHistory(id)?.generation };
      }
    } catch (error) {
      ErrorHandler.handle(error, `StationService.fetchStationsForConfig[${name}]`);
    }
    if (epoch === StationService.cacheEpoch && StationHistory.referenced(id)) {
      const failures = Math.min(3, (StationService.retries.get(id)?.failures || 0) + 1);
      const retryAt = Date.now() + ApiConfig.AUTO_REFRESH_INTERVAL * Math.pow(2, failures - 1);
      if (status === 429 || (status === 503 && serverDeadline)) {
        StationService.limitedUntil = Math.max(StationService.limitedUntil, serverDeadline || retryAt);
      }
      StationService.retries.set(id, { failures, retryAt, missing });
    }
    return null;
  }

  private static async loadStation(id: number, name: string, epoch: number, initial: StationData | null,
    canContinue: () => boolean, manual: boolean): Promise<StationReading | null> {
    const key = `${epoch}/${id}`;
    while (canContinue()) {
      const shared = StationService.inFlight.get(key);
      if (shared) return shared;
      // 排队期间另一个配置可能已完成同一站点的复查。
      const cached = DataCache.getStation(id);
      const retry = StationService.retries.get(id);
      if (cached && cached !== initial && !retry) {
        const entry = DataCache.getHistory(id);
        return { data: cached, fetchedAt: entry?.fetchedAt, generation: entry?.generation, fromCache: true };
      }
      const now = Date.now();
      if (now < StationService.limitedUntil || (!manual && retry && (retry.missing || now < retry.retryAt))) return null;
      if (StationService.inFlight.size < StationService.MAX_STATION_REQUESTS) {
        const request = StationService.queryStation(id, name, epoch).finally(() => {
          StationService.inFlight.delete(key);
        });
        StationService.inFlight.set(key, request);
        return request;
      }
      await Promise.race(Array.from(StationService.inFlight.values()));
    }
    return null;
  }

  static async fetchStationsForConfig(stationConfig: Record<string, number>,
    onProgress?: (progress: StationLoadProgress) => void, forceNetwork: boolean = false,
    shouldContinue?: () => boolean): Promise<StationLoadResult> {
    const epoch = StationService.cacheEpoch;
    const canContinue = (): boolean => epoch === StationService.cacheEpoch && (!shouldContinue || shouldContinue());
    const names = Object.keys(stationConfig);
    const byIndex = new Map<number, StationData>();
    const initialCache: (StationData | null)[] = [];
    const pending: number[] = [];
    let completed = 0;
    let oldestFetchedAt: number | undefined = undefined;

    let updated = false;
    const finish = (index: number, station: StationData | null, fetchedAt: number | undefined, fromCache: boolean,
      generation?: number): void => {
      const name = names[index];
      const id = stationConfig[name];
      if (station && !fromCache) updated = true;
      completed++;
      if (station) byIndex.set(index, station);
      if (fetchedAt !== undefined && (oldestFetchedAt === undefined || fetchedAt < oldestFetchedAt)) oldestFetchedAt = fetchedAt;
      if (!onProgress || !canContinue()) return;
      try {
        const retry = StationService.retries.get(id);
        const retryAt = Math.max(retry?.retryAt || 0, StationService.limitedUntil);
        onProgress({
          completed, total: names.length, succeeded: byIndex.size, failed: completed - byIndex.size,
          stationId: id, stationName: name, station, fetchedAt, fromCache, generation,
          retryAt: !station && retryAt > Date.now() ? retryAt : undefined,
          manualRetryAt: !station && StationService.limitedUntil > Date.now() ? StationService.limitedUntil : undefined,
          missing: retry?.missing
        });
      } catch (error) {
        ErrorHandler.handle(error, 'StationService.onProgress');
      }
    };

    // 缓存命中先展示，即使它排在几个慢站的后面。
    for (let index = 0; index < names.length && canContinue(); index++) {
      const name = names[index];
      const id = stationConfig[name];
      const cached = DataCache.getStation(id);
      initialCache.push(cached);
      if (cached && !forceNetwork && !StationService.retries.has(id)) {
        const entry = DataCache.getHistory(id);
        finish(index, { id, name, outlets: cached.outlets }, entry?.fetchedAt, true, entry?.generation);
      } else {
        pending.push(index);
      }
    }

    // 一个站点完成就补下一个，最多四个站同时走网络。
    let next = 0;
    const worker = async (): Promise<void> => {
      while (next < pending.length && canContinue()) {
        const index = pending[next++];
        const name = names[index];
        const id = stationConfig[name];
        let station: StationData | null = null;
        const reading = await StationService.loadStation(id, name, epoch, initialCache[index], canContinue, forceNetwork);
        if (reading) station = { id, name, outlets: reading.data.outlets };
        finish(index, station, reading?.fetchedAt, reading?.fromCache ?? false, reading?.generation);
      }
    };
    const workers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(StationService.MAX_STATION_REQUESTS, pending.length); i++) workers.push(worker());
    await Promise.all(workers);
    if (updated && epoch === StationService.cacheEpoch) await StationHistory.save();

    const stations: StationData[] = [];
    const failedNames: string[] = [];
    names.forEach((name, index) => {
      const station = byIndex.get(index);
      if (station) stations.push(station);
      else failedNames.push(name);
    });
    return { stations, failedNames, oldestFetchedAt };
  }

  private static nearbyScope(context?: common.UIAbilityContext): NearbyScope {
    if (!context) return 'no-context';
    const info = context.applicationInfo;
    if (info && info.name && info.accessTokenId > 0) return `app:${info.accessTokenId}:${info.name}`;
    return context;
  }

  private static notifyNearby(listener: NearbyPhaseListener, phase: NearbyLoadPhase): void {
    try { listener(phase); } catch (error) { ErrorHandler.handle(error, 'StationService.nearbyProgress'); }
  }

  static async fetchNearbyStations(context?: common.UIAbilityContext,
    onPhase?: NearbyPhaseListener, forceRefresh: boolean = false, source: NearbySource = 'device'): Promise<StationQueryResult> {
    const scope = source === 'campus' ? 'campus' : StationService.nearbyScope(context);
    const shared = StationService.nearbyFlights.get(scope);
    if (!forceRefresh && shared) {
      if (onPhase && !shared.listeners.has(onPhase)) {
        shared.listeners.add(onPhase);
        if (shared.phase !== undefined) StationService.notifyNearby(onPhase, shared.phase);
      }
      return shared.result;
    }
    const owner = StationService.nearbyCache.get(source);
    const cached = !forceRefresh && scope === owner?.scope ? DataCache.getNearbyStations(source) : null;
    if (cached && owner) {
      return {
        stations: cached,
        locationStatus: owner.status ? `${owner.status}（缓存）` : '使用缓存数据'
      };
    }

    const request = (StationService.nearbyRequest.get(source) || 0) + 1;
    StationService.nearbyRequest.set(source, request);
    const listeners = new Set<NearbyPhaseListener>();
    if (onPhase) listeners.add(onPhase);
    // 先注册共享任务，再进入会立即发出 LOCATING 的接口，后来的页面可订阅当前阶段。
    const flight: NearbyFlight = {
      listeners,
      result: Promise.resolve().then(async (): Promise<StationQueryResult> => {
        try {
          const result = await ChargerApi.fetchNearbyStations(context, (phase: NearbyLoadPhase) => {
            if (StationService.nearbyFlights.get(scope) !== flight) return;
            flight.phase = phase;
            for (const listener of Array.from(listeners)) StationService.notifyNearby(listener, phase);
          }, source);
          if (StationService.nearbyFlights.get(scope) === flight &&
            request === StationService.nearbyRequest.get(source) && result.stations.length > 0) {
            DataCache.setNearbyStations(result.stations, source);
            StationService.nearbyCache.set(source, { scope, status: result.locationStatus });
          }
          return result;
        } catch (error) {
          ErrorHandler.handle(error, 'StationService.fetchNearbyStations');
          return { stations: [], locationStatus: "加载失败: " + ErrorHandler.getErrorMessage(error) };
        } finally {
          listeners.clear();
          if (StationService.nearbyFlights.get(scope) === flight) StationService.nearbyFlights.delete(scope);
        }
      })
    };
    StationService.nearbyFlights.set(scope, flight);
    return flight.result;
  }

  // 清除所有缓存
  static clearCache(): void {
    // 旧请求完成后不能把清除前的快照重新写入缓存。
    StationService.cacheEpoch++;
    StationService.nearbyFlights.clear();
    StationService.nearbyCache.clear();
    StationService.retries.clear();
    StationService.limitedUntil = 0;
    DataCache.clearAll();
    StationHistory.save();
  }
}
