// ChargerModels.ets
export interface OutletDetail {
  serial: number;
  outletNo: string;
  status: number; // 1: 空闲, 2: 占用, 3: 损坏
  power_w?: number;
  fee?: number;
  used_min?: number;
}

export interface StationData {
  id: number;
  name: string;
  outlets: OutletDetail[];
}

export interface StationBrief {
  stationId: number;
  stationName: string;
  address: string;
  freeNum: number;
  distance?: number;          // 距离（米）
  formattedDistance?: string; // 格式化后的距离显示
}

// 定义排序模式
interface SortModeType {
  SERIAL: number;
  POWER: number;
  FEE: number;
  DURATION: number;
  FREE_COUNT: number;
}

export const SORT_MODE: SortModeType = {
  SERIAL: 0,
  POWER: 1,
  FEE: 2,
  DURATION: 3,
  FREE_COUNT: 4
};

// 配置管理相关接口
export interface ChargerConfig {
  id: string;
  name: string;
  stations: Record<string, number>; // {站点名称: 站点ID}
  createdAt: number;
}

export interface ConfigStorage {
  configs: ChargerConfig[];
  currentConfigId?: string;
}