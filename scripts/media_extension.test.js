import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';

import { mediaOperation } from '../macos/HankyeonSafariExtension/Resources/media/page-media.js';
import { createMediaService } from '../macos/HankyeonSafariExtension/Resources/media/media-service.js';
import { createMediaClient } from '../macos/HankyeonSafariExtension/Resources/media/media-client.js';
import { uniqueMedia, formatTime } from '../macos/HankyeonSafariExtension/Resources/media/media-model.js';
import { PopupView } from '../macos/HankyeonSafariExtension/Resources/ui/popup-view.js';
import { MediaRow } from '../macos/HankyeonSafariExtension/Resources/ui/media-row.js';

function fakeMedia(currentTime = 0) {
    return {
        dataset: {},
        tagName: 'VIDEO',
        matches: selector => selector === 'video, audio',
        seekable: { length: 2, start: index => [0, 60][index], end: index => [40, 100][index] },
        seeking: false,
        playbackRate: 1,
        volume: 1,
        muted: false,
        paused: false,
        ended: false,
        currentTime,
        duration: 100,
        addEventListener() {},
        removeEventListener() {},
        pause() { this.paused = true; },
        async play() { this.paused = false; },
    };
}

// Simulate executeScript serialization: the function receives no module helpers.
function pageOperation(elements, documentOverrides = {}) {
    const context = vm.createContext({
        setTimeout, clearTimeout, URL, crypto: webcrypto,
        location: { href: 'https://example.com/watch' },
        document: { title: 'Test', querySelectorAll: () => elements, ...documentOverrides },
    });
    return vm.runInContext(`(${mediaOperation.toString()})`, context);
}

function browserFixture() {
    const calls = [];
    const nativeMessages = [];
    const tabs = [
        { id: 3, windowId: 2, index: 0, url: 'https://example.com/3' },
        { id: 2, windowId: 1, index: 1, url: 'https://example.com/2' },
        { id: 1, windowId: 1, index: 0, url: 'https://example.com/1' },
    ];
    const api = {
        tabs: {
            async query() { return [...tabs, tabs[0]]; },
            async get(id) { return tabs.find(tab => tab.id === id); },
        },
        runtime: {
            async sendNativeMessage(app, message) {
                nativeMessages.push({ app, message });
                return { ok: true, count: message.mediaList.length };
            },
        },
        scripting: {
            async executeScript(options) {
                calls.push(options);
                return [{ frameId: 0, result: {
                    ok: true, embeddedUrls: [],
                    mediaList: [{ mediaId: `media-${options.target.tabId}`, mediaUrl: 'https://example.com/watch' }],
                } }];
            },
        },
    };
    return { api, calls, nativeMessages };
}

function controlRequest(overrides = {}) {
    return {
        tabId: 1, frameId: 0, mediaId: 'media-1',
        mediaUrl: 'https://example.com/watch', tabUrl: 'https://example.com/1',
        action: 'pause', ...overrides,
    };
}

test('page controls affect only the selected media; stale targets are rejected', async () => {
    const videos = [fakeMedia(), fakeMedia(1)];
    const operate = pageOperation(videos);
    const { mediaList: [a, b] } = await operate('snapshot');
    assert.notEqual(a.mediaId, b.mediaId);
    assert.equal('playbackRate' in a, false);

    assert.equal((await operate('pause', a.mediaId, a.mediaUrl)).ok, true);
    assert.equal(videos[0].paused, true);
    assert.equal(videos[1].paused, false);
    assert.equal((await operate('play', a.mediaId, a.mediaUrl)).ok, true);
    assert.equal(videos[0].paused, false);
    assert.equal((await operate('pause', 'missing', a.mediaUrl)).ok, false);
    assert.equal((await operate('pause', a.mediaId, 'https://old.example')).ok, false);

    videos[0].play = async () => { throw new Error('NotAllowedError'); };
    assert.match((await operate('play', a.mediaId, a.mediaUrl)).error, /NotAllowedError/);
});

