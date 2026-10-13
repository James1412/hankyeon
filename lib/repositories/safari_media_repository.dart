import 'package:flutter/services.dart';

import '../models/media_info.dart';
import '../models/media_target.dart';
import '../models/media_snapshot.dart';
import 'media_repository.dart';

/// Platform Channel 수신과 명령 전달만 담당합니다. UI 상태는 컨트롤러가 관리합니다.
class SafariMediaRepository implements MediaRepository {
  final EventChannel _events;
  final MethodChannel _commands;

  SafariMediaRepository({EventChannel? events, MethodChannel? commands})
    : _events = events ?? const EventChannel('hankyeon/media/events'),
      _commands = commands ?? const MethodChannel('hankyeon/media/commands');

  @override
  late final Stream<MediaSnapshot> snapshots = _events
      .receiveBroadcastStream()
      .map((event) {
        if (event is! Map) {
          throw const FormatException('Swift 이벤트 형식이 올바르지 않습니다.');
        }
        return MediaSnapshot.fromMap(Map<String, dynamic>.from(event));
      });

  @override
  Future<void> refresh() => _commands.invokeMethod<void>('refresh');

  @override
  Future<void> openSettings() =>
      _commands.invokeMethod<void>('openSafariSettings');

  @override
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) {
    final target = media.target;
    if (target is! SafariMediaTarget) {
      throw UnsupportedError('Safari 대상만 이 연결로 제어할 수 있습니다.');
    }
    if (action == MediaAction.volume &&
        (volume == null || !volume.isFinite || volume < 0 || volume > 1)) {
      throw ArgumentError('볼륨은 0부터 1 사이여야 합니다.');
    }
    if (action == MediaAction.seek &&
        (position == null || !media.canSeek || !position.isFinite)) {
      throw ArgumentError('탐색 가능한 위치를 지정해주세요.');
    }
    return _commands.invokeMethod<void>('control', {
      ...target.toMap(),
      'action': action.name,
      if (action == MediaAction.volume) 'volume': volume,
      if (action == MediaAction.seek) 'position': media.seekPosition(position!),
    });
  }
}
