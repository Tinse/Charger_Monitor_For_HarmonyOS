// Exercise the ArkTS network observer with deferred system callbacks and queries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const studio = process.env.DEVECO_CLI_STUDIO_PATH;
if (!studio) throw new Error('Set DEVECO_CLI_STUDIO_PATH to your DevEco Studio installation.');
const ts = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const filename = path.join(__dirname, '../entry/src/main/ets/pages/services/NetworkState.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;

function fixture(failure) {
  const checks = [];
  const listeners = [];
  const errors = [];
  const connection = {
    hasDefaultNet: () => new Promise((resolve, reject) => checks.push({ resolve, reject })),
    createNetConnection() {
      if (failure === 'create') throw new Error('network observer unavailable');
      const events = new Map();
      const listener = {
        events,
        unregisters: 0,
        register(callback) {
          if (failure === 'registerThrows') throw new Error('registration unavailable');
          this.completeRegistration = callback;
        },
        on: (name, callback) => events.set(name, callback),
        unregister(callback) {
          this.unregisters++;
          callback();
        }
      };
      listeners.push(listener);
      return listener;
    }
  };
  const module = { exports: {} };
  const dependencies = name => {
    if (name === '@kit.NetworkKit') return { connection };
    if (name === '../utils/ErrorHandler') return { ErrorHandler: { handle: (_error, where) => errors.push(where) } };
    throw new Error('Unexpected runtime dependency: ' + name);
  };
  new vm.Script(compiled, { filename }).runInNewContext({ module, exports: module.exports, require: dependencies });
  return { state: new module.exports.NetworkState(), listeners, checks, errors };
}

const settle = () => new Promise(resolve => setImmediate(resolve));

async function initialAndUpdates(initial) {
  const { state, listeners, checks } = fixture();
  const changes = [];
  state.start(online => changes.push(online));
  assert.deepEqual(changes, []);
  const first = checks[0];
  listeners[0].completeRegistration();
  checks.at(-1).resolve(initial);
  await settle();
  first.resolve(!initial);
  await settle();
  assert.deepEqual(changes, [initial], 'late startup query must not overwrite registration-time query');

  listeners[0].events.get('netUnavailable')();
  const lost = checks.at(-1);
  listeners[0].events.get('netAvailable')();
  const available = checks.at(-1);
  available.resolve(true);
  await settle();
  lost.resolve(false);
  await settle();
  assert.deepEqual(changes, [initial, true], 'a newer successful probe wins across event types');

  listeners[0].events.get('netLost')();
  checks.at(-1).resolve(false);
  await settle();
  listeners[0].events.get('netUnavailable')();
  checks.at(-1).reject(new Error('default-net probe failed'));
  await settle();
  assert.deepEqual(changes, [initial, true, false], 'failed probe must preserve a known offline state');

  listeners[0].events.get('netAvailable')();
  const pending = checks.at(-1);
  state.stop();
  pending.resolve(true);
  await settle();
  state.stop();
  assert.deepEqual(changes, [initial, true, false], 'stopped observer must ignore pending probes');
  assert.equal(listeners[0].unregisters, 1);
}

async function registrationRaces() {
  const { state, listeners, checks } = fixture();
  const oldChanges = [], changes = [];
  state.start(online => oldChanges.push(online));
  const pending = checks.at(-1);
  state.stop();
  assert.equal(listeners[0].unregisters, 0, 'pending registration cannot be unregistered until SDK confirms success');
  state.start(online => changes.push(online));
  listeners[0].completeRegistration();
  assert.equal(listeners[0].unregisters, 1, 'late successful registration must immediately be released');
  assert.equal(listeners[0].events.size, 0);
  pending.resolve(true);
  listeners[1].completeRegistration();
  checks.at(-1).resolve(false);
  await settle();
  assert.deepEqual(oldChanges, []);
  assert.deepEqual(changes, [false]);
  state.stop();
  assert.equal(listeners[1].unregisters, 1);

  state.start(online => changes.push(online));
  state.stop();
  listeners[2].completeRegistration(new Error('rejected'));
  checks.at(-1).reject(new Error('stopped probe failed'));
  await settle();
  assert.equal(listeners[2].unregisters, 0, 'registration failure never established a listener');
  assert.deepEqual(changes, [false]);
}

async function initialProbeFallback(failure) {
  const { state, listeners, checks } = fixture(failure);
  const changes = [];
  state.start(online => changes.push(online));
  if (failure === 'registerCallback') listeners[0].completeRegistration(new Error('permission denied'));
  checks.at(-1).reject(new Error('network state unavailable'));
  await settle();
  assert.deepEqual(changes, [true], 'unknown network must permit an initial HTTP probe: ' + failure);
  const retry = state.refresh();
  checks.at(-1).resolve(false);
  await retry;
  assert.deepEqual(changes, [true, false], 'later network observations can correct the fallback');
  state.stop();
}

async function detachedEvents() {
  const { state, listeners, checks } = fixture();
  const events = [];
  state.start(online => events.push(online));
  listeners[0].completeRegistration();
  checks.at(-1).resolve(true);
  await settle();
  const detached = Array.from(listeners[0].events.values());
  assert.equal(detached.length, 3);
  state.stop();
  const stoppedCount = checks.length;
  detached.forEach(callback => callback());
  assert.equal(checks.length, stoppedCount, 'queued native events after stop must not probe');
  state.start(online => events.push(online));
  const restartedCount = checks.length;
  const firstNewCheck = checks.at(-1);
  detached.forEach(callback => callback());
  assert.equal(checks.length, restartedCount, 'old listeners must not supersede a new startup query');
  firstNewCheck.resolve(false);
  await settle();
  assert.deepEqual(events, [true, false]);
  state.stop();
  listeners[1].completeRegistration();
}

async function main() {
  await initialAndUpdates(true);
  await initialAndUpdates(false);
  await registrationRaces();
  await detachedEvents();
  for (const failure of ['create', 'registerThrows', 'registerCallback']) await initialProbeFallback(failure);
  console.log('PASS: initial online/offline, stale network probes, registered/pending stop races, create/register failures and HTTP-probe fallback');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
