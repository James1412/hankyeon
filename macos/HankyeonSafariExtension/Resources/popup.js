import { createMediaClient } from './media/media-client.js';
import { formatTime } from './media/media-model.js';
import { PopupView } from './ui/popup-view.js';

/** 사용자 입력과 변경 이벤트를 조정합니다. 탐색과 화면 구성은 별도 모듈이 담당합니다. */
export class PopupController {
    constructor(client) {
        this.client = client;
        this.isBusy = false;
        this.isEditing = false;
        this.lastRevision = -1;
        this.pendingResponse = null;
        this.view = new PopupView(
            (media, action, options) => this.control(media, action, options),
            () => { this.isEditing = true; },
        );
    }

    start() {
        this.view.refreshButton.addEventListener('click', () => this.refresh());
        document.addEventListener('pointerup', () => this.finishEditing());
        document.addEventListener('pointercancel', () => this.finishEditing());
        document.addEventListener('keydown', event => {
            if (event.target?.type === 'range') this.isEditing = true;
        });
        document.addEventListener('keyup', () => this.finishEditing());
        window.addEventListener('blur', () => this.finishEditing());
        const unsubscribe = this.client.subscribe(response => this.receive(response));
        window.addEventListener('pagehide', unsubscribe, { once: true });
        this.refresh();
    }

    async runTask(task) {
        if (this.isBusy) return false;
        this.isBusy = true;
        this.view.showStatus('조회·제어 중…');
        this.view.setBusy(true);

        try {
            await task();
            return true;
        } catch (error) {
            this.view.showStatus(String(error));
            return false;
        } finally {
            this.isBusy = false;
            this.view.setBusy(false);
            this.flushPending();
        }
    }

    async loadList() {
        const response = await this.client.listMedia();
        this.view.showStatus('');
        this.receive(response, true);
    }

    refresh() {
        return this.runTask(() => this.loadList());
    }

    control(media, action, options) {
        return this.runTask(async () => {
            await this.client.controlMedia(media, action, options);
            this.view.showStatus(`${media.title}\n${this.successMessage(action, options)}`);
        });
    }

    successMessage(action, options) {
        switch (action) {
            case 'volume': return `볼륨 ${Math.round(options.volume * 100)}% 적용`;
            case 'seek': return `${formatTime(options.position)} 위치로 이동 확인됨`;
            case 'play': return '재생 확인됨';
            case 'pause': return '일시정지 확인됨';
            case 'mute': return '음소거 확인됨';
            case 'unmute': return '음소거 해제 확인됨';
        }
    }

    receive(response, force = false) {
        if (response.sessionId !== this.sessionId) {
            this.sessionId = response.sessionId;
            this.lastRevision = -1;
        }
        if (response.revision < this.lastRevision) return;
        this.lastRevision = response.revision;
        if (!force && (this.isBusy || this.isEditing)) {
            this.pendingResponse = response;
            return;
        }
        this.pendingResponse = null;
        this.view.render(response);
    }

    finishEditing() {
        this.isEditing = false;
        this.flushPending();
    }

    flushPending() {
        if (!this.isBusy && !this.isEditing && this.pendingResponse) {
            this.receive(this.pendingResponse);
        }
    }

}

if (typeof document !== 'undefined' && typeof browser !== 'undefined') {
    const controller = new PopupController(createMediaClient(browser.runtime));
    controller.start();
}
