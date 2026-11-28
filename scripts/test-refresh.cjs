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
const heldFetches = new Map();
function holdStation(id) {
  let release;
  heldFetches.set(id, new Promise(resolve => { release = resolve; }));
  return release;
}
const httpReplies = [];
const httpTrace = [];
let requests = 0, created = 0, destroyed = 0;
const fakeHttp = {
  RequestMethod: { GET: 'GET', POST: 'POST' },
  createHttp() {
    created++;
    return {
      request: async (url, options) => {
        requests++;
        httpTrace.push({ url, options });
        assert.ok(httpReplies.length, 'test must supply every HTTP response');
        const reply = httpReplies.shift();
        if (reply instanceof Error) throw reply;
        return reply;
      },
      destroy: () => { destroyed++; }
    };
  }
};
function reply(data, status = 200) { httpReplies.push({ responseCode: status, result: JSON.stringify(data) }); }

let active = 0, peak = 0, calls = 0, nearbyCalls = 0;
let nearbyStatus = '位置权限被拒绝，使用默认位置';
let locationResult = { location: { latitude: 0, longitude: 0 }, status: 'test location' };
let locationCalls = 0;
const savedHistory = new Map();
const prefs = {
  getAll: async () => Object.fromEntries(savedHistory),
  put: async (key, value) => savedHistory.set(key, value),
  delete: async key => savedHistory.delete(key),
  flush: async () => {}
};
const failed = new Set();
const fakeApi = {
  fetchNearbyStations: async (_context, onPhase) => {
    nearbyCalls++;
    onPhase?.('locating');
    onPhase?.('querying');
    return { stations: [{ stationId: 100, stationName: 'nearby', address: '', freeNum: 0 }], locationStatus: nearbyStatus };
  },
  fetchStation: async (id, name) => {
    calls++; active++; peak = Math.max(peak, active);
    const wait = heldFetches.get(id);
    heldFetches.delete(id);
    if (wait) await wait;
    else await Promise.resolve();
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
    if (name.includes('LocationService') && actualApi) return { LocationService: { getLocationWithPermissionRetry: async () => { locationCalls++; return locationResult; } } };
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => prefs } };
    if (name.includes('ErrorHandler')) return { ErrorHandler: { handle() {}, getErrorMessage: error => String(error) } };
    if (name === '@kit.AbilityKit') return {};
    if (!name.startsWith('.')) throw new Error(name);
    return load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')), actualApi);
  }
  new vm.Script(result.outputText, { filename }).runInNewContext({ module, exports: module.exports, require: localRequire,
    console: { log() {}, error() {} }, Date: TestDate, setTimeout, clearTimeout });
  return module.exports;
}

