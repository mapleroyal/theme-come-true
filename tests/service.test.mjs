import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../Service.qml', import.meta.url), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
function loadModel(name) {
  const context = vm.createContext({});
  vm.runInContext(readFileSync(new URL(`../${name}.js`, import.meta.url), 'utf8'), context);
  return context;
}

// Execute the current production function bodies, not a second implementation
// of the state machine. Qt bindings, subprocesses and timers are explicit fakes.
function functions(text) {
  const found = [];
  for (const match of text.matchAll(/^  function (\w+)\([^\n]*\) \{/gm)) {
    const start = match.index + 2;
    let i = text.indexOf('{', start), depth = 0, quote = '', comment = '';
    for (; i < text.length; i++) {
      const char = text[i], next = text[i + 1];
      if (comment === 'line') { if (char === '\n') comment = ''; continue; }
      if (comment === 'block') { if (char === '*' && next === '/') { comment = ''; i++; } continue; }
      if (quote) {
        if (char === '\\') i++;
        else if (char === quote) quote = '';
        continue;
      }
      if (char === '/' && next === '/') { comment = 'line'; i++; continue; }
      if (char === '/' && next === '*') { comment = 'block'; i++; continue; }
      if (char === '"' || char === "'" || char === '`') { quote = char; continue; }
      if (char === '{') depth++;
      if (char === '}' && --depth === 0) { i++; break; }
    }
    found.push({ name: match[1], text: text.slice(start, i) });
  }
  return found;
}

function inventory(theme = 'a', background = `/${theme}.png`, mode = 'dark') {
  return {
    version: 1,
    current: { theme, themeLabel: theme.toUpperCase(), background, backgroundName: background,
      mode, inThemePool: true, inModePool: true },
    pools: { theme: 3, mode: 3 },
    themes: ['a', 'b', 'c'].map(slug => ({ slug, label: slug, mode, validPalette: true })),
    palette: ['accent', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'foreground', 'background']
      .map(role => ({ role, label: role, color: '#111111' })),
  };
}

function harness() {
  const events = [], later = [], writes = [];
  let now = Date.now();
  class FakeDate extends Date {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
  }
  const root = {
    pluginId: 'io.github.mapleroyal.theme-come-true', helperPath: '/fixture/helper', operation: null,
    ready: true, requestSequence: 0, stateGeneration: 0, statusGeneration: -1,
    lastError: '', actionError: '', actionResult: null, actionStatus: '', actionFinished: true,
    actionStarted: false, statusFinished: true, statusReceived: false, statusError: '', refreshQueued: false,
    selectionFinished: true, selectionStarted: false, selectionOutput: '', selectionError: '',
    preparedSnapshot: null, pendingCompletion: null, themeRenderSerial: 0,
    lastScheduleToken: '', scheduleFailureToken: '', scheduleFailureCount: 0, scheduleRetryAt: 0,
    solarGeneration: 0, solarRequestGeneration: -1, solarFinished: true, solarReady: false,
    solarLoading: false, solarReceived: false, solarRefreshQueued: false, solarError: '', solarProcessError: '',
    solarEvents: [], solarLoadedAt: 0, solarLastAttemptAt: 0, solarLocation: '', solarLocationSource: '',
    clockNow: now, lightRandomBackHistory: [], darkRandomBackHistory: [],
    lightRandomHistoryTip: '', darkRandomHistoryTip: '', lightRandomBag: [], darkRandomBag: [],
    wallpaperRandomHistories: {}, wallpaperRandomTips: {},
  };
  let snapshot = inventory();
  Object.defineProperty(root, 'snapshot', { get: () => snapshot, set: value => {
    snapshot = value; events.push(['snapshot', value.current.theme, value.current.background, root.busy]);
  } });
  const getters = {
    busy: () => root.operation !== null, current: () => root.snapshot.current || {},
    currentTheme: () => root.current.theme || '', currentMode: () => root.current.mode || 'dark',
    currentBackground: () => root.current.background || '', currentInThemePool: () => root.current.inThemePool === true,
    themes: () => root.snapshot.themes || [], settings: () => root.settingsFromShell(),
    rememberedWallpapers: () => root.settings.rememberedWallpapers || {},
    wallpaperScope: () => root.settings.wallpaperScope || 'theme',
    lightThemeOptions: () => root.optionsForMode('light'), darkThemeOptions: () => root.optionsForMode('dark'),
    lightTheme: () => root.resolvedTheme('light', root.settings.lightTheme || 'a'),
    darkTheme: () => root.resolvedTheme('dark', root.settings.darkTheme || 'a'),
    themeNavigationBusy: () => root.busy,
    autoEnabled: () => root.settings.autoEnabled === true,
    lightStart: () => root.settings.lightStart || '07:00',
    darkStart: () => root.settings.darkStart || '19:00',
    usesSolarSchedule: () => root.lightStart === 'sunrise' || root.darkStart === 'sunset',
    manualOverrideMode: () => root.settings.manualOverrideMode || '',
    manualOverrideUntil: () => root.settings.manualOverrideUntil || 0,
  };
  for (const [key, get] of Object.entries(getters)) Object.defineProperty(root, key, { get });
  root.shell = {
    shellConfig: { bar: { layout: { left: [], center: [], right: [{ id: root.pluginId, darkTheme: 'a' }] } } },
    updateEntryInline(id, value) {
      writes.push(plain(value));
      this.shellConfig.bar.layout.right = [plain(value)];
      events.push(['settings', root.currentBackground, root.busy]);
      return true;
    },
  };
  const process = () => ({ running: false, command: [], signal() { this.running = false; } });
  const timer = () => ({ running: false, restart() { this.running = true; }, stop() { this.running = false; } });
  const rows = [];
  const context = vm.createContext({
    root, console, Date: FakeDate, ScheduleModel: loadModel('ScheduleModel'), NavigationModel: loadModel('NavigationModel'),
    Qt: { callLater: callback => later.push(callback), colorEqual: (a, b) => a === b },
    Color: { foreground: '#111111', background: '#111111', accent: '#111111' },
    actionProcess: process(), statusProcess: process(), selectionProcess: process(), solarProcess: process(),
    actionWatchdog: timer(), recoveryWatchdog: timer(), statusWatchdog: timer(), visualFallback: timer(), scheduleDebounce: timer(),
    solarWatchdog: timer(), solarRequestDebounce: timer(), weatherPanelProcess: process(),
    themePaletteModel: { get count() { return rows.length; }, get: index => rows[index],
      clear: () => { rows.length = 0; }, append: value => rows.push(value),
      setProperty: (index, key, value) => { rows[index][key] = value; } },
  });
  for (const fn of functions(source)) root[fn.name] = vm.runInContext(`(${fn.text})`, context);
  return { root, context, events, writes, later,
    setNow(value) { now = value; root.clockNow = value; },
    reveal(next = root.preparedSnapshot || root.snapshot) {
      root.themeRenderSerial += 1;
      for (const role of ['foreground', 'background', 'accent'])
        context.Color[role] = next.palette.find(entry => entry.role === role).color;
      root.commitPreparedVisual();
    },
    flush() { while (later.length) later.shift()(); },
  };
}

function complete(h, next, ok = true, exitCode = ok ? 0 : 1, options = {}) {
  if (ok && h.root.operation?.kind === 'theme' && options.reveal !== false) h.reveal(next);
  h.root.receiveActionLine(JSON.stringify({ version: 1, ok, status: next,
    warnings: options.warnings || [], error: ok ? '' : 'fixture failure' }));
  h.context.actionProcess.running = false;
  h.root.actionExited(exitCode);
}

test('rapid A→B→C wallpaper actions commit the observed state before unlocking; Previous returns B', () => {
  const h = harness(), { root } = h;
  root.startWallpaperAction('B', ['/fixture/helper'], 'random', '');
  assert.equal(root.busy, true);
  assert.equal(root.cycleWallpaper('next'), false);
  complete(h, inventory('a', '/b.png'));
  assert.equal(root.busy, false);
  assert.deepEqual(h.events.find(event => event[0] === 'snapshot'), ['snapshot', 'a', '/b.png', true]);
  root.startWallpaperAction('C', ['/fixture/helper'], 'random', '');
  assert.equal(root.operation.fromBackground, '/b.png');
  complete(h, inventory('a', '/c.png'));
  assert.deepEqual(plain(root.wallpaperRandomHistories['theme:a']), ['/a.png', '/b.png']);
  assert.equal(root.previousWallpaper(), true);
  assert.equal(root.operation.target, '/b.png');
  complete(h, inventory('a', '/b.png'));
  assert.deepEqual(plain(root.wallpaperRandomHistories['theme:a']), ['/a.png']);
  assert.equal(root.rememberedWallpapers['theme:a'], '/b.png');
});

test('inventories started before an operation cannot overwrite its committed snapshot', () => {
  const h = harness(), { root } = h;
  root.refresh();
  const oldGeneration = root.statusGeneration;
  root.startWallpaperAction('B', ['/fixture/helper'], 'random', '');
  root.consumeStatus(JSON.stringify(inventory('a', '/stale.png')));
  assert.equal(root.currentBackground, '/a.png');
  complete(h, inventory('a', '/b.png'));
  assert.notEqual(oldGeneration, root.stateGeneration);
  root.consumeStatus(JSON.stringify(inventory('a', '/stale.png')));
  h.context.statusProcess.running = false;
  root.statusExited(0);
  assert.equal(root.currentBackground, '/b.png');
  assert.equal(root.ready, true);
});

test('theme settings and random history persist only after a successful verified result', () => {
  const h = harness(), { root } = h;
  assert.equal(root.chooseTheme('dark', 'b', 'random', ['c']), true);
  complete(h, inventory('b'));
  assert.equal(root.settings.darkTheme, 'b');
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
  assert.deepEqual(plain(root.darkRandomBag), ['c']);
  root.chooseTheme('dark', 'c', 'random', []);
  complete(h, inventory('b'), false);
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.settings.darkTheme, 'b');
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
  assert.equal(root.lastError, 'fixture failure');
  assert.equal(root.busy, false);
});

