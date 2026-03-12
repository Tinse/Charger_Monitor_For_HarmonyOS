// ChargerApi.ets
import http from '@ohos.net.http';
import { geoLocationManager } from '@kit.LocationKit';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import { OutletDetail, StationData, StationBrief } from './ChargerModels';

interface HttpHeaders {
  "sec-ch-ua-platform": string;
  "user-agent": string;
  "content-type": string;
  "origin": string;
  "referer": string;
}

const HEADERS: HttpHeaders = {
  "sec-ch-ua-platform": "\"Android\"",
  "user-agent": "Mozilla/5.0 (Linux; Android 16; 2407FRK8EC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36",
  "content-type": "application/json;charset=utf-8",
  "origin": "https://api.issks.com",
  "referer": "https://api.issks.com/"
};

interface PowerFeeData {
  billingPower?: string;
}

interface OutletDetailData {
  powerFee?: PowerFeeData;
  usedfee?: string;
  usedmin?: string;
}

interface OutletItem {
  currentChargingRecordId?: number;
  outletSerialNo?: number;
  outletNo?: string;
}

interface ApiResponseData {
  code: string;
  data?: OutletDetailData | OutletItem[];
}

interface ElecStationDataItem {
  stationId?: number;
  stationName?: string;
  address?: string;
  freeNum?: number;
  latitude?: number;  // 添加纬度字段
  longitude?: number; // 添加经度字段
  distance?: number;  // 添加距离字段
}

interface NearbyStationData {
  elecStationData?: ElecStationDataItem[];
}

interface NearbyStationResponse {
  code: string;
  data?: NearbyStationData;
}

interface NearbyStationPayload {
  page: number;
  pageSize: number;
  scale: number;
  latitude: number;
  longitude: number;
  userLatitude: number;
  userLongitude: number;
}

interface LocationResult {
  latitude: number;
  longitude: number;
}

// 默认坐标（定位失败时使用）
const DEFAULT_LATITUDE = 40.74566536567867;
const DEFAULT_LONGITUDE = 103.92188101700906;

// 权限常量
const LOCATION_PERMISSIONS: Array<Permissions> = [
  'ohos.permission.LOCATION',
  'ohos.permission.APPROXIMATELY_LOCATION'
];

// 地球半径（米）
const EARTH_RADIUS = 6378137.0;

export class ChargerApi {
  // 计算两个经纬度之间的距离（米）
  private static calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const radLat1 = ChargerApi.toRadians(lat1);
    const radLat2 = ChargerApi.toRadians(lat2);
    const a = radLat1 - radLat2;
    const b = ChargerApi.toRadians(lng1) - ChargerApi.toRadians(lng2);
    
    let s = 2 * Math.asin(Math.sqrt(Math.pow(Math.sin(a / 2), 2) +
      Math.cos(radLat1) * Math.cos(radLat2) * Math.pow(Math.sin(b / 2), 2)));
    s = s * EARTH_RADIUS;
    s = Math.round(s * 10000) / 10000;
    
