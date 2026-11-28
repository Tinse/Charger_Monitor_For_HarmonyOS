const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
if (!process.env.DEVECO_CLI_STUDIO_PATH) throw new Error('Set DEVECO_CLI_STUDIO_PATH.');
const ts = require(path.join(process.env.DEVECO_CLI_STUDIO_PATH, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const loaded = new Map();
function load(relative) {
  const filename = path.resolve(root, relative);
  if (loaded.has(filename)) return loaded.get(filename);
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  const module = { exports: {} };
  loaded.set(filename, module.exports);
  const localRequire = name => load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')));
  new vm.Script(output, { filename }).runInNewContext({ module, exports: module.exports, require: localRequire });
  return module.exports;
}
const { StationSelection: S } = load('entry/src/main/ets/pages/utils/StationSelection.ets');
const current = { id: 'local', name: 'Saved', createdAt: 0,
  stations: { 'My main alias': 74677, 'Saved outside nearby list': 900001 },
  stationNames: { '74677': 'Main C original name', '900001': 'Other original name' } };
const saved = S.savedStations(current);
const aliases = S.displayNames(current);
assert.equal(saved[0].stationName, 'Main C original name');
assert.equal(aliases['74677'], 'My main alias');
const available = [{ stationId: 74677, stationName: 'Main C original name', address: 'Campus', freeNum: 1 },
  { stationId: 74746, stationName: 'Other available name', address: 'Commercial street', freeNum: 0 }];
const merged = S.mergeAvailable(available, saved, [74677, 900001]);
assert.deepEqual(Array.from(merged, station => station.stationId), [74677, 74746, 900001]);
const copyMap = S.toStationMap(merged, [74677, 900001], aliases);
assert.equal(copyMap['My main alias'], 74677, 'nearby refresh must not overwrite copied display aliases');
assert.equal(copyMap['Saved outside nearby list'], 900001);
const copyNames = S.toStationNames(merged, [74677, 900001], current.stationNames);
assert.equal(copyNames['74677'], 'Main C original name');
assert.equal(copyNames['900001'], 'Other original name');
assert.equal(S.filter(merged, '74677').length, 1);
assert.equal(S.filter(merged, 'commercialstreet').length, 1);
assert.equal(S.filter(merged, 'my main alias', aliases).length, 1);
assert.equal(S.filter(merged, 'maincoriginalname', aliases).length, 1);
const existing = [74677, 900001];
assert.equal(S.candidates(merged, 'add', existing).length, 3, 'add mode keeps joined rows visible');
assert.equal(S.canSelect(74677, 'add', existing), false, 'joined rows cannot be added again');
assert.deepEqual(Array.from(S.candidates(merged, 'replace', existing), station => station.stationId), [74746]);
assert.deepEqual(Array.from(S.setSelected([], 74677, true, 'add', existing)), []);
let selected = S.setSelected([], 74746, true, 'replace', []);
selected = S.setSelected(selected, 74677, true, 'replace', []);
assert.deepEqual(Array.from(selected), [74677], 'replacement selection must stay single');
selected = S.setSelected(selected, 74746, false, 'replace', []);
assert.deepEqual(Array.from(selected), [74677], 'old radio deselection must not clear the new selection');
assert.deepEqual(Array.from(S.setSelected(selected, 74677, false, 'replace', [])), []);
assert.throws(() => S.toStationMap(available, [74677, 74746], { '74677': 'same', '74746': 'same' }), /重名/);
assert.throws(() => S.toStationNames(available, [999999]), /缺失/);
const sameSource = [
  { stationId: 201, stationName: 'Shared original', address: 'Campus', freeNum: 0 },
  { stationId: 202, stationName: 'Shared original', address: 'Campus', freeNum: 0 },
  { stationId: 203, stationName: 'Other original', address: 'Campus', freeNum: 0 }
];
const createSameSource = S.toStationMap(sameSource, [201, 202]);
assert.equal(createSameSource['Shared original'], 201);
assert.equal(createSameSource['Shared original（202）'], 202);
const aliasPriority = S.toStationMap(sameSource, [201, 203], { '203': 'Shared original' });
assert.equal(aliasPriority['Shared original'], 203, 'explicit alias takes priority even if selected after the source-name station');
assert.equal(aliasPriority['Shared original（201）'], 201);
const nestedCollision = S.toStationMap(sameSource, [201, 202, 203], { '203': 'Shared original（202）' });
assert.equal(nestedCollision['Shared original（202）'], 203);
assert.equal(nestedCollision['Shared original（202） 2'], 202);
assert.throws(() => S.toStationMap(sameSource, [201, 203], { '201': 'My alias', '203': ' myALIAS ' }), /重名/);
assert.throws(() => S.toStationMap(sameSource, [201], { '201': '__proto__' }), /别名无效/);
const reservedSource = S.toStationMap([{ stationId: 204, stationName: '__proto__', address: '', freeNum: 0 }], [204]);
assert.equal(reservedSource['__proto__（204）'], 204);
assert.throws(() => S.toStationMap(sameSource, [201, 201]), /重复/);
assert.equal(Object.keys(S.toStationMap([], [])).length, 0, 'a named new or copied empty configuration can have no station rows');
const catalog = S.campusCatalog();
assert.equal(catalog.length, 22);
assert.equal(new Set(catalog.map(station => station.stationId)).size, 22);
assert.ok(catalog.every(station => station.freeNum === -1 && station.address.includes('本地校园预设')));
console.log('PASS: same-source name disambiguation/alias priority/named empty selection, picker modes, joined exclusion, replacement single-select, ID/address/alias search, copy alias/original-name preservation and offline campus catalog');
