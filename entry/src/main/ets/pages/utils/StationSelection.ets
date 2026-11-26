import { StationBrief } from '../ChargerModels';

export class StationSelection {
  static normalize(value: string): string {
    return value.toLowerCase().replace(/[\s\u3000]+/g, '');
  }

  static filter(stations: StationBrief[], keyword: string): StationBrief[] {
    const query = StationSelection.normalize(keyword);
    return stations.filter(station => StationSelection.normalize(station.stationName + station.address).includes(query));
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

  static toStationMap(stations: StationBrief[], selected: number[]): Record<string, number> {
    const result: Record<string, number> = {};
    for (const id of selected) {
      const station = stations.find(item => item.stationId === id);
      if (!station || !station.stationName.trim()) throw new Error('部分已选站点信息缺失，请重新加载后保存');
      const name = station.stationName;
      if (Object.keys(result).includes(name) && result[name] !== id) {
        throw new Error('已选站点存在重名，请调整选择后保存');
      }
      result[name] = id;
    }
    if (Object.keys(result).length !== selected.length) throw new Error('已选站点信息重复或异常，请重新选择');
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
