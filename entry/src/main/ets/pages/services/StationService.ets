// StationService.ets - 站点数据获取 + 缓存策略
import { ChargerApi } from '../api/ChargerApi';
import { StationData, StationBrief, StationQueryResult } from '../ChargerModels';
import { DataCache } from '../utils/DataCache';
import { ErrorHandler } from '../utils/ErrorHandler';
import { common } from '@kit.AbilityKit';

export class StationService {
  // 获取配置中的站点数据（带缓存）
  static async fetchStationsForConfig(stationConfig: Record<string, number>): Promise<StationData[]> {
    let newStations: StationData[] = [];
    let keys = Object.keys(stationConfig);

    const stationPromises = keys.map(async (name) => {
      const id = stationConfig[name];

      const cached = DataCache.getStation(id);
      if (cached) {
        return cached;
      }

      try {
        const data = await ChargerApi.fetchStation(id, name);
        if (data && data.outlets && data.outlets.length > 0) {
          DataCache.setStation(id, data);
          return data;
        }
      } catch (error) {
        ErrorHandler.handle(error, `StationService.fetchStationsForConfig[${name}]`);
      }
      return null;
    });

    const results = await Promise.allSettled(stationPromises);

    results.forEach(result => {
      if (result.status === 'fulfilled' && result.value) {
        newStations.push(result.value);
      }
    });

    return newStations;
  }

  // 获取附近站点（带缓存）
  static async fetchNearbyStations(context?: common.UIAbilityContext): Promise<StationQueryResult> {
    // 检查缓存
    const cached = DataCache.getNearbyStations();
    if (cached) {
      return {
        stations: cached,
        locationStatus: "使用缓存数据"
      };
    }

    try {
      const result = await ChargerApi.fetchNearbyStations(context);

      // 存入缓存
      if (result.stations.length > 0) {
        DataCache.setNearbyStations(result.stations);
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
    DataCache.clearAll();
  }
}