async function testStationProgress(StationService) {
  StationService.clearCache();
  const cacheTime = testNow;
  await StationService.fetchStationsForConfig({ OriginalName: 8 });
  const config = Object.fromEntries(Array.from({ length: 9 }, (_, i) => ['Display' + (i + 1), i + 1]));
  const events = [];
  const beforeCalls = calls;
  const release = [1, 2, 3, 4].map(holdStation);
  failed.add(3);
  failed.add(7);
  testNow += 1000;
  const fastTime = testNow;
  const request = StationService.fetchStationsForConfig(config, progress => {
    events.push(progress);
    if (progress.stationId === 2) throw new Error('observer was detached');
  });
  try {
    // Even with every network slot blocked, a later cached station must already be visible.
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(events.map(event => event.stationId), [8]);
    assert.equal(calls - beforeCalls, 4, 'only the first four network requests may have started');
    release.slice(1).forEach(finish => finish());
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(events.map(event => event.stationId).sort((a, b) => a - b), [2, 3, 4, 5, 6, 7, 8, 9],
      'all other station outcomes must be visible before the first slow station completes');
    assert.equal(calls - beforeCalls, 8, 'cached station 8 must not trigger a network request');
  } finally {
    testNow += 1000;
    release.forEach(finish => finish());
  }
  const result = await request;
  assert.deepEqual(Array.from(result.stations, station => station.id), [1, 2, 4, 5, 6, 8, 9],
    'the final station list must keep configuration order even after out-of-order finishes');
  assert.deepEqual(Array.from(result.failedNames), ['Display3', 'Display7']);
  assert.equal(result.oldestFetchedAt, cacheTime);
  assert.equal(events.length, 9);
  assert.equal(events.at(-1).stationId, 1);
  let completedFailures = 0;
  for (const [index, progress] of events.entries()) {
    const id = progress.stationId;
    const failure = failed.has(id);
    if (failure) completedFailures++;
    assert.equal(progress.completed, index + 1);
    assert.equal(progress.total, 9);
    assert.equal(progress.failed, completedFailures);
    assert.equal(progress.succeeded, progress.completed - completedFailures);
    assert.equal(progress.stationName, 'Display' + id);
    assert.equal(progress.fromCache, id === 8);
    if (failure) {
      assert.equal(progress.station, null);
      assert.equal(progress.fetchedAt, undefined);
    } else {
      assert.equal(progress.station.id, id);
      assert.equal(progress.station.name, progress.stationName);
      assert.equal(progress.station.outlets.length, 1);
      const actualFetchTime = id === 8 ? cacheTime : id === 1 ? testNow : fastTime;
      assert.equal(progress.fetchedAt, actualFetchTime, 'progress must retain the real acquisition time for each station');
    }
  }
  failed.clear();
  const emptyEvents = [];
  const beforeEmpty = calls;
  const empty = await StationService.fetchStationsForConfig({}, progress => emptyEvents.push(progress));
  assert.equal(empty.stations.length, 0);
  assert.equal(empty.failedNames.length, 0);
  assert.equal(empty.oldestFetchedAt, undefined);
  assert.equal(calls, beforeEmpty);
  assert.deepEqual(emptyEvents, []);
}

async function testSharedStationRefresh(StationService, DataCache) {
  StationService.clearCache();
  const fetch = StationService.fetchStationsForConfig.bind(StationService);
  await StationService.fetchNearbyStations();
  const nearbyBefore = nearbyCalls;
  const before = calls;
  const finish = holdStation(1);
  const progress = [];
  const requestA = fetch({ West: 1, OnlyA: 2 }, event => progress.push(event));
  const requestB = fetch({ East: 1, OnlyB: 3 }, event => progress.push(event));
  const manual = fetch({ Renamed: 1 }, event => progress.push(event), true);
  try {
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls - before, 3, 'two configurations and manual refresh must share one in-flight fetch for the same ID');
    assert.deepEqual(progress.map(event => event.stationId).sort(), [2, 3]);
  } finally {
    finish();
  }
  const [a, b, m] = await Promise.all([requestA, requestB, manual]);
  assert.deepEqual([a, b, m].map(result => result.stations[0].name), ['West', 'East', 'Renamed']);
  const sharedEvents = progress.filter(event => event.stationId === 1);
  assert.deepEqual(sharedEvents.map(event => event.station.name).sort(), ['East', 'Renamed', 'West']);
  assert.ok(sharedEvents.every(event => !event.fromCache && event.fetchedAt === testNow));

  const original = DataCache.getStation(1);
  const originalTime = DataCache.getStationTimestamp(1);
  testNow += 1000;
  failed.add(1);
  const forced = await fetch({ East: 1 }, undefined, true);
  assert.deepEqual(Array.from(forced.failedNames), ['East'], 'manual refresh must bypass a fresh station cache');
  assert.equal(calls - before, 4);
  assert.equal(DataCache.getStation(1), original, 'failed refresh must keep the previous measurements for display');
  assert.equal(DataCache.getStationTimestamp(1), originalTime);
  const retry = await fetch({ East: 1 });
  assert.deepEqual(Array.from(retry.failedNames), ['East'], 'auto refresh must recheck a failed station despite its retained cache');
  assert.equal(calls - before, 4, 'automatic retries wait for the backoff deadline');
  const otherEvents = [];
  await fetch({ OtherAlias: 2, Other: 3 }, event => otherEvents.push(event));
  assert.ok(otherEvents.every(event => event.fromCache));
  assert.equal(calls - before, 4, 'manual refresh only refreshes IDs in the selected configuration');
  await StationService.fetchNearbyStations();
  assert.equal(nearbyCalls, nearbyBefore, 'station refresh must not evict nearby results');
  failed.delete(1);
  const recovered = await fetch({ East: 1 }, undefined, true);
  assert.equal(recovered.oldestFetchedAt, testNow);
  const afterRecovery = [];
  await fetch({ West: 1 }, event => afterRecovery.push(event));
  assert.equal(afterRecovery[0].fromCache, true);
  assert.equal(calls - before, 5, 'a successfully revalidated station can use the cache again');
}

