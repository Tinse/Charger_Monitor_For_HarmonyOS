// ApiConfig.ets - API 配置集中管理

// API 端点接口
interface ApiEndpoints {
  STATION_OUTLETS: string;
  OUTLET_DETAIL: string;
  NEARBY_STATIONS: string;
}

// HTTP 配置接口
interface HttpConfig {
  CONNECT_TIMEOUT: number;
  READ_TIMEOUT: number;
}

export class ApiConfig {
  // API 基础 URL
  static readonly BASE_URL = 'https://wemp.issks.com';
  static readonly API_ORIGIN = 'https://api.issks.com';

  // API 端点
  static readonly ENDPOINTS: ApiEndpoints = {
    STATION_OUTLETS: '/charge/v1/outlet/station/outlets',
    OUTLET_DETAIL: '/charge/v1/charging/outlet',
    NEARBY_STATIONS: '/device/v1/near/station'
  };

  // HTTP 配置
  static readonly HTTP_CONFIG: HttpConfig = {
    CONNECT_TIMEOUT: 10000,
    READ_TIMEOUT: 15000
  };

  // 默认坐标（定位失败时使用）
  static readonly DEFAULT_LATITUDE = 40.74566536567867;
  static readonly DEFAULT_LONGITUDE = 103.92188101700906;

  // 缓存配置
  static readonly CACHE_DURATION = 60000; // 1分钟缓存

  // 刷新配置
  static readonly AUTO_REFRESH_INTERVAL = 30000; // 30秒自动刷新
  static readonly MANUAL_REFRESH_COOLDOWN = 3000; // 3秒手动刷新冷却
  static readonly DEBOUNCE_DELAY = 300; // 300ms 防抖延迟

  // 获取请求头
  static getHeaders(): Record<string, string> {
    return {
      'sec-ch-ua-platform': '"Android"',
      'user-agent': 'Mozilla/5.0 (Linux; Android 16; 2407FRK8EC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36',
      'content-type': 'application/json;charset=utf-8',
      'origin': ApiConfig.API_ORIGIN,
      'referer': `${ApiConfig.API_ORIGIN}/`
    };
  }

  // 构建站点插座 URL
  static buildStationOutletsUrl(stationId: number): string {
    return `${ApiConfig.BASE_URL}${ApiConfig.ENDPOINTS.STATION_OUTLETS}/${stationId}`;
  }

  // 构建插座详情 URL
  static buildOutletDetailUrl(outletNo: string): string {
    return `${ApiConfig.BASE_URL}${ApiConfig.ENDPOINTS.OUTLET_DETAIL}/${outletNo}`;
  }

  // 构建附近站点 URL
  static buildNearbyStationsUrl(): string {
    return `${ApiConfig.BASE_URL}${ApiConfig.ENDPOINTS.NEARBY_STATIONS}`;
  }
}