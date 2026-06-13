// ChargerApi.ets - 纯 HTTP 请求层
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import { OutletDetail, StationData, StationBrief, StationQueryResult, OutletStatus } from '../ChargerModels';
import { ApiConfig } from '../ApiConfig';
import { ErrorHandler } from '../utils/ErrorHandler';
import { calculateDistance, formatDistance } from '../utils/DistanceCalc';
import { LocationService } from '../services/LocationService';

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
            if (data.code == "1") {
              let outlets: OutletDetail[] = [];
              let promises: Promise<void>[] = [];

              let outletItems = data.data as OutletItem[] || [];
              for (let item of outletItems) {
                let rawStatus = item.currentChargingRecordId || 0;
                let status = [OutletStatus.FREE, OutletStatus.OCCUPIED, OutletStatus.BROKEN].includes(rawStatus) ? rawStatus : OutletStatus.BROKEN;

                let outlet: OutletDetail = {
                  serial: item.outletSerialNo || 0,
                  outletNo: item.outletNo || "",
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

        if (rawData && rawData.data && rawData.data.elecStationData) {
          let stations: StationBrief[] = [];
          for (let i = 0; i < rawData.data.elecStationData.length; i++) {
            let item = rawData.data.elecStationData[i];

            let distance = 0;
            if (item.latitude && item.longitude) {
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
              address: item.address || "",
              freeNum: item.freeNum || 0,
              distance: distance,
              formattedDistance: formatDistance(distance)
            };
            stations.push(stationBrief);
          }

          stations.sort((a, b) => (a.distance || 0) - (b.distance || 0));

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