// ConfigManager.ets
import { StationNames } from './utils/StationNames';
import { PresetConfigs } from './PresetConfigs';
import { ChargerConfig, ConfigStationMember, ConfigStorage, StationBrief } from './ChargerModels';
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
    // 与写操作共用队列，升级后的首次读取不会与用户的新修改互相覆盖。
    return ConfigManager.enqueueWrite(() => ConfigManager.readConfigs(true));
  }

  private static async readConfigs(persistMigration: boolean = false): Promise<ConfigStorage> {
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
    const migrating = configs.some(config => config && (config.members === undefined || config.id === 'preset_d'));
    const ids: string[] = [];
    for (const config of configs) {
      if (!config || typeof config.id !== 'string' || !config.id.trim() || ids.includes(config.id) ||
        typeof config.name !== 'string' || !config.name.trim() || typeof config.createdAt !== 'number' ||
        !config.stations || typeof config.stations !== 'object' || Array.isArray(config.stations) ||
        Object.keys(config.stations).some(name => !name.trim() || !Number.isInteger(config.stations[name]) || config.stations[name] <= 0)) {
        throw new Error('配置记录异常，原数据已保留');
      }
      if (config.stationNames !== undefined && (!config.stationNames || typeof config.stationNames !== 'object' ||
        Array.isArray(config.stationNames) || Object.keys(config.stationNames).some(key => typeof config.stationNames![key] !== 'string' || !config.stationNames![key].trim()))) {
        throw new Error('配置原站名记录异常，原数据已保留');
      }
      ConfigManager.prepareMembers(config);
      ids.push(config.id);
    }
    const deleted = storage.deletedPresetIds || [];
    if (deleted.some(id => typeof id !== 'string')) throw new Error('配置删除记录异常，原数据已保留');
    storage.deletedPresetIds = deleted.filter((id, index) => deleted.indexOf(id) === index);
    const custom = configs.filter(config => config.id !== 'preset_d' && !PresetConfigs.isPreset(config.id));
    const presets = PresetConfigs.create().filter(config => !deleted.includes(config.id))
      .map(preset => configs.find(config => config.id === preset.id) || preset);
    storage.configs = [...presets, ...custom];
    storage.configs.filter(config => !config.members).forEach(config => ConfigManager.prepareMembers(config));
    if (!storage.configs.some(config => config.id === storage.currentConfigId)) {
      storage.currentConfigId = storage.configs.length ? storage.configs[0].id : undefined;
    }
    if (persistMigration && migrating) await ConfigManager.saveConfigs(storage);
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

  private static validateConfig(name: string, stations: Record<string, number>, configs: ChargerConfig[], excludedId: string = '', allowEmpty: boolean = false): void {
    const normalized = name.trim();
    if (!normalized || normalized.length > 24) throw new Error('配置名称需为 1～24 个字符');
    if (configs.some(config => config.id !== excludedId && config.name.trim().toLowerCase() === normalized.toLowerCase())) {
      throw new Error('配置名称已存在，请换一个名称');
    }
    const names = Object.keys(stations);
    if (!allowEmpty && names.length === 0) throw new Error('请至少保留一个站点');
    if (names.some(key => !key.trim() || !Number.isInteger(stations[key]) || stations[key] <= 0)) {
      throw new Error('站点信息无效，请重新选择');
    }
    const ids = Object.values(stations);
    if (ids.some((id, index) => ids.indexOf(id) !== index)) throw new Error('配置中不能包含重复站点');
  }

  private static sourceNamesFor(stations: Record<string, number>, sources?: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    if (sources && Object.keys(sources).some(key => typeof sources[key] !== 'string' || !sources[key].trim())) {
      throw new Error('站点原名无效，请重新选择');
    }
    Object.keys(stations).forEach(display => {
      const key = String(stations[display]);
      const source = sources ? sources[key] : '';
      result[key] = typeof source === 'string' && source.trim() ? source.trim() : display;
    });
    return result;
  }

  private static prepareMembers(config: ChargerConfig): void {
    if (config.members === undefined) {
      const sources = ConfigManager.sourceNamesFor(config.stations, config.stationNames);
      config.members = Object.keys(config.stations).map((display: string): ConfigStationMember => {
        const id = config.stations[display];
        const original = sources[String(id)];
        return { stationId: id, originalName: original, alias: StationNames.isAlias(display, original, id) ? display : '',
          note: '', paused: false };
      });
    }
    if (!Array.isArray(config.members)) throw new Error('配置成员格式异常，原数据已保留');
    const reserved: Record<string, number> = {};
    const labels: Map<number, string> = new Map();
    const seen: Set<number> = new Set();
    const originalNames: Record<string, string> = {};
    for (const member of config.members) {
      if (!member || !Number.isInteger(member.stationId) || member.stationId <= 0 || seen.has(member.stationId) ||
        typeof member.originalName !== 'string' || !member.originalName.trim() || typeof member.alias !== 'string' ||
        typeof member.note !== 'string' || member.note.length > 200 || typeof member.paused !== 'boolean') {
        throw new Error('配置成员记录异常，原数据已保留');
      }
      seen.add(member.stationId);
      originalNames[String(member.stationId)] = member.originalName;
      if (member.alias) {
        if (member.alias === '__proto__' || StationNames.taken(reserved, member.alias)) throw new Error('此配置中已存在同名或无效别名');
        reserved[member.alias] = member.stationId;
        labels.set(member.stationId, member.alias);
      }
    }
    const previous = new Map<number, string>();
    Object.keys(config.stations).forEach(display => previous.set(config.stations[display], display));
    // 保留已有的自动消歧名称；重新排序和移除邻站不会使同名站互换标签。
    for (const member of config.members) {
      const old = previous.get(member.stationId);
      if (!member.alias && old && old !== '__proto__' && !StationNames.isAlias(old, member.originalName, member.stationId) &&
        !StationNames.taken(reserved, old)) {
        reserved[old] = member.stationId;
        labels.set(member.stationId, old);
      }
    }
    const projection: Record<string, number> = {};
    for (const member of config.members) {
      const display = labels.get(member.stationId) || StationNames.unique(reserved, member.originalName, member.stationId);
      reserved[display] = member.stationId;
      projection[display] = member.stationId;
    }
    config.stations = projection;
    config.stationNames = originalNames;
  }

  static activeStations(config: ChargerConfig | null): Record<string, number> {
    if (!config) return {};
    const paused = new Set<number>((config.members || []).filter(item => item.paused).map(item => item.stationId));
    const result: Record<string, number> = {};
    Object.keys(config.stations).forEach(name => {
      if (!paused.has(config.stations[name])) result[name] = config.stations[name];
    });
    return result;
  }

  private static member(config: ChargerConfig, id: number): ConfigStationMember {
    const item = config.members!.find(member => member.stationId === id);
    if (!item) throw new Error('站点已不在此配置中，请重新读取');
    return item;
  }

  static copyName(name: string, configs: ChargerConfig[]): string {
    const names = new Set<string>(configs.map(config => config.name.trim().toLowerCase()));
    for (let index = 1; ; index++) {
      const suffix = index === 1 ? ' 副本' : ` 副本 ${index}`;
      const copy = name.slice(0, 24 - suffix.length).trimEnd() + suffix;
      if (!names.has(copy.toLowerCase())) return copy;
    }
  }

  private static validateStation(station: StationBrief): string {
    if (!Number.isInteger(station.stationId) || station.stationId <= 0 || !station.stationName.trim()) throw new Error('站点信息无效，请重新选择');
    return station.stationName.trim();
  }

  private static async changeConfig(configId: string, change: (config: ChargerConfig) => void, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.enqueueWrite(async () => {
      const storage = await ConfigManager.readConfigs();
      const config = storage.configs.find(item => item.id === configId);
      if (!config) throw new Error('配置不存在或已被删除');
      change(config);
      ConfigManager.prepareMembers(config);
      ConfigManager.validateConfig(config.name, config.stations, storage.configs, configId, true);
      await ConfigManager.saveConfigs(storage);
      ConfigManager.emitCommit(storage, configId, onCommitted);
    });
  }

  static async addStations(configId: string, stations: StationBrief[], onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      for (const station of stations) {
        const source = ConfigManager.validateStation(station);
        if (config.members!.some(member => member.stationId === station.stationId)) continue;
        config.members!.push({ stationId: station.stationId, originalName: source, alias: '', note: '', paused: false });
      }
    }, onCommitted);
  }

  static async editStation(configId: string, stationId: number, aliasInput: string | undefined, note: string | undefined,
    paused: boolean | undefined, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      const member = ConfigManager.member(config, stationId);
      if (aliasInput !== undefined) {
        const alias = aliasInput.trim();
        if (alias === '__proto__') throw new Error('此站点别名不可用，请换一个名称');
        if (alias.length > 40) throw new Error('站点别名不能超过 40 个字符');
        if (alias && StationNames.taken(config.stations, alias, stationId)) throw new Error('此配置中已存在同名站点，请换一个别名');
        member.alias = alias;
      }
      if (note !== undefined && note.length > 200) throw new Error('站点备注不能超过 200 个字符');
      if (note !== undefined) member.note = note.trim();
      if (paused !== undefined) member.paused = paused;
    }, onCommitted);
  }

  static async renameStation(configId: string, stationId: number, displayName: string, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.editStation(configId, stationId, displayName, undefined, undefined, onCommitted);
  }

  static async replaceStation(configId: string, stationId: number, station: StationBrief, onCommitted?: ConfigCommitListener,
    keepNote: boolean = false): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      const member = ConfigManager.member(config, stationId);
      const source = ConfigManager.validateStation(station);
      if (config.members!.some(item => item.stationId === station.stationId)) throw new Error('目标站点已在此配置中，不能重复替换');
      member.stationId = station.stationId;
      member.originalName = source;
      if (!keepNote) member.note = '';
    }, onCommitted);
  }

  static async moveStation(configId: string, stationId: number, offset: number, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      const members = config.members!;
      const index = members.indexOf(ConfigManager.member(config, stationId));
      const dest = index + offset;
      if (Math.abs(offset) !== 1 || dest < 0 || dest >= members.length) throw new Error('站点已位于边界，请重新查看顺序');
      const item = members.splice(index, 1)[0];
      members.splice(dest, 0, item);
    }, onCommitted);
  }

  static async removeStations(configId: string, stationIds: number[], onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      if (!stationIds.length) throw new Error('请先选择要移除的站点');
      const ids = new Set<number>(stationIds);
      ids.forEach(id => { ConfigManager.member(config, id); });
      config.members = config.members!.filter(item => !ids.has(item.stationId));
    }, onCommitted);
  }

  static async removeStation(configId: string, stationId: number, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.removeStations(configId, [stationId], onCommitted);
  }

  static async renameConfig(configId: string, name: string, onCommitted?: ConfigCommitListener): Promise<void> {
    return ConfigManager.changeConfig(configId, config => {
      if (PresetConfigs.isPreset(config.id)) throw new Error('默认配置名称不能修改');
      config.name = name.trim();
    }, onCommitted);
  }

  // 添加新配置
  static async addConfig(name: string, stations: Record<string, number>, onCommitted?: ConfigCommitListener, stationNames?: Record<string, string>, memberSeed?: ConfigStationMember[]): Promise<ChargerConfig> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.readConfigs();
      ConfigManager.validateConfig(name, stations, configStorage.configs, '', true);
    
      const newConfig: ChargerConfig = {
        id: ConfigManager.generateId(),
        name: name.trim(),
        stations: stations,
        stationNames: ConfigManager.sourceNamesFor(stations, stationNames),
        createdAt: Date.now()
      };
      ConfigManager.prepareMembers(newConfig);
      if (memberSeed) {
        const incoming = newConfig.members!;
        const copied: ConfigStationMember[] = [];
        for (const source of memberSeed) {
          const selected = incoming.find(member => member.stationId === source.stationId);
          if (selected) copied.push({ stationId: selected.stationId, originalName: source.originalName,
            alias: source.alias, note: source.note, paused: source.paused });
        }
        newConfig.members = [...copied, ...incoming.filter(member => !copied.some(copy => copy.stationId === member.stationId))];
        ConfigManager.prepareMembers(newConfig);
      }
    
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
      const configStorage = await ConfigManager.readConfigs();
      const configIndex = configStorage.configs.findIndex(config => config.id === configId);
    
      if (configIndex === -1) return false;
      const previous = configStorage.configs[configIndex];
      if (PresetConfigs.isPreset(configId) && name.trim() !== previous.name) throw new Error('默认配置名称不能修改');
      ConfigManager.validateConfig(name, stations, configStorage.configs, configId, true);
    
      // 创建一个新的配置对象而不是使用展开操作符
      const updatedConfig: ChargerConfig = {
        id: configStorage.configs[configIndex].id,
        name: name.trim(),
        stations: stations,
        stationNames: ConfigManager.sourceNamesFor(stations, previous.stationNames),
        createdAt: configStorage.configs[configIndex].createdAt
      };
    
      ConfigManager.prepareMembers(updatedConfig);
      for (const member of updatedConfig.members!) {
        const old = previous.members?.find(item => item.stationId === member.stationId);
        if (old) { member.paused = old.paused; member.note = old.note; }
      }
      configStorage.configs[configIndex] = updatedConfig;
    
      await ConfigManager.saveConfigs(configStorage);
      ConfigManager.emitCommit(configStorage, configId, onCommitted);
      return true;
    });
  }

  // 删除配置
  static async deleteConfig(configId: string, onCommitted?: ConfigCommitListener): Promise<boolean> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.readConfigs();
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
      const storage = await ConfigManager.readConfigs();
      const missing = PresetConfigs.create().filter(preset => !storage.configs.some(config => config.id === preset.id));
      if (missing.some(preset => storage.configs.some(config => config.name.trim().toLowerCase() === preset.name.toLowerCase()))) {
        throw new Error('已有与默认配置同名的配置，请先重命名后恢复');
      }
      missing.forEach(config => ConfigManager.prepareMembers(config));
      storage.deletedPresetIds = [];
      storage.configs = [...storage.configs, ...missing];
      if (!storage.configs.some(config => config.id === storage.currentConfigId)) storage.currentConfigId = storage.configs.length ? storage.configs[0].id : undefined;
      await ConfigManager.saveConfigs(storage);
      ConfigManager.emitCommit(storage, '', onCommitted);
    });
  }

  // 设置当前配置
  static async setCurrentConfig(configId: string, onCommitted?: ConfigCommitListener): Promise<boolean> {
    return ConfigManager.enqueueWrite(async () => {
      const configStorage = await ConfigManager.readConfigs();
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
