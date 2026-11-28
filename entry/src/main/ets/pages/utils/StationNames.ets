// 统一站点显示名的归一、冲突消歧与显式别名识别。
export class StationNames {
  static normalize(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, '');
  }

  static taken(stations: Record<string, number>, display: string, excludedId: number = -1): boolean {
    return Object.keys(stations).some(name => stations[name] !== excludedId &&
      StationNames.normalize(name) === StationNames.normalize(display));
  }

  static unique(stations: Record<string, number>, source: string, stationId: number, excludedId: number = -1): string {
    if (source !== '__proto__' && !StationNames.taken(stations, source, excludedId)) return source;
    const base = `${source}（${stationId}）`;
    let display = base;
    let suffix = 2;
    while (StationNames.taken(stations, display, excludedId)) display = `${base} ${suffix++}`;
    return display;
  }

  static isAlias(display: string, source: string, stationId: number): boolean {
    const autoName = `${source}（${stationId}）`;
    const suffix = display.startsWith(`${autoName} `) ? display.substring(autoName.length + 1) : '';
    const numericSuffix = /^\d+$/.test(suffix) && Number(suffix) >= 2 && String(Number(suffix)) === suffix;
    return display !== source && display !== autoName && !numericSuffix;
  }
}
