import { mediaOperation } from './page-media.js';
import { uniqueMedia } from './media-model.js';

const supportedActions = new Set(['play', 'pause', 'volume', 'mute', 'unmute', 'seek']);
const maxConcurrentScans = 4;
const nativeAppId = 'com.jiganglee1412.hankyeon';

/** 브라우저 접근을 담당합니다. API를 인자로 받아 실제 브라우저 없이 테스트할 수 있습니다. */
export function createMediaService(browserApi) {
    async function executeInTab(tabId, action, options = {}) {
        const { mediaId = null, mediaUrl = null, volume = null, position = null, frameId = null } = options;
        const target = action === 'snapshot'
            ? { tabId, allFrames: true }
            : { tabId, frameIds: [frameId] };

        return browserApi.scripting.executeScript({
            target,
            func: mediaOperation,
            args: [action, mediaId, mediaUrl, volume, position],
        });
    }

    function combineFrames(results) {
        if (!results.length) {
            throw new Error('사이트 접근이 허용되지 않았거나 프레임을 조회할 수 없습니다.');
        }

        const mediaList = [];
        const errors = [];
        const observedUrls = new Set(results.map(entry => entry.result?.documentUrl).filter(Boolean));
        const missingUrls = new Set();
        const sortedFrames = [...results].sort((a, b) => a.frameId - b.frameId);

        for (const entry of sortedFrames) {
            if (!entry.result?.ok) {
                const error = entry.result?.error ?? entry.error ?? '응답 없음';
                errors.push(`프레임 ${entry.frameId}: ${error}`);
                continue;
            }

            for (const url of entry.result.embeddedUrls ?? []) {
                if (!observedUrls.has(url)) missingUrls.add(url);
            }
            for (const media of entry.result.mediaList) {
                mediaList.push({ ...media, frameId: entry.frameId });
            }
        }

        for (const url of missingUrls) {
            errors.push(`일부 하위 프레임 미조회: ${new URL(url).hostname} (사이트 권한 또는 프레임 로드 상태 확인 필요)`);
        }

        // 부모와 빈 프레임에서 같은 미디어가 발견될 수 있으므로 중복을 제거합니다.
        return { mediaList: uniqueMedia(mediaList), errors };
    }

    async function scanTab(tab) {
        try {
            const frames = await executeInTab(tab.id, 'snapshot');
            const result = combineFrames(frames);
            // iframe 플레이어의 사이트 대신 사용자가 열어둔 탭의 아이콘을 사용합니다.
            const siteIcon = tab.favIconUrl
                || frames.find(frame => frame.frameId === 0)?.result?.siteIconUrl
                || new URL('/favicon.ico', tab.url).href;
            return {
                mediaList: result.mediaList.map(media => ({
                    ...media,
                    thumbnailUrl: media.thumbnailUrl ?? siteIcon,
                    title: tab.title || media.title || '제목 없는 미디어',
                    tabUrl: tab.url,
                    tabId: tab.id,
                })),
                errors: result.errors.map(error => `${tab.title ?? '탭'}: ${error}`),
            };
        } catch (error) {
            return { mediaList: [], errors: [`${tab.title ?? '탭'}: ${error}`] };
        }
    }

    async function queryTabs() {
        const queriedTabs = await browserApi.tabs.query({ url: ['http://*/*', 'https://*/*'] });
        const uniqueTabs = new Map(queriedTabs.map(tab => [tab.id, tab]));
        return Array.from(uniqueTabs.values()).sort((a, b) =>
            a.windowId - b.windowId || a.index - b.index || a.id - b.id
        );
    }

    async function scanTabs(tabs) {
        const results = new Array(tabs.length);
        let nextIndex = 0;

        async function worker() {
            while (nextIndex < tabs.length) {
                const index = nextIndex++;
                // 완료 시점과 관계없이 탭 순서대로 저장하여 화면의 항목 순서를 유지합니다.
                results[index] = await scanTab(tabs[index]);
            }
        }

        const workerCount = Math.min(maxConcurrentScans, tabs.length);
        await Promise.all(Array.from({ length: workerCount }, worker));
        return results;
    }

    async function sendSnapshotToNative(mediaList) {
        try {
            const receipt = await browserApi.runtime.sendNativeMessage(nativeAppId, {
                type: 'hankyeon-snapshot',
                mediaList,
            });
            if (!receipt?.ok) throw new Error(receipt?.error ?? '네이티브 응답 없음');
            return receipt;
        } catch (error) {
            // Swift 통신이 실패해도 Safari 목록과 제어는 계속 사용할 수 있습니다.
            return { ok: false, error: String(error) };
        }
    }

    async function listMedia() {
        const tabs = await queryTabs();
        const results = await scanTabs(tabs);
        const mediaList = results.flatMap(result => result.mediaList);
        const errors = results.flatMap(result => result.errors);
        const nativeReceipt = await sendSnapshotToNative(mediaList);
        return { ok: true, mediaList, errors, nativeReceipt };
    }

    function validateControl(message) {
        const hasValidTarget = Number.isInteger(message.tabId)
            && Number.isInteger(message.frameId)
            && message.frameId >= 0
            && typeof message.mediaId === 'string'
            && typeof message.mediaUrl === 'string'
            && typeof message.tabUrl === 'string';

        if (!hasValidTarget || !supportedActions.has(message.action)) {
            throw new Error('잘못된 제어 요청입니다.');
        }
    }

    async function controlMedia(message) {
        validateControl(message);
        const tab = await browserApi.tabs.get(message.tabId);
        if (!/^https?:\/\//.test(tab.url ?? '')) {
            throw new Error('브라우저 내부 페이지는 지원하지 않습니다.');
        }
        if (tab.url !== message.tabUrl) {
            throw new Error('탭의 페이지가 바뀌었습니다. 목록을 새로고침해주세요.');
        }

        const results = await executeInTab(message.tabId, message.action, message);
        const result = results.find(entry => entry.frameId === message.frameId)?.result;
        if (!result) {
            throw new Error('대상 프레임에서 실행 결과를 받지 못했습니다. 사이트 접근 권한을 확인해주세요.');
        }
        return result;
    }

    return { listMedia, controlMedia };
}
