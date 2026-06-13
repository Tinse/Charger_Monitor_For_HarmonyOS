// DataCache.ets - 数据缓存管理
import { StationData, StationBrief } from '../ChargerModels';
import { ApiConfig } from '../ApiConfig';

interface CacheEntry<T> {
  data: T;
  timestamp: number;
}

export class DataCache {
  private static stationCache: Map<number, CacheEntry<StationData>> = new Map();
  private static nearbyStationsCache: CacheEntry<StationBrief[]> | null = null;

  // 获取缓存的站点数据
  static getStation(stationId: number): StationData | null {
    const cached = DataCache.stationCache.get(stationId);
    if (cached && DataCache.isValid(cached.timestamp)) {
      console.log(`[DataCache] Cache hit for station ${stationId}`);
      return cached.data;
    }

    // 缓存过期，清除
    if (cached) {
      DataCache.stationCache.delete(stationId);
    }

    console.log(`[DataCache] Cache miss for station ${stationId}`);
    return null;
  }

  // 设置站点数据缓存
  static setStation(stationId: number, data: StationData): void {
    DataCache.stationCache.set(stationId, {
      data: data,
      timestamp: Date.now()
    });
    console.log(`[DataCache] Cached station ${stationId}`);
  }

  // 获取缓存的附近站点数据
  static getNearbyStations(): StationBrief[] | null {
    if (DataCache.nearbyStationsCache && DataCache.isValid(DataCache.nearbyStationsCache.timestamp)) {
      console.log('[DataCache] Cache hit for nearby stations');
      return DataCache.nearbyStationsCache.data;
    }

    DataCache.nearbyStationsCache = null;
    console.log('[DataCache] Cache miss for nearby stations');
    return null;
  }

  // 设置附近站点数据缓存
  static setNearbyStations(stations: StationBrief[]): void {
    DataCache.nearbyStationsCache = {
      data: stations,
      timestamp: Date.now()
    };
    console.log(`[DataCache] Cached ${stations.length} nearby stations`);
  }

  // 清除所有缓存
  static clearAll(): void {
    DataCache.stationCache.clear();
    DataCache.nearbyStationsCache = null;
    console.log('[DataCache] All cache cleared');
  }

  // 清除过期缓存
  static clearExpired(): void {
    const keysToDelete: number[] = [];

    DataCache.stationCache.forEach((value, key) => {
      if (!DataCache.isValid(value.timestamp)) {
        keysToDelete.push(key);
      }
    });

    keysToDelete.forEach(key => {
      DataCache.stationCache.delete(key);
    });

    if (DataCache.nearbyStationsCache && !DataCache.isValid(DataCache.nearbyStationsCache.timestamp)) {
      DataCache.nearbyStationsCache = null;
    }

    console.log(`[DataCache] Cleared ${keysToDelete.length} expired entries`);
  }

  // 检查缓存是否有效
  private static isValid(timestamp: number): boolean {
    return Date.now() - timestamp < ApiConfig.CACHE_DURATION;
  }
}