test('independent volume/mute controls reject invalid volume values', async () => {
    const videos = [fakeMedia(), fakeMedia()];
    const operate = pageOperation(videos);
    const { mediaList: [a, b] } = await operate('snapshot');
    assert.equal((await operate('volume', a.mediaId, a.mediaUrl, 0.2)).ok, true);
    assert.equal((await operate('volume', b.mediaId, b.mediaUrl, 0.7)).ok, true);
    assert.deepEqual(videos.map(video => video.volume), [0.2, 0.7]);

    for (const volume of [-1, 1.1, NaN, '0.4', null]) {
        assert.equal((await operate('volume', a.mediaId, a.mediaUrl, volume)).ok, false);
    }
    assert.equal((await operate('mute', a.mediaId, a.mediaUrl)).ok, true);
    assert.equal(videos[0].muted, true);
    assert.equal(videos[1].muted, false);
    assert.equal((await operate('unmute', a.mediaId, a.mediaUrl)).ok, true);
    assert.equal(videos[0].volume, 0.2);
    assert.equal(videos[0].paused, false);
});

test('seek respects allowed ranges and leaves other media untouched', async () => {
    const videos = [fakeMedia(), fakeMedia(1)];
    const operate = pageOperation(videos);
    const { mediaList: [a] } = await operate('snapshot');
    assert.equal((await operate('seek', a.mediaId, a.mediaUrl, null, 30)).ok, true);
    assert.deepEqual(videos.map(video => video.currentTime), [30, 1]);
    assert.equal(videos[0].paused, false);
    assert.equal(videos[0].volume, 1);
    for (const position of [-1, NaN, '20', 50, 101]) {
        assert.equal((await operate('seek', a.mediaId, a.mediaUrl, null, position)).ok, false);
    }
    assert.equal(videos[0].currentTime, 30);
});

test('discovery includes shadow DOM and readable blank frames only once', async () => {
    const main = fakeMedia();
    const shadow = fakeMedia();
    const blank = fakeMedia();
    const blankDocument = { URL: 'about:srcdoc', querySelectorAll: () => [blank] };
    const elements = [
        main,
        { matches: () => false, shadowRoot: { querySelectorAll: () => [shadow] } },
        { matches: selector => selector === 'iframe, frame', contentDocument: blankDocument },
        { matches: selector => selector === 'iframe, frame', contentDocument: blankDocument },
    ];
    const result = await pageOperation(elements)('snapshot');
    assert.equal(result.mediaList.length, 3);
});

test('frame routing and stale tab guards survive refactoring', async () => {
    const { api, calls } = browserFixture();
    api.scripting.executeScript = async options => {
        calls.push(options);
        return options.target.allFrames ? [
            { frameId: 0, result: { ok: true, mediaList: [] } },
            { frameId: 7, result: { ok: true, mediaList: [{ mediaId: 'frame-video', mediaUrl: 'https://player.example/lesson' }] } },
        ] : [{ frameId: 7, result: { ok: true, mediaList: [] } }];
    };
    const service = createMediaService(api);
    const result = await service.listMedia();
    assert.equal(result.mediaList[0].frameId, 7);
    await service.controlMedia(controlRequest({ frameId: 7 }));
    assert.deepEqual(calls.at(-1).target.frameIds, [7]);
    await assert.rejects(service.controlMedia(controlRequest({ tabUrl: 'https://old.example' })), /페이지가 바뀌었습니다/);
    await assert.rejects(service.controlMedia(controlRequest({ frameId: -1 })), /잘못된 제어 요청/);
    await assert.rejects(service.controlMedia(controlRequest({ action: 'unknown' })), /잘못된 제어 요청/);
});

test('duplicate tabs and reversed scan completion do not reorder or grow the list', async () => {
    const { api } = browserFixture();
    let reversed = false;
    const execute = api.scripting.executeScript;
    api.scripting.executeScript = async options => {
        const delay = reversed ? options.target.tabId : 4 - options.target.tabId;
        await new Promise(resolve => setTimeout(resolve, delay * 5));
        return execute(options);
    };
    const service = createMediaService(api);
    const first = await service.listMedia();
    reversed = true;
    const second = await service.listMedia();
    assert.deepEqual(first.mediaList.map(media => media.tabId), [1, 2, 3]);
    assert.equal(first.mediaList.some(media => 'frameTitle' in media || 'windowId' in media), false);
    assert.deepEqual(second.mediaList.map(media => media.tabId), [1, 2, 3]);
});

test('native receipt is separate from browser control and failures preserve the list', async () => {
    const { api, nativeMessages } = browserFixture();
    const service = createMediaService(api);
    const first = await service.listMedia();
    assert.equal(first.nativeReceipt.count, 3);
    assert.equal(nativeMessages[0].app, 'com.jiganglee1412.hankyeon');
    assert.equal(nativeMessages[0].message.type, 'hankyeon-snapshot');
    api.runtime.sendNativeMessage = async () => { throw new Error('native unavailable'); };
    const second = await service.listMedia();
    assert.equal(second.mediaList.length, 3);
    assert.equal(second.nativeReceipt.ok, false);
});

