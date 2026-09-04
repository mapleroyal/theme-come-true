import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

// Only this test process's timezone changes; production uses the desktop zone.
process.env.TZ = 'America/Chicago';
function model(name) {
  const context = vm.createContext({});
  vm.runInContext(readFileSync(fileURLToPath(new URL(`../${name}.js`, import.meta.url)), 'utf8'), context);
  return context;
}
const schedule = model('ScheduleModel');
const navigation = model('NavigationModel');
const ms = value => new Date(value).getTime();
const plain = value => JSON.parse(JSON.stringify(value));
const base = { lightStart: '07:00', darkStart: '19:00', currentMode: 'dark', solarReady: false, solarEvents: [] };
const state = (at, patch = {}) => schedule.scheduleState({ ...base, ...patch }, ms(at));

test('fixed boundaries switch exactly at the configured local time', () => {
  assert.equal(state('2026-09-04T06:59:59-05:00').mode, 'dark');
  const morning = state('2026-09-04T07:00:00-05:00');
  assert.equal(morning.mode, 'light');
  assert.equal(morning.nextEpoch, ms('2026-09-04T19:00:00-05:00'));
  assert.equal(state('2026-09-04T19:00:00-05:00').mode, 'dark');
});

test('reversed and midnight schedules preserve chronological ordering', () => {
  const reversed = { lightStart: '22:00', darkStart: '07:00' };
  assert.equal(state('2026-09-04T12:00:00-05:00', reversed).mode, 'dark');
  assert.equal(state('2026-09-05T00:00:00-05:00', reversed).mode, 'light');
  assert.equal(state('2026-09-04T00:00:00-05:00', { lightStart: '00:00' }).mode, 'light');
});

test('equal times preserve the currently observed mode and advance the boundary', () => {
  const result = state('2026-09-04T07:00:00-05:00', { darkStart: '07:00', currentMode: 'light' });
  assert.equal(result.mode, 'light');
  assert.equal(result.nextEpoch, ms('2026-09-05T07:00:00-05:00'));
  assert.match(result.token, /^equal:light:/);
});

test('manual override expires exactly at its persisted deadline', () => {
  const override = { manualOverrideMode: 'dark', manualOverrideUntil: ms('2026-09-04T12:00:00-05:00') / 1000 };
  assert.equal(state('2026-09-04T11:59:59-05:00', override).mode, 'dark');
  assert.equal(state('2026-09-04T12:00:00-05:00', override).mode, 'light');
  assert.equal(state('2026-09-04T11:00:00-05:00', { ...override, manualOverrideMode: 'invalid' }).mode, 'light');
});

test('an active manual override remains usable while solar data is unavailable', () => {
  const result = state('2026-09-04T11:00:00-05:00', {
    lightStart: 'sunrise', manualOverrideMode: 'light',
    manualOverrideUntil: ms('2026-09-04T12:00:00-05:00') / 1000,
  });
  assert.equal(result.valid, true);
  assert.equal(result.nextEvent, 'override');
});

const solarEvents = [
  { event: 'sunrise', epoch: ms('2026-09-03T06:31:00-05:00') / 1000 },
  { event: 'sunset', epoch: ms('2026-09-03T19:18:00-05:00') / 1000 },
  { event: 'sunrise', epoch: ms('2026-09-04T06:32:00-05:00') / 1000 },
  { event: 'sunset', epoch: ms('2026-09-04T19:16:00-05:00') / 1000 },
  { event: 'sunrise', epoch: ms('2026-09-05T06:33:00-05:00') / 1000 },
];
test('solar and mixed schedules use actual event epochs', () => {
  const solar = { lightStart: 'sunrise', darkStart: 'sunset', solarReady: true, solarEvents };
  assert.equal(state('2026-09-04T06:31:59-05:00', solar).mode, 'dark');
  assert.equal(state('2026-09-04T06:32:00-05:00', solar).mode, 'light');
  assert.equal(state('2026-09-04T12:00:00-05:00', solar).nextEpoch, ms('2026-09-04T19:16:00-05:00'));
  assert.equal(state('2026-09-04T12:00:00-05:00', { ...solar, darkStart: '18:00' }).nextEpoch,
    ms('2026-09-04T18:00:00-05:00'));
  assert.equal(state('2026-09-04T06:45:00-05:00', { ...solar, lightStart: '07:00' }).mode, 'dark');
});

test('missing solar data never guesses a schedule and malformed events are excluded', () => {
  assert.equal(state('2026-09-04T12:00:00-05:00', { lightStart: 'sunrise' }).token, 'solar:waiting');
  const result = state('2026-09-04T12:00:00-05:00', {
    lightStart: 'sunrise', darkStart: 'sunset', solarReady: true,
    solarEvents: [{ event: 'sunrise', epoch: NaN }, { event: 'sunset', epoch: -1 }],
  });
  assert.equal(result.valid, false);
  assert.equal(result.token, 'schedule:incomplete');
});

