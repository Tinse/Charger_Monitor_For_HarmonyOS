import { StationBrief } from '../ChargerModels';

export class StationSelection {
  static normalize(value: string): string {
    return value.toLowerCase().replace(/[\s\u3000]+/g, '');
  }

  static filter(stations: StationBrief[], keyword: string): StationBrief[] {
    const query = StationSelection.normalize(keyword);
    return stations.filter(station => StationSelection.normalize(station.stationName + station.address).includes(query));
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