test('popup identities retain distinct media with matching titles and URLs', () => {
    const a = { tabId: 1, frameId: 0, mediaId: 'a', tabUrl: 'https://example.com', mediaUrl: 'about:srcdoc', title: 'Same title' };
    const result = uniqueMedia([a, { ...a, frameId: 7 }, { ...a, mediaId: 'b' }, { ...a, tabId: 2 }]);
    assert.equal(result.length, 3);
    assert.equal(uniqueMedia(result).length, 3);
    assert.equal(formatTime(3661), '1:01:01');
    assert.equal(formatTime(null), '라이브');
});

test('snapshots use mediaUrl and select safe poster/page thumbnail URLs', async () => {
    const media = fakeMedia();
    const document = {
        URL: 'https://example.com/lesson',
        baseURI: 'https://example.com/course/',
        querySelector: selector => selector.includes('og:image')
            ? { content: '/images/lesson.jpg' }
            : null,
    };
    media.ownerDocument = document;
    media.poster = 'poster.jpg';
    const operate = pageOperation([media]);
    let result = (await operate('snapshot')).mediaList[0];
    assert.equal(result.mediaUrl, document.URL);
    assert.equal('url' in result, false);
    assert.equal(result.thumbnailUrl, 'https://example.com/course/poster.jpg');

    media.poster = '';
    result = (await operate('snapshot')).mediaList[0];
    assert.equal(result.thumbnailUrl, 'https://example.com/images/lesson.jpg');

    media.poster = 'blob:https://example.com/not-shared';
    document.querySelector = selector => selector.includes('twitter:image')
        ? { content: 'https://example.com/twitter.jpg' }
        : { content: 'javascript:invalid' };
    result = (await operate('snapshot')).mediaList[0];
    assert.equal(result.thumbnailUrl, 'https://example.com/twitter.jpg');

    document.querySelector = () => null;
    result = (await operate('snapshot')).mediaList[0];
    assert.equal(result.thumbnailUrl, null);
});

test('missing iframe artwork uses the containing website icon', async () => {
    const { api } = browserFixture();
    const query = api.tabs.query;
    api.tabs.query = async () => (await query()).map(tab => ({
        ...tab, favIconUrl: 'https://example.com/site-icon.png',
    }));
    const service = createMediaService(api);
    const result = await service.listMedia();
    assert.equal(result.mediaList[0].thumbnailUrl, 'https://example.com/site-icon.png');
    api.tabs.query = query;
    const fallback = await service.listMedia();
    assert.equal(fallback.mediaList[0].thumbnailUrl, 'https://example.com/favicon.ico');
});

test('client sends target identity and validates returned volume', async () => {
    const messages = [];
    const runtime = { async sendMessage(message) {
        messages.push(message);
        return { ok: true, mediaList: [{ mediaId: 'a', volume: 0.2 }] };
    } };
    const client = createMediaClient(runtime);
    const media = { ...controlRequest(), mediaId: 'a' };
    await client.controlMedia(media, 'volume', { volume: 0.2 });
    assert.equal(messages[0].type, 'hankyeon-control');
    assert.equal(messages[0].frameId, 0);
    assert.equal(messages[0].mediaUrl, media.mediaUrl);
    assert.equal('url' in messages[0], false);
    await assert.rejects(client.controlMedia(media, 'volume', { volume: 0.7 }), /볼륨 적용 확인 실패/);
});

class FakeElement {
    constructor() {
        this.children = [];
        this.listeners = new Map();
    }
    append(...elements) { this.children.push(...elements); }
    replaceChildren(...elements) { this.children = elements; }
    addEventListener(name, listener) { this.listeners.set(name, listener); }
    setAttribute() {}
    removeAttribute(name) { delete this[name]; }
}

