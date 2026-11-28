import { ChargerConfig, StationBrief } from '../ChargerModels';
import { StationNames } from './StationNames';
import { PresetConfigs } from '../PresetConfigs';

export class StationSelection {
  static normalize(value: string): string {
    return value.toLowerCase().replace(/[\s\u3000]+/g, '');
  }

  static filter(stations: StationBrief[], keyword: string, displayNames: Record<string, string> = {}): StationBrief[] {
    const query = StationSelection.normalize(keyword);
    return stations.filter(station => StationSelection.normalize(
      station.stationName + ' ' + station.address + ' ' + station.stationId.toString() + ' ' + (displayNames[station.stationId.toString()] || '')
    ).includes(query));
  }

  static displayNames(config: ChargerConfig | null): Record<string, string> {
    const result: Record<string, string> = {};
    if (config) Object.keys(config.stations).forEach(name => { result[config.stations[name].toString()] = name; });
    return result;
  }

  static savedStations(config: ChargerConfig): StationBrief[] {
    return Object.keys(config.stations).map(name => ({
      stationId: config.stations[name],
      stationName: config.stationNames?.[config.stations[name].toString()] || name,
      address: '已保存站点', freeNum: -1
    } as StationBrief));
  }

  static campusCatalog(): StationBrief[] {
    const stations: StationBrief[] = [];
    PresetConfigs.create().forEach(config => {
      StationSelection.savedStations(config).forEach(station => {
        if (!stations.some(item => item.stationId === station.stationId)) {
          stations.push({ stationId: station.stationId, stationName: station.stationName,
            address: '清水河校区 · 本地校园预设', freeNum: -1 });
        }
      });
    });
    return stations;
  }

  static candidates(stations: StationBrief[], mode: string, existing: number[]): StationBrief[] {
    return mode === 'replace' ? stations.filter(station => !existing.includes(station.stationId)) : stations;
  }

  static canSelect(id: number, mode: string, existing: number[]): boolean {
    return (mode !== 'add' && mode !== 'replace') || !existing.includes(id);
  }

  static setSelected(selected: number[], id: number, checked: boolean, mode: string, existing: number[]): number[] {
    if (!StationSelection.canSelect(id, mode, existing) || selected.includes(id) === checked) return selected;
    if (mode === 'replace') return checked ? [id] : [];
    return checked ? [...selected, id] : selected.filter(value => value !== id);
  }

  static mergeAvailable(fetched: StationBrief[], previous: StationBrief[], selected: number[]): StationBrief[] {
    const result: StationBrief[] = [];
    const seen: number[] = [];
    for (const station of [...fetched, ...previous.filter(item => selected.includes(item.stationId))]) {
      if (!seen.includes(station.stationId)) {
        result.push(station);
        seen.push(station.stationId);
      }
    }
    return result;
  }

  static toStationMap(stations: StationBrief[], selected: number[], displayNames: Record<string, string> = {}): Record<string, number> {
    const reserved: Record<string, number> = {};
    const assigned: Record<string, string> = {};
    if (selected.some((id, index) => !Number.isInteger(id) || id <= 0 || selected.indexOf(id) !== index)) {
      throw new Error('已选站点信息重复或异常，请重新选择');
    }
    // 优先保留显式别名，原名冲突由统一规则分配可读显示名。
    for (const id of selected) {
      const station = stations.find(item => item.stationId === id);
      if (!station || !station.stationName.trim()) throw new Error('部分已选站点信息缺失，请重新加载后保存');
      const source = station.stationName.trim();
      const display = displayNames[id.toString()]?.trim() || source;
      if (!StationNames.isAlias(display, source, id)) continue;
      if (display === '__proto__' || display.length > 40) throw new Error('已选站点别名无效，请调整后保存');
      if (StationNames.taken(reserved, display)) throw new Error('已选站点存在重名别名，请调整后保存');
      reserved[display] = id;
      assigned[id.toString()] = display;
    }
    for (const id of selected) {
      if (assigned[id.toString()]) continue;
      const station = stations.find(item => item.stationId === id);
      if (!station) throw new Error('部分已选站点信息缺失，请重新加载后保存');
      const display = StationNames.unique(reserved, station.stationName.trim(), id);
      reserved[display] = id;
      assigned[id.toString()] = display;
    }
    const result: Record<string, number> = {};
    selected.forEach(id => { result[assigned[id.toString()]] = id; });
    return result;
  }

  static toStationNames(stations: StationBrief[], selected: number[], originalNames: Record<string, string> = {}): Record<string, string> {
    const result: Record<string, string> = {};
    selected.forEach(id => {
      const station = stations.find(item => item.stationId === id);
      if (!station) throw new Error('部分已选站点信息缺失，请重新加载后保存');
      result[id.toString()] = originalNames[id.toString()] || station.stationName;
    });
    return result;
  }

  static selectMatches(selected: number[], matches: StationBrief[]): number[] {
    const result = [...selected];
    matches.forEach(station => {
      if (!result.includes(station.stationId)) result.push(station.stationId);
    });
    return result;
  }

  static clearMatches(selected: number[], matches: StationBrief[]): number[] {
    return selected.filter(id => !matches.some(station => station.stationId === id));
  }
}
