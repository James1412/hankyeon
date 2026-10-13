import 'media_slider.dart';
import 'marquee_title.dart';

import 'package:flutter/material.dart';

import '../../models/media_info.dart';
import '../../repositories/media_repository.dart';

typedef MediaCommand = Future<void> Function(
  MediaInfo media,
  MediaAction action, {
  double? volume,
  double? position,
});

/// 슬라이더를 드래그하는 동안의 임시 값만 보관합니다. 명령은 손을 놓을 때 한 번 보냅니다.
class MediaCard extends StatefulWidget {
  final MediaInfo media;
  final bool enabled;
  final bool busy;
  final MediaCommand onCommand;
  const MediaCard({
    super.key,
    required this.media,
    required this.enabled,
    required this.busy,
    required this.onCommand,
  });
  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  double? _draftVolume;
  double? _draftPosition;
  bool get enabled =>
      widget.enabled && widget.media.controlAvailable && !widget.busy;

  Future<void> _commitVolume(double value) async {
    await widget.onCommand(widget.media, MediaAction.volume, volume: value);
    if (mounted) setState(() => _draftVolume = null);
  }

  Future<void> _commitPosition(double value) async {
    await widget.onCommand(widget.media, MediaAction.seek, position: value);
    if (mounted) setState(() => _draftPosition = null);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final volume = _draftVolume ?? media.volume;
    final position = _draftPosition ?? media.currentTime;
    final min = media.canSeek ? media.seekable.first.start : 0.0;
    final max = media.canSeek ? media.seekable.last.end : 1.0;
    if (media.kind == 'appAudio') {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: MarqueeTitle(title: media.title)),
                  Text(
                    '${(volume * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              MediaSlider(
                label: '${media.title} 볼륨',
                valueText: '${(volume * 100).round()}%',
                height: 30,
                value: volume,
                min: 0,
                max: 1,
                step: .05,
                onChanged: enabled
                    ? (value) => setState(() => _draftVolume = value)
                    : null,
                onChangeEnd: enabled ? _commitVolume : null,
              ),
              if (!media.controlAvailable)
                const Text(
                  '오디오 접근 허용 후 조절할 수 있어요',
                  style: TextStyle(fontSize: 10, color: Colors.white60),
                ),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .07),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarqueeTitle(title: media.title),
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: media.thumbnailUrl == null
                        ? _fallback(context)
                        : Image.network(
                            media.thumbnailUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            cacheHeight: 96,
                            errorBuilder: (context, error, stack) =>
                                _fallback(context),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      MediaSlider(
                        label: '${media.title} 재생 위치',
                        valueText: formatMediaTime(position),
                        height: 28,
                        step: 5,
                        value: position.clamp(min, max).toDouble(),
                        min: min,
                        max: max,
                        onChanged: enabled && media.canSeek
                            ? (value) => setState(() => _draftPosition = value)
                            : null,
                        onChangeEnd: enabled && media.canSeek
                            ? _commitPosition
                            : null,
                      ),
                      Text(
                        '${formatMediaTime(position)} / ${media.duration == null ? '라이브' : formatMediaTime(media.duration!)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      MediaSlider(
                        label: '${media.title} 볼륨',
                        valueText: '${(volume * 100).round()}%',
                        height: 28,
                        value: volume,
                        min: 0,
                        max: 1,
                        step: .05,
                        onChanged: enabled
                            ? (value) => setState(() => _draftVolume = value)
                            : null,
                        onChangeEnd: enabled ? _commitVolume : null,
                      ),
                      Text(
                        '볼륨 ${(volume * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                IconButton(
                  tooltip: media.paused ? '재생' : '일시정지',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: enabled
                      ? () => widget.onCommand(
                          media,
                          media.paused ? MediaAction.play : MediaAction.pause,
                        )
                      : null,
                  icon: Icon(
                    media.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                ),
                IconButton(
                  tooltip: media.muted ? '음소거 해제' : '음소거',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: enabled
                      ? () => widget.onCommand(
                          media,
                          media.muted ? MediaAction.unmute : MediaAction.mute,
                        )
                      : null,
                  icon: Icon(
                    media.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    media.paused ? '일시정지' : '재생 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (widget.busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      widget.media.kind == 'audio'
          ? Icons.music_note_rounded
          : Icons.ondemand_video_rounded,
    ),
  );
}

String formatMediaTime(double seconds) {
  final value = seconds.isFinite ? seconds.floor().clamp(0, 86400000) : 0;
  final hours = value ~/ 3600;
  final minutes = (value ~/ 60) % 60;
  final remaining = (value % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$remaining'
      : '$minutes:$remaining';
}
