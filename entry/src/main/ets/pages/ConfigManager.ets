// ConfigManager.ets
import { ChargerConfig, ConfigStorage } from './ChargerModels';
import preferences from '@ohos.data.preferences';

const STORAGE_KEY = 'charger_configs';

// 全局Preferences实例
let preferencesInstance: preferences.Preferences | null = null;

// 初始化Preferences
async function initPreferences(): Promise<preferences.Preferences> {
  if (preferencesInstance) {
    return preferencesInstance;
  }
  
  try {
    preferencesInstance = await preferences.getPreferences(getContext(), STORAGE_KEY);
    return preferencesInstance;
  } catch (error) {
    console.error('Failed to initialize preferences:', error);
    throw new Error('Failed to initialize preferences');
  }
}

export class ConfigManager {
  // 生成唯一ID
  private static generateId(): string {
    return 'config_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  // 获取所有配置
  static async getConfigs(): Promise<ConfigStorage> {
    try {
      const prefs = await initPreferences();
      const configJson = await prefs.get(STORAGE_KEY, '{}');
      
      if (typeof configJson === 'string') {
        const configStorage: ConfigStorage = JSON.parse(configJson);
        
        // 验证配置数据格式
        if (!configStorage.configs) {
          configStorage.configs = [];
        }
        if (!configStorage.currentConfigId && configStorage.configs.length > 0) {
          configStorage.currentConfigId = configStorage.configs[0].id;
        }
        
        return configStorage;
      }
      
      return ConfigManager.getDefaultConfigStorage();
    } catch (error) {
      console.error('Failed to get configs:', error);
      return ConfigManager.getDefaultConfigStorage();
    }
  }

  // 保存配置
  static async saveConfigs(configStorage: ConfigStorage): Promise<void> {
    try {
      const prefs = await initPreferences();
      
      // 验证配置数据
      if (!configStorage.configs) {
        configStorage.configs = [];
      }
      
      await prefs.put(STORAGE_KEY, JSON.stringify(configStorage));
      await prefs.flush(); // 确保数据写入磁盘
      
      console.log('Config saved successfully');
    } catch (error) {
      console.error('Failed to save configs:', error);
      throw new Error('Failed to save configs');
    }
  }

  // 添加新配置
  static async addConfig(name: string, stations: Record<string, number>): Promise<ChargerConfig> {
    const configStorage = await ConfigManager.getConfigs();
    
    const newConfig: ChargerConfig = {
      id: ConfigManager.generateId(),
      name: name,
      stations: stations,
      createdAt: Date.now()
    };
    
    configStorage.configs.push(newConfig);
    
    // 如果是第一个配置，设为当前配置
    if (configStorage.configs.length === 1) {
      configStorage.currentConfigId = newConfig.id;
    }
    
    await ConfigManager.saveConfigs(configStorage);
    return newConfig;
  }

  // 更新配置
  static async updateConfig(configId: string, name: string, stations: Record<string, number>): Promise<boolean> {
    const configStorage = await ConfigManager.getConfigs();
    const configIndex = configStorage.configs.findIndex(config => config.id === configId);
    
    if (configIndex === -1) return false;
    
    // 创建一个新的配置对象而不是使用展开操作符
    const updatedConfig: ChargerConfig = {
      id: configStorage.configs[configIndex].id,
      name: name,
      stations: stations,
      createdAt: configStorage.configs[configIndex].createdAt
    };
    
    configStorage.configs[configIndex] = updatedConfig;
    
    await ConfigManager.saveConfigs(configStorage);
    return true;
  }

  // 删除配置
  static async deleteConfig(configId: string): Promise<boolean> {
    const configStorage = await ConfigManager.getConfigs();
    const configIndex = configStorage.configs.findIndex(config => config.id === configId);
    
    if (configIndex === -1) return false;
    
    configStorage.configs.splice(configIndex, 1);
    
    // 如果删除的是当前配置，选择另一个配置
    if (configStorage.currentConfigId === configId) {
      configStorage.currentConfigId = configStorage.configs.length > 0 ? configStorage.configs[0].id : undefined;
    }
    
    await ConfigManager.saveConfigs(configStorage);
    return true;
  }

  // 设置当前配置
  static async setCurrentConfig(configId: string): Promise<boolean> {
    const configStorage = await ConfigManager.getConfigs();
    const configExists = configStorage.configs.some(config => config.id === configId);
    
    if (!configExists) return false;
    
    configStorage.currentConfigId = configId;
    await ConfigManager.saveConfigs(configStorage);
    return true;
  }

  // 获取当前配置
  static async getCurrentConfig(): Promise<ChargerConfig | null> {
    const configStorage = await ConfigManager.getConfigs();
    
    if (!configStorage.currentConfigId) return null;
    
    return configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
  }

  // 获取默认配置（用于初始化）
  static getDefaultConfig(): Record<string, number> {
    return {
      "D区1号充电桩": 177972,
      "D区2号充电桩": 177970,
      "D区3号充电桩": 177968
    };
  }

  // 获取默认配置存储
  private static getDefaultConfigStorage(): ConfigStorage {
    return {
      configs: [],
      currentConfigId: undefined
    };
  }

  // 清除所有配置数据（用于测试）
  static async clearAllConfigs(): Promise<void> {
    try {
      const prefs = await initPreferences();
      await prefs.delete(STORAGE_KEY);
      await prefs.flush();
      console.log('All configs cleared');
    } catch (error) {
      console.error('Failed to clear configs:', error);
    }
  }
}