async function testChangedConfiguration(StationService) {
  StationService.clearCache();
  const before = calls;
  const release = [1, 2, 3, 4].map(holdStation);
  const oldEvents = [];
  let current = true;
  const oldConfig = { One: 1, Two: 2, Three: 3, Four: 4, Five: 5, Six: 6 };
  const oldRequest = StationService.fetchStationsForConfig(oldConfig, event => oldEvents.push(event), false, () => current);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls - before, 4);
  current = false;
  const newConfig = { A: 11, B: 12, C: 13, D: 14, E: 15 };
  const newRequest = StationService.fetchStationsForConfig(newConfig);
  try {
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls - before, 4, 'rapid config switching must share a single network concurrency budget');
  } finally {
    release.forEach(finish => finish());
  }
  const [, newResult] = await Promise.all([oldRequest, newRequest]);
  assert.deepEqual(oldEvents, [], 'a superseded consumer must not see late progress');
  assert.equal(newResult.stations.length, 5);
  assert.equal(calls - before, 9, 'queued members of the old config must not start');
  assert.equal(peak, 4);
}

async function testOverlappingCacheEpochs(StationService, DataCache) {
  StationService.clearCache();
  const before = calls;
  const releaseOld = [1, 2].map(holdStation);
  const oldEvents = [];
  const old = StationService.fetchStationsForConfig({ Old1: 1, Old2: 2 }, event => oldEvents.push(event));
  await new Promise(resolve => setImmediate(resolve));
  StationService.clearCache();
  const releaseNew = holdStation(1);
  const initialTime = testNow;
  const fresh = StationService.fetchStationsForConfig({ New1: 1, New2: 2 });
  let follower;
  try {
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls - before, 4, 'new epoch must start its own fetch for both IDs');
    assert.equal(DataCache.getStationTimestamp(2), initialTime);
    testNow += 1000;
    releaseOld.forEach(finish => finish());
    await old;
    assert.deepEqual(oldEvents, []);
    assert.equal(DataCache.getStationTimestamp(2), initialTime, 'late old response must not overwrite a newer response');
    follower = StationService.fetchStationsForConfig({ AnotherName: 1 }, undefined, true);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls - before, 4, 'old completion must not remove a newer in-flight request');
  } finally {
    releaseOld.forEach(finish => finish());
    releaseNew();
  }
  const [freshResult, followerResult] = await Promise.all([fresh, follower]);
  assert.deepEqual(Array.from(freshResult.stations, station => station.name), ['New1', 'New2']);
  assert.equal(followerResult.stations[0].name, 'AnotherName');
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function nearbyReply(id) {
  const data = { elecStationData: [{ stationId: id, stationName: 'Site ' + id }] };
  return { responseCode: 200, result: JSON.stringify({ code: '1', data }) };
}