test('UI reuses rows, refreshes mute actions and collapses repeated diagnostics', async () => {
    const nodes = new Map();
    const previousDocument = globalThis.document;
    const previousWindow = globalThis.window;
    globalThis.document = {
        createElement: () => new FakeElement(),
        querySelector(selector) {
            if (!nodes.has(selector)) nodes.set(selector, new FakeElement());
            return nodes.get(selector);
        },
    };
    globalThis.window = { scrollX: 0, scrollY: 100, scrollTo() {} };

    try {
        const commands = [];
        const media = {
            tabId: 1, frameId: 0, mediaId: 'a', tabUrl: 'https://example.com', mediaUrl: 'https://example.com',
            title: 'Test', seekable: [{ start: 0, end: 100 }], currentTime: 2, duration: 100,
            volume: 1, muted: false, paused: true,
        };
        const onCommand = async (_, action) => { commands.push(action); return true; };
        const view = new PopupView(onCommand, () => {});
        view.render({ mediaList: [media, media], errors: ['denied', 'denied'] });
        const firstRow = nodes.get('#media-list').children[0];
        assert.equal(nodes.get('#media-list').children.length, 1);
        assert.match(nodes.get('#warning').textContent, /1건/);
        assert.equal(nodes.get('#diagnostic-text').textContent, 'denied');
        view.render({ mediaList: [{ ...media, muted: true }], errors: [] });
        assert.equal(nodes.get('#media-list').children[0], firstRow);
        assert.equal(nodes.get('#diagnostics').hidden, true);

        const row = new MediaRow(media, onCommand, () => {});
        row.update({ ...media, muted: true, seekable: [] });
        await row.muteButton.listeners.get('click')();
        assert.deepEqual(commands, ['unmute']);
        row.setBusy(false);
        assert.equal(row.seekSlider.disabled, true);
        row.update({ ...media, thumbnailUrl: 'https://example.com/cover.jpg' });
        assert.equal(row.thumbnail.src, 'https://example.com/cover.jpg');
        assert.equal(row.thumbnail.hidden, false);
        row.thumbnail.listeners.get('error')();
        assert.equal(row.thumbnail.hidden, true);
        assert.equal(row.artworkFallback.hidden, false);
        row.update({ ...media, thumbnailUrl: null });
        assert.equal(row.thumbnail.src, undefined);
    } finally {
        globalThis.document = previousDocument;
        globalThis.window = previousWindow;
    }
});

test('background rejects messages from webpages and allows its own popup', async () => {
    const previousBrowser = globalThis.browser;
    const { api } = browserFixture();
    let listener;
    api.runtime.getURL = name => `extension://${name}`;
    api.runtime.onMessage = { addListener(fn) { listener = fn; } };
    globalThis.browser = api;
    try {
        await import('../macos/HankyeonSafariExtension/Resources/background.js');
        let denied;
        listener({ type: 'hankyeon-list' }, { url: 'https://example.com' }, response => { denied = response; });
        assert.equal(denied.ok, false);
        const reply = await new Promise(resolve => {
            assert.equal(listener({ type: 'hankyeon-list' }, { url: 'extension://popup.html' }, resolve), true);
        });
        assert.equal(reply.mediaList.length, 3);
    } finally {
        globalThis.browser = previousBrowser;
    }
});

test('popup defers updates while editing and discards stale snapshots', async () => {
    const { PopupController } = await import('../macos/HankyeonSafariExtension/Resources/popup.js');
    const rendered = [];
    const controller = Object.create(PopupController.prototype);
    Object.assign(controller, { isBusy: false, isEditing: true, lastRevision: -1,
        pendingResponse: null, view: { render: response => rendered.push(response.revision) } });
    controller.receive({ revision: 2 });
    controller.receive({ revision: 1 });
    assert.deepEqual(rendered, []);
    controller.finishEditing();
    assert.deepEqual(rendered, [2]);
    controller.receive({ revision: 1 });
    assert.deepEqual(rendered, [2]);
});

test('YouTube thumbnail tracks the current video even with stale metadata', async () => {
    const media = fakeMedia();
    const mediaDocument = { URL: 'https://www.youtube.com/watch?v=bxDFCGGhX8E',
        querySelector: () => ({ content: 'https://example.com/old-thumbnail.jpg' }) };
    media.ownerDocument = mediaDocument;
    const operate = pageOperation([media]);
    assert.equal((await operate('snapshot')).mediaList[0].thumbnailUrl,
        'https://i.ytimg.com/vi/bxDFCGGhX8E/hqdefault.jpg');
    mediaDocument.URL = 'https://www.youtube.com/watch?v=4mqGIaVif6o';
    assert.equal((await operate('snapshot')).mediaList[0].thumbnailUrl,
        'https://i.ytimg.com/vi/4mqGIaVif6o/hqdefault.jpg');
});

