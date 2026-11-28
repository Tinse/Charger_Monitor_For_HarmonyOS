import { ChargerConfig, ConfigStationMember, OutletDetail, OutletStatus, SORT_MODE, StationData } from '../ChargerModels';
import { StationSelection } from './StationSelection';
import { ApiConfig } from '../ApiConfig';
import { StationSnapshot } from '../services/OutletDetails';

export interface MonitorDetail {
  stationId: number;
  outletNo: string;
  generation: number;
  state: string;
  fetchedAt?: number;
  power_w?: number;
  fee?: number;
  used_min?: number;
}

export interface MonitorTarget {
  stationId: number;
  outletNo: string;
  generation: number;
}

export interface MonitorOutletRow {
  renderKey: string;
  serial: number;
  outletNo: string;
  status: number;
  detailState: string;
  detailFetchedAt?: number;
  power_w?: number;
  fee?: number;
  used_min?: number;
}

export interface MonitorStationRow {
  id: number;
  name: string;
  originalName: string;
  note: string;
  order: number;
  paused: boolean;
  pending: boolean;
  failed: boolean;
  missing: boolean;
  confirmed: boolean;
  fromDisk: boolean;
  fetchedAt?: number;
  generation?: number;
  retryAt?: number;
  manualRetryAt?: number;
  outlets: MonitorOutletRow[];
  freeCount?: number;
  occupiedCount?: number;
  brokenCount?: number;
  renderKey: string;
}

export interface MonitorStats {
  active: number;
  covered: number;
  total: number;
  free: number;
  occupied: number;
  broken: number;
}

// 纯显示模型：不会执行网络查询；键和统计仅随数据变化重新计算。
export class MonitorModel {
  static members(config: ChargerConfig | null, active: Record<string, number>): ConfigStationMember[] {
    if (config?.members) return config.members;
    const source = config ? config.stations : active;
    return Object.keys(source).map((name: string): ConfigStationMember => {
      const id = source[name];
      return { stationId: id, originalName: config?.stationNames?.[id.toString()] || name,
        alias: name, note: '', paused: !Object.values(active).includes(id) };
    });
  }

  static key(stationId: number, outletNo: string, generation: number): string {
    return `${stationId}/${generation}/${outletNo}`;
  }

  static rows(members: ConfigStationMember[], snapshots: Map<number, StationSnapshot>,
    details: Map<string, MonitorDetail>, pending: number[], failed: number[], retries: Map<number, number>, manualRetries: Map<number, number> = new Map(), missing: number[] = []): MonitorStationRow[] {
    return members.map((member: ConfigStationMember, index: number): MonitorStationRow => {
      const snapshot = snapshots.get(member.stationId);
      const confirmed = !member.paused && !!snapshot?.confirmed;
      const outlets: MonitorOutletRow[] = member.paused ? [] : (snapshot?.station.outlets || []).map((outlet: OutletDetail): MonitorOutletRow => {
        const detail = confirmed && snapshot ? details.get(MonitorModel.key(member.stationId, outlet.outletNo, snapshot.generation)) : undefined;
        // 基础数据中即使意外带有详情字段也不直接显示：只绑定本世代显式查询的详情。
        const displayed: MonitorOutletRow = { renderKey: '', serial: outlet.serial, outletNo: outlet.outletNo, status: outlet.status,
          detailState: outlet.status !== OutletStatus.OCCUPIED ? '' : !confirmed ? 'history' : detail?.state || 'unknown',
          detailFetchedAt: detail?.fetchedAt, power_w: detail?.power_w, fee: detail?.fee, used_min: detail?.used_min };
        displayed.renderKey = JSON.stringify(displayed);
        return displayed;
      });
      const row: MonitorStationRow = {
        id: member.stationId, name: member.alias || member.originalName, originalName: member.originalName,
        note: member.note, order: index, paused: member.paused, pending: pending.includes(member.stationId),
        failed: failed.includes(member.stationId), missing: missing.includes(member.stationId), confirmed, fromDisk: snapshot?.fromDisk || false,
        fetchedAt: snapshot?.fetchedAt, generation: snapshot?.generation, retryAt: retries.get(member.stationId), manualRetryAt: manualRetries.get(member.stationId), outlets,
        freeCount: snapshot && !member.paused ? outlets.filter(outlet => outlet.status === OutletStatus.FREE).length : undefined,
        occupiedCount: snapshot && !member.paused ? outlets.filter(outlet => outlet.status === OutletStatus.OCCUPIED).length : undefined,
        brokenCount: snapshot && !member.paused ? outlets.filter(outlet => outlet.status === OutletStatus.BROKEN).length : undefined,
        renderKey: ''
      };
      row.renderKey = JSON.stringify(row);
      return row;
    });
  }

  static stats(rows: MonitorStationRow[]): MonitorStats {
    const result: MonitorStats = { active: 0, covered: 0, total: 0, free: 0, occupied: 0, broken: 0 };
    rows.forEach((row: MonitorStationRow) => {
      if (!row.paused) result.active++;
      if (!row.confirmed) return;
      result.covered++;
      result.total += row.outlets.length;
      result.free += row.freeCount ?? 0;
      result.occupied += row.occupiedCount ?? 0;
      result.broken += row.brokenCount ?? 0;
    });
    return result;
  }