async function testNearbySubscribers(StationService) {
  StationService.clearCache();
  const context = () => ({ applicationInfo: { name: 'campus.test', accessTokenId: 17 } });
  const fix = locationResult;
  const waitingForLocation = deferred();
  const waitingForHttp = deferred();
  locationResult = waitingForLocation.promise;
  httpReplies.push(waitingForHttp.promise);
  const before = requests;
  const initialPhases = [], resumedPhases = [], latePhases = [];
  const original = StationService.fetchNearbyStations(context(), phase => initialPhases.push(phase));
  await new Promise(resolve => setImmediate(resolve));
  const resumed = StationService.fetchNearbyStations(context(), phase => resumedPhases.push(phase));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(initialPhases, ['locating']);
  assert.deepEqual(resumedPhases, ['locating'], 'a resumed page must receive the current location phase');
  assert.equal(requests, before);
  locationResult = fix;
  waitingForLocation.resolve(fix);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(requests - before, 1, 'permission resolution must send only one POST across resumed pages');
  assert.deepEqual(initialPhases, ['locating', 'querying']);
  assert.deepEqual(resumedPhases, ['locating', 'querying']);
  const late = StationService.fetchNearbyStations(context(), phase => latePhases.push(phase));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(latePhases, ['querying'], 'a late subscriber must not replay obsolete location activity');
  assert.equal(requests - before, 1, 'permission lifecycle reentry must issue only one nearby POST');
  waitingForHttp.resolve(nearbyReply(70));
  const results = await Promise.all([original, resumed, late]);
  assert.deepEqual(results.map(result => result.stations[0].stationId), [70, 70, 70]);

  // A relocation or cache clear supersedes an older HTTP result that arrives last.
  for (const clearBetween of [false, true]) {
    StationService.clearCache();
    const beforeReplacement = requests;
    const oldHttp = deferred();
    httpReplies.push(oldHttp.promise, nearbyReply(72));
    const old = StationService.fetchNearbyStations(context());
    await new Promise(resolve => setImmediate(resolve));
    if (clearBetween) StationService.clearCache();
    const newer = StationService.fetchNearbyStations(context(), undefined, !clearBetween);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(requests - beforeReplacement, 2);
    assert.equal((await newer).stations[0].stationId, 72);
    oldHttp.resolve(nearbyReply(71));
    await old;
    const after = await StationService.fetchNearbyStations(context());
    assert.equal(after.stations[0].stationId, 72, 'obsolete nearby result must not overwrite a newer lookup');
    assert.equal(requests - beforeReplacement, 2);
  }
}

async function testNearbyContextIsolation(StationService) {
  const app = { applicationInfo: { name: 'campus.test', accessTokenId: 17 } };
  const otherToken = { applicationInfo: { name: 'campus.test', accessTokenId: 19 } };
  const otherName = { applicationInfo: { name: 'other.test', accessTokenId: 17 } };
  for (const [left, right] of [[undefined, app], [app, otherToken], [app, otherName], [{}, {}]]) {
    StationService.clearCache();
    const before = requests;
    const oldHttp = deferred();
    httpReplies.push(oldHttp.promise, nearbyReply(82));
    const first = StationService.fetchNearbyStations(left);
    await new Promise(resolve => setImmediate(resolve));
    const second = StationService.fetchNearbyStations(right);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(requests - before, 2, 'different location contexts must not share an in-flight nearby POST');
    assert.equal((await second).stations[0].stationId, 82);
    oldHttp.resolve(nearbyReply(81));
    await first;

    // Only the left context holds an answer here. Right must not consume it as a warm cache hit.
    StationService.clearCache();
    httpReplies.push(nearbyReply(83), nearbyReply(84));
    assert.equal((await StationService.fetchNearbyStations(left)).stations[0].stationId, 83);
    assert.equal((await StationService.fetchNearbyStations(right)).stations[0].stationId, 84);
    assert.equal(requests - before, 4);
  }
}

