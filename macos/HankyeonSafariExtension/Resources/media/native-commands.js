/** 앱에서 보낸 명령을 Safari native port로 받습니다. 콘텐츠 스크립트 메시지와 분리합니다. */
export function connectNativeCommands(browserApi, handleCommand) {
    let port = null;
    let retry = null;
    let retryDelay = 500;
    let stopped = false;
    const seen = new Set();

    function connect() {
        if (stopped || !browserApi.runtime.connectNative) return;
        try {
            port = browserApi.runtime.connectNative('com.jiganglee1412.hankyeon');
            const currentPort = port;
            port.onMessage.addListener(async envelope => {
                if (stopped || port !== currentPort) return;
                // Safari가 전달하는 native message의 userInfo가 명령 본문입니다.
                const command = envelope?.userInfo ?? envelope;
                if (envelope?.name && envelope.name !== 'hankyeon-command') return;
                const id = command?.requestId;
                if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id) || seen.has(id)) return;
                seen.add(id);
                if (seen.size > 256) seen.delete(seen.values().next().value);
                retryDelay = 500;
                let reply;
                try {
                    const result = await handleCommand(command);
                    reply = { ok: result?.ok !== false, error: result?.error };
                } catch (error) { reply = { ok: false, error: String(error) }; }
                try {
                    await browserApi.runtime.sendNativeMessage('com.jiganglee1412.hankyeon', {
                        type: 'hankyeon-command-result', requestId: id,
                        ok: reply.ok, ...(reply.error ? { error: reply.error } : {}),
                    });
                } catch (_) { /* 앱은 응답 제한 시간 뒤 연결 오류를 표시합니다. */ }
                reconnect();
            });
            port.onDisconnect.addListener(() => {
                if (port === currentPort) scheduleReconnect();
            });
        } catch (_) { scheduleReconnect(); }
    }

    function scheduleReconnect() {
        if (stopped || retry !== null) return;
        // 연결이 끊겼을 때만 다시 연결합니다. 미디어 목록을 주기 조회하지 않습니다.
        retry = setTimeout(() => { retry = null; connect(); }, retryDelay);
        retryDelay = Math.min(retryDelay * 2, 10000);
    }

    function reconnect() {
        if (stopped) return;
        clearTimeout(retry); retry = null;
        const previous = port; port = null;
        previous?.disconnect();
        connect();
    }

    connect();
    const stop = () => { stopped = true; clearTimeout(retry); port?.disconnect(); };
    // Safari에서는 일회성 native 메시지 뒤 명령 포트를 새로 열어 수신을 유지합니다.
    stop.reconnect = reconnect;
    return stop;
}
