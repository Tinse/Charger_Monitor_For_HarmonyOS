// ConfigManager.ets
import { PresetConfigs } from './PresetConfigs';
import { ChargerConfig, ConfigStorage } from './ChargerModels';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORAGE_KEY = 'charger_configs';

export type ConfigCommitListener = (storage: ConfigStorage, changedId: string) => void;

// 全局Preferences实例
let preferencesPromise: Promise<preferences.Preferences> | null = null;

// 初始化Preferences
async function initPreferences(): Promise<preferences.Preferences> {
  if (!preferencesPromise) {
    throw new Error('ConfigManager must be initialized by EntryAbility');
  }
  return preferencesPromise;
}

export class ConfigManager {
  private static writeQueue: Promise<void> = Promise.resolve();

  // 队列覆盖完整的读取、修改和落盘过程，避免不同操作的旧快照相互覆盖。
  // 失败仅反馈给该次调用，后续操作仍继续；内部 saveConfigs 不再入队。
  private static enqueueWrite<T>(operation: () => Promise<T>): Promise<T> {
    const result = ConfigManager.writeQueue.then(operation);
    ConfigManager.writeQueue = result.then(() => {}, () => {});
    return result;
  }

  // 在同一串行操作内、落盘成功后发布快照，不再做可能失败的后置存储读取。
  private static emitCommit(storage: ConfigStorage, changedId: string, listener?: ConfigCommitListener): void {
    if (!listener) return;
    try {
      const snapshot = JSON.parse(JSON.stringify(storage)) as ConfigStorage;
      listener(snapshot, changedId);
    } catch (error) { console.error('Config commit listener failed:', error); }
  }

  // 在 Ability 创建时注入 Context，避免依赖已废弃的全局 getContext。
  static async initialize(context: common.Context): Promise<void> {
    try {
      if (!preferencesPromise) {
        preferencesPromise = preferences.getPreferences(context, { name: STORAGE_KEY });
      }
      await preferencesPromise;
    } catch (error) {
      preferencesPromise = null;
      throw new Error(`Failed to initialize preferences: ${(error as Error).message}`);
    }
  }