const turn = () => new Promise(resolve => setImmediate(resolve));
const outletList = (...states) => ({
  responseCode: 200, result: JSON.stringify({ code: '1', data: states.map((status, index) => ({
    outletSerialNo: index + 1, outletNo: 'socket-' + (index + 1), currentChargingRecordId: status
  })) })
});
const metrics = (value = '1.2kW') => ({
  responseCode: 200, result: JSON.stringify({ code: '1', data: { powerFee: { billingPower: value } } })
});

async function testLayeredReading(service) {
  service.clearCache();
  const origin = testNow;
  httpReplies.push(outletList(2, 2, 2, 1));
  const start = requests;
  await service.fetchStationsForConfig({ Alpha: 7 });
  const snap = service.getSnapshot(7, 'Shared alias');
  assert.equal(requests, start + 1, 'three occupied outlets must not start any detail requests during a basic fetch');
  assert.equal(snap.station.name, 'Shared alias');
  assert.ok(snap.confirmed && !snap.fromDisk);
  assert.equal(snap.station.outlets[0].power_w, undefined);
  const waits = [deferred(), deferred(), deferred()];
  httpReplies.push(...waits.map(wait => wait.promise));
  const events = [];
  const run = service.fetchOccupiedDetails([snap], event => events.push(event));
  await turn();
  assert.equal(requests, start + 3, 'start exactly two occupied detail tasks on explicit demand');
  waits[1].resolve(metrics());
  await turn();
  assert.equal(requests, start + 4);
  assert.equal(events[0].completed, 1);
  assert.equal(events[0].total, 3);
  assert.equal(events[0].detail.power_w, 1200);
  waits[0].resolve({ responseCode: 500, result: '' });
  waits[2].resolve(metrics('0W'));
  await run;
  assert.deepEqual([events.at(-1).succeeded, events.at(-1).failed, events.at(-1).skipped], [2, 1, 0]);
  assert.equal(events.at(-1).generation, snap.generation);
  assert.equal(service.getSnapshot(7, 'Alpha').fetchedAt, snap.fetchedAt);
  assert.equal(service.getSnapshot(7, 'Alpha').station.outlets[0].power_w, undefined);
  const errors = events.filter(e => !e.detail).map(e => e.outletNo);
  httpReplies.push(metrics());
  await service.fetchOccupiedDetails([snap], e => assert.equal(e.total, 1), () => true, errors);
  assert.equal(requests, start + 5, 'retry only the requested failed outlet');

  const late = deferred();
  const stopped = deferred();
  httpReplies.push(late.promise, stopped.promise);
  let visible = true;
  const afterStop = [];
  const queue = service.fetchOccupiedDetails([snap], e => afterStop.push(e), () => visible);
  await turn();
  visible = false;
  late.resolve(metrics());
  stopped.resolve(metrics());
  await queue;
  assert.equal(requests, start + 7);
  assert.deepEqual(afterStop, [], 'stop suppresses new jobs and late progress');

  testNow = origin + 14999;
  await service.fetchStationsForConfig({ Alpha: 7 });
  assert.equal(requests, start + 7);
  const obsolete1 = deferred(), obsolete2 = deferred();
  httpReplies.push(obsolete1.promise, obsolete2.promise);
  const staleEvents = [];
  const old = service.fetchOccupiedDetails([snap], e => staleEvents.push(e));
  await turn();
  testNow = origin + 15000;
  httpReplies.push(outletList(1, 2, 2, 1));
  await service.fetchStationsForConfig({ Alpha: 7 });
  const updated = service.getSnapshot(7, 'Alpha');
  assert.ok(updated.generation > snap.generation);
  obsolete1.resolve(metrics());
  obsolete2.resolve(metrics());
  await old;
  assert.equal(staleEvents.at(-1).skipped, 3);
  assert.ok(staleEvents.every(e => !e.detail));
  assert.equal(service.getSnapshot(7, 'Alpha', updated.fetchedAt + 29999).confirmed, true);
  assert.equal(service.getSnapshot(7, 'Alpha', updated.fetchedAt + 30000).confirmed, false);
  assert.ok(service.getSnapshot(7, 'Alpha', updated.fetchedAt + 599999));
  assert.equal(service.getSnapshot(7, 'Alpha', updated.fetchedAt + 600000), null);
  assert.ok(httpTrace.slice(-10).some(call => call.url.endsWith('/outlets/7')));
}