  static compareKnown(a: number | undefined, b: number | undefined): number {
    const aKnown = a !== undefined && Number.isFinite(a);
    const bKnown = b !== undefined && Number.isFinite(b);
    if (aKnown && bKnown) return b! - a!;
    if (aKnown) return -1;
    if (bKnown) return 1;
    return 0;
  }

  private static metric(outlet: MonitorOutletRow, mode: number): number | undefined {
    if (outlet.status !== OutletStatus.OCCUPIED || outlet.detailState !== 'success') return undefined;
    if (mode === SORT_MODE.POWER) return outlet.power_w;
    if (mode === SORT_MODE.FEE) return outlet.fee;
    if (mode === SORT_MODE.DURATION) return outlet.used_min;
    return undefined;
  }

  private static maximum(row: MonitorStationRow, mode: number): number | undefined {
    if (!row.confirmed) return undefined;
    const values: number[] = [];
    row.outlets.forEach((outlet: MonitorOutletRow) => {
      const value = MonitorModel.metric(outlet, mode);
      if (value !== undefined && Number.isFinite(value)) values.push(value);
    });
    return values.length ? Math.max(...values) : undefined;
  }

  static sorted(rows: MonitorStationRow[], mode: number): MonitorStationRow[] {
    const metricMode = mode === SORT_MODE.POWER || mode === SORT_MODE.FEE || mode === SORT_MODE.DURATION;
    return rows.map((row: MonitorStationRow): MonitorStationRow => {
        const outlets = [...row.outlets].sort((a: MonitorOutletRow, b: MonitorOutletRow): number => {
          return (metricMode ? MonitorModel.compareKnown(MonitorModel.metric(a, mode), MonitorModel.metric(b, mode)) : 0) || a.serial - b.serial;
        });
        const displayed: MonitorStationRow = {
          id: row.id, name: row.name, originalName: row.originalName, note: row.note, order: row.order,
          paused: row.paused, pending: row.pending, failed: row.failed, missing: row.missing, confirmed: row.confirmed,
          fromDisk: row.fromDisk, fetchedAt: row.fetchedAt, generation: row.generation, retryAt: row.retryAt, manualRetryAt: row.manualRetryAt,
          outlets, freeCount: row.freeCount, occupiedCount: row.occupiedCount, brokenCount: row.brokenCount,
          renderKey: `${row.renderKey}/${mode}`
        };
        return displayed;
      })
      .sort((a: MonitorStationRow, b: MonitorStationRow): number => {
        let difference = 0;
        if (mode === SORT_MODE.FREE_COUNT) difference = MonitorModel.compareKnown(a.confirmed ? a.freeCount : undefined, b.confirmed ? b.freeCount : undefined);
        else if (metricMode) difference = MonitorModel.compareKnown(MonitorModel.maximum(a, mode), MonitorModel.maximum(b, mode));
        return difference || a.order - b.order;
      });
  }

  static filter(rows: MonitorStationRow[], keyword: string): MonitorStationRow[] {
    const key = StationSelection.normalize(keyword);
    return rows.filter((row: MonitorStationRow) => StationSelection.normalize(`${row.name} ${row.originalName} ${row.id} ${row.note}`).includes(key));
  }

  static filterSort(rows: MonitorStationRow[], keyword: string, mode: number): MonitorStationRow[] {
    return MonitorModel.filter(MonitorModel.sorted(rows, mode), keyword);
  }

  static targets(rows: MonitorStationRow[]): MonitorTarget[] {
    const targets: MonitorTarget[] = [];
    rows.forEach((row: MonitorStationRow) => {
      if (!row.confirmed || row.generation === undefined) return;
      row.outlets.forEach((outlet: MonitorOutletRow) => {
        if (outlet.status === OutletStatus.OCCUPIED) targets.push({ stationId: row.id, outletNo: outlet.outletNo, generation: row.generation! });
      });
    });
    return targets;
  }

  static validTarget(target: MonitorTarget, rows: MonitorStationRow[]): boolean {
    const row = rows.find(item => item.id === target.stationId);
    return !!row?.confirmed && row.generation === target.generation && row.outlets.some(outlet => outlet.outletNo === target.outletNo && outlet.status === OutletStatus.OCCUPIED);
  }

  static dueIds(rows: MonitorStationRow[], now: number, retryOnly: boolean = false): number[] {
    return rows.filter((row: MonitorStationRow) => !row.paused && !row.pending && !row.missing &&
      (!retryOnly || row.failed) && (!row.retryAt || row.retryAt <= now) &&
      (row.failed || row.fromDisk || row.fetchedAt === undefined || now < row.fetchedAt || now - row.fetchedAt >= ApiConfig.AUTO_REFRESH_INTERVAL))
      .map(row => row.id);
  }
}
