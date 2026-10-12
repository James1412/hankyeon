/** 변경된 탭만 다시 읽고, 캐시된 전체 목록을 이벤트로 전달합니다. */
export function createMediaTracker(browserApi, service) {
    const sessionId = `${Date.now()}-${Math.random()}`;
    const tabs = new Map();
    const versions = new Map();
    let revision = 0;
    let loading = 0;
    let initialized = false;
    let initialization = null;
    let publication = Promise.resolve();

    async function readTab(tab) {
        const version = (versions.get(tab.id) ?? 0) + 1;
        versions.set(tab.id, version);
        const result = await service.scanTab(tab);
        // 페이지 이동 또는 탭 종료 뒤 도착한 오래된 응답을 무시합니다.
        if (versions.get(tab.id) === version) {
            tabs.set(tab.id, { tab, result });
            revision++;
        }
    }

    async function snapshot() {
        const entries = Array.from(tabs.values()).sort((a, b) =>
            a.tab.windowId - b.tab.windowId || a.tab.index - b.tab.index || a.tab.id - b.tab.id
        );
        const mediaList = entries.flatMap(entry => entry.result.mediaList);
        const errors = entries.flatMap(entry => entry.result.errors);
        const snapshotRevision = revision;
        const nativeReceipt = await service.sendSnapshotToNative(mediaList);
        return { ok: true, mediaList, errors, nativeReceipt, revision: snapshotRevision, sessionId };
    }

    function publish() {
        if (loading) return Promise.resolve();
        publication = publication.catch(() => {}).then(async () => {
            const response = await snapshot();
            try {
                await browserApi.runtime.sendMessage({ type: 'hankyeon-list-updated', response });
            } catch (_) { /* 팝업이 닫혔으면 수신자가 없어도 정상입니다. */ }
        });
        return publication;
    }

    function removeTab(tabId) {
        versions.set(tabId, (versions.get(tabId) ?? 0) + 1);
        if (tabs.delete(tabId)) revision++;
        return publish();
    }

    async function refreshTab(tabId) {
        if (!initialized) {
            initialization ??= listMedia().finally(() => { initialization = null; });
            await initialization;
        }
        const beforeGet = versions.get(tabId);
        let tab;
        try { tab = await browserApi.tabs.get(tabId); }
        catch (_) { return removeTab(tabId); }
        if (versions.get(tabId) !== beforeGet) return;
        if (!/^https?:\/\//.test(tab.url ?? '')) return removeTab(tabId);
        await readTab(tab);
        await publish();
    }

    async function listMedia() {
        loading++;
        try {
            const currentTabs = await service.queryTabs();
            const ids = new Set(currentTabs.map(tab => tab.id));
            for (const tabId of tabs.keys()) {
                if (!ids.has(tabId)) {
                    versions.set(tabId, (versions.get(tabId) ?? 0) + 1);
                    tabs.delete(tabId);
                    revision++;
                }
            }
            let nextIndex = 0;
            async function worker() {
                while (nextIndex < currentTabs.length) await readTab(currentTabs[nextIndex++]);
            }
            await Promise.all(Array.from({ length: Math.min(4, currentTabs.length) }, worker));
            initialized = true;
            return await snapshot();
        } finally {
            loading--;
            // 처음 조회하는 동안 발생한 변경도 마지막 캐시를 전달하여 반영합니다.
            await publish();
        }
    }

    async function updateOrder() {
        const currentTabs = await service.queryTabs();
        for (const tab of currentTabs) {
            const entry = tabs.get(tab.id);
            if (entry) entry.tab = tab;
        }
        revision++;
        return publish();
    }

    return { listMedia, refreshTab, removeTab, updateOrder };
}
