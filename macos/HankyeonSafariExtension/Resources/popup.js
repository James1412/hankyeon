import { createMediaClient } from './media/media-client.js';
import { formatTime } from './media/media-model.js';
import { PopupView } from './ui/popup-view.js';

const pollingIntervalMs = 1500;

/** 사용자 입력과 주기 조회를 조정합니다. 탐색과 화면 구성은 별도 모듈이 담당합니다. */
export class PopupController {
    constructor(client) {
        this.client = client;
        this.isBusy = false;
        this.isEditing = false;
        this.isPolling = false;
        this.revision = 0;
        this.view = new PopupView(
            (media, action, options) => this.control(media, action, options),
            () => { this.isEditing = true; },
        );
    }

    start() {
        this.view.refreshButton.addEventListener('click', () => this.refresh());
        document.addEventListener('pointerup', () => { this.isEditing = false; });
        document.addEventListener('pointercancel', () => { this.isEditing = false; });
        document.addEventListener('keydown', event => {
            if (event.target?.type === 'range') this.isEditing = true;
        });
        document.addEventListener('keyup', () => { this.isEditing = false; });
        window.addEventListener('blur', () => { this.isEditing = false; });
        const timer = setInterval(() => this.poll(), pollingIntervalMs);
        window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
        this.refresh();
    }

    async runTask(task) {
        if (this.isBusy) return false;
        this.isBusy = true;
        this.revision++;
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
        }
    }

    async loadList() {
        const response = await this.client.listMedia();
        this.view.showStatus('');
        this.view.render(response);
    }

    refresh() {
        return this.runTask(() => this.loadList());
    }

    control(media, action, options) {
        return this.runTask(async () => {
            await this.client.controlMedia(media, action, options);
            await this.loadList();
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

    canPoll() {
        return !this.isBusy && !this.isEditing;
    }

    async poll() {
        if (!this.canPoll() || this.isPolling) return;
        this.isPolling = true;
        const startedAtRevision = this.revision;

        try {
            const response = await this.client.listMedia();
            // 조회를 기다리는 중 사용자가 명령을 보냈다면 오래된 조회 결과를 버립니다.
            if (this.canPoll() && this.revision === startedAtRevision) {
                this.view.render(response);
            }
        } catch (error) {
            if (this.canPoll() && this.revision === startedAtRevision) {
                this.view.showStatus(`상태 갱신 실패: ${error}`);
            }
        } finally {
            this.isPolling = false;
        }
    }
}

if (typeof document !== 'undefined' && typeof browser !== 'undefined') {
    const controller = new PopupController(createMediaClient(browser.runtime));
    controller.start();
}