test('short videos and empty players are hidden while live and paused media remain', async () => {
    const short = fakeMedia(); short.duration = 5;
    const boundary = fakeMedia(); boundary.duration = 10;
    const long = fakeMedia(); long.duration = 11; long.paused = true;
    const live = fakeMedia(); live.duration = Infinity;
    const empty = fakeMedia(); empty.readyState = 0;
    const audio = fakeMedia(); audio.tagName = 'AUDIO'; audio.duration = 3;
    const operate = pageOperation([short, boundary, long, live, empty, audio]);
    const result = await operate('snapshot');
    assert.equal(result.mediaList.length, 3);
    assert.deepEqual(Array.from(result.mediaList, item => item.duration), [11, null, 3]);
    assert.equal((await operate('play', short.dataset.hankyeonMediaId, 'https://example.com/watch')).ok, false);
    short.duration = 60;
    empty.readyState = 2;
    assert.equal((await operate('snapshot')).mediaList.length, 5);
});

test('explicit advertising is hidden and the content returns when advertising ends', async () => {
    const video = fakeMedia();
    let showingAd = true;
    video.closest = selector => {
        if (!selector.includes('#movie_player.ad-showing')) return null;
        return showingAd ? {} : null;
    };
    const operate = pageOperation([video]);
    assert.equal((await operate('snapshot')).mediaList.length, 0);
    showingAd = false;
    assert.equal((await operate('snapshot')).mediaList.length, 1);
});

test('long marketing/background videos are hidden, not just short clips', async () => {
    const demo = fakeMedia();
    demo.duration = 120; demo.autoplay = true; demo.muted = true; demo.loop = true;
    const preview = fakeMedia(); preview.autoplay = true; preview.muted = true;
    const lesson = fakeMedia(); lesson.controls = true; lesson.paused = true;
    const customPlayer = fakeMedia(); customPlayer.autoplay = true; customPlayer.muted = true;
    customPlayer.closest = selector => selector.includes('.video-js') ? {} : null;
    const decorative = fakeMedia(); decorative.controls = true;
    decorative.closest = selector => selector.includes('.hero-video') ? {} : null;
    const operate = pageOperation([demo, preview, lesson, customPlayer, decorative]);
    const result = await operate('snapshot');
    assert.equal(result.mediaList.length, 2);
    assert.equal(result.mediaList[0].mediaId, lesson.dataset.hankyeonMediaId);
    assert.equal(result.mediaList[1].mediaId, customPlayer.dataset.hankyeonMediaId);
});

test('YouTube main and preview videos with identical classes are not both listed', async () => {
    const main = fakeMedia(); main.duration = 10227.101;
    const preview = fakeMedia(); preview.duration = 1660.561; preview.paused = true; preview.muted = true;
    const mediaDocument = {
        URL: 'https://www.youtube.com/watch?v=cbuZfY2S2UQ', title: 'Tab title',
        querySelector: selector => selector.includes('h1.') ? { textContent: 'Coding playlist' } : null,
    };
    for (const media of [main, preview]) {
        media.ownerDocument = mediaDocument;
        media.className = 'video-stream html5-main-video';
        media.closest = selector => {
            if (selector.includes('#inline-preview-player')) return media === preview ? {} : null;
            if (selector === '#movie_player') return media === main ? {} : null;
            if (selector.includes('.html5-video-player')) return {};
            return null;
        };
    }
    const operate = pageOperation([main, preview]);
    const result = await operate('snapshot');
    assert.equal(result.mediaList.length, 1);
    assert.equal(result.mediaList[0].mediaId, main.dataset.hankyeonMediaId);
    assert.equal(result.mediaList[0].title, 'Coding playlist');
    assert.equal((await operate('play', preview.dataset.hankyeonMediaId, mediaDocument.URL)).ok, false);
    main.paused = true;
    assert.equal((await operate('snapshot')).mediaList.length, 1, 'Paused main content remains controllable');
});

test('service preserves the main YouTube title instead of assigning the tab title', async () => {
    const { api } = browserFixture();
    api.scripting.executeScript = async () => [{ frameId: 0, result: { ok: true, mediaList: [{
        mediaId: 'main', mediaUrl: 'https://www.youtube.com/watch?v=cbuZfY2S2UQ', title: 'Coding playlist',
    }] } }];
    const response = await createMediaService(api).listMedia();
    assert.equal(response.mediaList[0].title, 'Coding playlist');
});

