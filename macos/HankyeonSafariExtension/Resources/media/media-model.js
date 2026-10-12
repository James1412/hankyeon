/** 제목과 URL이 같아도 다른 탭이나 다른 미디어 요소일 수 있습니다. */
export function mediaKey(media) {
    return JSON.stringify([media.tabId, media.mediaId, media.tabUrl, media.mediaUrl]);
}

export function uniqueMedia(mediaList) {
    const byIdentity = new Map();
    for (const media of mediaList) {
        const key = mediaKey(media);
        if (!byIdentity.has(key)) byIdentity.set(key, media);
    }
    return Array.from(byIdentity.values());
}

/** 프레임이 바뀌면 명령의 대상도 바뀌므로 화면을 다시 구성합니다. */
export function listSignature(mediaList) {
    const keys = mediaList.map(media => [mediaKey(media), media.frameId]);
    return JSON.stringify(keys.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))));
}

export function currentSeekRange(media) {
    return media.seekable.find(range =>
        media.currentTime >= range.start && media.currentTime <= range.end
    );
}

export function formatTime(seconds) {
    if (!Number.isFinite(seconds)) return '라이브';
    const totalSeconds = Math.max(0, Math.floor(seconds));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor(totalSeconds / 60) % 60;
    const secondText = String(totalSeconds % 60).padStart(2, '0');
    const minuteText = hours ? String(minutes).padStart(2, '0') : String(minutes);
    return `${hours ? hours + ':' : ''}${minuteText}:${secondText}`;
}
