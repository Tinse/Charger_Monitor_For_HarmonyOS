// LocationService.ets - 位置服务（定位获取、权限管理）
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, Permissions, common } from '@kit.AbilityKit';
import { ApiConfig } from '../ApiConfig';
import { ErrorHandler } from '../utils/ErrorHandler';

export interface LocationResult {
  latitude: number;
  longitude: number;
}

export interface LocationResolveResult {
  location: LocationResult;
  status: string;
  needOpenLocationService?: boolean;
}

// 权限常量
export const LOCATION_PERMISSIONS: Array<Permissions> = [
  'ohos.permission.LOCATION' as Permissions,
  'ohos.permission.APPROXIMATELY_LOCATION' as Permissions
];

export class LocationService {
  // 检查位置权限是否可用（尝试获取一次定位）
  static async checkLocationPermissions(): Promise<boolean> {
    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        maxAccuracy: 100,
        timeoutMs: 5000
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);
      return !!(location && location.latitude && location.longitude);
    } catch (error) {
      console.log('Location permission check failed:', error);
      return false;
    }
  }

  // 请求位置权限
  static async requestLocationPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const requestResult = await atManager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);

      const grantStatus: Array<number> = requestResult.authResults;
      for (let i = 0; i < grantStatus.length; i++) {
        if (grantStatus[i] !== 0) {
          console.log('Permission request denied for:', LOCATION_PERMISSIONS[i]);
          return false;
        }
      }

      console.log('All location permissions granted');
      return true;
    } catch (error) {
      ErrorHandler.handle(error, 'LocationService.requestLocationPermissions');
      return false;
    }
  }

  // 获取当前地理位置
  static async getCurrentLocation(): Promise<LocationResult> {
    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        maxAccuracy: 100,
        timeoutMs: 30000
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);

      if (location && location.latitude && location.longitude) {
        return {
          latitude: location.latitude,
          longitude: location.longitude
        };
      } else {
        throw new Error('Invalid location data received');
      }
    } catch (error) {
      ErrorHandler.handle(error, 'LocationService.getCurrentLocation');
      return {
        latitude: ApiConfig.DEFAULT_LATITUDE,
        longitude: ApiConfig.DEFAULT_LONGITUDE
      };
    }
  }

  // 获取位置（带权限重试）：先尝试定位 → 失败则请求权限 → 重试定位
  static async getLocationWithPermissionRetry(context?: common.UIAbilityContext): Promise<LocationResolveResult> {
    let userLocation: LocationResult = {
      latitude: ApiConfig.DEFAULT_LATITUDE,
      longitude: ApiConfig.DEFAULT_LONGITUDE
    };
    let locationStatus = "使用默认位置";

    // 第一次尝试获取位置
    let locationSuccess = false;

    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        maxAccuracy: 100,
        timeoutMs: 10000
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);

      if (location && location.latitude && location.longitude) {
        userLocation = {
          latitude: location.latitude,
          longitude: location.longitude
        };
        locationSuccess = true;
        locationStatus = "已获取实际位置";
      }
    } catch (error) {
      console.log('Location access failed:', error);
      locationSuccess = false;
    }

    // 如果获取位置失败，请求权限后重试
    if (!locationSuccess && context) {
      const granted = await LocationService.requestLocationPermissions(context);

      if (granted) {
        try {
          const requestInfo: geoLocationManager.CurrentLocationRequest = {
            priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
            maxAccuracy: 100,
            timeoutMs: 30000
          };

          const location = await geoLocationManager.getCurrentLocation(requestInfo);

          if (location && location.latitude && location.longitude) {
            userLocation = {
              latitude: location.latitude,
              longitude: location.longitude
            };
            locationSuccess = true;
            locationStatus = "已获取实际位置";
          }
        } catch (error) {
          ErrorHandler.handle(error, 'LocationService.getLocationWithPermissionRetry');
          return {
            location: userLocation,
            status: "定位服务未开启，使用默认位置",
            needOpenLocationService: true
          };
        }
      } else {
        locationStatus = "位置权限被拒绝，使用默认位置";
      }
    }

    return {
      location: userLocation,
      status: locationStatus
    };
  }
}
