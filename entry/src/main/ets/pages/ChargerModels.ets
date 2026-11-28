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

// 站点查询结果（包含位置状态）
export interface StationQueryResult {
  stations: StationBrief[];
  locationStatus: string; // 位置状态描述
  needOpenLocationService?: boolean; // 是否需要提示用户开启定位服务
}

// 插座状态枚举
export enum OutletStatus {
  FREE = 1,       // 空闲
  OCCUPIED = 2,   // 占用
  BROKEN = 3      // 损坏
}

// 定义排序模式
interface SortModeType {
  SERIAL: number;
  POWER: number;
  FEE: number;
  DURATION: number;
  FREE_COUNT: number;
  CONFIG_ORDER: number;
}

export const SORT_MODE: SortModeType = {
  SERIAL: 0,
  POWER: 1,
  FEE: 2,
  DURATION: 3,
  FREE_COUNT: 4,
  CONFIG_ORDER: 5
};

// 配置管理相关接口
export interface ConfigStationMember {
  stationId: number;
  originalName: string;
  alias: string;
  note: string;
  paused: boolean;
}

export interface ChargerConfig {
  members?: ConfigStationMember[]; // 有序成员；旧配置首次读取时从 stations 迁移
  id: string;
  name: string;
  stations: Record<string, number>; // {本配置内显示名称: 真实站点ID}
  stationNames?: Record<string, string>; // {String(真实站点ID): 服务端原站名}，兼容旧配置
  createdAt: number;
}

// 数据验证工具类
export class DataValidator {
  // 验证OutletDetail数据
  static validateOutletDetail(data: object | null): boolean {
    if (typeof data !== 'object' || data === null) return false;
    
    const outlet = data as Record<string, number | string>;
    return !!(outlet && 
      typeof outlet.serial === 'number' && 
      typeof outlet.outletNo === 'string' && 
      typeof outlet.status === 'number' &&
      [OutletStatus.FREE, OutletStatus.OCCUPIED, OutletStatus.BROKEN].includes(outlet.status));
  }

  // 验证StationData数据
  static validateStationData(data: object | null): boolean {
    if (typeof data !== 'object' || data === null) return false;
    
    const station = data as Record<string, number | string | object[]>;
    if (!(station && 
      typeof station.id === 'number' && 
      typeof station.name === 'string' && 
      Array.isArray(station.outlets))) {
      return false;
    }
    
    // 验证插座数组中的每个元素
    const outlets = station.outlets as object[];
    return outlets.every((outlet: object) => DataValidator.validateOutletDetail(outlet));
  }

  // 验证ChargerConfig数据
  static validateChargerConfig(data: object | null): boolean {
    if (typeof data !== 'object' || data === null) return false;
    
    const config = data as Record<string, string | number | object>;
    return !!(config && 
      typeof config.id === 'string' && 
      typeof config.name === 'string' && 
      typeof config.stations === 'object' &&
      typeof config.createdAt === 'number');
  }
}

export interface ConfigStorage {
  configs: ChargerConfig[];
  currentConfigId?: string;
  deletedPresetIds?: string[];
}