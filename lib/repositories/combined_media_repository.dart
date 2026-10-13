import 'dart:async';

import '../models/media_info.dart';
import '../models/media_snapshot.dart';
import '../models/media_target.dart';
import 'media_repository.dart';

/// 소스별 상태를 유지하며, 명령은 해당 대상의 소스로만 전달합니다.
class CombinedMediaRepository implements MediaRepository {
  final MediaRepository safari;
  final MediaRepository browsers;
  final MediaRepository? native;
  CombinedMediaRepository(this.safari, this.browsers, [this.native]);
  MediaSnapshot _safariState = const MediaSnapshot();
  MediaSnapshot _browserState = const MediaSnapshot();
  MediaSnapshot _nativeState = const MediaSnapshot();
  MediaSnapshot _latest = const MediaSnapshot();
  final _subscriptions = <StreamSubscription<MediaSnapshot>>[];
  late final _updates = StreamController<MediaSnapshot>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  @override
  late final Stream<MediaSnapshot> snapshots = Stream.multi((sink) {
    sink.add(_latest);
    final subscription = _updates.stream.listen(
      sink.add,
      onError: sink.addError,
    );
    sink.onCancel = subscription.cancel;
  });

  void _start() {
    _subscriptions.add(
      safari.snapshots.listen((value) {
        _safariState = value;
        _publish();
      }, onError: _updates.addError),
    );
    _subscriptions.add(
      browsers.snapshots.listen((value) {
        _browserState = value;
        _publish();
      }, onError: _updates.addError),
    );
    if (native != null) {
      _subscriptions.add(
        native!.snapshots.listen((value) {
          _nativeState = value;
          _publish();
        }, onError: _updates.addError),
      );
    }
  }

  void _stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _publish() {
    final sources = [_safariState, _browserState, _nativeState];
    final ready = sources.any((source) => source.canControl);
    final times =
        sources.map((source) => source.updatedAt).whereType<DateTime>().toList()
          ..sort();
    _latest = MediaSnapshot(
      mediaList: sources
          .expand(
            (source) => source.mediaList.map(
              (media) => media.withControlAvailable(source.canControl),
            ),
          )
          .toList(growable: false),
      errors: sources.expand((source) => source.errors).toList(growable: false),
      connection: ready ? MediaConnection.ready : _safariState.connection,
      message: ready ? '미디어 연결됨' : _safariState.message,
      updatedAt: times.lastOrNull,
    );
    _updates.add(_latest);
  }

  @override
  Future<void> refresh() async {
    final results = await Future.wait([
      safari.refresh().then<Object?>((_) => null).catchError((Object e) => e),
      if (native != null)
        native!
            .refresh()
            .then<Object?>((_) => null)
            .catchError((Object e) => e),
      browsers.refresh().then<Object?>((_) => null).catchError((Object e) => e),
    ]);
    if (results.every((e) => e != null)) throw StateError('미디어 연결을 확인해주세요.');
  }

  @override
  Future<void> openSettings() => safari.openSettings();
  @override
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) =>
      (media.target is NativeAppTarget
              ? (native ?? (throw StateError("앱 오디오 소스가 없습니다.")))
              : media.target is BrowserMediaTarget
              ? browsers
              : safari)
          .control(media, action, volume: volume, position: position);
}
