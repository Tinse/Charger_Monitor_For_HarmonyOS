// Run the actual non-UI ArkTS modules with the SDK's TypeScript compiler.
// Preferences is an in-memory adapter: device APIs are verified separately on HarmonyOS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const studio = process.env.DEVECO_CLI_STUDIO_PATH;
if (!studio) throw new Error('Set DEVECO_CLI_STUDIO_PATH to your DevEco Studio installation.');
const ts = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const storedValues = new Map();
let now = 1000000;
class TestDate extends Date {
  static now() { return now; }
}
const prefs = {
  get: async (key, fallback) => storedValues.has(key) ? storedValues.get(key) : fallback,
  put: async (key, value) => storedValues.set(key, value),
  flush: async () => {},
  delete: async key => storedValues.delete(key)
};
let storeOpenCount = 0;
const messages = [];
const cache = new Map();
const stationServiceStub = { clearCache: () => {} };

function load(relativePath, fresh = false) {
  const filename = path.resolve(root, relativePath);
  if (!fresh && cache.has(filename)) return cache.get(filename);
  const source = fs.readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  });
  const module = { exports: {} };
  cache.set(filename, module.exports);
  function localRequire(name) {
    if (name === '@kit.ArkData') return { preferences: {
      getPreferences: async (context, options) => {
        if (options === 'theme_store') {
          assert.equal(context.kind, 'UIAbilityContext');
          return prefs;
        }
        assert.equal(context.kind, 'ApplicationContext');
        assert.equal(options.name, 'charger_configs');
        storeOpenCount++;
        return prefs;
      }
    } };
    if (name === '@kit.AbilityKit') return { ConfigurationConstant: {
      ColorMode: { COLOR_MODE_NOT_SET: -1, COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1 }
    } };
    if (name === './StationService') return { StationService: stationServiceStub };
    if (!name.startsWith('.')) throw new Error(`Unexpected runtime dependency: ${name}`);
    return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
  }
  const context = vm.createContext({
    module, exports: module.exports, require: localRequire, Date: TestDate,
    console: { log: (...args) => messages.push(args.join(' ')), error: (...args) => messages.push(args.join(' ')) }
  });
  new vm.Script(result.outputText, { filename }).runInContext(context);
  return module.exports;
}

const base = 'entry/src/main/ets/pages/';
async function testAppearance() {
  const { ThemeManager, ThemeMode } = load(`${base}theme/ThemeManager.ets`);
  let systemColor;
  const context = {
    kind: 'UIAbilityContext',
    getApplicationContext: () => ({ setColorMode: mode => { systemColor = mode; } })
  };
  const getBeforeFailure = prefs.get;
  storedValues.set('theme_mode', ThemeMode.DARK);
  prefs.get = async () => { throw new Error('simulated read failure'); };
  const fallback = await ThemeManager.loadThemeMode(context);
  ThemeManager.applyThemeMode(context, fallback);
  assert.equal(storedValues.get('theme_mode'), ThemeMode.DARK, 'startup fallback must not rewrite user settings');
  prefs.get = getBeforeFailure;
  assert.equal(await ThemeManager.loadThemeMode(context), ThemeMode.DARK);
  const flushBeforeFailure = prefs.flush;
  prefs.flush = async () => { throw new Error('simulated flush failure'); };
  await assert.rejects(ThemeManager.changeThemeMode(context, ThemeMode.LIGHT, ThemeMode.DARK));
  assert.equal(storedValues.get('theme_mode'), ThemeMode.DARK);
  assert.equal(systemColor, ThemeManager.getColorModeConstant(ThemeMode.DARK));
  await assert.rejects(ThemeManager.saveImmersiveEnabled(context, false, true));
  assert.equal(await ThemeManager.loadImmersiveEnabled(context), true);
  prefs.flush = flushBeforeFailure;
  await ThemeManager.changeThemeMode(context, ThemeMode.LIGHT, ThemeMode.DARK);
  await ThemeManager.saveImmersiveEnabled(context, false, true);
  assert.equal(await ThemeManager.loadThemeMode(context), ThemeMode.LIGHT);
  assert.equal(await ThemeManager.loadImmersiveEnabled(context), false);
  storedValues.set('theme_mode', 99);
  assert.equal(await ThemeManager.loadThemeMode(context), ThemeMode.SYSTEM);
  console.log('PASS: read-only appearance startup, invalid values, save failure rollback and retry');
}

