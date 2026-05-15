// ChargerApi.ets
import http from '@ohos.net.http';
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

interface NearbyStationResponse {
  code: string;
  data?: {
    elecStationData?: any[];
  };
}

export class ChargerApi {
  // 获取单个插座的详情（功率、费用、时长）
  static async fetchOutletDetail(outletNo: string): Promise<Partial<OutletDetail>> {
    let httpRequest = http.createHttp();
    let url = `https://wemp.issks.com/charge/v1/charging/outlet/${outletNo}`;

    try {
      let response = await httpRequest.request(url, { method: http.RequestMethod.GET, header: HEADERS });
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

  // 获取单个站点的所有插座
  static async fetchStation(stationId: number, stationName: string): Promise<StationData | null> {
    let httpRequest = http.createHttp();
    let url = `https://wemp.issks.com/charge/v1/outlet/station/outlets/${stationId}`;

    try {
      let response = await httpRequest.request(url, { method: http.RequestMethod.GET, header: HEADERS });
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
          await Promise.all(promises);
          return { id: stationId, name: stationName, outlets: outlets };
        }
      }
    } catch (e) {
      console.error(`Fetch station failed: ${e}`);
    }
    return null;
  }

  // 新增：获取附近的站点列表 (用于 Picker)
  static async fetchNearbyStations(): Promise<StationBrief[]> {
    let httpRequest = http.createHttp();
    let url = "https://wemp.issks.com/device/v1/near/station";

    // 参照 Python 原项目的固定 Payload
    let payload = {
      page: 1,
      pageSize: 200,
      scale: 3,
      latitude: 30.74566536567867,
      longitude: 103.92188101700906,
      userLatitude: 30.74566536567867,
      userLongitude: 103.92188101700906
    };

    try {
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: HEADERS,
        extraData: JSON.stringify(payload)
      });

      if (response.responseCode === 200) {
        let rawData: NearbyStationResponse = JSON.parse(response.result as string);
        if (rawData && rawData.data && rawData.data.elecStationData) {
          // 将返回的任意对象数组，映射为 StationBrief 类型
          let stations: StationBrief[] = [];
          for (let i = 0; i < rawData.data.elecStationData.length; i++) {
            let item = rawData.data.elecStationData[i];
            stations.push({
              stationId: item.stationId || 0,
              stationName: item.stationName || "未知站点",
              address: item.address || "",
              freeNum: item.freeNum || 0
            });
          }
          return stations;
        }
      }
    } catch (e) {
      console.error(`Fetch nearby stations failed: ${e}`);
    }
    return [];
  }
}