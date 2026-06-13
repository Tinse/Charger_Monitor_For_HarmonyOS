// ConfigService.ets - 配置管理 + 变更通知
import { ChargerConfig, ConfigStorage } from '../ChargerModels';
import { ConfigManager } from '../ConfigManager';
import { StationService } from './StationService';

type ConfigChangeListener = (config: Record<string, number>, configObj: ChargerConfig | null) => void;

export class ConfigService {
  private static listeners: ConfigChangeListener[] = [];

  // 注册配置变更监听
  static addListener(listener: ConfigChangeListener): void {
    ConfigService.listeners.push(listener);
  }

  // 注销配置变更监听
  static removeListener(listener: ConfigChangeListener): void {
    const index = ConfigService.listeners.indexOf(listener);
    if (index > -1) {
      ConfigService.listeners.splice(index, 1);
    }
  }

  // 通知所有监听器
  private static notifyListeners(config: Record<string, number>, configObj: ChargerConfig | null): void {
    for (const listener of ConfigService.listeners) {
      listener(config, configObj);
    }
  }

  // 获取所有配置
  static async loadConfigs(): Promise<ConfigStorage> {
    return ConfigManager.getConfigs();
  }

  // 获取当前配置的站点映射
  static async getCurrentStationConfig(): Promise<Record<string, number>> {
    const config = await ConfigManager.getCurrentConfig();
    return config ? config.stations : ConfigManager.getDefaultConfig();
  }

  // 获取当前配置对象
  static async getCurrentConfig(): Promise<ChargerConfig | null> {
    return ConfigManager.getCurrentConfig();
  }

  // 切换配置
  static async switchConfig(configId: string): Promise<void> {
    await ConfigManager.setCurrentConfig(configId);
    StationService.clearCache();

    const config = await ConfigManager.getCurrentConfig();
    const stationConfig = config ? config.stations : ConfigManager.getDefaultConfig();
    ConfigService.notifyListeners(stationConfig, config);
  }

  // 添加配置
  static async addConfig(name: string, stations: Record<string, number>): Promise<ChargerConfig> {
    const newConfig = await ConfigManager.addConfig(name, stations);
    StationService.clearCache();

    // 如果是第一个配置，自动成为当前配置
    const configStorage = await ConfigManager.getConfigs();
    if (configStorage.currentConfigId === newConfig.id) {
      ConfigService.notifyListeners(stations, newConfig);
    }

    return newConfig;
  }

  // 更新配置
  static async updateConfig(configId: string, name: string, stations: Record<string, number>): Promise<boolean> {
    const result = await ConfigManager.updateConfig(configId, name, stations);
    if (result) {
      StationService.clearCache();

      // 如果更新的是当前配置，通知变更
      const currentConfig = await ConfigManager.getCurrentConfig();
      if (currentConfig && currentConfig.id === configId) {
        ConfigService.notifyListeners(stations, currentConfig);
      }
    }
    return result;
  }

  // 删除配置
  static async deleteConfig(configId: string): Promise<boolean> {
    const result = await ConfigManager.deleteConfig(configId);
    if (result) {
      StationService.clearCache();

      // 通知当前配置可能已变更
      const config = await ConfigManager.getCurrentConfig();
      const stationConfig = config ? config.stations : ConfigManager.getDefaultConfig();
      ConfigService.notifyListeners(stationConfig, config);
    }
    return result;
  }

  // 获取默认配置
  static getDefaultConfig(): Record<string, number> {
    return ConfigManager.getDefaultConfig();
  }
}
