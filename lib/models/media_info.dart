import 'media_target.dart';

/// 외부 미디어를 앱에서 사용하는 형태로 변환합니다. 화면·통신에는 의존하지 않습니다.
class MediaInfo {
  final MediaTarget target;
  final bool controlAvailable;
  final String title;
  final String? thumbnailUrl;
  final String kind;
  final bool paused;
  final bool ended;
  final bool muted;
  final double volume;
  final double currentTime;
  final double? duration;
  final List<SeekRange> seekable;

  const MediaInfo({
    required this.target,
    this.controlAvailable = true,
    required this.title,
    this.thumbnailUrl,
    this.kind = 'video',
    this.paused = true,
    this.ended = false,
    this.muted = false,
    this.volume = 1,
    this.currentTime = 0,
    this.duration,
    this.seekable = const [],
  });

  /// 제목이 같은 영상도 구별하고, 페이지 이동 후 이전 대상을 제어하지 않습니다.
  String get identity => target.identity;
  bool get canSeek => seekable.isNotEmpty;
  String get website => target.sourceLabel;

  MediaInfo withControlAvailable(bool available) => MediaInfo(
    target: target,
    title: title,
    thumbnailUrl: thumbnailUrl,
    kind: kind,
    paused: paused,
    ended: ended,
    muted: muted,
    volume: volume,
    currentTime: currentTime,
    duration: duration,
    seekable: seekable,
    controlAvailable: available && controlAvailable,
  );

  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    final mediaId = map['mediaId'];
    final tabId = _integer(map['tabId']);
    final frameId = _integer(map['frameId']);
    final tabUrl = _webUrl(map['tabUrl']);
    final mediaUrl = _webUrl(map['mediaUrl']);
    if (mediaId is! String ||
        mediaId.isEmpty ||
        tabId == null ||
        frameId == null ||
        frameId < 0 ||
        tabUrl == null ||
        mediaUrl == null) {
      throw const FormatException('미디어 식별자가 올바르지 않습니다.');
    }
    final ranges = <SeekRange>[];
    if (map['seekable'] case final List values) {
      for (final value in values) {
        if (value is! Map) continue;
        final start = _number(value['start']);
        final end = _number(value['end']);
        if (start != null && end != null && start >= 0 && end > start) {
          ranges.add(SeekRange(start, end));
        }
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final title = map['title'];
    final duration = _number(map['duration']);
    return MediaInfo(
      target: map['browserClient'] is String
          ? BrowserMediaTarget(
              clientId: map['browserClient'] as String,
              browserName: map['browserName'] as String? ?? 'Browser',
              mediaId: mediaId,
              tabId: tabId,
              frameId: frameId,
              tabUrl: tabUrl,
              mediaUrl: mediaUrl,
            )
          : SafariMediaTarget(
              mediaId: mediaId,
              tabId: tabId,
              frameId: frameId,
              tabUrl: tabUrl,
              mediaUrl: mediaUrl,
            ),
      title: title is String && title.trim().isNotEmpty ? title : '제목 없는 미디어',
      thumbnailUrl: _webUrl(map['thumbnailUrl']),
      kind: map['kind'] == 'audio' ? 'audio' : 'video',
      paused: map['paused'] is bool ? map['paused'] as bool : true,
      ended: map['ended'] == true,
      muted: map['muted'] == true,
      volume: (_number(map['volume']) ?? 1).clamp(0, 1).toDouble(),
      currentTime: (_number(map['currentTime']) ?? 0)
          .clamp(0, double.infinity)
          .toDouble(),
      duration: duration != null && duration > 0 ? duration : null,
      seekable: List.unmodifiable(ranges),
    );
  }

  /// 라이브·분할 재생 범위의 빈 구간으로 이동하지 않도록 가장 가까운 위치를 선택합니다.
  double seekPosition(double requested) {
    if (!requested.isFinite || !canSeek) {
      throw const FormatException('탐색할 수 없는 미디어입니다.');
    }
    var closest = seekable.first.start;
    var distance = double.infinity;
    for (final range in seekable) {
      final candidate = requested.clamp(range.start, range.end).toDouble();
      final delta = (requested - candidate).abs();
      if (delta < distance) {
        closest = candidate;
        distance = delta;
      }
    }
    return closest;
  }

  static double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  static int? _integer(Object? value) =>
      value is num && value.isFinite && value == value.roundToDouble()
      ? value.toInt()
      : null;
  static String? _webUrl(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? value
        : null;
  }
}

class SeekRange {
  final double start;
  final double end;
  const SeekRange(this.start, this.end);
}