async function testRetryPolicy(service) {
  service.clearCache();
  const fetch = (id, manual = false) => service.fetchStationsForConfig({ Site: id }, undefined, manual);
  httpReplies.push(outletList(1));
  await fetch(1);
  httpReplies.push({ responseCode: 503, result: '' });
  await fetch(1, true);
  assert.equal(service.getSnapshot(1, 'Site').confirmed, false);
  const count = requests;
  for (const delay of [15000, 30000, 60000]) {
    testNow += delay - 1;
    const before = requests;
    await fetch(1);
    assert.equal(requests, before, 'a failing station respects its own backoff');
    testNow++;
    httpReplies.push({ responseCode: 503, result: '' });
    await fetch(1);
    assert.equal(requests, before + 1);
  }
  assert.equal(requests, count + 3);
  httpReplies.push({ responseCode: 429, header: { 'Retry-After': '3' }, result: '' });
  await fetch(1, true);
  const limited = requests;
  await fetch(2, true);
  assert.equal(requests, limited, 'server Retry-After applies even to a manual query for another station');
  testNow += 3000;
  httpReplies.push(outletList(2));
  await fetch(2, true);
  assert.equal(requests, limited + 1);
  httpReplies.push({ responseCode: 410, result: '' });
  await fetch(3);
  const missing = requests;
  testNow += 120000;
  await fetch(3);
  assert.equal(requests, missing, 'explicitly removed station waits for manual recheck');
  httpReplies.push(outletList(1));
  await fetch(3, true);
  assert.ok(service.getSnapshot(3, 'Site').confirmed);
  httpReplies.push({ responseCode: 404, result: 'upstream route unavailable' });
  await fetch(4);
  testNow += 15000;
  httpReplies.push(outletList(1));
  await fetch(4);
  assert.ok(service.getSnapshot(4, 'Site').confirmed, 'an ambiguous gateway 404 must not permanently remove a station');
}

async function testCampusSource(service) {
  service.clearCache();
  const before = locationCalls;
  const phases = [];
  httpReplies.push(nearbyReply(11), nearbyReply(22));
  await service.fetchNearbyStations(undefined, stage => phases.push(stage), false, 'campus');
  assert.equal(locationCalls, before);
  assert.deepEqual(phases, ['querying']);
  assert.equal(JSON.parse(httpTrace.at(-1).options.extraData).latitude, 30.751);
  assert.equal((await service.fetchNearbyStations()).stations[0].stationId, 22);
  assert.equal(locationCalls, before + 1);
  assert.equal((await service.fetchNearbyStations(undefined, undefined, false, 'campus')).stations[0].stationId, 11);
  assert.equal((await service.fetchNearbyStations()).stations[0].stationId, 22);
}

