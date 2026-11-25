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
        assert.equal(context.kind, 'ApplicationContext');
        assert.equal(options.name, 'charger_configs');
        storeOpenCount++;
        return prefs;
      }
    } };
    if (name === '@kit.AbilityKit') return {};
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
async function main() {
  const { ConfigManager } = load(`${base}ConfigManager.ets`);
  const context = { kind: 'ApplicationContext' };
  await Promise.all([ConfigManager.initialize(context), ConfigManager.initialize(context)]);
  assert.equal(storeOpenCount, 1, 'concurrent initialization must open the store once');
  assert.equal((await ConfigManager.getConfigs()).configs.length, 3);
  assert.equal(Object.keys(ConfigManager.getDefaultConfig()).length, 3);

  const a = await ConfigManager.addConfig('A', { stationA: 101 });
  const b = await ConfigManager.addConfig('B', { stationB: 102 });
  assert.notEqual(a.id, b.id);
  assert.equal((await ConfigManager.getCurrentConfig()).id, 'preset_d');
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
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_d');
  assert.equal(await reloaded.deleteConfig(a.id), true);
  assert.equal((await reloaded.getCurrentConfig()).id, 'preset_d');
  storedValues.set('charger_configs', '{invalid json');
  assert.equal((await reloaded.getConfigs()).configs.length, 3);

  const { PresetConfigs } = load(`${base}PresetConfigs.ets`);
  const presets = PresetConfigs.create();
  assert.deepEqual(Array.from(presets, p => Object.keys(p.stations).length), [3, 3, 19]);
  assert.equal(await reloaded.deleteConfig('preset_main_c'), false);
  assert.equal(await reloaded.updateConfig('preset_street', 'overwrite', {}), false);
  const legacy = { configs: [{ id: 'legacy', name: 'Old custom', stations: { custom: 88 }, createdAt: 123 }], currentConfigId: 'legacy' };
  storedValues.set('charger_configs', JSON.stringify(legacy));
  assert.equal((await reloaded.getConfigs()).configs.length, 4);
  assert.equal((await reloaded.getCurrentConfig()).id, 'legacy');
  assert.equal((await reloaded.getConfigs()).configs.length, 4, 'presets must not duplicate');
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
  console.log('PASS: presets/legacy migration, keyword union/deselection, config CRUD/switch/reload, cache TTL/clear, distance, data validation');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
