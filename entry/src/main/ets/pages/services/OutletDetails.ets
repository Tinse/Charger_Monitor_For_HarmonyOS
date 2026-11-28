import { ChargerApi, StationHttpFailure } from '../api/ChargerApi';
import { OutletDetail, OutletStatus, StationData } from '../ChargerModels';

export interface StationSnapshot {
  station: StationData;
  fetchedAt: number;
  generation: number;
  confirmed: boolean;
  fromDisk: boolean;
}

export interface OutletLoadProgress {
  stationId: number;
  outletNo: string;
  generation: number;
  detail: Partial<OutletDetail> | null;
  completed: number;
  total: number;
  succeeded: number;
  failed: number;
  skipped: number;
}

interface DetailTarget {
  stationId: number;
  generation: number;
  outletNo: string;
}

export class OutletDetails {
  private static active: Map<string, Promise<Partial<OutletDetail> | null>> = new Map();
  private static limitedUntil: number = 0;

  private static async query(outletNo: string): Promise<Partial<OutletDetail> | null> {
    try {
      const detail = await ChargerApi.fetchOutletDetail(outletNo, (failure: StationHttpFailure) => {
        if (failure.status === 429 || (failure.status === 503 && failure.retryAt !== undefined)) {
          OutletDetails.limitedUntil = Math.max(OutletDetails.limitedUntil, failure.retryAt || Date.now() + 15000);
        }
      });
      if (detail.power_w !== undefined || detail.fee !== undefined || detail.used_min !== undefined) return detail;
    } catch (error) { console.error('Outlet detail unavailable', (error as Error).message); }
    return null;
  }

  private static async load(target: DetailTarget, valid: () => boolean): Promise<Partial<OutletDetail> | null> {
    const key = `${target.stationId}/${target.generation}/${target.outletNo}`;
    while (valid()) {
      const shared = OutletDetails.active.get(key);
      if (shared) return shared;
      if (Date.now() < OutletDetails.limitedUntil) return null;
      if (OutletDetails.active.size < 2) {
        const request = OutletDetails.query(target.outletNo).finally(() => { OutletDetails.active.delete(key); });
        OutletDetails.active.set(key, request);
        return request;
      }
      await Promise.race(Array.from(OutletDetails.active.values()));
    }
    return null;
  }

  static async fetch(stations: StationSnapshot[], current: (id: number, generation: number) => boolean,
    onProgress?: (progress: OutletLoadProgress) => void, shouldContinue?: () => boolean,
    onlyOutletNos?: string[]): Promise<void> {
    const targets: DetailTarget[] = [];
    const only = onlyOutletNos ? new Set(onlyOutletNos) : null;
    for (const snapshot of stations) {
      if (!snapshot.confirmed) continue;
      for (const outlet of snapshot.station.outlets) {
        if (outlet.status === OutletStatus.OCCUPIED && (!only || only.has(outlet.outletNo))) {
          targets.push({ stationId: snapshot.station.id, generation: snapshot.generation, outletNo: outlet.outletNo });
        }
      }
    }
    let next = 0;
    let succeeded = 0;
    let failed = 0;
    let skipped = 0;
    const worker = async (): Promise<void> => {
      while (next < targets.length && (!shouldContinue || shouldContinue())) {
        const target = targets[next++];
        const valid = (): boolean => (!shouldContinue || shouldContinue()) && current(target.stationId, target.generation);
        let detail = await OutletDetails.load(target, valid);
        if (shouldContinue && !shouldContinue()) return;
        if (!current(target.stationId, target.generation)) { detail = null; skipped++; }
        else if (detail) succeeded++;
        else failed++;
        try {
          onProgress?.({ stationId: target.stationId, generation: target.generation, outletNo: target.outletNo, detail,
            completed: succeeded + failed + skipped, total: targets.length, succeeded, failed, skipped });
        } catch (error) { console.error('Outlet progress observer failed', (error as Error).message); }
      }
    };
    await Promise.all([worker(), worker()]);
  }
}
