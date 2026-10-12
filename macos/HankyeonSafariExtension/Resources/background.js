import { createMediaService } from './media/media-service.js';
import { createMediaTracker } from './media/media-tracker.js';

const mediaService = createMediaService(browser);
const tracker = createMediaTracker(browser, mediaService);
const allowedMessageTypes = new Set(['hankyeon-list', 'hankyeon-control']);

async function handleMessage(message) {
    if (message.type === 'hankyeon-list') return tracker.listMedia();
    const result = await mediaService.controlMedia(message);
    await tracker.refreshTab(message.tabId);
    return result;
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.type === 'hankyeon-media-changed') {
        // 웹페이지가 보낸 상태를 믿지 않고, 확장 콘텐츠 스크립트의 실제 탭을 다시 읽습니다.
        if (sender.id !== browser.runtime.id || !Number.isInteger(sender.tab?.id)
            || sender.url !== message.documentUrl) return;
        tracker.refreshTab(sender.tab.id)
            .then(() => sendResponse({ ok: true }))
            .catch(error => sendResponse({ ok: false, error: String(error) }));
        return true;
    }
    if (!allowedMessageTypes.has(message?.type)) return;
    if (sender.url !== browser.runtime.getURL('popup.html')) {
        sendResponse({ ok: false, error: '허용되지 않은 요청입니다.' });
        return;
    }
    handleMessage(message)
        .then(sendResponse)
        .catch(error => sendResponse({ ok: false, error: String(error) }));
    return true;
});

// 새 문서에도 감지기를 설치하고, 닫힌 탭과 이동한 탭을 목록에 반영합니다.
browser.tabs.onUpdated?.addListener((tabId, change) => {
    if (change.status === 'complete' || change.url || change.title) {
        tracker.refreshTab(tabId).catch(console.error);
    }
});
browser.tabs.onRemoved?.addListener(tabId => tracker.removeTab(tabId).catch(console.error));
browser.tabs.onMoved?.addListener(() => tracker.updateOrder().catch(console.error));
browser.tabs.onAttached?.addListener(() => tracker.updateOrder().catch(console.error));
