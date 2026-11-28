// ConfigService.ets - 配置管理 + 变更通知
import { ChargerConfig, ConfigStationMember, ConfigStorage, StationBrief } from '../ChargerModels';
import { ConfigManager } from '../ConfigManager';

import { StationService } from './StationService';

type ConfigChangeListener = (config: Record<string, number>, configObj: ChargerConfig | null) => void;

export class ConfigService {
  private static listeners: ConfigChangeListener[] = [];

  // 注册配置变更监听
  static addListener(listener: ConfigChangeListener): void {
    if (!ConfigService.listeners.includes(listener)) ConfigService.listeners.push(listener);
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
    // 已成功持久化的操作不能因某个界面回调异常而向调用者报告保存失败。
    for (const listener of [...ConfigService.listeners]) {
      try { listener(config, configObj); } catch (error) { console.error('Config listener failed:', error); }
    }
  }

  // 获取所有配置
  static async loadConfigs(): Promise<ConfigStorage> {
    const storage = await ConfigManager.getConfigs();
    ConfigService.retainSnapshots(storage);
    return storage;
  }

  // 获取当前配置的站点映射
  static async getCurrentStationConfig(): Promise<Record<string, number>> {
    const config = await ConfigManager.getCurrentConfig();
    return ConfigManager.activeStations(config);
  }

  // 获取当前配置对象
  static async getCurrentConfig(): Promise<ChargerConfig | null> {
    return ConfigManager.getCurrentConfig();
  }

  private static retainSnapshots(storage: ConfigStorage): void {
    const ids: Set<number> = new Set();
    storage.configs.forEach(config => Object.values(config.stations).forEach(id => ids.add(id)));
    try { StationService.retainStationIds(Array.from(ids)); } catch (error) { console.error('Snapshot retention failed:', error); }
  }

  private static afterCommit(storage: ConfigStorage, changedId: string, onlyIfCurrent: boolean = false): void {
    ConfigService.retainSnapshots(storage);
    const config = storage.configs.find(item => item.id === storage.currentConfigId) || null;
    if (onlyIfCurrent && (!config || config.id !== changedId)) return;
    ConfigService.notifyListeners(ConfigManager.activeStations(config), config);
  }

  // 写操作返回成功与持久化结果一致；通知使用写入成功时的快照，不依赖后置读取。
  static async switchConfig(configId: string): Promise<void> {
    const switched = await ConfigManager.setCurrentConfig(configId, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId);
    });
    if (!switched) throw new Error('配置不存在或已被删除');
  }

  static async addConfig(name: string, stations: Record<string, number>, stationNames?: Record<string, string>, memberSeed?: ConfigStationMember[]): Promise<ChargerConfig> {
    return ConfigManager.addConfig(name, stations, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    }, stationNames, memberSeed);
  }

  static async updateConfig(configId: string, name: string, stations: Record<string, number>): Promise<boolean> {
    return ConfigManager.updateConfig(configId, name, stations, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async deleteConfig(configId: string): Promise<boolean> {
    return ConfigManager.deleteConfig(configId, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId);
    });
  }

  static async restoreDefaultConfigs(): Promise<void> {
    return ConfigManager.restoreDefaultConfigs((storage, changedId) => {
      ConfigService.afterCommit(storage, changedId);
    });
  }

  static async addStations(configId: string, stations: StationBrief[]): Promise<void> {
    return ConfigManager.addStations(configId, stations, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async renameStation(configId: string, stationId: number, displayName: string): Promise<void> {
    return ConfigManager.renameStation(configId, stationId, displayName, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async replaceStation(configId: string, stationId: number, station: StationBrief, keepNote: boolean = false): Promise<void> {
    return ConfigManager.replaceStation(configId, stationId, station, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    }, keepNote);
  }

  static async removeStation(configId: string, stationId: number): Promise<void> {
    return ConfigManager.removeStation(configId, stationId, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async editStation(configId: string, stationId: number, alias: string | undefined, note: string | undefined,
    paused: boolean | undefined): Promise<void> {
    return ConfigManager.editStation(configId, stationId, alias, note, paused, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async moveStation(configId: string, stationId: number, offset: number): Promise<void> {
    return ConfigManager.moveStation(configId, stationId, offset, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async removeStations(configId: string, stationIds: number[]): Promise<void> {
    return ConfigManager.removeStations(configId, stationIds, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  static async renameConfig(configId: string, name: string): Promise<void> {
    return ConfigManager.renameConfig(configId, name, (storage, changedId) => {
      ConfigService.afterCommit(storage, changedId, true);
    });
  }

  // 获取默认配置
  static getDefaultConfig(): Record<string, number> {
    return ConfigManager.getDefaultConfig();
  }
}
