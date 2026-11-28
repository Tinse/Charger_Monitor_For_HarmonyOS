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
let stationCacheClearCount = 0;
let retainedStationIds = [];
const stationServiceStub = {
  clearCache: () => { stationCacheClearCount++; },
  retainStationIds: ids => { retainedStationIds = Array.from(ids); }
};

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
  const legacy = { configs: [{ id: 'legacy', name: 'Old custom', stations: { custom: 88 }, createdAt: 123 }], currentConfigId: 'legacy' };
  storedValues.set('charger_configs', JSON.stringify(legacy));
  await assert.rejects(reloaded.updateConfig('preset_street', 'overwrite', {}), /默认配置名称/);
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
  const emptyNamed = await reloaded.addConfig('Empty', {});
  assert.equal(Object.keys(emptyNamed.stations).length, 0);
  await reloaded.deleteConfig(emptyNamed.id);
  assert.equal(await reloaded.updateConfig('legacy', 'Old custom', {}), true);
  assert.equal(Object.keys((await reloaded.getConfigs()).configs.find(config => config.id === 'legacy').stations).length, 0);
  await reloaded.updateConfig('legacy', 'Old custom', { custom: 88 });
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

  // Per-configuration CRUD is based on real station IDs and preserves preset edits.
  const stationFixture = (id, name) => ({ stationId: id, stationName: name, address: 'Campus', freeNum: 0 });
  const getConfig = async id => (await ConfigService.loadConfigs()).configs.find(config => config.id === id);
  const presetBefore = await getConfig('preset_main_c');
  const presetFirstId = Object.values(presetBefore.stations)[0];
  await ConfigService.renameStation(presetBefore.id, presetFirstId, '上课常用');
  assert.equal((await getConfig(presetBefore.id)).stations['上课常用'], presetFirstId);
  const renamedPresetRaw = storedValues.get('charger_configs');
  const reloadWithPresetEdits = load(`${base}ConfigManager.ets`, true).ConfigManager;
  await reloadWithPresetEdits.initialize(context);
  assert.equal((await reloadWithPresetEdits.getConfigs()).configs.find(config => config.id === presetBefore.id).stations['上课常用'], presetFirstId);
  await ConfigService.restoreDefaultConfigs();
  assert.equal((await getConfig(presetBefore.id)).stations['上课常用'], presetFirstId, 'restore must not overwrite retained preset edits');
  assert.ok(renamedPresetRaw.includes('上课常用'));
  await assert.rejects(ConfigService.renameConfig(presetBefore.id, 'New preset name'), /默认配置名称/);
  const memberConfig = await ConfigService.addConfig('Member CRUD', { Original: 101 }, { '101': 'Real original' });
  assert.equal((await getConfig(memberConfig.id)).stationNames['101'], 'Real original');
  await ConfigService.addStations(memberConfig.id, [stationFixture(102, 'Same source'), stationFixture(103, 'Same source'), stationFixture(102, 'Ignored duplicate')]);
  let members = await getConfig(memberConfig.id);
  assert.equal(Object.keys(members.stations).length, 3);
  assert.equal(members.stations['Same source'], 102);
  assert.equal(members.stations['Same source（103）'], 103);
  assert.equal(members.stationNames['103'], 'Same source');
  const beforeAliasConflict = storedValues.get('charger_configs');
  await assert.rejects(ConfigService.renameStation(memberConfig.id, 101, 'Same source'), /同名/);
  await assert.rejects(ConfigService.renameStation(memberConfig.id, 101, '__proto__'), /不可用/);
  assert.equal(storedValues.get('charger_configs'), beforeAliasConflict);
  await ConfigService.renameStation(memberConfig.id, 101, '我常去的');
  await ConfigService.replaceStation(memberConfig.id, 101, stationFixture(104, 'Replacement source'));
  members = await getConfig(memberConfig.id);
  assert.equal(members.stations['我常去的'], 104, 'replacing a station retains an explicit alias');
  assert.equal(Object.values(members.stations)[0], 104, 'rename and replacement retain the existing row position');
  assert.equal(members.stationNames['104'], 'Replacement source');
  assert.equal(members.stationNames['101'], undefined);
  await ConfigService.renameStation(memberConfig.id, 104, '');
  assert.equal((await getConfig(memberConfig.id)).stations['Replacement source'], 104, 'empty alias restores real source name');
  await ConfigService.replaceStation(memberConfig.id, 104, stationFixture(105, 'New source'));
  assert.equal((await getConfig(memberConfig.id)).stations['New source'], 105, 'unaliasied station follows replacement source name');
  await assert.rejects(ConfigService.replaceStation(memberConfig.id, 105, stationFixture(102, 'Same source')), /已在/);
  await Promise.all([
    ConfigService.addStations(memberConfig.id, [stationFixture(106, 'Parallel add')]),
    ConfigService.renameStation(memberConfig.id, 105, 'Parallel alias'),
    ConfigService.removeStation(memberConfig.id, 102)
  ]);
  members = await getConfig(memberConfig.id);
  assert.equal(members.stations['Parallel add'], 106);
  assert.equal(members.stations['Parallel alias'], 105);
  assert.equal(Object.values(members.stations).includes(102), false);
  for (const id of Object.values(members.stations)) await ConfigService.removeStation(memberConfig.id, id);
  members = await getConfig(memberConfig.id);
  assert.equal(Object.keys(members.stations).length, 0, 'removing the last station retains the configuration');
  assert.equal(Object.keys(members.stationNames).length, 0);
  await ConfigService.renameConfig(memberConfig.id, 'Empty but retained');
  assert.equal((await getConfig(memberConfig.id)).name, 'Empty but retained');
  await ConfigService.addStations(memberConfig.id, [stationFixture(107, 'Back again')]);
  const sourceConfig = await getConfig(presetBefore.id);
  const copied = await ConfigService.addConfig('Alias copy', sourceConfig.stations, sourceConfig.stationNames);
  assert.equal((await getConfig(copied.id)).stationNames[String(presetFirstId)], sourceConfig.stationNames[String(presetFirstId)]);
  await ConfigService.renameStation(copied.id, presetFirstId, '');
  assert.ok(Object.keys((await getConfig(copied.id)).stations).includes(sourceConfig.stationNames[String(presetFirstId)]));
  await ConfigService.addStations(memberConfig.id, [stationFixture(109, '__proto__')]);
  assert.equal((await getConfig(memberConfig.id)).stations['__proto__（109）'], 109, 'reserved source names receive a readable safe suffix');
  assert.equal((await getConfig(memberConfig.id)).stationNames['109'], '__proto__');
  await ConfigService.renameStation(memberConfig.id, 109, '');
  assert.equal((await getConfig(memberConfig.id)).stations['__proto__（109）'], 109);
  await ConfigService.renameStation(memberConfig.id, 107, 'Back again（107） 备用门');
  await ConfigService.replaceStation(memberConfig.id, 107, stationFixture(110, 'Changed source'));
  assert.equal((await getConfig(memberConfig.id)).stations['Back again（107） 备用门'], 110,
    'a user alias with nonnumeric suffix must survive replacement');
  await ConfigService.addStations(memberConfig.id, [stationFixture(111, 'Auto name'), stationFixture(113, 'Auto name（112）'), stationFixture(112, 'Auto name')]);
  assert.equal((await getConfig(memberConfig.id)).stations['Auto name（112） 2'], 112);
  await ConfigService.replaceStation(memberConfig.id, 112, stationFixture(114, 'Auto replacement'));
  assert.equal((await getConfig(memberConfig.id)).stations['Auto replacement'], 114, 'generated numeric disambiguation follows the replacement source');
  const beforeBadBatch = storedValues.get('charger_configs');
  await assert.rejects(ConfigService.addStations(memberConfig.id, [stationFixture(108, 'Good'), stationFixture(0, 'Invalid')]), /无效/);
  assert.equal(storedValues.get('charger_configs'), beforeBadBatch, 'invalid batch must be atomic');
  await assert.rejects(ConfigService.removeStation('missing', 110), /不存在/);
  await assert.rejects(ConfigService.renameStation(memberConfig.id, 999, 'Missing'), /不在/);

  const currentBeforeNonCurrentEdit = (await ConfigService.getCurrentConfig()).id;
  const clearCountBeforeNonCurrentEdit = stationCacheClearCount;
  const selectionNotifications = [];
  const selectionListener = (_stations, config) => selectionNotifications.push(config ? config.id : null);
  ConfigService.addListener(selectionListener);
  const beforeFailedRemoval = storedValues.get('charger_configs');
  prefs.flush = async () => {
    prefs.flush = originalFlush;
    throw new Error('simulated failure while removing a station');
  };
  await assert.rejects(ConfigService.removeStation(presetBefore.id, presetFirstId), /配置保存失败/);
  assert.equal(storedValues.get('charger_configs'), beforeFailedRemoval, 'failed removal must preserve the member and its alias');
  assert.deepEqual(selectionNotifications, [], 'failed removal must not update the monitor');
  await ConfigService.renameStation(memberConfig.id, 110, '仅此配置别名');
  assert.equal((await ConfigService.getCurrentConfig()).id, currentBeforeNonCurrentEdit, 'editing another configuration must not change the current selection');
  assert.equal(stationCacheClearCount, clearCountBeforeNonCurrentEdit, 'non-current station edits must not cancel current cache requests');
  assert.equal(selectionNotifications.length, 0, 'non-current edits must not notify current monitor');
  await ConfigService.renameStation(presetBefore.id, presetFirstId, '当前站点更新');
  assert.equal(stationCacheClearCount, clearCountBeforeNonCurrentEdit, 'renaming an active member must preserve its physical station measurements');
  assert.deepEqual(selectionNotifications, [presetBefore.id], 'current edits must still notify the monitor');
  await ConfigService.switchConfig(copied.id);
  await ConfigService.deleteConfig(copied.id);
  const fallbackId = (await ConfigService.getCurrentConfig()).id;
  assert.deepEqual(selectionNotifications, [presetBefore.id, copied.id, fallbackId]);
  assert.equal(stationCacheClearCount, 0, 'config edits, switch, delete and restore operations must not flush shared station data');
  ConfigService.removeListener(selectionListener);

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
  const sameSourceMap = StationSelection.toStationMap([
    { ...candidates[0], stationName: 'Same name' }, { ...candidates[1], stationName: 'Same name' }
  ], [1, 2]);
  assert.equal(sameSourceMap['Same name'], 1);
  assert.equal(sameSourceMap['Same name（2）'], 2);

  await emptyReload.clearAllConfigs();
  await Promise.all([emptyReload.deleteConfig('preset_main_c'), emptyReload.deleteConfig('preset_street')]);
  const emptyFirst = await ConfigService.addConfig('Named empty first', {});
  assert.equal((await ConfigService.getCurrentConfig()).id, emptyFirst.id, 'a first named empty config becomes current');
  assert.equal(Object.keys((await ConfigService.getCurrentConfig()).stations).length, 0);
  const emptyCopy = await ConfigService.addConfig('Named empty copy', emptyFirst.stations, emptyFirst.stationNames);
  assert.notEqual(emptyCopy.id, emptyFirst.id);
  assert.equal(Object.keys(emptyCopy.stations).length, 0);
  await ConfigService.addStations(emptyFirst.id, [stationFixture(130, 'Added after empty creation')]);
  assert.equal((await ConfigService.getCurrentConfig()).stations['Added after empty creation'], 130);
  await assert.rejects(ConfigService.addConfig(' ', {}), /名称/);

  await ConfigService.addStations(emptyFirst.id, [stationFixture(131, 'Second'), stationFixture(132, 'Third')]);
  await Promise.all([
    ConfigService.editStation(emptyFirst.id, 130, 'North gate', undefined, undefined),
    ConfigService.editStation(emptyFirst.id, 130, undefined, 'Near the exit', undefined),
    ConfigService.editStation(emptyFirst.id, 130, undefined, undefined, true)
  ]);
  const editedMember = (await getConfig(emptyFirst.id)).members.find(member => member.stationId === 130);
  assert.deepEqual([editedMember.alias, editedMember.note, editedMember.paused], ['North gate', 'Near the exit', true],
    'concurrent edits of different preferences on the same membership must merge');
  assert.ok(retainedStationIds.includes(130), 'paused but referenced stations retain snapshots');
  assert.deepEqual(Object.values(await ConfigService.getCurrentStationConfig()), [131, 132]);
  await ConfigService.moveStation(emptyFirst.id, 132, -1);
  const source = await ConfigService.getCurrentConfig();
  assert.deepEqual(Array.from(source.members, item => item.stationId), [130, 132, 131]);
  const copyName = emptyReload.copyName(source.name, (await ConfigService.loadConfigs()).configs);
  const memberCopy = await ConfigService.addConfig(copyName, source.stations, source.stationNames, source.members);
  assert.equal(emptyReload.copyName(source.name, (await ConfigService.loadConfigs()).configs), source.name + ' 副本 2');
  assert.ok(emptyReload.copyName('123456789012345678901234', []).length <= 24);
  assert.deepEqual(JSON.parse(JSON.stringify(memberCopy.members)), JSON.parse(JSON.stringify(source.members)));
  await ConfigService.replaceStation(emptyFirst.id, 130, stationFixture(133, 'Replaced'), true);
  const replaced = (await ConfigService.getCurrentConfig()).members[0];
  assert.deepEqual([replaced.stationId, replaced.alias, replaced.note, replaced.paused], [133,'North gate','Near the exit',true]);
  await ConfigService.replaceStation(emptyFirst.id, 133, stationFixture(134, 'New'));
  assert.equal((await ConfigService.getCurrentConfig()).members[0].note, '');
  assert.equal((await getConfig(memberCopy.id)).members[0].note, 'Near the exit');
  await assert.rejects(ConfigService.editStation(memberCopy.id, 130, '', 'x'.repeat(201), false), /备注/);
  const intact = storedValues.get('charger_configs');
  await assert.rejects(ConfigService.removeStations(emptyFirst.id, [132, 999999]), /不在/);
  assert.equal(storedValues.get('charger_configs'), intact);
  const beforeBatchFlush = prefs.flush;
  prefs.flush = async () => { prefs.flush = beforeBatchFlush; throw new Error('batch flush interrupted'); };
  await assert.rejects(ConfigService.removeStations(emptyFirst.id, [132, 131]), /保存失败/);
  assert.equal(storedValues.get('charger_configs'), intact, 'failed batch must not partially remove stations');
  await ConfigService.removeStations(emptyFirst.id, [132, 131]);
  assert.deepEqual(Object.keys(await ConfigService.getCurrentStationConfig()), [], 'all-paused differs from no members');
  assert.equal((await ConfigService.getCurrentConfig()).members.length, 1);
  await ConfigService.deleteConfig(emptyFirst.id);
  assert.equal((await getConfig(memberCopy.id)).members.length, 3);
  assert.ok(!retainedStationIds.includes(134) && retainedStationIds.includes(130));

  const legacyDraft = { configs: [{ id: 'legacyAlias', name: 'Legacy', createdAt: 1,
    stations: { 'My own label': 10, 'Source B': 20 }, stationNames: { '10': 'Source A', '20': 'Source B' } }],
    currentConfigId: 'legacyAlias', deletedPresetIds: ['preset_street'] };
  const beforeMigration = JSON.stringify(legacyDraft);
  storedValues.set('charger_configs', beforeMigration);
  const migrationFlush = prefs.flush;
  prefs.flush = async () => { prefs.flush = migrationFlush; throw new Error('interrupted schema upgrade'); };
  await assert.rejects(ConfigService.loadConfigs(), /保存失败/);
  assert.equal(storedValues.get('charger_configs'), beforeMigration, 'failed migration must restore the exact legacy bytes');
  const upgraded = await ConfigService.loadConfigs();
  const upgradedMember = upgraded.configs.find(config => config.id === 'legacyAlias').members[0];
  assert.deepEqual([upgraded.currentConfigId, upgradedMember.stationId, upgradedMember.originalName, upgradedMember.alias],
    ['legacyAlias', 10, 'Source A', 'My own label']);
  assert.ok(!upgraded.configs.some(config => ['preset_street','preset_d'].includes(config.id)));
  const committedUpgrade = storedValues.get('charger_configs');
  await ConfigService.loadConfigs();
  assert.equal(storedValues.get('charger_configs'), committedUpgrade, 'a successful migration must be idempotent');

  const { DataCache } = load(`${base}utils/DataCache.ets`);
  const { ApiConfig } = load(`${base}ApiConfig.ets`);
  const station = { id: 101, name: 'stationA', outlets: [] };
  DataCache.setStation(101, station);
  DataCache.setNearbyStations([{ stationId: 101, stationName: 'stationA', address: '', freeNum: 0 }]);
  now += ApiConfig.AUTO_REFRESH_INTERVAL - 1;
  assert.equal(DataCache.getStation(101), station);
  assert.equal(DataCache.getNearbyStations().length, 1);
  now++;
  assert.equal(DataCache.getStation(101), null, 'TTL must expire at the boundary');
  assert.equal(DataCache.getHistory(101).data, station, 'stale station remains available for history');
  now += ApiConfig.CACHE_DURATION - ApiConfig.AUTO_REFRESH_INTERVAL;
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
  console.log('PASS: durable member migration/rollback, independent copies/notes/pausing/order, atomic bulk removal, concurrent field edits, per-config station CRUD/preset edits/aliases/concurrent deltas, committed snapshot notifications without post-read, listener isolation/snapshot consistency, unreadable-store protection, station selection preservation, serialized concurrent writers/recovery, preset deletion/restore/empty-state/reload, legacy migration, keyword union/deselection, config CRUD/switch/reload, cache TTL/clear, distance, data validation');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
