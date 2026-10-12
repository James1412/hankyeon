import { createMediaService } from './media/media-service.js';

const mediaService = createMediaService(browser);
const allowedMessageTypes = new Set(['hankyeon-list', 'hankyeon-control']);

async function handleMessage(message) {
    if (message.type === 'hankyeon-list') return mediaService.listMedia();
    return mediaService.controlMedia(message);
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!allowedMessageTypes.has(message?.type)) return;

    // 웹페이지가 이 통신을 이용하여 다른 탭을 제어하지 못하도록 발신자를 확인합니다.
    if (sender.url !== browser.runtime.getURL('popup.html')) {
        sendResponse({ ok: false, error: '허용되지 않은 요청입니다.' });
        return;
    }

    handleMessage(message)
        .then(sendResponse)
        .catch(error => sendResponse({ ok: false, error: String(error) }));

    // 비동기 작업이 끝날 때까지 Safari의 응답 통로를 열어둡니다.
    return true;
});