test('successful exit with a wrong theme is not accepted as a completed request', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b', 'random', ['c']);
  complete(h, inventory('a'), true);
  assert.equal(root.settings.darkTheme, 'a');
  assert.deepEqual(plain(root.darkRandomBackHistory), []);
  assert.equal(root.busy, false);
  assert.equal(root.lastError, 'Appearance change failed');
});

test('missing final output keeps the lock while inventory verifies failure', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b', 'random', ['c']);
  h.context.actionProcess.running = false;
  root.actionExited(1);
  assert.equal(root.busy, true);
  assert.equal(root.operation.phase, 'verifying');
  assert.equal(h.context.statusProcess.running, true);
  root.consumeStatus(JSON.stringify(inventory('b')));
  h.context.statusProcess.running = false;
  root.statusExited(0);
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.busy, false);
  assert.equal(root.settings.darkTheme, 'a');
  assert.deepEqual(plain(root.darkRandomBackHistory), []);
});

test('failed recovery inventory releases the lock and disables actions until a refresh succeeds', () => {
  const h = harness(), { root } = h;
  root.startWallpaperAction('B', ['/fixture/missing'], 'random', '');
  h.context.actionProcess.running = false;
  root.recoverAction('Could not start appearance helper');
  h.context.statusProcess.running = false;
  root.statusExited(-1);
  assert.equal(root.busy, false);
  assert.equal(root.ready, false);
  assert.equal(root.randomWallpaper(), false);
  root.refresh();
  root.consumeStatus(JSON.stringify(inventory('a')));
  h.context.statusProcess.running = false;
  root.statusExited(0);
  assert.equal(root.ready, true);
});