async function main() {
  await testAppearance();
  const { ConfigManager } = load(`${base}ConfigManager.ets`);
  const context = { kind: 'ApplicationContext' };
  await Promise.all([ConfigManager.initialize(context), ConfigManager.initialize(context)]);
  assert.equal(storeOpenCount, 1, 'concurrent initialization must open the store once');
  assert.equal((await ConfigManager.getConfigs()).configs.length, 2);
  assert.equal(Object.keys(ConfigManager.getDefaultConfig()).length, 3);

  const a = await ConfigManager.addConfig('A', { stationA: 101 });
  const b = await ConfigManager.addConfig('B', { stationB: 102 });
  assert.notEqual(a.id, b.id);
  assert.equal((await ConfigManager.getCurrentConfig()).id, 'preset_main_c');
  assert.equal(await ConfigManager.setCurrentConfig(b.id), true);
  assert.equal(await ConfigManager.updateConfig(b.id, 'B edited', { stationB: 102, stationC: 103 }), true);
  assert.equal((await ConfigManager.getCurrentConfig()).name, 'B edited');
  assert.equal(Object.keys((await ConfigManager.getCurrentConfig()).stations).length, 2);
  assert.equal(await ConfigManager.updateConfig('missing', 'bad', {}), false);
  assert.equal(await ConfigManager.setCurrentConfig('missing'), false);

  // Reload the module while keeping the adapter's persisted values.
  const reloaded = load(`${base}ConfigManager.ets`, true).ConfigManager;
  await reloaded.initialize(context);
  assert.equal((await reloaded.getCurrentConfig()).name, 'B edited');
  assert.equal(await reloaded.deleteConfig(b.id), true);
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_main_c');
  assert.equal(await reloaded.deleteConfig(a.id), true);
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_main_c');
  storedValues.set('charger_configs', '{invalid json');
  await assert.rejects(reloaded.getConfigs(), /损坏/);
  assert.equal(storedValues.get('charger_configs'), '{invalid json');

  const { PresetConfigs } = load(`${base}PresetConfigs.ets`);
  const presets = PresetConfigs.create();
  assert.deepEqual(Array.from(presets, p => Object.keys(p.stations).length), [3, 19]);
  assert.equal(await reloaded.updateConfig('preset_street', 'overwrite', {}), false);
  const legacy = { configs: [{ id: 'legacy', name: 'Old custom', stations: { custom: 88 }, createdAt: 123 }], currentConfigId: 'legacy' };
  storedValues.set('charger_configs', JSON.stringify(legacy));
  assert.equal((await reloaded.getConfigs()).configs.length, 3);
  assert.equal((await reloaded.getCurrentConfig()).id, 'legacy');
  assert.equal((await reloaded.getConfigs()).configs.length, 3, 'presets must not duplicate');
  const retired = { configs: [{ id: 'preset_d', name: 'D区', stations: { D: 177972 }, createdAt: 0 }, ...legacy.configs], currentConfigId: 'preset_d' };
  storedValues.set('charger_configs', JSON.stringify(retired));
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_main_c');
  assert.equal((await reloaded.getConfigs()).configs.some(config => config.id === 'preset_d'), false);
  assert.equal((await reloaded.getConfigs()).configs.some(config => config.id === 'legacy'), true);
  await assert.rejects(reloaded.addConfig('   ', { x: 10 }), /配置名称/);
  await assert.rejects(reloaded.addConfig('主楼C区', { x: 10 }), /已存在/);
  await assert.rejects(reloaded.addConfig('Empty', {}), /至少保留/);
  await assert.rejects(reloaded.updateConfig('legacy', 'Old custom', {}), /至少保留/);
  assert.equal(Object.keys((await reloaded.getConfigs()).configs.find(config => config.id === 'legacy').stations).length, 1);
  storedValues.set('charger_configs', JSON.stringify({ ...legacy, currentConfigId: 'missing' }));
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_main_c');

  // Explicit preset deletions survive repeated reads and process reloads.
  assert.equal(await reloaded.deleteConfig('preset_main_c'), true);
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_street');
  assert.equal((await reloaded.getConfigs()).configs.some(c => c.id === 'preset_main_c'), false);
  const afterDeletion = load(`${base}ConfigManager.ets`, true).ConfigManager;
  await afterDeletion.initialize(context);
  assert.equal((await afterDeletion.getConfigs()).configs.some(c => c.id === 'preset_main_c'), false);
  assert.equal(await afterDeletion.deleteConfig('preset_main_c'), false);
  assert.equal(await afterDeletion.deleteConfig('preset_street'), true);
  assert.equal((await afterDeletion.getCurrentConfig()).id, 'legacy');
  assert.equal(await afterDeletion.deleteConfig('legacy'), true);
  assert.equal((await afterDeletion.getConfigs()).configs.length, 0);
  assert.equal(await afterDeletion.getCurrentConfig(), null);
  const emptyReload = load(`${base}ConfigManager.ets`, true).ConfigManager;
  await emptyReload.initialize(context);
  assert.equal((await emptyReload.getConfigs()).configs.length, 0, 'empty state must survive reload');
  const namedAfterPreset = await emptyReload.addConfig('主楼C区', { retained: 99 });
  assert.equal((await emptyReload.getCurrentConfig()).id, namedAfterPreset.id);
  await assert.rejects(emptyReload.restoreDefaultConfigs(), /同名/);
  assert.equal((await emptyReload.getConfigs()).configs.length, 1, 'restore conflict must not overwrite custom');
  await emptyReload.updateConfig(namedAfterPreset.id, 'My saved configuration', { retained: 99 });
  await emptyReload.restoreDefaultConfigs();
  assert.equal((await emptyReload.getConfigs()).configs.length, 3);
  assert.equal((await emptyReload.getCurrentConfig()).id, namedAfterPreset.id, 'restore preserves current custom');
  await emptyReload.restoreDefaultConfigs();
  assert.equal((await emptyReload.getConfigs()).configs.length, 3, 'restore remains idempotent');
  assert.equal((await emptyReload.getConfigs()).deletedPresetIds.length, 0);
  await emptyReload.deleteConfig(namedAfterPreset.id);
  assert.equal((await emptyReload.getCurrentConfig()).id, 'preset_main_c');

  // All writers must serialize the full read-modify-save transaction.
  await emptyReload.clearAllConfigs();
  const parallelDeletes = await Promise.all([
    emptyReload.deleteConfig('preset_main_c'), emptyReload.deleteConfig('preset_street')
  ]);
  assert.deepEqual(parallelDeletes, [true, true]);
  assert.equal((await emptyReload.getConfigs()).configs.length, 0, 'parallel preset deletions must both persist');
  assert.equal((await emptyReload.getConfigs()).deletedPresetIds.length, 2);
  await Promise.all([emptyReload.restoreDefaultConfigs(), emptyReload.deleteConfig('preset_main_c')]);
  assert.deepEqual(Array.from((await emptyReload.getConfigs()).configs, config => config.id), ['preset_street'],
    'queued restore then delete must leave the later deletion intact');
  await Promise.all([emptyReload.deleteConfig('preset_street'), emptyReload.restoreDefaultConfigs()]);
  assert.equal((await emptyReload.getConfigs()).configs.length, 2, 'queued delete then restore must restore both presets');
  const [parallelA, parallelB] = await Promise.all([
    emptyReload.addConfig('Parallel A', { a: 11 }), emptyReload.addConfig('Parallel B', { b: 12 })
  ]);
  assert.equal((await emptyReload.getConfigs()).configs.length, 4, 'parallel additions must not overwrite each other');
  const afterFailedWrite = await Promise.allSettled([
    emptyReload.addConfig('主楼C区', { rejected: 13 }), emptyReload.addConfig('After failure', { kept: 14 })
  ]);
  assert.equal(afterFailedWrite[0].status, 'rejected');
  assert.equal(afterFailedWrite[1].status, 'fulfilled', 'failed validation must not block the writer queue');
  const originalPut = prefs.put;
  let failNextPut = true;
  prefs.put = async (key, value) => {
    if (failNextPut) { failNextPut = false; throw new Error('simulated preferences write failure'); }
    return originalPut(key, value);
  };
  const afterStorageFailure = await Promise.allSettled([
    emptyReload.addConfig('Failed disk write', { rejected: 16 }), emptyReload.addConfig('After disk failure', { kept: 17 })
  ]);
  prefs.put = originalPut;
  assert.equal(afterStorageFailure[0].status, 'rejected');
  assert.equal(afterStorageFailure[1].status, 'fulfilled', 'preferences write failure must not block the writer queue');
  assert.equal((await emptyReload.getConfigs()).configs.some(config => config.name === 'Failed disk write'), false);
  assert.equal((await emptyReload.getConfigs()).configs.some(config => config.name === 'After disk failure'), true);
  await Promise.all([
    emptyReload.updateConfig(parallelA.id, 'Parallel A edited', { a: 11, c: 15 }),
    emptyReload.setCurrentConfig(parallelB.id), emptyReload.deleteConfig(parallelB.id)
  ]);
  assert.equal((await emptyReload.getConfigs()).configs.find(config => config.id === parallelA.id).name, 'Parallel A edited');
  assert.equal((await emptyReload.getCurrentConfig()).id, 'preset_main_c');

  // A read failure or corrupted JSON must never be turned into a destructive default write.
  const savedBeforeReadFailure = storedValues.get('charger_configs');
  const originalGet = prefs.get;
  prefs.get = async () => { throw new Error('simulated preferences read failure'); };
  await assert.rejects(emptyReload.addConfig('Blocked by unreadable store', { blocked: 18 }), /配置读取失败/);
  prefs.get = originalGet;
  assert.equal(storedValues.get('charger_configs'), savedBeforeReadFailure);
  await emptyReload.addConfig('After read recovery', { kept: 19 });
  const savedBeforeCorruption = storedValues.get('charger_configs');
  for (const invalidData of ['{broken json', 'null', '[]', '{"configs":{}}', '{"configs":[null]}']) {
    storedValues.set('charger_configs', invalidData);
    await assert.rejects(emptyReload.addConfig('Blocked by corrupt store', { blocked: 20 }), /配置数据|配置记录/);
    assert.equal(storedValues.get('charger_configs'), invalidData, 'corrupted content must be preserved for recovery');
  }
  storedValues.set('charger_configs', savedBeforeCorruption);
  assert.equal((await emptyReload.getConfigs()).configs.some(config => config.name === 'After read recovery'), true);

  const { ConfigService } = load(`${base}services/ConfigService.ets`);
  const listenerResults = [];
  const brokenListener = () => { throw new Error('simulated detached UI listener'); };
  const workingListener = (stations, config) => listenerResults.push({ stations: JSON.stringify(stations), current: JSON.stringify(config ? config.stations : {}) });
  ConfigService.addListener(brokenListener);
  ConfigService.addListener(workingListener);
  ConfigService.addListener(workingListener);
  await ConfigService.switchConfig('preset_main_c');
  assert.equal(listenerResults.length, 1, 'a detached listener must not reject persistence or skip later listeners; duplicates subscribe once');
  const eventConfig = await emptyReload.addConfig('Event race fixture', { first: 21 });
  await ConfigService.switchConfig(eventConfig.id);
  await Promise.all([
    ConfigService.updateConfig(eventConfig.id, 'Event race fixture', { older: 22 }),
    ConfigService.updateConfig(eventConfig.id, 'Event race fixture', { newest: 23 })
  ]);
  assert.ok(listenerResults.every(result => result.stations === result.current), 'notifications must describe one consistent current snapshot');
  assert.equal((await ConfigService.getCurrentConfig()).stations.newest, 23);
  ConfigService.removeListener(brokenListener);
  ConfigService.removeListener(workingListener);

  const savedBeforeFlushFailure = storedValues.get('charger_configs');
  const originalFlush = prefs.flush;
  let failNextFlush = true;
  prefs.flush = async () => {
    if (failNextFlush) { failNextFlush = false; throw new Error('simulated preferences flush failure'); }
  };
  await assert.rejects(emptyReload.addConfig('Failed flush write', { rejected: 24 }), /配置保存失败/);
  prefs.flush = originalFlush;
  assert.equal(storedValues.get('charger_configs'), savedBeforeFlushFailure, 'failed flush must restore the previous Preferences value');
  await emptyReload.addConfig('After flush recovery', { kept: 25 });
  assert.equal((await emptyReload.getConfigs()).configs.some(config => config.name === 'Failed flush write'), false);

  // Successful persistence must not be reported as failure because a later read fails.
  // Simulate storage becoming unreadable immediately after every successful flush.
  async function commitWithoutPostRead(operation, label) {
    const getBeforeCommit = prefs.get;
    const flushBeforeCommit = prefs.flush;
    let committed = false;
    prefs.get = async (key, fallback) => {
      if (committed) throw new Error('simulated post-commit read failure');
      return getBeforeCommit(key, fallback);
    };
    prefs.flush = async () => { await flushBeforeCommit(); committed = true; };
    try {
      const result = await operation();
      assert.equal(committed, true, `${label} must actually persist`);
      return result;
    } finally { prefs.get = getBeforeCommit; prefs.flush = flushBeforeCommit; }
  }
  await emptyReload.clearAllConfigs();
  await Promise.all([emptyReload.deleteConfig('preset_main_c'), emptyReload.deleteConfig('preset_street')]);
  const committedEvents = [];
  const committedListener = (stations, config) => committedEvents.push({ id: config ? config.id : null, stations: JSON.parse(JSON.stringify(stations)) });
  ConfigService.addListener(committedListener);
  const committedAdd = await commitWithoutPostRead(() => ConfigService.addConfig('Committed add', { saved: 31 }), 'add');
  assert.equal(committedEvents.at(-1).id, committedAdd.id);
  assert.equal(committedEvents.at(-1).stations.saved, 31);
  assert.equal(await commitWithoutPostRead(() => ConfigService.updateConfig(committedAdd.id, 'Committed edit', { edited: 32 }), 'update'), true);
  assert.equal(committedEvents.at(-1).stations.edited, 32);
  const committedOther = await ConfigService.addConfig('Other committed', { other: 33 });
  await commitWithoutPostRead(() => ConfigService.switchConfig(committedOther.id), 'switch');
  assert.equal(committedEvents.at(-1).id, committedOther.id);
  assert.equal(await commitWithoutPostRead(() => ConfigService.deleteConfig(committedOther.id), 'delete'), true);
  assert.equal(committedEvents.at(-1).id, committedAdd.id);
  assert.equal(await commitWithoutPostRead(() => ConfigService.deleteConfig(committedAdd.id), 'delete last'), true);
  assert.equal(committedEvents.at(-1).id, null);
  assert.deepEqual(committedEvents.at(-1).stations, {});
  await commitWithoutPostRead(() => ConfigService.restoreDefaultConfigs(), 'restore');
  assert.equal(committedEvents.at(-1).id, 'preset_main_c');
  assert.equal((await ConfigService.loadConfigs()).configs.length, 2);
  ConfigService.removeListener(committedListener);

  const { StationSelection } = load(`${base}utils/StationSelection.ets`);
  const candidates = [
    { stationId: 1, stationName: '主楼C 区1号', address: '清水河', freeNum: 0 },
    { stationId: 2, stationName: '商业街1号', address: '清水河', freeNum: 0 },
    { stationId: 3, stationName: '商业街2号', address: '清水河', freeNum: 1 }
  ];
  assert.equal(StationSelection.filter(candidates, '主楼c区').length, 1);
  assert.equal(StationSelection.filter(candidates, '商业街').length, 2);
  assert.equal(StationSelection.filter(candidates, '不存在').length, 0);
  const matches = StationSelection.filter(candidates, '商业街');
  const selected = StationSelection.selectMatches([1], matches);
  assert.deepEqual(Array.from(selected), [1, 2, 3]);
  assert.deepEqual(Array.from(StationSelection.selectMatches(selected, matches)), [1, 2, 3]);
  assert.deepEqual(Array.from(StationSelection.clearMatches(selected, matches)), [1]);

  const merged = StationSelection.mergeAvailable([candidates[1], candidates[1]], [candidates[0], candidates[2]], [1]);
  assert.deepEqual(Array.from(merged, station => station.stationId), [2, 1], 'retain selected off-list stations and deduplicate IDs');
  assert.equal(StationSelection.toStationMap(merged, [1, 2])['主楼C 区1号'], 1);
  assert.throws(() => StationSelection.toStationMap(merged, [99]), /信息缺失/);
  assert.throws(() => StationSelection.toStationMap([
    { ...candidates[0], stationName: 'Same name' }, { ...candidates[1], stationName: 'Same name' }
  ], [1, 2]), /重名/);

  const { DataCache } = load(`${base}utils/DataCache.ets`);
  const { ApiConfig } = load(`${base}ApiConfig.ets`);
  const station = { id: 101, name: 'stationA', outlets: [] };
  DataCache.setStation(101, station);
  DataCache.setNearbyStations([{ stationId: 101, stationName: 'stationA', address: '', freeNum: 0 }]);
  now += ApiConfig.CACHE_DURATION - 1;
  assert.equal(DataCache.getStation(101), station);
  assert.equal(DataCache.getNearbyStations().length, 1);
  now++;
  assert.equal(DataCache.getStation(101), null, 'TTL must expire at the boundary');
  assert.equal(DataCache.getNearbyStations(), null);
  DataCache.setStation(101, station);
  DataCache.clearAll();
  assert.equal(DataCache.getStation(101), null);

  const { calculateDistance, formatDistance } = load(`${base}utils/DistanceCalc.ets`);
  assert.equal(calculateDistance(0, 0, 0, 0), 0);
  assert.ok(Math.abs(calculateDistance(0, 0, 0, 1) - 111319.4908) < 0.1);
  assert.equal(formatDistance(999), '999米');
  assert.equal(formatDistance(1000), '1.0公里');
  const { DataValidator } = load(`${base}ChargerModels.ets`);
  assert.equal(DataValidator.validateStationData({ id: 1, name: 'ok', outlets: [
    { serial: 1, outletNo: 'a', status: 1 }
  ] }), true);
  assert.equal(DataValidator.validateStationData({ id: 1, name: 'bad', outlets: [
    { serial: 1, outletNo: 'a', status: 99 }
  ] }), false);
  console.log('PASS: committed snapshot notifications without post-read, listener isolation/snapshot consistency, unreadable-store protection, station selection preservation, serialized concurrent writers/recovery, preset deletion/restore/empty-state/reload, legacy migration, keyword union/deselection, config CRUD/switch/reload, cache TTL/clear, distance, data validation');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
