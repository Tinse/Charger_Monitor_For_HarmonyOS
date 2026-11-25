import { ChargerConfig } from './ChargerModels';

// 2026-11-25 根据服务端站点名称、校区地址及坐标核对；详见 docs/stations.md。
export class PresetConfigs {
  static isPreset(id: string): boolean {
    return ['preset_d', 'preset_main_c', 'preset_street'].includes(id);
  }

  static create(): ChargerConfig[] {
    return [
      { id: "preset_d", name: "D区", createdAt: 0, stations: {"D区1号充电桩": 177972, "D区2号充电桩": 177970, "D区3号充电桩": 177968} },
      { id: "preset_main_c", name: "主楼C区", createdAt: 0, stations: {"清水河校区主楼C 区停车场1号充电桩": 74677, "清水河校区主楼C 区停车场2号充电桩": 74746, "清水河校区主楼C 区停车场3号充电桩": 74719} },
      { id: "preset_street", name: "商业街", createdAt: 0, stations: {"清水河商业街1号电站": 56934, "清水河商业街2号电站": 56924, "清水河商业街3号电站": 56929, "清水河商业街4号电站": 56922, "清水河校区商业街5号电站": 51641, "清水河商业街6号电站": 67951, "清水河商业街7号充电桩": 120161, "清水河校区商业街8号电站": 120170, "清水河商业街9号电站": 88939, "清水河商业街10号充电桩": 252437, "清水河商业街11号充电桩": 252403, "清水河商业街12号充电桩": 252348, "清水河商业街13号充电桩": 252755, "清水河商业街14号充电桩": 252339, "清水河商业街15号充电桩": 252463, "清水河商业街16号充电桩": 172650, "清水河商业街17号充电桩": 165008, "清水河商业街18号充电桩": 164998, "清水河商业街商业街19号充电桩": 165000} },
    ];
  }
}
