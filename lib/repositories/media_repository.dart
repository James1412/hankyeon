import '../models/media_info.dart';
import '../models/media_snapshot.dart';

enum MediaAction { play, pause, mute, unmute, volume, seek }

/// 화면은 Safari API를 알 필요가 없습니다. 다른 미디어 소스도 이 계약을 구현할 수 있습니다.
abstract interface class MediaRepository {
  Stream<MediaSnapshot> get snapshots;
  Future<void> refresh();
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  });
  Future<void> openSettings();
}
