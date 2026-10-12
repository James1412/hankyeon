import { listSignature, mediaKey, uniqueMedia } from '../media/media-model.js';
import { MediaRow } from './media-row.js';

/** 화면 표시만 담당합니다. 메시지 전송과 주기 조회는 컨트롤러가 처리합니다. */
export class PopupView {
    constructor(onCommand, onEditing) {
        this.onCommand = onCommand;
        this.onEditing = onEditing;
        this.list = document.querySelector('#media-list');
        this.status = document.querySelector('#status');
        this.refreshButton = document.querySelector('#refresh');
        this.nativeStatus = document.querySelector('#native-status');
        this.diagnostics = document.querySelector('#diagnostics');
        this.warning = document.querySelector('#warning');
        this.diagnosticText = document.querySelector('#diagnostic-text');
        this.rows = new Map();
        this.signature = null;
    }

    render(response) {
        const mediaList = uniqueMedia(response.mediaList);
        const signature = listSignature(mediaList);

        if (signature !== this.signature) {
            const scrollPosition = { x: window.scrollX, y: window.scrollY };
            this.rows.clear();
            const elements = mediaList.map(media => {
                const row = new MediaRow(media, this.onCommand, this.onEditing);
                this.rows.set(mediaKey(media), row);
                return row.element;
            });
            this.list.replaceChildren(...elements);
            this.signature = signature;
            window.scrollTo(scrollPosition.x, scrollPosition.y);
        } else {
            // 기존 행의 값을 갱신하여 스크롤과 슬라이더 위치를 유지합니다.
            for (const media of mediaList) this.rows.get(mediaKey(media)).update(media);
        }

        this.renderDiagnostics(response.errors);
        this.nativeStatus.textContent = response.nativeReceipt?.ok
            ? `Swift 연결 확인 · 미디어 ${response.nativeReceipt.count}개 수신`
            : 'Swift 연결 미확인 · Safari 제어는 사용 가능';

        if (!mediaList.length) {
            this.showStatus('조회 가능한 미디어가 없습니다. 해당 사이트와 플레이어 도메인의 접근을 허용해주세요.');
        }
    }

    renderDiagnostics(errors = []) {
        const uniqueErrors = [...new Set(errors)];
        this.diagnostics.hidden = uniqueErrors.length === 0;
        this.warning.textContent = `일부 페이지·프레임을 조회하지 못했습니다 (${uniqueErrors.length}건)`;
        this.diagnosticText.textContent = uniqueErrors.join('\n');
    }

    showStatus(message) {
        this.status.textContent = message;
    }

    setBusy(isBusy) {
        this.refreshButton.disabled = isBusy;
        for (const row of this.rows.values()) row.setBusy(isBusy);
    }
}
