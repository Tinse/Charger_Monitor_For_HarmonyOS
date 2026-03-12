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
      [1, 2, 3].includes(outlet.status));
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
}