  // 生成唯一ID
  private static generateId(): string {
    return 'config_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  // 读取失败或数据损坏时停止后续写入，不能拿默认配置覆盖用户原数据。
  static async getConfigs(): Promise<ConfigStorage> {
    const prefs = await initPreferences();
    let configJson: preferences.ValueType;
    try {
      configJson = await prefs.get(STORAGE_KEY, '{}');
    } catch (error) {
      console.error('Failed to read configs:', error);
      throw new Error('配置读取失败，原数据已保留，请重试');
    }
    if (typeof configJson !== 'string') throw new Error('配置数据格式异常，原数据已保留');
    let storage: ConfigStorage;
    try {
      storage = JSON.parse(configJson) as ConfigStorage;
    } catch (error) {
      throw new Error('配置数据损坏，原数据已保留，请重试');
    }
    if (!storage || typeof storage !== 'object' || Array.isArray(storage) ||
      (storage.configs !== undefined && !Array.isArray(storage.configs)) ||
      (storage.deletedPresetIds !== undefined && !Array.isArray(storage.deletedPresetIds))) {
      throw new Error('配置数据结构异常，原数据已保留');
    }
    const configs = storage.configs || [];
    const ids: string[] = [];
    for (const config of configs) {
      if (!config || typeof config.id !== 'string' || !config.id.trim() || ids.includes(config.id) ||
        typeof config.name !== 'string' || !config.name.trim() || typeof config.createdAt !== 'number' ||
        !config.stations || typeof config.stations !== 'object' || Array.isArray(config.stations) ||
        Object.keys(config.stations).some(name => !name.trim() || !Number.isInteger(config.stations[name]) || config.stations[name] <= 0)) {
        throw new Error('配置记录异常，原数据已保留');
      }
      ids.push(config.id);
    }
    const deleted = storage.deletedPresetIds || [];
    if (deleted.some(id => typeof id !== 'string')) throw new Error('配置删除记录异常，原数据已保留');
    storage.deletedPresetIds = deleted.filter((id, index) => deleted.indexOf(id) === index);
    const custom = configs.filter(config => config.id !== 'preset_d' && !PresetConfigs.isPreset(config.id));
    storage.configs = [...PresetConfigs.create().filter(config => !deleted.includes(config.id)), ...custom];
    if (!storage.configs.some(config => config.id === storage.currentConfigId)) {
      storage.currentConfigId = storage.configs.length ? storage.configs[0].id : undefined;
    }
    return storage;
  }

  // put 会先更新 Preferences 内存值；flush 失败时恢复旧值，避免报错后悄悄带入下一次保存。
  private static async saveConfigs(configStorage: ConfigStorage): Promise<void> {
    const prefs = await initPreferences();
    let previous: preferences.ValueType;
    try { previous = await prefs.get(STORAGE_KEY, '{}'); } catch (error) {
      throw new Error('配置读取失败，原数据已保留，请重试');
    }
    try {
      if (!configStorage.configs) configStorage.configs = [];
      await prefs.put(STORAGE_KEY, JSON.stringify(configStorage));
      await prefs.flush();
      console.log('Config saved successfully');
    } catch (error) {
      console.error('Failed to save configs:', error);
      try {
        await prefs.put(STORAGE_KEY, previous);
        await prefs.flush();
      } catch (rollbackError) {
        console.error('Failed to restore previous configs:', rollbackError);
        throw new Error('配置保存失败，请重新打开应用核对数据');
      }
      throw new Error('配置保存失败，原数据已保留，请重试');
    }
  }

  private static validateConfig(name: string, stations: Record<string, number>, configs: ChargerConfig[], excludedId: string = ''): void {
    const normalized = name.trim();
    if (!normalized || normalized.length > 24) throw new Error('配置名称需为 1～24 个字符');
    if (configs.some(config => config.id !== excludedId && config.name.trim().toLowerCase() === normalized.toLowerCase())) {
      throw new Error('配置名称已存在，请换一个名称');
    }
    const names = Object.keys(stations);
    if (names.length === 0) throw new Error('请至少保留一个站点');
    if (names.some(key => !key.trim() || !Number.isInteger(stations[key]) || stations[key] <= 0)) {
      throw new Error('站点信息无效，请重新选择');
    }
    const ids = Object.values(stations);
    if (ids.some((id, index) => ids.indexOf(id) !== index)) throw new Error('配置中不能包含重复站点');
  }

  // 添加新配置
  static async addConfig(name: string, stations: Record<string, number>, onCommitted?: ConfigCommitListener): Promise<ChargerConfig> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.getConfigs();
      ConfigManager.validateConfig(name, stations, configStorage.configs);
    
      const newConfig: ChargerConfig = {
        id: ConfigManager.generateId(),
        name: name.trim(),
        stations: stations,
        createdAt: Date.now()
      };
    
      configStorage.configs.push(newConfig);
    
      // 如果是第一个配置，设为当前配置
      if (configStorage.configs.length === 1) {
        configStorage.currentConfigId = newConfig.id;
      }
    
      await ConfigManager.saveConfigs(configStorage);
      ConfigManager.emitCommit(configStorage, newConfig.id, onCommitted);
      return newConfig;
    });
  }

  // 更新配置
  static async updateConfig(configId: string, name: string, stations: Record<string, number>, onCommitted?: ConfigCommitListener): Promise<boolean> {
    return ConfigManager.enqueueWrite(async () => {
      if (PresetConfigs.isPreset(configId)) return false;
      const configStorage = await ConfigManager.getConfigs();
      const configIndex = configStorage.configs.findIndex(config => config.id === configId);
    
      if (configIndex === -1) return false;
      ConfigManager.validateConfig(name, stations, configStorage.configs, configId);
    
      // 创建一个新的配置对象而不是使用展开操作符
      const updatedConfig: ChargerConfig = {
        id: configStorage.configs[configIndex].id,
        name: name.trim(),
        stations: stations,
        createdAt: configStorage.configs[configIndex].createdAt
      };
    
      configStorage.configs[configIndex] = updatedConfig;
    
      await ConfigManager.saveConfigs(configStorage);
      ConfigManager.emitCommit(configStorage, configId, onCommitted);
      return true;
    });
  }

  // 删除配置
  static async deleteConfig(configId: string, onCommitted?: ConfigCommitListener): Promise<boolean> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.getConfigs();
      const configIndex = configStorage.configs.findIndex(config => config.id === configId);
    
      if (configIndex === -1) return false;
    
      configStorage.configs.splice(configIndex, 1);
      if (PresetConfigs.isPreset(configId)) {
        const deleted = configStorage.deletedPresetIds || [];
        if (!deleted.includes(configId)) deleted.push(configId);
        configStorage.deletedPresetIds = deleted;
      }

      // 如果删除的是当前配置，选择另一个配置
      if (configStorage.currentConfigId === configId) {
        configStorage.currentConfigId = configStorage.configs.length > 0 ? configStorage.configs[0].id : undefined;
      }
    
      await ConfigManager.saveConfigs(configStorage);
      ConfigManager.emitCommit(configStorage, configId, onCommitted);
      return true;
    });
  }

  // 只在用户明确操作时恢复预设，不覆盖自定义配置或有效的当前选择。
  static async restoreDefaultConfigs(onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.enqueueWrite(async () => {
      const storage = await ConfigManager.getConfigs();
      const custom = storage.configs.filter(config => !PresetConfigs.isPreset(config.id));
      const presets = PresetConfigs.create();
      if (presets.some(preset => custom.some(config => config.name.trim().toLowerCase() === preset.name.toLowerCase()))) {
        throw new Error('已有与默认配置同名的自定义配置，请先重命名后恢复');
      }
      storage.deletedPresetIds = [];
      storage.configs = [...presets, ...custom];
      if (!storage.configs.some(config => config.id === storage.currentConfigId)) storage.currentConfigId = presets[0].id;
      await ConfigManager.saveConfigs(storage);
      ConfigManager.emitCommit(storage, '', onCommitted);
    });
  }

  // 设置当前配置
  static async setCurrentConfig(configId: string, onCommitted?: ConfigCommitListener): Promise<boolean> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.getConfigs();
      const configExists = configStorage.configs.some(config => config.id === configId);
    
      if (!configExists) return false;
    
      configStorage.currentConfigId = configId;
      await ConfigManager.saveConfigs(configStorage);
      ConfigManager.emitCommit(configStorage, configId, onCommitted);
      return true;
    });
  }

  // 获取当前配置
  static async getCurrentConfig(): Promise<ChargerConfig | null> {
    const configStorage = await ConfigManager.getConfigs();
    
    if (!configStorage.currentConfigId) return null;
    
    return configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
  }

  // 获取默认配置（用于初始化）
  static getDefaultConfig(): Record<string, number> {
    return PresetConfigs.create()[0].stations;
  }

  // 获取默认配置存储
  private static getDefaultConfigStorage(): ConfigStorage {
    return {
      configs: PresetConfigs.create(),
      currentConfigId: 'preset_main_c',
      deletedPresetIds: []
    };
  }

  // 清除所有配置数据（用于测试）
  static async clearAllConfigs(): Promise<void> {
    return ConfigManager.enqueueWrite(async () => {
      try {
        const prefs = await initPreferences();
        await prefs.delete(STORAGE_KEY);
        await prefs.flush();
        console.log('All configs cleared');
      } catch (error) {
        console.error('Failed to clear configs:', error);
      }
    });
  }
}
