const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const studio = process.env.DEVECO_CLI_STUDIO_PATH;
if (!studio) throw new Error('Set DEVECO_CLI_STUDIO_PATH.');
const ts = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
let testNow = 1000000;
class TestDate extends Date { static now() { return testNow; } }
const modules = new Map();
const apiModules = new Map();
let heldFetch = null;
const httpReplies = [];
let requests = 0, destroyed = 0;
const fakeHttp = {
  RequestMethod: { GET: 'GET', POST: 'POST' },
  createHttp: () => ({
    request: async () => {
      requests++;
      assert.ok(httpReplies.length, 'test must supply every HTTP response');
      const reply = httpReplies.shift();
      if (reply instanceof Error) throw reply;
      return reply;
    },
    destroy: () => { destroyed++; }
  })
};
function reply(data, status = 200) { httpReplies.push({ responseCode: status, result: JSON.stringify(data) }); }

let active = 0, peak = 0, calls = 0, nearbyCalls = 0;
let nearbyStatus = '位置权限被拒绝，使用默认位置';
const failed = new Set();
const fakeApi = {
  fetchNearbyStations: async () => {
    nearbyCalls++;
    return { stations: [{ stationId: 100, stationName: 'nearby', address: '', freeNum: 0 }], locationStatus: nearbyStatus };
  },
  fetchStation: async (id, name) => {
    calls++; active++; peak = Math.max(peak, active);
    if (heldFetch) {
      const wait = heldFetch;
      heldFetch = null;
      await wait;
    } else await Promise.resolve();
    active--;
    if (failed.has(id)) return null;
    return { id, name, outlets: [{ serial: 1, outletNo: String(id), status: 1 }] };
  }
};
function load(relative, actualApi = false) {
  const filename = path.resolve(root, relative);
  const selectedModules = actualApi ? apiModules : modules;
  if (selectedModules.has(filename)) return selectedModules.get(filename);
  const source = fs.readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  selectedModules.set(filename, module.exports);
  function localRequire(name) {
    if (name.includes('ChargerApi') && !actualApi) return { ChargerApi: fakeApi };
    if (name === '@kit.NetworkKit') return { http: fakeHttp };
    if (name.includes('LocationService') && actualApi) return { LocationService: { getLocationWithPermissionRetry: async () => ({ location: { latitude: 0, longitude: 0 }, status: 'test location' }) } };
    if (name.includes('ErrorHandler')) return { ErrorHandler: { handle() {} } };
    if (name === '@kit.AbilityKit') return {};
    if (!name.startsWith('.')) throw new Error(name);
    return load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')), actualApi);
  }
  new vm.Script(result.outputText, { filename }).runInNewContext({ module, exports: module.exports, require: localRequire,
    console: { log() {}, error() {} }, Date: TestDate, setTimeout });
  return module.exports;
}
async function main() {
  const base = 'entry/src/main/ets/pages/';
  const { RefreshGate } = load(base + 'utils/RefreshGate.ets');
  const gate = new RefreshGate(3000);
  assert.equal(gate.tryStart(10000), true);
  assert.equal(gate.remaining(10000), 3000);
  assert.equal(gate.remaining(11001), 1999);
  assert.equal(gate.tryStart(12000), false);
  assert.equal(gate.remaining(50000), 0, 'time jumps and suspended timers must expire immediately');
  assert.equal(gate.tryStart(50000), false, 'slow request remains single-flight after countdown');
  gate.finish();
  assert.equal(gate.tryStart(50000), true);
  gate.finish();
  assert.equal(gate.tryStart(51000), false, 'completion must not bypass cooldown');
  assert.equal(gate.tryStart(53000), true);
  gate.finish();
  const { StationService } = load(base + 'services/StationService.ets');
  const config = Object.fromEntries(Array.from({ length: 9 }, (_, i) => ['station' + (i + 1), i + 1]));
  failed.add(3);
  let result = await StationService.fetchStationsForConfig(config);
  assert.equal(result.stations.length, 8);
  assert.deepEqual(Array.from(result.failedNames), ['station3']);
  assert.equal(peak, 4, 'large config concurrency must stay bounded');
  const firstCalls = calls;
  await StationService.fetchStationsForConfig(config);
  assert.equal(calls, firstCalls + 1, 'successful stations cached; failed station retried');
  StationService.clearCache();
  for (let i = 1; i <= 9; i++) failed.add(i);
  result = await StationService.fetchStationsForConfig(config);
  assert.equal(result.stations.length, 0);
  assert.equal(result.failedNames.length, 9, 'total network failure must not masquerade as empty config');
  failed.clear();
  StationService.clearCache();
  await StationService.fetchStationsForConfig({ Original: 1 });
  const beforeAlias = calls;
  const renamed = await StationService.fetchStationsForConfig({ Renamed: 1 });
  assert.equal(renamed.stations[0].name, 'Renamed', 'cached station name must follow the current configuration');
  assert.equal(calls, beforeAlias, 'renaming should still reuse cached measurements');

  // A slow request from the old cache epoch must not repopulate a cleared cache.
  StationService.clearCache();
  let releaseOld;
  heldFetch = new Promise(resolve => { releaseOld = resolve; });
  const oldRequest = StationService.fetchStationsForConfig({ Old: 1 });
  StationService.clearCache();
  releaseOld();
  await oldRequest;
  const afterOld = calls;
  const freshResult = await StationService.fetchStationsForConfig({ Fresh: 1 });
  assert.equal(calls, afterOld + 1, 'cache clear must invalidate in-flight writes too');
  assert.equal(freshResult.stations[0].name, 'Fresh');

  StationService.clearCache();
  const originalNearby = await StationService.fetchNearbyStations();
  assert.ok(originalNearby.locationStatus.includes('默认位置'));
  const cachedNearby = await StationService.fetchNearbyStations();
  assert.ok(cachedNearby.locationStatus.includes('默认位置'));
  assert.ok(cachedNearby.locationStatus.includes('权限'), 'cached lookup must retain location provenance for permission retry');
  assert.equal(nearbyCalls, 1);
  StationService.clearCache();
  nearbyStatus = '已获取设备位置';
  assert.equal((await StationService.fetchNearbyStations()).locationStatus, '已获取设备位置');
  assert.equal(nearbyCalls, 2);

  StationService.clearCache();
  testNow = 2000000;
  const acquired = await StationService.fetchStationsForConfig({ First: 1 });
  assert.equal(acquired.oldestFetchedAt, 2000000);
  testNow += 30000;
  const fromCache = await StationService.fetchStationsForConfig({ First: 1 });
  assert.equal(fromCache.oldestFetchedAt, acquired.oldestFetchedAt, 'reading valid cache must not claim freshly acquired data');
  testNow += 1000;
  const mixed = await StationService.fetchStationsForConfig({ First: 1, Second: 2 });
  assert.equal(mixed.oldestFetchedAt, acquired.oldestFetchedAt, 'mixed cached/new data reports the earliest successful acquisition');
  StationService.clearCache();
  testNow += 1000;
  const refreshed = await StationService.fetchStationsForConfig({ First: 1, Second: 2 });
  assert.equal(refreshed.oldestFetchedAt, testNow, 'clear followed by a successful refresh advances the acquisition time');
  assert.ok(refreshed.oldestFetchedAt > fromCache.oldestFetchedAt);

  const { ChargerApi } = load(base + 'api/ChargerApi.ets', true);
  reply({ code: '1', data: { powerFee: { billingPower: '12.5W' }, usedfee: '1.25', usedmin: '35' } });
  let detail = await ChargerApi.fetchOutletDetail('decimal');
  assert.equal(detail.power_w, 12.5, 'decimal power must not be multiplied by stripping punctuation');
  assert.equal(detail.fee, 1.25);
  assert.equal(detail.used_min, 35);
  reply({ code: '1', data: { powerFee: { billingPower: '0.5kW' }, usedfee: '0', usedmin: 0 } });
  detail = await ChargerApi.fetchOutletDetail('kilowatt');
  assert.equal(detail.power_w, 500);
  assert.equal(detail.fee, 0);
  assert.equal(detail.used_min, 0);
  reply({ code: '1', data: { powerFee: { billingPower: '-4W' }, usedfee: 'NaN' } });
  detail = await ChargerApi.fetchOutletDetail('missing');
  assert.equal(detail.power_w, undefined);
  assert.equal(detail.fee, undefined);
  assert.equal(detail.used_min, undefined, 'missing details must not be fabricated as zero');
  httpReplies.push(new Error('offline'));
  assert.deepEqual(Object.keys(await ChargerApi.fetchOutletDetail('offline')), []);
  const valid = { outletSerialNo: 1, outletNo: 'valid', currentChargingRecordId: 1 };
  reply({ code: '1', data: [valid] });
  assert.equal((await ChargerApi.fetchStation(1, 'valid', 0)).outlets.length, 1);
  reply({ code: '1', data: [{ ...valid, currentChargingRecordId: 999 }] });
  assert.equal(await ChargerApi.fetchStation(1, 'unknown', 0), null, 'unknown status must not masquerade as broken');
  reply({ code: '1', data: [valid, valid] });
  assert.equal(await ChargerApi.fetchStation(1, 'duplicate', 0), null, 'duplicate outlet data must not double-count totals');
  reply({ code: '1', data: { unexpected: 'shape' } });
  assert.equal(await ChargerApi.fetchStation(1, 'malformed', 0), null);
  reply({ code: '0', data: { elecStationData: [{ stationId: 1, stationName: 'stale error payload' }] } });
  assert.equal((await ChargerApi.fetchNearbyStations()).stations.length, 0);
  reply({ code: '1', data: { elecStationData: [
    { stationId: 1, stationName: 'zero coordinates', latitude: 0, longitude: 0, freeNum: 0 },
    { stationId: 1, stationName: 'duplicate' },
    { stationId: 0, stationName: 'invalid id' },
    { stationId: 2, stationName: 'unknown coordinates', latitude: 999, longitude: 0 },
    { stationId: 3, stationName: 'farther coordinates', latitude: 0, longitude: 1, freeNum: 1 }
  ] } });
  const nearby = await ChargerApi.fetchNearbyStations();
  assert.deepEqual(Array.from(nearby.stations, station => station.stationId), [1, 3, 2]);
  assert.equal(nearby.stations[0].distance, 0, 'zero latitude and longitude are valid');
  assert.equal(nearby.stations[2].distance, undefined);
  assert.equal(nearby.stations[2].formattedDistance, '距离未知');
  assert.equal(nearby.stations[2].freeNum, -1, 'unknown free count is not zero');
  assert.equal(httpReplies.length, 0);
  assert.equal(destroyed, requests, 'every HTTP object must be destroyed, including failures');
  console.log('PASS: cooldown/single-flight, cache epochs/names/acquisition time, failures/concurrency, API decimals/units/missing data, response validation and HTTP cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