test('picker cancellation is a state-preserving result, and failed launch releases its lock', () => {
  const h = harness(), { root } = h;
  root.startWallpaperSelection('Choose', ['/fixture/picker'], 'browse');
  root.selectionOutput = JSON.stringify({ version: 1, selected: false });
  root.finishWallpaperSelection(0);
  assert.equal(root.busy, false);
  assert.equal(root.currentBackground, '/a.png');
  assert.equal(h.writes.length, 0);
  assert.equal(h.context.statusProcess.running, false);
  h.context.selectionProcess.running = false;
  root.startWallpaperSelection('Choose', ['/fixture/missing'], 'file');
  root.finishWallpaperSelection(-1);
  assert.equal(root.busy, false);
  assert.equal(root.lastError, 'Could not open the file chooser');
});

test('selected wallpaper moves directly into an apply operation with its current snapshot captured', () => {
  const h = harness(), { root } = h;
  root.startWallpaperSelection('Choose', ['/fixture/picker'], 'file');
  root.selectionOutput = JSON.stringify({ version: 1, selected: true, path: '/personal.png' });
  h.context.selectionProcess.running = false;
  root.finishWallpaperSelection(0);
  assert.equal(root.busy, true);
  assert.equal(root.operation.kind, 'wallpaper');
  assert.equal(root.operation.fromBackground, '/a.png');
  assert.equal(root.operation.target, '/personal.png');
});

