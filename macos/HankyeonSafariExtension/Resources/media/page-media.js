/**
 * Safari가 이 함수를 직렬화해서 대상 웹페이지 안에서 실행합니다.
 * 외부 함수를 함께 전달하지 않으므로 도우미 함수는 이 함수 안에 둡니다.
 * 탭을 선택하거나 Safari를 앞으로 가져오지 않습니다.
 */
export async function mediaOperation(action, mediaId, expectedMediaUrl, volume = null, position = null) {
    const commandTimeoutMs = 6000;
    const minimumVideoDurationSeconds = 10;

    function isContentPlayer(media) {
        // 사용자 조작용 플레이어와 장식용 video를 구분합니다.
        return Boolean(media.controls || media.closest?.(
            '.html5-video-player, .video-js, .plyr, .vp-player, [data-content-player]'
        ));
    }

    function isBackgroundVideo(media) {
        if (media.tagName?.toLowerCase() !== 'video') return false;
        const explicitlyDecorative = media.closest?.(
            '[data-background-video], .background-video, .hero-video, .video-background'
        );
        if (explicitlyDecorative) return true;
        if (isContentPlayer(media)) return false;
        return Boolean(media.loop || (media.autoplay && media.muted));
    }

    function shouldListMedia(media) {
        // 아직 미디어 정보가 없는 빈/초기화 중 플레이어는 다음 조회에서 다시 확인합니다.
        if (media.readyState === 0) return false;
        if (isBackgroundVideo(media)) return false;

        const isVideo = media.tagName?.toLowerCase() === 'video';
        if (isVideo && Number.isFinite(media.duration)
            && media.duration <= minimumVideoDurationSeconds) return false;

        // 광고라는 명시적인 표시만 사용합니다. 제목에 'ad' 등이 포함된 것은 판단 근거가 아닙니다.
        const adContainer = media.closest?.(
            '#movie_player.ad-showing, [data-ad-player], [data-ad-video], .ima-ad-container, .video-ad-container'
        );
        return !adContainer;
    }

    function discoverMedia() {
        const mediaElements = [];
        const visitedRoots = new Set();
        const visitedElements = new Set();

        function visit(root, depth = 0) {
            if (!root || depth > 20 || visitedRoots.has(root)) return;
            visitedRoots.add(root);

            for (const element of root.querySelectorAll('*')) {
                if (element.matches('video, audio') && !visitedElements.has(element)) {
                    visitedElements.add(element);
                    mediaElements.push(element);
                }

                if (element.shadowRoot) visit(element.shadowRoot, depth + 1);
                if (!element.matches('iframe, frame')) continue;

                try {
                    const childDocument = element.contentDocument;
                    if (childDocument && /^(about:blank|about:srcdoc)/.test(childDocument.URL)) {
                        visit(childDocument, depth + 1);
                    }
                } catch (_) {
                    // 다른 출처의 프레임에는 Safari가 별도로 함수를 주입합니다.
                }
            }
        }

        visit(document);
        for (const media of mediaElements) {
            if (!media.dataset.hankyeonMediaId) {
                media.dataset.hankyeonMediaId = crypto.randomUUID();
            }
        }
        return mediaElements;
    }

    function documentUrl(media) {
        return media.ownerDocument?.URL ?? location.href;
    }

    function thumbnailUrl(media) {
        const mediaDocument = media.ownerDocument ?? document;
        // SPA의 대표 이미지 메타 태그가 이전 영상에 머물러 있어도 현재 영상 ID를 사용합니다.
        try {
            const page = new URL(documentUrl(media));
            if (page.hostname === 'youtube.com' || page.hostname.endsWith('.youtube.com')) {
                const videoId = page.searchParams.get('v')
                    ?? page.pathname.match(/^\/(?:embed|shorts)\/([\w-]+)/)?.[1];
                if (/^[\w-]{11}$/.test(videoId ?? '')) {
                    return `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;
                }
            }
        } catch (_) { /* 일반 문서의 poster와 대표 이미지를 확인합니다. */ }
        // 영상 자체의 poster를 우선 사용하고, 없으면 페이지 대표 이미지를 사용합니다.
        const candidates = [
            media.poster,
            mediaDocument.defaultView?.navigator?.mediaSession?.metadata?.artwork?.[0]?.src,
            mediaDocument.querySelector?.('meta[property="og:image"]')?.content,
            mediaDocument.querySelector?.('meta[name="twitter:image"]')?.content,
        ];

        for (const candidate of candidates) {
            if (!candidate?.trim()) continue;
            try {
                const imageUrl = new URL(candidate, mediaDocument.baseURI ?? documentUrl(media));
                // 페이지의 blob 주소는 확장 화면에서 사용할 수 없으므로 제외합니다.
                if (['https:', 'http:'].includes(imageUrl.protocol)) return imageUrl.href;
            } catch (_) {
                // 잘못된 주소이면 다음 후보를 확인합니다.
            }
        }
        return null;
    }

    function siteIconUrl() {
        const icon = document.querySelector?.('link[rel~="icon"]')?.href;
        if (!icon) return null;
        try {
            const url = new URL(icon, document.baseURI ?? location.href);
            return ['https:', 'http:'].includes(url.protocol) ? url.href : null;
        } catch (_) {
            return null;
        }
    }

    function snapshot(media) {
        const seekable = [];
        for (let index = 0; index < media.seekable.length; index++) {
            seekable.push({
                start: media.seekable.start(index),
                end: media.seekable.end(index),
            });
        }

        return {
            mediaId: media.dataset.hankyeonMediaId,
            title: media.ownerDocument?.title || document.title,
            mediaUrl: documentUrl(media),
            thumbnailUrl: thumbnailUrl(media),
            kind: media.tagName?.toLowerCase() ?? 'video',
            paused: media.paused,
            ended: media.ended,
            volume: media.volume,
            muted: media.muted,
            currentTime: media.currentTime,
            seekable,
            duration: Number.isFinite(media.duration) ? media.duration : null,
        };
    }

    function setVolume(media, requestedVolume) {
        if (typeof requestedVolume !== 'number' || !Number.isFinite(requestedVolume)
            || requestedVolume < 0 || requestedVolume > 1) {
            throw new Error('볼륨은 0~100% 범위여야 합니다.');
        }

        media.volume = requestedVolume;
        if (Math.abs(media.volume - requestedVolume) > 0.001) {
            throw new Error('볼륨 변경을 확인하지 못했습니다.');
        }
    }

    async function play(media) {
        let timeout;
        try {
            await Promise.race([
                media.play(),
                new Promise((_, reject) => {
                    timeout = setTimeout(() => {
                        media.pause();
                        reject(new Error('재생 요청 시간이 초과되었습니다.'));
                    }, commandTimeoutMs);
                }),
            ]);
        } finally {
            clearTimeout(timeout);
        }
    }

    async function seek(media, requestedPosition) {
        if (typeof requestedPosition !== 'number' || !Number.isFinite(requestedPosition)
            || requestedPosition < 0) {
            throw new Error('재생 위치는 유효한 초 단위 값이어야 합니다.');
        }

        let isSeekable = false;
        for (let index = 0; index < media.seekable.length; index++) {
            if (requestedPosition >= media.seekable.start(index)
                && requestedPosition <= media.seekable.end(index)) {
                isSeekable = true;
                break;
            }
        }
        if (!isSeekable) {
            throw new Error('현재 이동 가능한 범위 밖입니다. 목록을 새로고침해주세요.');
        }

        await new Promise((resolve, reject) => {
            let timeout;

            function cleanup() {
                clearTimeout(timeout);
                media.removeEventListener('seeked', onSeeked);
                media.removeEventListener('error', onError);
            }

            function onSeeked() {
                cleanup();
                if (Math.abs(media.currentTime - requestedPosition) < 1) {
                    resolve();
                } else {
                    reject(new Error('재생 위치 변경을 확인하지 못했습니다.'));
                }
            }

            function onError() {
                cleanup();
                reject(new Error('미디어 탐색 중 오류가 발생했습니다.'));
            }

            media.addEventListener('seeked', onSeeked);
            media.addEventListener('error', onError);
            timeout = setTimeout(() => {
                cleanup();
                reject(new Error('재생 위치 변경 시간이 초과되었습니다.'));
            }, commandTimeoutMs);

            try {
                media.currentTime = requestedPosition;
                if (!media.seeking) onSeeked();
            } catch (error) {
                cleanup();
                reject(error);
            }
        });
    }

    async function executeCommand(media) {
        switch (action) {
            case 'play':
                await play(media);
                break;
            case 'pause':
                media.pause();
                break;
            case 'volume':
                setVolume(media, volume);
                break;
            case 'mute':
                media.muted = true;
                break;
            case 'unmute':
                media.muted = false;
                break;
            case 'seek':
                await seek(media, position);
                break;
            default:
                throw new Error('지원하지 않는 명령입니다.');
        }

        const playbackStateIsIncorrect = (action === 'play' && media.paused)
            || (action === 'pause' && !media.paused);
        if (playbackStateIsIncorrect) {
            throw new Error('요청한 상태로 바뀌지 않았습니다.');
        }
    }

    try {
        const mediaElements = discoverMedia();
        if (action !== 'snapshot') {
            const media = mediaElements.find(element => element.dataset.hankyeonMediaId === mediaId);
            if (!media) {
                throw new Error('대상 미디어가 사라졌습니다. 목록을 새로고침해주세요.');
            }
            if (expectedMediaUrl && documentUrl(media) !== expectedMediaUrl) {
                throw new Error('미디어 문서가 바뀌었습니다. 목록을 새로고침해주세요.');
            }
            if (!shouldListMedia(media)) {
                throw new Error('광고·짧은 영상 또는 준비되지 않은 미디어입니다. 목록을 새로고침해주세요.');
            }
            await executeCommand(media);
        }

        const embeddedUrls = Array.from(document.querySelectorAll('iframe, frame'))
            .map(frame => frame.src)
            .filter(url => /^https?:\/\//.test(url));

        return {
            ok: true,
            documentUrl: location.href,
            embeddedUrls,
            mediaList: mediaElements.filter(shouldListMedia).map(snapshot),
            siteIconUrl: siteIconUrl(),
        };
    } catch (error) {
        return { ok: false, error: String(error) };
    }
}
