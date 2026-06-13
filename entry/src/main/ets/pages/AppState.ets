// AppState.ets - 全局状态管理常量定义
import { ChargerConfig } from './ChargerModels';

// AppStorage 键名接口
interface AppStateKeysType {
  SYSTEM_DARK_MODE: string;
  THEME_MODE: string;
  STATION_CONFIG: string;
  CONFIGS: string;
  CURRENT_CONFIG: string;
}

// AppStorage 键名常量
export const AppStateKeys: AppStateKeysType = {
  // 系统主题状态（由 EntryAbility 设置）
  SYSTEM_DARK_MODE: 'systemDarkMode',
  // 应用主题模式
  THEME_MODE: 'app.themeMode',
  // 站点配置
  STATION_CONFIG: 'app.stationConfig',
  // 配置列表
  CONFIGS: 'app.configs',
  // 当前配置
  CURRENT_CONFIG: 'app.currentConfig'
};

// 状态类型定义
export interface AppStateType {
  systemDarkMode: boolean;
  themeMode: number;
  stationConfig: Record<string, number>;
  configs: ChargerConfig[];
  currentConfig: ChargerConfig | null;
}