test('visual preparation updates presentation without claiming final success or consuming history', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b', 'random', ['c']);
  assert.equal(root.prepareVisual('obsolete', JSON.stringify(inventory('b'))), 'ignored');
  assert.equal(root.prepareVisual(root.operation.id, JSON.stringify(inventory('b'))), 'ready');
  assert.equal(root.currentTheme, 'a');
  h.flush();
  assert.equal(root.currentTheme, 'a', 'preparation only preloads until the visual reveal arrives');
  root.receiveActionLine(JSON.stringify({ version: 1, event: 'applied', status: inventory('b') }));
  h.reveal(inventory('b'));
  h.flush();
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.operation.visualCommitted, true);
  assert.equal(root.busy, true);
  assert.equal(root.settings.darkTheme, 'a');
  assert.deepEqual(plain(root.darkRandomBackHistory), []);
  complete(h, inventory('a'), false);
  assert.equal(root.currentTheme, 'a');
  assert.equal(root.busy, false);
  assert.deepEqual(plain(root.darkRandomBackHistory), []);
});

test('reload preserves preferences and remembered paths but intentionally starts fresh random history', () => {
  const h = harness();
  h.root.chooseTheme('dark', 'b', 'random', ['c']);
  complete(h, inventory('b'));
  const reloaded = harness();
  reloaded.root.shell.shellConfig = plain(h.root.shell.shellConfig);
  assert.equal(reloaded.root.settings.darkTheme, 'b');
  assert.equal(reloaded.root.rememberedWallpapers['theme:b'], '/b.png');
  assert.deepEqual(plain(reloaded.root.darkRandomBackHistory), []);
  assert.deepEqual(plain(reloaded.root.darkRandomBag), []);
});

test('mode roundtrips preserve random-theme history for Previous', () => {
  const h = harness(), { root } = h;
  const bothModes = (theme, mode = 'dark') => ({
    ...inventory(theme, `/${theme}.png`, mode),
    themes: [...inventory().themes, { slug: 'light', label: 'Light', mode: 'light', validPalette: true }],
  });
  root.snapshot = bothModes('a');
  root.updateSettings({ lightTheme: 'light' });
  root.chooseTheme('dark', 'c', 'random', ['b']);
  complete(h, bothModes('c'));
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
  assert.equal(root.requestMode('light', false), true);
  complete(h, bothModes('light', 'light'));
  assert.equal(root.requestMode('dark', false), true);
  complete(h, bothModes('c'));
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
  assert.deepEqual(plain(root.darkRandomBag), ['b']);
  assert.equal(root.previousTheme(), true);
  assert.equal(root.operation.theme, 'a', 'Previous returns the random predecessor, not sorted b');
});

test('failed scheduled changes back off, grow the delay, and allow a new boundary immediately', () => {
  const h = harness(), { root } = h;
  const startedAt = root.clockNow;
  root.updateSettings({ autoEnabled: true, darkTheme: 'b' });
  let token = 'first-boundary';
  root.scheduleState = () => ({ valid: true, token, mode: 'dark', nextEpoch: startedAt + 3600000 });
  root.checkSchedule();
  assert.equal(root.busy, true);
  complete(h, inventory('a'), false);
  assert.equal(root.scheduleRetryAt, startedAt + 30000);
  root.checkSchedule();
  assert.equal(root.busy, false, 'the 350 ms completion debounce must not repeat a failed change');
  h.setNow(startedAt + 29999);
  root.checkSchedule();
  assert.equal(root.busy, false);
  h.setNow(startedAt + 30000);
  root.checkSchedule();
  assert.equal(root.busy, true);
  complete(h, inventory('a'), false);
  assert.equal(root.scheduleRetryAt, startedAt + 90000, 'second failure delays another minute');
  token = 'next-boundary';
  root.checkSchedule();
  assert.equal(root.busy, true, 'a different schedule window does not inherit the previous retry delay');
  complete(h, inventory('b'));
  assert.equal(root.scheduleRetryAt, 0);
  assert.equal(root.scheduleFailureCount, 0);
});

