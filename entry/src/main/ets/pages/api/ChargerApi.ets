// ChargerApi.ets - 纯 HTTP 请求层
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { OutletDetail, StationData, StationBrief, StationQueryResult, OutletStatus } from '../ChargerModels';
import { ApiConfig } from '../ApiConfig';
import { ErrorHandler } from '../utils/ErrorHandler';
import { calculateDistance, formatDistance } from '../utils/DistanceCalc';
import { LocationService } from '../services/LocationService';

interface PowerFeeData {
  billingPower?: string | number;
}

interface OutletDetailData {
  powerFee?: PowerFeeData;
  usedfee?: string | number;
  usedmin?: string | number;
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
  latitude?: number;
  longitude?: number;
  distance?: number;
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

export class ChargerApi {
  private static parseNonNegative(value: string | number | undefined): number | undefined {
    if (value === undefined || (typeof value === 'string' && !value.trim())) return undefined;
    const parsed = typeof value === 'number' ? value : parseFloat(value);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
  }

  // 获取单个插座的详情
  static async fetchOutletDetail(outletNo: string): Promise<Partial<OutletDetail>> {
    let httpRequest = http.createHttp();
    let url = ApiConfig.buildOutletDetailUrl(outletNo);

    try {
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: ApiConfig.getHeaders(),
        connectTimeout: ApiConfig.HTTP_CONFIG.CONNECT_TIMEOUT,
        readTimeout: ApiConfig.HTTP_CONFIG.READ_TIMEOUT
      });

