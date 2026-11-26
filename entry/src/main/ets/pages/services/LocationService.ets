import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, Permissions, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
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

const LOCATION_PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

export class LocationService {
  private static async requestLocationPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const status = await manager.checkAccessToken(context.applicationInfo.accessTokenId,
        'ohos.permission.APPROXIMATELY_LOCATION');
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      const result = await manager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);
      // 用户只允许模糊定位时也可查询附近站点，不强求精确定位。
      return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      ErrorHandler.handle(error, 'LocationService.requestLocationPermissions');
      return false;
    }
  }

  static async getLocationWithPermissionRetry(context?: common.UIAbilityContext): Promise<LocationResolveResult> {
    const fallback: LocationResult = {
      latitude: ApiConfig.DEFAULT_LATITUDE,
      longitude: ApiConfig.DEFAULT_LONGITUDE
    };
    if (canIUse('SystemCapability.Location.Location.Core')) {
      try {
        if (!geoLocationManager.isLocationEnabled()) {
          return { location: fallback, status: '定位服务未开启，请开启后重新定位', needOpenLocationService: true };
        }
        if (context && !await LocationService.requestLocationPermissions(context)) {
          return { location: fallback, status: '位置权限被拒绝，使用默认位置' };
        }
        const request: geoLocationManager.CurrentLocationRequest = {
          priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
          maxAccuracy: 100,
          timeoutMs: 10000
        };
        const location = await geoLocationManager.getCurrentLocation(request);
        if (Number.isFinite(location.latitude) && Number.isFinite(location.longitude) &&
          Math.abs(location.latitude) <= 90 && Math.abs(location.longitude) <= 180) {
          return {
            location: { latitude: location.latitude, longitude: location.longitude },
            status: '已获取设备位置'
          };
        }
        return { location: fallback, status: '定位数据无效，使用默认位置' };
      } catch (error) {
        ErrorHandler.handle(error, 'LocationService.getLocationWithPermissionRetry');
        if ((error as BusinessError).code === 3301100) {
          return { location: fallback, status: '定位服务未开启，请开启后重新定位', needOpenLocationService: true };
        }
        return { location: fallback, status: '定位暂不可用，使用默认位置' };
      }
    }
    return { location: fallback, status: '设备不支持定位，使用默认位置' };
  }
}