test('local calendar boundaries span 23 and 25 hours across DST', () => {
  const spring = schedule.fixedBoundaryEvents('light', '07:00', ms('2026-03-08T12:00:00-05:00'));
  const autumn = schedule.fixedBoundaryEvents('light', '07:00', ms('2026-11-01T12:00:00-06:00'));
  assert.equal(spring[1].epoch - spring[0].epoch, 23 * 3600000);
  assert.equal(autumn[1].epoch - autumn[0].epoch, 25 * 3600000);
  assert.equal(spring[1].epoch, ms('2026-03-08T07:00:00-05:00'));
  assert.equal(autumn[1].epoch, ms('2026-11-01T07:00:00-06:00'));
});

test('DST gap normalizes forward and repeated time selects the first occurrence', () => {
  assert.equal(state('2026-03-08T03:00:00-05:00', { lightStart: '02:30' }).nextEpoch,
    ms('2026-03-08T03:30:00-05:00'));
  assert.equal(state('2026-11-01T01:15:00-06:00', { lightStart: '01:30' }).mode, 'light');
});

test('boundary normalization preserves supported choices', () => {
  assert.equal(schedule.normalizedBoundary('light', 'sunrise'), 'sunrise');
  assert.equal(schedule.normalizedBoundary('dark', 'sunset'), 'sunset');
  assert.equal(schedule.normalizedBoundary('light', 'sunset'), '07:00');
  assert.equal(schedule.validTime('24:00'), false);
  assert.equal(schedule.parseMinutes('23:59'), 1439);
});

test('ordered theme navigation wraps and handles external or removed current themes', () => {
  const options = [{ value: 'a' }, { value: 'b' }, { value: 'c' }];
  assert.equal(navigation.nextValue(options, 'c', 'next'), 'a');
  assert.equal(navigation.nextValue(options, 'a', 'previous'), 'c');
  assert.equal(navigation.nextValue(options, 'removed', 'next'), 'a');
  assert.equal(navigation.nextValue(options, 'removed', 'previous'), 'c');
  assert.equal(navigation.nextValue([], 'a', 'next'), '');
});

test('history commits use captured action endpoints without mutating inputs', () => {
  const history = Object.freeze(['a']);
  const next = navigation.commitHistory(history, 'b', 'random', 'b', 'c');
  assert.deepEqual(plain(next), { history: ['a', 'b'], tip: 'c' });
  const back = navigation.backTarget(next.history, next.tip, 'c', ['a', 'b', 'c']);
  assert.equal(back.target, 'b');
  assert.deepEqual(plain(navigation.commitHistory(next.history, next.tip, 'history-back', 'c', 'b')),
    { history: ['a'], tip: 'b' });
  assert.deepEqual(history, ['a']);
});

test('external changes invalidate history and deleted targets are pruned', () => {
  assert.equal(navigation.backTarget(['a'], 'b', 'external').invalidated, true);
  assert.deepEqual(plain(navigation.backTarget(['a', 'deleted', 'current'], 'current', 'current', ['a', 'current'])),
    { history: ['a'], tip: 'current', target: 'a', invalidated: false });
  assert.deepEqual(plain(navigation.commitHistory(['old'], 'different', 'select', 'actual', 'new')),
    { history: ['actual'], tip: 'new' });
});

test('ordered navigation clears random history and history stays bounded', () => {
  assert.deepEqual(plain(navigation.commitHistory(['a'], 'b', 'sorted', 'b', 'c')), { history: [], tip: '' });
  const result = navigation.commitHistory(Array.from({ length: 40 }, (_, i) => String(i)), '40', 'random', '40', '41');
  assert.equal(result.history.length, 32);
  assert.equal(result.history.at(-1), '40');
});

test('random plans do not consume caller state until a successful commit', () => {
  const bag = Object.freeze(['b', 'c', 'd']);
  const first = navigation.chooseRandom(['a', 'b', 'c', 'd'], 'a', bag, [], 0);
  const retry = navigation.chooseRandom(['a', 'b', 'c', 'd'], 'a', bag, [], 0);
  assert.deepEqual(plain(first), plain(retry));
  assert.deepEqual(bag, ['b', 'c', 'd']);
  assert.deepEqual(plain(first), { target: 'b', bag: ['c', 'd'] });
});

test('shuffle bags avoid repeats, removed choices, current value and recent history', () => {
  const options = ['a', 'b', 'c', 'd', 'e'];
  const first = navigation.chooseRandom(options, 'a', ['a', 'deleted', 'b', 'b', 'c', 'd', 'e'], ['b', 'c', 'd'], 0);
  assert.equal(first.target, 'e');
  assert.deepEqual(plain(first.bag), ['b', 'c', 'd']);
  const second = navigation.chooseRandom(options, 'e', first.bag, [], 0);
  assert.equal(second.target, 'b');
  assert.equal(second.bag.includes('e'), false);
  assert.equal(navigation.chooseRandom(['only'], 'only', [], [], 0).target, 'only');
  assert.equal(navigation.chooseRandom([], 'a', [], [], 0).target, '');
});
