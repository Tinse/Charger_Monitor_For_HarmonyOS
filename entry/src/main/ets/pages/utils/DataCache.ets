import { StationData, StationBrief } from '../ChargerModels';
import { ApiConfig } from '../ApiConfig';

export interface StationEntry {
  data: StationData;
  fetchedAt: number;
  generation: number;
  fromDisk: boolean;
}

interface NearbyEntry {
  data: StationBrief[];
  fetchedAt: number;
}

export class DataCache {
  private static sequence: number = 0;
  private static stations: Map<number, StationEntry> = new Map();
  private static nearby: Map<string, NearbyEntry> = new Map();

  static getHistory(id: number, now: number = Date.now()): StationEntry | undefined {
    const entry = DataCache.stations.get(id);
    if (entry && now >= entry.fetchedAt && now - entry.fetchedAt < ApiConfig.STATION_HISTORY_DURATION) return entry;
    if (entry) DataCache.stations.delete(id);
    return undefined;
  }

  static getStation(id: number): StationData | null {
    const entry = DataCache.getHistory(id);
    return entry && !entry.fromDisk && Date.now() - entry.fetchedAt < ApiConfig.AUTO_REFRESH_INTERVAL ? entry.data : null;
  }

  static getStationTimestamp(id: number): number | undefined {
    return DataCache.getHistory(id)?.fetchedAt;
  }

  static setStation(id: number, data: StationData, fetchedAt: number = Date.now(), fromDisk: boolean = false): void {
    DataCache.stations.set(id, { data, fetchedAt, generation: ++DataCache.sequence, fromDisk });
  }

  static historyEntries(): StationEntry[] {
    const entries: StationEntry[] = [];
    DataCache.stations.forEach((_value, id) => {
      const entry = DataCache.getHistory(id);
      if (entry) entries.push(entry);
    });
    return entries;
  }

  static retain(ids: Set<number>): void {
    DataCache.stations.forEach((_entry, id) => { if (!ids.has(id)) DataCache.stations.delete(id); });
  }

  static getNearbyStations(source: string = 'device'): StationBrief[] | null {
    const entry = DataCache.nearby.get(source);
    const now = Date.now();
    if (entry && now >= entry.fetchedAt && now - entry.fetchedAt < ApiConfig.CACHE_DURATION) return entry.data;
    if (entry) DataCache.nearby.delete(source);
    return null;
  }

  static setNearbyStations(data: StationBrief[], source: string = 'device'): void {
    DataCache.nearby.set(source, { data, fetchedAt: Date.now() });
  }

  static clearAll(): void {
    DataCache.stations.clear();
    DataCache.nearby.clear();
  }

  static clearExpired(): void {
    DataCache.historyEntries();
    DataCache.nearby.forEach((_value, source) => { DataCache.getNearbyStations(source); });
  }
}