async function testHistory(base) {
  modules.clear();
  savedHistory.clear();
  const start = testNow;
  for (let id = 1; id <= 130; id++) {
    savedHistory.set('s' + id, JSON.stringify({ id, fetchedAt: start - id,
      outlets: [{ serial: 1, outletNo: String(id), status: 2, fee: 123, used_min: 12 }] }));
  }
  savedHistory.set('s140', 'not valid JSON');
  savedHistory.set('s141', JSON.stringify({ id: 141, fetchedAt: start + 1, outlets: [{ serial: 1, outletNo: '141', status: 2 }] }));
  const service = load(base + 'services/StationService.ets').StationService;
  await service.initSnapshots({});
  const history = service.getSnapshot(1, 'Custom');
  assert.deepEqual([history.confirmed, history.fromDisk, history.station.name], [false, true, 'Custom']);
  assert.equal(history.station.outlets[0].fee, undefined);
  assert.equal(savedHistory.size, 128);
  assert.equal(service.getSnapshot(129, 'Expired'), null);
  assert.equal(service.getSnapshot(140, 'Bad'), null);
  assert.equal(service.getSnapshot(141, 'Future'), null);
  assert.ok(!savedHistory.get('s1').includes('fee'));
  const before = calls;
  await service.fetchStationsForConfig({ Custom: 1 });
  assert.equal(calls, before + 1, 'disk-only records require network verification even when younger than 15s');
  assert.equal(service.getSnapshot(1, 'Custom').fromDisk, false);
  service.retainStationIds([1, 2]);
  await turn();
  assert.deepEqual(Array.from(savedHistory.keys()).sort(), ['s1', 's2']);
  assert.equal(service.getSnapshot(3, 'Removed'), null);
  testNow++;
  const unblock = holdStation(2);
  const partial = service.fetchStationsForConfig({ Fast: 1, Slow: 2 }, undefined, true);
  try {
    await new Promise(resolve => setTimeout(resolve, 225));
    assert.equal(JSON.parse(savedHistory.get('s1')).fetchedAt, testNow, 'early basic results persist while other stations are still waiting');
  } finally { unblock(); }
  await partial;
  service.retainStationIds([1, 2, 3]);
  await turn();
  const flush = prefs.flush;
  prefs.flush = async () => { prefs.flush = flush; throw new Error('flush failed'); };
  await service.fetchStationsForConfig({ Temporary: 3 });
  assert.ok(service.getSnapshot(3, 'Temporary').confirmed, 'cache I/O failure cannot fail valid network data');
  service.retainStationIds([1, 2]);
  await turn();
  assert.ok(!savedHistory.has('s3'), 'retention reconciles partial preferences writes after failed flush');
  const serialized = savedHistory.get('s1');
  assert.ok(!serialized.includes('Custom') && !serialized.includes('power_w') && !serialized.includes('used_min'));
  modules.clear();
  const reopened = load(base + 'services/StationService.ets').StationService;
  await reopened.initSnapshots({});
  assert.ok(reopened.getSnapshot(1, 'Local').fromDisk && !reopened.getSnapshot(1, 'Local').confirmed);
  assert.equal(reopened.getSnapshot(1, 'Local', start - 1), null, 'reject a timestamp in the future');
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
  assert.equal(calls, firstCalls, 'successful stations cached; failed station in automatic backoff');
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
  const releaseOld = holdStation(1);
  const oldEvents = [];
  const beforeOld = calls;
  const oldRequest = StationService.fetchStationsForConfig(config, progress => oldEvents.push(progress));
  StationService.clearCache();
  releaseOld();
  await oldRequest;
  assert.deepEqual(oldEvents, [], 'invalidated queries must not emit progress for the next configuration');
  assert.ok(calls - beforeOld <= 4, 'workers must not start queued requests from an invalidated query');
  const afterOld = calls;
  const freshResult = await StationService.fetchStationsForConfig({ Fresh: 1 });
  assert.equal(calls, afterOld + 1, 'cache clear must invalidate in-flight writes too');
  assert.equal(freshResult.stations[0].name, 'Fresh');

  StationService.clearCache();
  await StationService.fetchStationsForConfig({ Active: 1 });
  const beforeRelocate = calls;
  const coldPhases = [];
  const originalNearby = await StationService.fetchNearbyStations(undefined, phase => coldPhases.push(phase));
  assert.deepEqual(coldPhases, ['locating', 'querying']);
  assert.ok(originalNearby.locationStatus.includes('默认位置'));
  const cachedPhases = [];
  const cachedNearby = await StationService.fetchNearbyStations(undefined, phase => cachedPhases.push(phase));
  assert.deepEqual(cachedPhases, [], 'a nearby cache hit must not display network or permission activity');
  assert.ok(cachedNearby.locationStatus.includes('默认位置'));
  assert.ok(cachedNearby.locationStatus.includes('权限'), 'cached lookup must retain location provenance for permission retry');
  assert.equal(nearbyCalls, 1);
  nearbyStatus = '已获取设备位置';
  const forcedPhases = [];
  const forcedNearby = await StationService.fetchNearbyStations(undefined, phase => forcedPhases.push(phase), true);
  assert.equal(forcedNearby.locationStatus, '已获取设备位置');
  assert.deepEqual(forcedPhases, coldPhases);
  assert.equal(nearbyCalls, 2);
  await StationService.fetchStationsForConfig({ Active: 1 });
  assert.equal(calls, beforeRelocate, 'requerying nearby stations must preserve the monitor cache');

  StationService.clearCache();
  testNow = 2000000;
  const acquired = await StationService.fetchStationsForConfig({ First: 1 });
  assert.equal(acquired.oldestFetchedAt, 2000000);
  testNow += 5000;
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

  await testStationProgress(StationService);
  const { DataCache } = load(base + 'utils/DataCache.ets');
  await testSharedStationRefresh(StationService, DataCache);
  await testChangedConfiguration(StationService);
  await testOverlappingCacheEpochs(StationService, DataCache);

  const { ChargerApi } = load(base + 'api/ChargerApi.ets', true);
  const realNearbyService = load(base + 'services/StationService.ets', true).StationService;
  await testNearbySubscribers(realNearbyService);
  await testNearbyContextIsolation(realNearbyService);
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
  const knownLocation = locationResult;
  let releaseLocation;
  locationResult = new Promise(resolve => { releaseLocation = resolve; });
  const apiPhases = [];
  const beforeLocation = requests;
  const nearbyQuery = ChargerApi.fetchNearbyStations(undefined, phase => apiPhases.push(phase));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(apiPhases, ['locating'], 'the UI must remain in locating phase while the device location is pending');
  assert.equal(requests, beforeLocation);
  releaseLocation(knownLocation);
  const nearby = await nearbyQuery;
  assert.deepEqual(apiPhases, ['locating', 'querying']);
  assert.equal(requests, beforeLocation + 1);
  assert.deepEqual(Array.from(nearby.stations, station => station.stationId), [1, 3, 2]);
  assert.equal(nearby.stations[0].distance, 0, 'zero latitude and longitude are valid');
  assert.equal(nearby.stations[2].distance, undefined);
  assert.equal(nearby.stations[2].formattedDistance, '距离未知');
  assert.equal(nearby.stations[2].freeNum, -1, 'unknown free count is not zero');
  locationResult = { ...knownLocation, needOpenLocationService: true };
  const disabledPhases = [];
  const beforeDisabled = requests;
  const disabledNearby = await ChargerApi.fetchNearbyStations(undefined, phase => disabledPhases.push(phase));
  assert.equal(disabledNearby.needOpenLocationService, true);
  assert.deepEqual(disabledPhases, ['locating']);
  assert.equal(requests, beforeDisabled, 'system location disabled must not claim a nearby network query');
  locationResult = knownLocation;
  await testLayeredReading(realNearbyService);
  await testRetryPolicy(realNearbyService);
  await testCampusSource(realNearbyService);
  await testHistory(base);
  assert.equal(httpReplies.length, 0);
  assert.equal(destroyed, created, 'every HTTP object must be destroyed, including failures and early returns');
  console.log('PASS: split basic/detail requests, detail concurrency/stop/generation/retry, 15s/30s/10min freshness, persistent cold snapshots/retention/corruption, bounded infrastructure and station retries, incremental progress, nearby sources/authorization/reentry, HTTP validation/cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
