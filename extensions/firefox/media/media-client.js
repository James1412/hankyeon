/** 팝업과 background 사이의 통신만 담당합니다. 화면이나 탭을 직접 조작하지 않습니다. */
export function createMediaClient(runtime) {
    async function request(message) {
        const response = await runtime.sendMessage(message);
        if (!response?.ok) throw new Error(response?.error ?? '확장 응답이 없습니다.');
        return response;
    }

    function listMedia() {
        return request({ type: 'hankyeon-list' });
    }

    async function controlMedia(media, action, options = {}) {
        const response = await request({
            type: 'hankyeon-control',
            tabId: media.tabId,
            frameId: media.frameId,
            tabUrl: media.tabUrl,
            mediaId: media.mediaId,
            mediaUrl: media.mediaUrl,
            action,
            ...options,
        });

        if (action === 'volume') {
            const actual = response.mediaList.find(item => item.mediaId === media.mediaId);
            if (!actual || Math.abs(actual.volume - options.volume) > 0.001) {
                throw new Error('볼륨 적용 확인 실패');
            }
        }
        return response;
    }

    function subscribe(onSnapshot) {
        const listener = (message, sender) => {
            if (sender?.tab || (sender?.id && sender.id !== runtime.id)) return;
            if (message?.type === 'hankyeon-list-updated' && message.response?.ok) {
                onSnapshot(message.response);
            }
        };
        runtime.onMessage.addListener(listener);
        return () => runtime.onMessage.removeListener(listener);
    }

    return { listMedia, controlMedia, subscribe };
}
