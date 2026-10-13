(() => {
    /** Safari가 웹페이지에 주입하는 변경 감지기입니다. 미디어를 조작하지 않습니다. */
    function observeMedia() {
        const version = 1;
        const existing = globalThis.hankyeonMediaObserver;
        if (existing?.version === version) return { ok: true };
        existing?.stop();

        const runtime = typeof browser !== 'undefined' ? browser.runtime : globalThis.chrome?.runtime;
        if (!runtime) return { ok: false, error: '미디어 이벤트 통신을 사용할 수 없습니다.' };

        const roots = new Map();
        let timeout = null;
        let scheduledAt = Infinity;
        let lastSentAt = 0;
        let stopped = false;

        function notify(reason) {
            if (stopped) return;
            // 시간 변화는 최대 초당 한 번, 사용자 조작과 구조 변화는 빠르게 전달합니다.
            const delay = reason === 'timeupdate' ? Math.max(0, 1000 - (Date.now() - lastSentAt)) : 50;
            const requestedAt = Date.now() + delay;
            if (timeout !== null && requestedAt >= scheduledAt) return;
            clearTimeout(timeout);
            scheduledAt = requestedAt;
            timeout = setTimeout(() => {
                timeout = null;
                scheduledAt = Infinity;
                lastSentAt = Date.now();
                runtime.sendMessage({ type: 'hankyeon-media-changed', documentUrl: location.href })
                    .catch(() => {}); // 확장 재시작 또는 연결 종료 시 다음 이벤트에서 다시 시도합니다.
            }, delay);
        }

        function onMediaEvent(event) {
            if (event.target?.matches?.('video, audio')) notify(event.type);
        }

        function containsMedia(node) {
            return Boolean(node.matches?.('video, audio, iframe, frame')
                || node.querySelector?.('video, audio, iframe, frame'));
        }

        function relevantMutation(mutation) {
            const target = mutation.target;
            if (target.matches?.('title, h1, meta[property="og:image"], meta[name="twitter:image"], link[rel~="icon"]')
                || target.parentElement?.matches?.('title, h1')) return true;
            if (mutation.type === 'attributes') {
                return target.matches?.('video, audio, iframe, frame')
                    || (target.matches?.('#movie_player, [data-ad-player], [data-ad-video], .video-js, .plyr')
                        && containsMedia(target));
            }
            return [...mutation.addedNodes, ...mutation.removedNodes].some(containsMedia);
        }

        const events = ['play', 'pause', 'ended', 'volumechange', 'timeupdate', 'seeked',
            'loadedmetadata', 'durationchange', 'emptied', 'ratechange'];

        function attach(root, depth = 0) {
            if (!root || depth > 20 || roots.has(root)) return;
            for (const event of events) root.addEventListener(event, onMediaEvent, true);
            const observer = new MutationObserver(mutations => {
                for (const mutation of mutations) {
                    for (const node of mutation.addedNodes) discoverRoots(node, depth);
                }
                if (mutations.some(relevantMutation)) notify('mutation');
            });
            observer.observe(root, {
                childList: true, subtree: true, characterData: true, attributes: true,
                attributeFilter: ['src', 'poster', 'content', 'href', 'class', 'hidden', 'aria-hidden'],
            });
            roots.set(root, observer);
            discoverRoots(root, depth);
        }

        function discoverRoots(root, depth) {
            const elements = [root, ...Array.from(root.querySelectorAll?.('*') ?? [])];
            for (const element of elements) {
                if (element.shadowRoot) attach(element.shadowRoot, depth + 1);
                if (!element.matches?.('iframe, frame')) continue;
                try {
                    const child = element.contentDocument;
                    if (child && /^(about:blank|about:srcdoc)/.test(child.URL)) attach(child, depth + 1);
                } catch (_) { /* 접근 가능한 다른 프레임에는 Safari가 별도로 주입합니다. */ }
            }
        }

        function stop() {
            stopped = true;
            clearTimeout(timeout);
            for (const [root, observer] of roots) {
                observer.disconnect();
                for (const event of events) root.removeEventListener(event, onMediaEvent, true);
            }
            roots.clear();
        }

        globalThis.hankyeonMediaObserver = { version, stop };
        window.addEventListener('pagehide', event => { if (!event.persisted) stop(); }, { once: true });
        window.addEventListener('pageshow', () => notify('navigation'));
        window.addEventListener('popstate', () => notify('navigation'));
        attach(document);
        return { ok: true };
    }

    observeMedia();
})();