    return s;
  }

  // 角度转弧度
  private static toRadians(degree: number): number {
    return degree * Math.PI / 180.0;
  }

  // 格式化距离显示
  private static formatDistance(distance: number): string {
    if (distance < 1000) {
      return `${Math.round(distance)}米`;
    } else {
      return `${(distance / 1000).toFixed(1)}公里`;
    }
  }

  // 获取应用的accessTokenId
  private static async getAccessTokenId(): Promise<number> {
    try {
      const bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
      return appInfo.accessTokenId;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error(`Failed to get access token ID. Code: ${err.code}, Message: ${err.message}`);
      return 0;
    }
  }

  // 检查单个权限状态
  private static async checkAccessToken(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = await ChargerApi.getAccessTokenId();
      
      if (tokenId === 0) {
        return abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
      }
      
      const grantStatus = await atManager.checkAccessToken(tokenId, permission);
      return grantStatus;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error(`Failed to check access token. Code: ${err.code}, Message: ${err.message}`);
      return abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    }
  }

  // 检查位置权限 - 简化版本，直接尝试获取位置来判断权限
  static async checkLocationPermissions(): Promise<boolean> {
    try {
      // 直接尝试获取位置，如果成功说明有权限
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        maxAccuracy: 100,
        timeoutMs: 5000 // 5秒超时，快速检查
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);
      return !!(location && location.latitude && location.longitude);
    } catch (error) {
      console.log('Location permission check failed, likely no permission:', error);
      return false;
    }
  }

  // 请求位置权限
  static async requestLocationPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      
      console.log('Requesting location permissions...');
      
      // 请求权限
      const requestResult = await atManager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);
      
      // 检查授权结果
      const grantStatus: Array<number> = requestResult.authResults;
      for (let i = 0; i < grantStatus.length; i++) {
        if (grantStatus[i] !== 0) { // 0表示授权成功
          console.log('Permission request denied for:', LOCATION_PERMISSIONS[i]);
          return false;
        }
      }
      
      console.log('All location permissions granted');
      return true;
      
    } catch (error) {
      console.error('Failed to request location permissions:', error);
      return false;
    }
  }

  // 获取当前地理位置
  static async getCurrentLocation(): Promise<LocationResult> {
    try {
      // 获取当前位置 - 使用快速定位优先策略
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        maxAccuracy: 100,
        timeoutMs: 30000 // 30秒超时
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);
      
      if (location && location.latitude && location.longitude) {
        console.log('Location acquired successfully:', location.latitude, location.longitude);
        return {
          latitude: location.latitude,
          longitude: location.longitude
        };
      } else {
        throw new Error('Invalid location data received');
      }
    } catch (error) {
      console.error('Failed to get current location:', error);
      console.log('Using default coordinates as fallback');
      // 定位失败时返回默认坐标
      return {
        latitude: DEFAULT_LATITUDE,
        longitude: DEFAULT_LONGITUDE
      };
    }
  }

  // 获取单个插座的详情（功率、费用、时长）
  static async fetchOutletDetail(outletNo: string): Promise<Partial<OutletDetail>> {
    let httpRequest = http.createHttp();
    let url = `https://wemp.issks.com/charge/v1/charging/outlet/${outletNo}`;

    try {
      let response = await httpRequest.request(url, { 
        method: http.RequestMethod.GET, 
        header: HEADERS,
        connectTimeout: 10000, // 10秒连接超时
        readTimeout: 15000     // 15秒读取超时
      });
      if (response.responseCode === 200) {
        let data: ApiResponseData = JSON.parse(response.result as string);
        if (data.code == "1" && data.data) {
          let d: OutletDetailData = data.data as OutletDetailData;
          let powerStr = d.powerFee?.billingPower || "0W";
          let power_w = parseInt(powerStr.replace(/[^0-9]/g, '')) || 0;
          return {
            power_w: power_w,
            fee: parseFloat(d.usedfee || "0") || 0.0,
            used_min: parseInt(d.usedmin || "0") || 0
          };
        }
      }
    } catch (e) {
      console.error(`Fetch detail failed for ${outletNo}: ${e}`);
    }
    return {};
  }

  // 获取单个站点的所有插座（带重试机制）
  static async fetchStation(stationId: number, stationName: string, maxRetries = 2): Promise<StationData | null> {
    let httpRequest = http.createHttp();
    let url = `https://wemp.issks.com/charge/v1/outlet/station/outlets/${stationId}`;

    for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
      try {
        console.log(`Fetching station ${stationName} (attempt ${attempt}/${maxRetries + 1})`);
        
        let response = await httpRequest.request(url, { 
          method: http.RequestMethod.GET, 
          header: HEADERS,
          connectTimeout: 10000, // 10秒连接超时
          readTimeout: 15000     // 15秒读取超时
        });
        
        if (response.responseCode === 200) {
          let data: ApiResponseData = JSON.parse(response.result as string);
          if (data.code == "1") {
            let outlets: OutletDetail[] = [];
            let promises: Promise<void>[] = [];

            let outletItems: OutletItem[] = data.data as OutletItem[] || [];
            for (let item of outletItems) {
              let rawStatus = item.currentChargingRecordId || 0;
              let status = [1, 2, 3].includes(rawStatus) ? rawStatus : 3;

              let outlet: OutletDetail = {
                serial: item.outletSerialNo || 0,
                outletNo: item.outletNo || "",
                status: status
              };
              outlets.push(outlet);

              // 并发获取占用中的插座详情
              if (status === 2 && outlet.outletNo) {
                let p = ChargerApi.fetchOutletDetail(outlet.outletNo).then(detail => {
                  outlet.power_w = detail.power_w;
                  outlet.fee = detail.fee;
                  outlet.used_min = detail.used_min;
                });
                promises.push(p);
              }
            }
            await Promise.all<void>(promises);
            console.log(`✅ Station ${stationName} fetched successfully`);
            return { id: stationId, name: stationName, outlets: outlets };
          }
        }
      } catch (e) {
        console.error(`❌ Attempt ${attempt} failed for station ${stationName}: ${e}`);
        
        // 如果不是最后一次尝试，等待一段时间后重试
        if (attempt <= maxRetries) {
          await new Promise<void>(resolve => setTimeout(resolve, 1000 * attempt)); // 递增等待时间
          continue;
        }
      }
    }
    
    console.error(`❌ All attempts failed for station ${stationName}`);
    return null;
  }

  // 获取附近的站点列表 (用于 Picker)
  static async fetchNearbyStations(context?: common.UIAbilityContext): Promise<StationBrief[]> {
    let httpRequest = http.createHttp();
    let url = "https://wemp.issks.com/device/v1/near/station";
    
    try {
      // 直接尝试获取当前位置
      console.log('=== 开始获取附近站点 ===');
      console.log('Attempting to get current location...');
      let userLocation: LocationResult;
      
      try {
        userLocation = await ChargerApi.getCurrentLocation();
        console.log('✅ Location obtained:', userLocation.latitude, userLocation.longitude);
        
        // 检查是否是默认坐标
        if (userLocation.latitude === DEFAULT_LATITUDE && userLocation.longitude === DEFAULT_LONGITUDE) {
          console.log('⚠️ 使用的是默认坐标，可能权限有问题');
        } else {
          console.log('🎯 使用的是实际获取的位置坐标');
        }
      } catch (locationError) {
        console.log('❌ Location failed, checking permissions...');
        
        // 如果获取位置失败，检查权限
        if (context) {
          console.log('Requesting permissions...');
          const granted = await ChargerApi.requestLocationPermissions(context);
          if (granted) {
            // 权限申请成功，再次尝试获取位置
            userLocation = await ChargerApi.getCurrentLocation();
            console.log('✅ Location after permission granted:', userLocation.latitude, userLocation.longitude);
          } else {
            // 权限被拒绝，使用默认坐标
            console.log('❌ Permission denied, using default location');
            userLocation = {
              latitude: DEFAULT_LATITUDE,
              longitude: DEFAULT_LONGITUDE
            };
          }
        } else {
          // 没有context，使用默认坐标
          console.log('❌ No context provided, using default location');
          userLocation = {
            latitude: DEFAULT_LATITUDE,
            longitude: DEFAULT_LONGITUDE
          };
        }
      }

      console.log('📌 Final user location for API request:', userLocation.latitude, userLocation.longitude);

      // 使用获取到的坐标
      let payload: NearbyStationPayload = {
        page: 1,
        pageSize: 200,
        scale: 3,
        latitude: userLocation.latitude,
        longitude: userLocation.longitude,
        userLatitude: userLocation.latitude,
        userLongitude: userLocation.longitude
      };

      console.log('🌐 API request payload:', JSON.stringify(payload));

      let response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: HEADERS,
        extraData: JSON.stringify(payload),
        connectTimeout: 10000, // 10秒连接超时
        readTimeout: 15000     // 15秒读取超时
      });

      if (response.responseCode === 200) {
        let rawData: NearbyStationResponse = JSON.parse(response.result as string);
        console.log('📡 API response code:', rawData.code);
        
        if (rawData && rawData.data && rawData.data.elecStationData) {
          console.log('🔍 Number of stations found:', rawData.data.elecStationData.length);
          
          // 将返回的任意对象数组，映射为 StationBrief 类型
          let stations: StationBrief[] = [];
          for (let i = 0; i < rawData.data.elecStationData.length; i++) {
            let item = rawData.data.elecStationData[i];
            
            // 检查API返回的数据是否包含经纬度
            console.log(`🏢 Station ${i}: ${item.stationName}`);
            console.log(`   - Has latitude: ${!!item.latitude}, Has longitude: ${!!item.longitude}`);
            
            // 计算距离
            let distance = 0;
            if (item.latitude && item.longitude) {
              distance = ChargerApi.calculateDistance(
                userLocation.latitude, 
                userLocation.longitude,
                item.latitude, 
                item.longitude
              );
              console.log(`   📏 Distance: ${distance}m (from user location: ${userLocation.latitude}, ${userLocation.longitude})`);
            } else {
              console.warn(`   ⚠️ Station ${item.stationName} has no latitude/longitude data`);
            }
            
            let stationBrief: StationBrief = {
              stationId: item.stationId || 0,
              stationName: item.stationName || "未知站点",
              address: item.address || "",
              freeNum: item.freeNum || 0,
              distance: distance,
              formattedDistance: ChargerApi.formatDistance(distance)
            };
            stations.push(stationBrief);
          }
          
          // 按距离排序（从近到远）
          stations.sort((a, b) => (a.distance || 0) - (b.distance || 0));
          
          console.log('✅ Nearby stations fetched and sorted by distance:', stations.length);
          console.log('📊 First station distance:', stations[0]?.distance, stations[0]?.formattedDistance);
          
          return stations;
        }
      }
    } catch (e) {
      console.error(`❌ Fetch nearby stations failed: ${e}`);
    }
    return [];
  }
}