      if (response.responseCode === 200) {
        let data = JSON.parse(response.result as string) as ApiResponseData;
        if (data.code == "1" && data.data) {
          let d = data.data as OutletDetailData;
          const powerValue = d.powerFee?.billingPower;
          let power = ChargerApi.parseNonNegative(powerValue);
          if (power !== undefined && typeof powerValue === 'string' && /kw/i.test(powerValue)) power *= 1000;
          if (power !== undefined && !Number.isFinite(power)) power = undefined;
          return {
            power_w: power,
            fee: ChargerApi.parseNonNegative(d.usedfee),
            used_min: ChargerApi.parseNonNegative(d.usedmin)
          };
        }
      }
    } catch (e) {
      ErrorHandler.handle(e, `ChargerApi.fetchOutletDetail[${outletNo}]`);
    } finally {
      httpRequest.destroy();
    }
    return {};
  }

  // 获取单个站点的所有插座
  static async fetchStation(stationId: number, stationName: string, maxRetries = 2): Promise<StationData | null> {
    let httpRequest = http.createHttp();
    let url = ApiConfig.buildStationOutletsUrl(stationId);

    try {
      for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
        try {
          console.log(`Fetching station ${stationName} (attempt ${attempt}/${maxRetries + 1})`);

          let response = await httpRequest.request(url, {
            method: http.RequestMethod.GET,
            header: ApiConfig.getHeaders(),
            connectTimeout: ApiConfig.HTTP_CONFIG.CONNECT_TIMEOUT,
            readTimeout: ApiConfig.HTTP_CONFIG.READ_TIMEOUT
          });

          if (response.responseCode === 200) {
            let data = JSON.parse(response.result as string) as ApiResponseData;
            if (data.code == "1" && Array.isArray(data.data)) {
              let outlets: OutletDetail[] = [];
              let promises: Promise<void>[] = [];

              const outletItems = data.data as OutletItem[];
              // 畸形或未知状态不能被计入“故障”，也不应静默少计插座。
              if (outletItems.some(item => !item || !Number.isInteger(item.outletSerialNo) ||
                (item.outletSerialNo as number) <= 0 || typeof item.outletNo !== 'string' || !item.outletNo.trim() ||
                ![OutletStatus.FREE, OutletStatus.OCCUPIED, OutletStatus.BROKEN].includes(item.currentChargingRecordId as number))) {
                return null;
              }
              if (outletItems.some((item, index) => outletItems.findIndex(other => other.outletNo === item.outletNo || other.outletSerialNo === item.outletSerialNo) !== index)) return null;
              for (let item of outletItems) {
                const status = item.currentChargingRecordId as number;
                let outlet: OutletDetail = {
                  serial: item.outletSerialNo as number,
                  outletNo: item.outletNo as string,
                  status: status
                };
                outlets.push(outlet);

                // 并发获取占用中的插座详情
                if (status === OutletStatus.OCCUPIED && outlet.outletNo) {
                  let p = ChargerApi.fetchOutletDetail(outlet.outletNo).then(detail => {
                    outlet.power_w = detail.power_w;
                    outlet.fee = detail.fee;
                    outlet.used_min = detail.used_min;
                  });
                  promises.push(p);
                }
              }
              await Promise.all<void>(promises);
              return { id: stationId, name: stationName, outlets: outlets };
            }
          }
        } catch (e) {
          ErrorHandler.handle(e, `ChargerApi.fetchStation[${stationName}] attempt ${attempt}`);

          if (attempt <= maxRetries) {
            await new Promise<void>(resolve => setTimeout(resolve, 1000 * attempt));
            continue;
          }
        }
      }

      console.error(`All attempts failed for station ${stationName}`);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  // 获取附近的站点列表
  static async fetchNearbyStations(context?: common.UIAbilityContext): Promise<StationQueryResult> {
    let httpRequest = http.createHttp();
    let url = ApiConfig.buildNearbyStationsUrl();

    try {
      // 通过 LocationService 获取位置（含权限重试）
      const locationResult = await LocationService.getLocationWithPermissionRetry(context);
      const userLocation = locationResult.location;
      const locationStatus = locationResult.status;

      if (locationResult.needOpenLocationService) {
        return {
          stations: [],
          locationStatus: locationStatus,
          needOpenLocationService: true
        };
      }

      let payload: NearbyStationPayload = {
        page: 1,
        pageSize: 200,
        scale: 3,
        latitude: userLocation.latitude,
        longitude: userLocation.longitude,
        userLatitude: userLocation.latitude,
        userLongitude: userLocation.longitude
      };

      let response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: ApiConfig.getHeaders(),
        extraData: JSON.stringify(payload),
        connectTimeout: ApiConfig.HTTP_CONFIG.CONNECT_TIMEOUT,
        readTimeout: ApiConfig.HTTP_CONFIG.READ_TIMEOUT
      });

      if (response.responseCode === 200) {
        let rawData = JSON.parse(response.result as string) as NearbyStationResponse;

        if (rawData && rawData.code == "1" && rawData.data && Array.isArray(rawData.data.elecStationData)) {
          let stations: StationBrief[] = [];
          for (let i = 0; i < rawData.data.elecStationData.length; i++) {
            const item = rawData.data.elecStationData[i];
            if (!item || !Number.isInteger(item.stationId) || (item.stationId as number) <= 0 ||
              typeof item.stationName !== 'string' || !item.stationName.trim() ||
              stations.some(station => station.stationId === item.stationId)) continue;

            let distance: number | undefined = undefined;
            if (item.latitude !== undefined && item.longitude !== undefined &&
              Number.isFinite(item.latitude) && Number.isFinite(item.longitude) &&
              Math.abs(item.latitude) <= 90 && Math.abs(item.longitude) <= 180) {
              distance = calculateDistance(
                userLocation.latitude,
                userLocation.longitude,
                item.latitude,
                item.longitude
              );
            }

            let stationBrief: StationBrief = {
              stationId: item.stationId || 0,
              stationName: item.stationName || "未知站点",
              address: typeof item.address === 'string' ? item.address : '',
              freeNum: Number.isInteger(item.freeNum) && (item.freeNum as number) >= 0 ? item.freeNum as number : -1,
              distance: distance,
              formattedDistance: distance === undefined ? '距离未知' : formatDistance(distance)
            };
            stations.push(stationBrief);
          }

          stations.sort((a, b) => (a.distance === undefined ? Number.MAX_VALUE : a.distance) - (b.distance === undefined ? Number.MAX_VALUE : b.distance));

          return {
            stations: stations,
            locationStatus: locationStatus
          };
        } else {
          return {
            stations: [],
            locationStatus: locationStatus + "，API返回数据无效"
          };
        }
      } else {
        return {
          stations: [],
          locationStatus: locationStatus + "，网络请求失败"
        };
      }
    } catch (e) {
      ErrorHandler.handle(e, 'ChargerApi.fetchNearbyStations');
      return {
        stations: [],
        locationStatus: "加载失败: " + ErrorHandler.getErrorMessage(e)
      };
    } finally {
      httpRequest.destroy();
    }
  }
}
