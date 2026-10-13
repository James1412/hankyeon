import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/media_info.dart';
import '../models/media_snapshot.dart';
import '../repositories/media_repository.dart';

/// 최신 목록, 명령 진행 상태, 사용자 오류를 관리합니다. 위젯이나 Swift에 의존하지 않습니다.
class MediaController extends ChangeNotifier {
  final MediaRepository repository;
  StreamSubscription<MediaSnapshot>? _subscription;
  bool _disposed = false;
  final Set<String> _busyTargets = {};
  MediaSnapshot snapshot = const MediaSnapshot();
  bool refreshing = false;
  String? commandError;

  MediaController(this.repository);
  bool isBusy(MediaInfo media) => _busyTargets.contains(media.identity);

  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = repository.snapshots.listen(
      (value) {
        snapshot = value;
        _notify();
      },
      onError: (Object error) {
        snapshot = MediaSnapshot(
          mediaList: snapshot.mediaList,
          errors: snapshot.errors,
          updatedAt: snapshot.updatedAt,
          connection: MediaConnection.error,
          message: _message(error),
        );
        _notify();
      },
    );
  }

  Future<void> refresh() async {
    if (refreshing || _disposed) return;
    refreshing = true;
    commandError = null;
    _notify();
    try {
      await repository.refresh();
    } catch (error) {
      commandError = _message(error);
    } finally {
      refreshing = false;
      _notify();
    }
  }

  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) async {
    if (_disposed || isBusy(media)) return;
    if (!snapshot.canControl ||
        !snapshot.mediaList.any((item) => item.identity == media.identity)) {
      commandError = '미디어가 변경됐거나 연결이 끊겼습니다. 목록을 다시 확인해주세요.';
      _notify();
      return;
    }
    _busyTargets.add(media.identity);
    commandError = null;
    _notify();
    try {
      await repository.control(
        media,
        action,
        volume: volume,
        position: position,
      );
    } catch (error) {
      commandError = _message(error);
    } finally {
      _busyTargets.remove(media.identity);
      _notify();
    }
  }

  Future<void> openSettings() async {
    try {
      await repository.openSettings();
    } catch (error) {
      commandError = _message(error);
      _notify();
    }
  }

  void dismissError() {
    commandError = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _message(Object error) => error is PlatformException
      ? error.message ?? error.code
      : error.toString();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