test('an old-location solar response cannot become ready after location invalidation', () => {
  const h = harness(), { root } = h;
  root.updateSettings({ lightStart: 'sunrise' });
  root.requestSolarRefresh(false);
  const oldGeneration = root.solarRequestGeneration;
  root.invalidateSolar();
  root.requestSolarRefresh(false); // the new-location debounce fires while the old request is running
  assert.notEqual(root.solarGeneration, oldGeneration);
  const solar = name => ({ version: 1, location: { name, source: 'weather' },
    events: [{ event: 'sunrise', epoch: root.clockNow / 1000 + 1000 }] });
  root.consumeSolar(JSON.stringify(solar('Old location')));
  assert.equal(root.solarReady, false);
  assert.deepEqual(plain(root.solarEvents), []);
  h.context.solarProcess.running = false;
  root.solarExited();
  h.flush();
  assert.equal(h.context.solarProcess.running, true);
  assert.equal(root.solarRequestGeneration, root.solarGeneration);
  root.consumeSolar(JSON.stringify(solar('New location')));
  assert.equal(root.solarReady, true);
  assert.equal(root.solarLocation, 'New location');
});

test('recovery does not accept a previously consumed status from an older generation', () => {
  const h = harness(), { root } = h;
  root.refresh();
  root.consumeStatus(JSON.stringify(inventory('a')));
  assert.equal(root.statusReceived, true);
  root.chooseTheme('dark', 'b', 'random', ['c']);
  h.context.actionProcess.running = false;
  root.actionExited(1);
  assert.equal(root.operation.phase, 'verifying');
  h.context.statusProcess.running = false;
  root.statusExited(0);
  assert.equal(root.busy, true);
  assert.equal(h.context.statusProcess.running, true, 'recovery starts a current-generation probe');
  assert.equal(root.statusReceived, false);
  root.consumeStatus(JSON.stringify(inventory('b')));
  h.context.statusProcess.running = false;
  root.statusExited(0);
  assert.equal(root.busy, false);
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.settings.darkTheme, 'a', 'an unconfirmed request does not commit the pair setting');
});

test('a final result for a same-palette theme waits for a fresh native render event', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b', 'random', ['c']);
  complete(h, inventory('b'), true, 0, { reveal: false });
  assert.equal(root.busy, true);
  assert.equal(root.operation.phase, 'rendering');
  assert.equal(root.currentTheme, 'a');
  assert.equal(root.settings.darkTheme, 'a');
  assert.deepEqual(plain(root.darkRandomBackHistory), []);
  root.commitPreparedVisual();
  assert.equal(root.currentTheme, 'a', 'equal RGB values do not prove that the new reveal started');
  h.reveal(inventory('b'));
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.busy, false);
  assert.equal(root.settings.darkTheme, 'b');
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
});

test('a render cue with the wrong colors cannot publish the pending final snapshot', () => {
  const h = harness(), { root } = h;
  const target = inventory('b');
  target.palette = target.palette.map(entry => ({ ...entry, color: '#222222' }));
  root.chooseTheme('dark', 'b');
  complete(h, target, true, 0, { reveal: false });
  root.themeRenderSerial += 1;
  root.commitPreparedVisual();
  assert.equal(root.currentTheme, 'a');
  assert.equal(root.busy, true);
  h.reveal(target);
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.busy, false);
});

test('bounded visual fallback can finish an otherwise verified theme without a render signal', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b');
  complete(h, inventory('b'), true, 0, { reveal: false });
  assert.equal(h.context.visualFallback.running, true);
  root.commitPreparedVisual(true); // production fallback timer's final-result branch
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.busy, false);
  assert.equal(h.context.visualFallback.running, false);
});

test('a successful authoritative result preserves warnings while committing settings and history', () => {
  const h = harness(), { root } = h;
  root.chooseTheme('dark', 'b', 'random', ['c']);
  complete(h, inventory('b'), true, 0, { warnings: ['An application hook timed out'] });
  assert.equal(root.currentTheme, 'b');
  assert.equal(root.busy, false);
  assert.equal(root.lastError, 'An application hook timed out');
  assert.equal(root.settings.darkTheme, 'b');
  assert.deepEqual(plain(root.darkRandomBackHistory), ['a']);
});
