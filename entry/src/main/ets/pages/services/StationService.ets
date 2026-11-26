// StationService.ets - 站点数据获取 + 缓存策略
import { ChargerApi } from '../api/ChargerApi';
import { StationData, StationBrief, StationQueryResult } from '../ChargerModels';
import { DataCache } from '../utils/DataCache';
import { ErrorHandler } from '../utils/ErrorHandler';
import { common } from '@kit.AbilityKit';

export interface StationLoadResult {
  stations: StationData[];
  failedNames: string[];
  // 当前成功加载站点中最早的实际获取时间，不是本次读取缓存的时间。
  oldestFetchedAt?: number;
}

export class StationService {
  private static cacheEpoch: number = 0;
  private static nearbyLocationStatus: string = "";
  // 获取配置中的站点数据（带缓存）
  static async fetchStationsForConfig(stationConfig: Record<string, number>): Promise<StationLoadResult> {
    const epoch = StationService.cacheEpoch;
    let newStations: StationData[] = [];
    const failedNames: string[] = [];
    const fetchedTimes: number[] = [];
    let keys = Object.keys(stationConfig);

    const fetchOne = async (name: string): Promise<StationData | null> => {
      const id = stationConfig[name];
      if (epoch !== StationService.cacheEpoch) return null;

      const cached = DataCache.getStation(id);
      if (cached) {
        const fetchedAt = DataCache.getStationTimestamp(id);
        if (fetchedAt !== undefined) fetchedTimes.push(fetchedAt);
        // 缓存共享实时数据，不共享另一套配置中的显示名称。
        return { id: cached.id, name: name, outlets: cached.outlets };
      }

      try {
        const data = await ChargerApi.fetchStation(id, name);
        if (data && data.outlets && data.outlets.length > 0) {
          const fetchedAt = Date.now();
          fetchedTimes.push(fetchedAt);
          if (epoch === StationService.cacheEpoch) DataCache.setStation(id, data, fetchedAt);
          return { id: data.id, name: name, outlets: data.outlets };
        }
      } catch (error) {
        ErrorHandler.handle(error, `StationService.fetchStationsForConfig[${name}]`);
      }
      return null;
    };

    // 商业街包含 19 个站点，限制并发站点数，避免同时启动上百个插座详情请求。
    for (let offset = 0; offset < keys.length; offset += 4) {
      const results = await Promise.allSettled(keys.slice(offset, offset + 4).map(fetchOne));
      results.forEach((result, index) => {
        if (result.status === 'fulfilled' && result.value) newStations.push(result.value);
        else failedNames.push(keys[offset + index]);
      });
    }

    return {
      stations: newStations, failedNames: failedNames,
      oldestFetchedAt: fetchedTimes.length ? Math.min(...fetchedTimes) : undefined
    };
  }

  // 获取附近站点（带缓存）
  static async fetchNearbyStations(context?: common.UIAbilityContext): Promise<StationQueryResult> {
    const epoch = StationService.cacheEpoch;
    // 检查缓存
    const cached = DataCache.getNearbyStations();
    if (cached) {
      return {
        stations: cached,
        locationStatus: StationService.nearbyLocationStatus ? `${StationService.nearbyLocationStatus}（缓存）` : '使用缓存数据'
      };
    }

    try {
      const result = await ChargerApi.fetchNearbyStations(context);

      // 存入缓存
      if (epoch === StationService.cacheEpoch && result.stations.length > 0) {
        DataCache.setNearbyStations(result.stations);
        StationService.nearbyLocationStatus = result.locationStatus;
      }

      return result;
    } catch (error) {
      ErrorHandler.handle(error, 'StationService.fetchNearbyStations');
      return {
        stations: [],
        locationStatus: "加载失败: " + ErrorHandler.getErrorMessage(error)
      };
    }
  }

  // 清除所有缓存
  static clearCache(): void {
    // 旧请求完成后不能把清除前的快照重新写入缓存。
    StationService.cacheEpoch++;
    StationService.nearbyLocationStatus = '';
    DataCache.clearAll();
  }
}
