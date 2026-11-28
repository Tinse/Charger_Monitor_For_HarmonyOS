import { OutletStatus } from '../ChargerModels';
import { MonitorOutletRow, MonitorStationRow, MonitorStats } from './MonitorModel';

export interface MonitorBadge {
  text: string;
  tone: string;
}

// 仅处理展示：打开信息、切换排序和状态文案均不能触发网络请求。
export class MonitorPresentation {
  static title(stats: MonitorStats, loading: boolean, online: boolean, memberCount: number): string {
    if (!memberCount) return '充电监控';
    if (!stats.active) return '监控已暂停';
    if (!online) return '网络未连接';
    if (!stats.covered) return loading ? '正在获取站点状态' : '站点状态待更新';
    if (stats.covered < stats.active) return stats.free > 0 ? '部分站点有空闲' : '部分站点已确认';
    return stats.free > 0 ? '有空闲插座' : '暂无空闲插座';
  }

  static clock(time: number | undefined, detailed: boolean = false): string {
    if (time === undefined) return '尚未获取';
    const date = new Date(time);
    const hour = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    return detailed ? `${date.getMonth() + 1}月${date.getDate()}日 ${hour}:${date.getSeconds().toString().padStart(2, '0')}` : hour;
  }

  static coverage(stats: MonitorStats, rows: MonitorStationRow[]): string {
    const confirmed = rows.filter(row => row.confirmed && row.fetchedAt !== undefined);
    const time = confirmed.length ? Math.min(...confirmed.map(row => row.fetchedAt!)) : undefined;
    return `已确认 ${stats.covered}/${stats.active} 站${time !== undefined ? ' · 更新于 ' + MonitorPresentation.clock(time) : ''}`;
  }

  static rowStatus(row: MonitorStationRow): string {
    if (row.paused) return '已暂停监控';
    if (row.missing && !row.pending) return '站点不存在，请检查配置或手动重新核实';
    if (row.pending && !row.confirmed) return row.fetchedAt === undefined ? '正在获取状态' : '正在核实历史数据';
    if (row.failed) return row.fetchedAt === undefined ? '获取失败，暂无记录' : '查询失败 · 显示历史数据';
    if (!row.confirmed) return row.fetchedAt === undefined ? '尚未获取站点状态' : '历史数据 · 不计入当前统计';
    return '';
  }

  static rowCaption(row: MonitorStationRow): string {
    if (row.paused) return '暂停期间不发起查询';
    if (row.fetchedAt === undefined) return '插座数 — · 等待获取';
    return `${row.outlets.length} 个插座 · ${row.confirmed ? '更新于' : '历史于'} ${MonitorPresentation.clock(row.fetchedAt)}`;
  }

  static badges(outlet: MonitorOutletRow): MonitorBadge[] {
    if (outlet.status !== OutletStatus.OCCUPIED || outlet.detailState !== 'success') return [];
    const powerKnown = outlet.power_w !== undefined && Number.isFinite(outlet.power_w);
    const feeKnown = outlet.fee !== undefined && Number.isFinite(outlet.fee);
    const durationKnown = outlet.used_min !== undefined && Number.isFinite(outlet.used_min);
    const badges: MonitorBadge[] = [
      { text: powerKnown ? `${outlet.power_w}W` : '功率 —', tone: powerKnown ? 'info' : 'neutral' },
      { text: feeKnown ? `¥${outlet.fee!.toFixed(2)}` : '费用 —', tone: feeKnown ? 'success' : 'neutral' },
      { text: durationKnown ? `${outlet.used_min}分钟` : '时长 —', tone: durationKnown ? 'warning' : 'neutral' }
    ];
    return badges;
  }

  static outletStatus(outlet: MonitorOutletRow, confirmed: boolean): string {
    const status = outlet.status === OutletStatus.FREE ? '空闲' : outlet.status === OutletStatus.OCCUPIED ? '占用' : '故障';
    if (!confirmed) return `历史${status}`;
    if (outlet.status !== OutletStatus.OCCUPIED) return status;
    if (outlet.detailState === 'pending') return '占用 · 查询中';
    if (outlet.detailState === 'failed') return '占用 · 详情失败';
    return status;
  }

  static detailCaption(row: MonitorStationRow): string {
    const times = row.outlets.filter(outlet => outlet.detailFetchedAt !== undefined).map(outlet => outlet.detailFetchedAt!);
    return times.length ? `占用信息获取于 ${MonitorPresentation.clock(Math.min(...times))} · 手动更新` : '';
  }

  static detailSummary(completed: number, succeeded: number, failed: number, skipped: number, stopped: boolean = false): string {
    if (stopped) return `已停止 · 已获取 ${succeeded} 项`;
    if (failed) return `${succeeded} 项成功 · ${failed} 项失败${skipped ? ' · ' + skipped + ' 项已失效' : ''}`;
    if (skipped) return `已获取 ${succeeded} 项 · ${skipped} 项已失效`;
    return `已获取 ${completed} 项占用详情`;
  }
}