test('tracker rescans only the changed tab and removes closed tabs', async () => {
    const { createMediaTracker } = await import('../macos/HankyeonSafariExtension/Resources/media/media-tracker.js');
    const scanned = [], published = [];
    let queries = 0;
    const tabs = [{ id: 1, index: 0, windowId: 1, url: 'https://one.test' },
        { id: 2, index: 1, windowId: 1, url: 'https://two.test' }];
    const tracker = createMediaTracker({ tabs: { get: async id => tabs.find(tab => tab.id === id) },
        runtime: { sendMessage: async message => published.push(message.response) } }, {
        queryTabs: async () => { queries++; return tabs; },
        scanTab: async tab => { scanned.push(tab.id); return { mediaList: [{ tabId: tab.id }], errors: [] }; },
        sendSnapshotToNative: async () => ({ ok: true }),
    });
    await tracker.listMedia();
    scanned.length = 0;
    await tracker.refreshTab(2);
    assert.deepEqual(scanned, [2]);
    assert.equal(queries, 1);
    assert.deepEqual(published.at(-1).mediaList.map(media => media.tabId), [1, 2]);
    await tracker.removeTab(1);
    assert.deepEqual(published.at(-1).mediaList.map(media => media.tabId), [2]);
});

test('client subscribes only to background updates and releases its listener', () => {
    let listener, removed;
    const runtime = { id: 'ours', onMessage: {
        addListener: fn => { listener = fn; }, removeListener: fn => { removed = fn; },
    } };
    const responses = [];
    const unsubscribe = createMediaClient(runtime).subscribe(value => responses.push(value));
    const message = { type: 'hankyeon-list-updated', response: { ok: true } };
    listener(message, { id: 'ours', tab: { id: 1 } });
    listener(message, { id: 'other' });
    listener(message, { id: 'ours' });
    assert.equal(responses.length, 1);
    unsubscribe();
    assert.equal(removed, listener);
});

test('observer installs once, batches events, and prioritizes pause over progress', async () => {
    const observerSource = readFileSync(new URL('../macos/HankyeonSafariExtension/Resources/media/media-observer.js', import.meta.url), 'utf8');
    const listeners = new Map(), timers = new Map(), sent = [];
    let timerId = 0, now = 2000, installations = 0;
    const context = vm.createContext({
        browser: { runtime: { sendMessage: async message => sent.push(message) } },
        location: { href: 'https://example.com/watch' },
        Date: { now: () => now },
        document: { addEventListener: (name, fn) => listeners.set(name, fn),
            removeEventListener: name => listeners.delete(name), querySelectorAll: () => [] },
        window: { addEventListener() {} },
        MutationObserver: class { observe() { installations++; } disconnect() {} },
        setTimeout: (fn, delay) => { timers.set(++timerId, { fn, delay }); return timerId; },
        clearTimeout: id => timers.delete(id),
    });
    const install = () => vm.runInContext(observerSource, context);
    install();
    install();
    assert.equal(installations, 1);
    const emit = name => listeners.get(name)({ type: name, target: { matches: () => true } });
    const flush = () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(timer => timer.fn()); };
    emit('timeupdate'); flush();
    assert.equal(sent.length, 1);
    now += 100;
    emit('timeupdate'); emit('timeupdate');
    assert.equal(timers.size, 1);
    assert.equal([...timers.values()][0].delay, 900);
    emit('pause');
    assert.equal([...timers.values()][0].delay, 50);
    flush();
    assert.equal(sent.length, 2);
    context.hankyeonMediaObserver.stop();
    assert.equal(listeners.size, 0);
});

test('tracker does not resurrect a tab when its delayed scan finishes after close', async () => {
    const { createMediaTracker } = await import('../macos/HankyeonSafariExtension/Resources/media/media-tracker.js');
    let resolveScan, delay = false;
    const published = [];
    const tab = { id: 1, windowId: 1, index: 0, url: 'https://one.test' };
    const tracker = createMediaTracker({ tabs: { get: async () => tab },
        runtime: { sendMessage: async message => published.push(message.response) } }, {
        queryTabs: async () => [tab],
        scanTab: async () => {
            if (delay) await new Promise(resolve => { resolveScan = resolve; });
            return { mediaList: [{ tabId: 1 }], errors: [] };
        },
        sendSnapshotToNative: async () => ({ ok: true }),
    });
    await tracker.listMedia();
    delay = true;
    const pending = tracker.refreshTab(1);
    await Promise.resolve(); await Promise.resolve();
    await tracker.removeTab(1);
    resolveScan(); await pending;
    assert.deepEqual(published.at(-1).mediaList, []);
});
