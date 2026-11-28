import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ApiConfig } from '../ApiConfig';
import { OutletDetail, OutletStatus } from '../ChargerModels';
import { DataCache, StationEntry } from '../utils/DataCache';

interface SavedStation {
  id: number;
  fetchedAt: number;
  outlets: OutletDetail[];
}

// 独立偏好库，每站一个值。只保存核实过的基础字段。
export class StationHistory {
  private static prefs?: preferences.Preferences;
  private static opening?: Promise<void>;
  private static saved: Map<string, string> = new Map();
  private static writing?: Promise<void>;
  private static dirty: boolean = false;
  private static reconcile: boolean = false;
  private static timer: number = -1;
  private static encoded: WeakMap<StationEntry, string> = new WeakMap();
  private static ids?: Set<number>;

  static referenced(id: number): boolean {
    return !StationHistory.ids || StationHistory.ids.has(id);
  }

  static retain(ids: number[]): void {
    const next = new Set(ids);
    if (StationHistory.ids && next.size === StationHistory.ids.size && ids.every(id => StationHistory.ids!.has(id))) return;
    StationHistory.ids = next;
    DataCache.retain(StationHistory.ids);
    StationHistory.save();
  }

  private static decode(raw: string, id: number): SavedStation | undefined {
    try {
      const row = JSON.parse(raw) as SavedStation;
      const age = Date.now() - row.fetchedAt;
      if (row.id !== id || !Number.isInteger(id) || id <= 0 || !Number.isFinite(row.fetchedAt) ||
        age < 0 || age >= ApiConfig.STATION_HISTORY_DURATION || !Array.isArray(row.outlets) || !row.outlets.length) return undefined;
      const serials = new Set<number>();
      const numbers = new Set<string>();
      const outlets: OutletDetail[] = [];
      for (const item of row.outlets) {
        if (!item || !Number.isInteger(item.serial) || item.serial <= 0 || typeof item.outletNo !== 'string' ||
          !item.outletNo.trim() || ![OutletStatus.FREE, OutletStatus.OCCUPIED, OutletStatus.BROKEN].includes(item.status) ||
          serials.has(item.serial) || numbers.has(item.outletNo)) return undefined;
        serials.add(item.serial);
        numbers.add(item.outletNo);
        outlets.push({ serial: item.serial, outletNo: item.outletNo, status: item.status });
      }
      return { id, fetchedAt: row.fetchedAt, outlets };
    } catch (_error) { return undefined; }
  }

  static initialize(context: common.Context): Promise<void> {
    if (!StationHistory.opening) StationHistory.opening = StationHistory.read(context);
    return StationHistory.opening;
  }

  private static async read(context: common.Context): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: 'station_basic_history' });
      const values = await prefs.getAll() as Record<string, preferences.ValueType>;
      const rows: SavedStation[] = [];
      Object.keys(values).forEach(key => {
        const raw = values[key];
        StationHistory.saved.set(key, typeof raw === 'string' ? raw : '');
        if (typeof raw !== 'string' || !/^s[1-9]\d*$/.test(key)) return;
        const row = StationHistory.decode(raw, Number(key.slice(1)));
        if (row && StationHistory.referenced(row.id)) rows.push(row);
      });
      rows.sort((a, b) => b.fetchedAt - a.fetchedAt).slice(0, 128).forEach(row => {
        if (!DataCache.getHistory(row.id)) {
          DataCache.setStation(row.id, { id: row.id, name: '', outlets: row.outlets }, row.fetchedAt, true);
        }
      });
      StationHistory.prefs = prefs;
      await StationHistory.save();
    } catch (error) {
      console.error('Station history unavailable', (error as Error).message);
      StationHistory.opening = undefined;
    }
  }

  private static encode(entry: StationEntry): string {
    const previous = StationHistory.encoded.get(entry);
    if (previous) return previous;
    const outlets: OutletDetail[] = entry.data.outlets.map((item: OutletDetail): OutletDetail => {
      return { serial: item.serial, outletNo: item.outletNo, status: item.status };
    });
    const row: SavedStation = { id: entry.data.id, fetchedAt: entry.fetchedAt, outlets };
    const raw = JSON.stringify(row);
    StationHistory.encoded.set(entry, raw);
    return raw;
  }

  static changed(): void {
    if (StationHistory.prefs && StationHistory.timer < 0) {
      StationHistory.timer = setTimeout(() => {
        StationHistory.timer = -1;
        StationHistory.save();
      }, 150);
    }
  }

  static save(): Promise<void> {
    const prefs = StationHistory.prefs;
    if (!prefs) return Promise.resolve();
    if (StationHistory.timer >= 0) {
      clearTimeout(StationHistory.timer);
      StationHistory.timer = -1;
    }
    StationHistory.dirty = true;
    if (!StationHistory.writing) {
      StationHistory.writing = Promise.resolve().then(async () => {
        while (StationHistory.dirty) {
          StationHistory.dirty = false;
          if (StationHistory.reconcile) {
            const actual = await prefs.getAll() as Record<string, preferences.ValueType>;
            StationHistory.saved.clear();
            Object.keys(actual).forEach(key => { StationHistory.saved.set(key, String(actual[key])); });
          }
          const keep = DataCache.historyEntries().filter(entry => StationHistory.referenced(entry.data.id))
            .sort((a, b) => b.fetchedAt - a.fetchedAt || b.generation - a.generation).slice(0, 128);
          const next = new Map<string, string>();
          let changed = StationHistory.reconcile;
          for (const entry of keep) {
            const key = 's' + entry.data.id;
            const value = StationHistory.encode(entry);
            next.set(key, value);
            if (StationHistory.saved.get(key) !== value) { await prefs.put(key, value); changed = true; }
          }
          for (const key of StationHistory.saved.keys()) {
            if (!next.has(key)) { await prefs.delete(key); changed = true; }
          }
          if (changed) await prefs.flush();
          StationHistory.saved = next;
          StationHistory.reconcile = false;
        }
      }).catch((error: Error) => {
        StationHistory.reconcile = true;
        console.error('Station history save failed', error.message);
      }).finally(() => {
        StationHistory.writing = undefined;
        if (StationHistory.dirty) StationHistory.save();
      });
    }
    return StationHistory.writing;
  }
}
