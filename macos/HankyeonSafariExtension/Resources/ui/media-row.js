import { currentSeekRange, formatTime } from '../media/media-model.js';

/** 미디어 한 개의 화면입니다. 버튼 명령은 컨트롤러에 전달합니다. */
export class MediaRow {
    constructor(media, onCommand, onEditing) {
        this.media = media;
        this.onCommand = onCommand;
        this.onEditing = onEditing;
        this.element = document.createElement('article');
        this.title = this.createText('title');
        this.metadata = this.createText('meta');
        this.createHeader();

        this.playButton = this.createButton('재생', () => this.sendCommand('play'));
        this.pauseButton = this.createButton('일시정지', () => this.sendCommand('pause'));
        this.muteButton = this.createButton('', () =>
            this.sendCommand(this.media.muted ? 'unmute' : 'mute')
        );
        this.element.append(this.playButton, this.pauseButton, this.muteButton);

        const volumeControl = this.createSlider('볼륨', 'volume-row');
        this.volumeSlider = volumeControl.slider;
        this.volumeOutput = volumeControl.output;
        this.volumeSlider.min = '0';
        this.volumeSlider.max = '100';
        this.volumeSlider.step = '1';
        this.volumeSlider.addEventListener('input', () => {
            this.volumeOutput.textContent = `${this.volumeSlider.value}%`;
        });
        this.volumeSlider.addEventListener('change', () => {
            this.sendCommand('volume', { volume: Number(this.volumeSlider.value) / 100 });
        });

        const seekControl = this.createSlider('위치', 'seek-row');
        this.seekSlider = seekControl.slider;
        this.seekOutput = seekControl.output;
        this.seekSlider.step = '0.1';
        this.seekSlider.addEventListener('input', () => this.updateTime());
        this.seekSlider.addEventListener('change', () => {
            this.sendCommand('seek', { position: Number(this.seekSlider.value) });
        });
        this.seekNote = this.createText('meta');
        this.seekNote.textContent = '아직 이동 가능한 범위가 없습니다.';
        this.element.append(this.seekNote);

        this.update(media);
    }

    createHeader() {
        const header = document.createElement('div');
        header.className = 'media-header';
        const artwork = document.createElement('div');
        artwork.className = 'media-artwork';
        artwork.setAttribute('aria-hidden', 'true');
        this.thumbnail = document.createElement('img');
        this.thumbnail.alt = '';
        this.thumbnail.loading = 'lazy';
        this.thumbnail.referrerPolicy = 'no-referrer';
        this.thumbnail.addEventListener('error', () => {
            this.thumbnail.hidden = true;
            this.artworkFallback.hidden = false;
        });
        this.artworkFallback = document.createElement('span');
        artwork.append(this.thumbnail, this.artworkFallback);
        const description = document.createElement('div');
        description.className = 'media-description';
        description.append(this.title, this.metadata);
        header.append(artwork, description);
        this.element.append(header);
    }

    updateThumbnail(media) {
        this.artworkFallback.textContent = media.kind === 'audio' ? '♫' : '▶';
        const nextUrl = media.thumbnailUrl ?? null;
        // 주기 조회마다 같은 이미지를 다시 불러오지 않습니다.
        if (this.currentThumbnailUrl === nextUrl) return;
        this.currentThumbnailUrl = nextUrl;
        this.thumbnail.hidden = !nextUrl;
        this.artworkFallback.hidden = Boolean(nextUrl);
        if (nextUrl) this.thumbnail.src = nextUrl;
        else this.thumbnail.removeAttribute('src');
    }

    createText(className) {
        const element = document.createElement('p');
        element.className = className;
        return element;
    }

    createButton(label, onClick) {
        const button = document.createElement('button');
        button.textContent = label;
        button.addEventListener('click', onClick);
        return button;
    }

    createSlider(label, className) {
        const row = document.createElement('label');
        row.className = className;
        const name = document.createElement('span');
        name.textContent = label;
        const slider = document.createElement('input');
        slider.type = 'range';
        slider.addEventListener('pointerdown', this.onEditing);
        const output = document.createElement('output');
        row.append(name, slider, output);
        this.element.append(row);
        return { slider, output };
    }

    async sendCommand(action, options = {}) {
        const succeeded = await this.onCommand(this.media, action, options);
        if (!succeeded) this.update(this.media);
    }

    updateTime() {
        this.seekOutput.textContent = `${formatTime(Number(this.seekSlider.value))} / ${formatTime(this.media.duration)}`;
    }

    update(media) {
        this.media = media;
        this.updateThumbnail(media);
        this.title.textContent = media.title;
        const playback = media.paused ? '일시정지' : '재생 중';
        const mute = media.muted ? ' · 음소거' : '';
        const kind = media.kind === 'audio' ? '오디오' : '영상';
        this.metadata.textContent = `${playback}${mute} · ${kind} · 프레임 ${media.frameId}`;
        this.muteButton.textContent = media.muted ? '음소거 해제' : '음소거';

        this.volumeSlider.setAttribute('aria-label', `${media.title} 볼륨`);
        this.volumeSlider.value = String(Math.round(media.volume * 100));
        this.volumeOutput.textContent = `${this.volumeSlider.value}%`;

        const range = currentSeekRange(media);
        this.canSeek = Boolean(range && range.end > range.start);
        this.seekSlider.setAttribute('aria-label', `${media.title} 재생 위치`);
        this.seekSlider.min = String(range?.start ?? 0);
        this.seekSlider.max = String(range?.end ?? 0);
        this.seekSlider.value = String(media.currentTime);
        this.seekSlider.disabled = !this.canSeek;
        this.seekNote.hidden = this.canSeek;
        this.updateTime();
    }

    setBusy(isBusy) {
        this.playButton.disabled = isBusy;
        this.pauseButton.disabled = isBusy;
        this.muteButton.disabled = isBusy;
        this.volumeSlider.disabled = isBusy;
        this.seekSlider.disabled = isBusy || !this.canSeek;
    }
}
