import 'dart:async';

import 'package:flutter/services.dart';

import '../models/media_info.dart';
import '../models/media_snapshot.dart';
import '../models/media_target.dart';
import 'media_repository.dart';

/// Public Core Audio process taps. Browsers still keep their per-element controls.
class NativeAudioRepository implements MediaRepository {
  static const _events = EventChannel('hankyeon/audio/events');
  static const _methods = MethodChannel('hankyeon/audio/commands');
  @override
  Stream<MediaSnapshot> get snapshots => _snapshots;
  late final Stream<MediaSnapshot> _snapshots = _events
      .receiveBroadcastStream()
      .map((value) {
        final map = Map<String, dynamic>.from(value as Map);
        final apps = (map['apps'] as List? ?? []).whereType<Map>();
        return MediaSnapshot(
          connection: map['connection'] == 'ready'
              ? MediaConnection.ready
              : MediaConnection.waiting,
          message: map['message'] as String? ?? '앱 오디오 연결 대기',
          errors: (map['errors'] as List? ?? []).whereType<String>().toList(),
          mediaList: apps
              .map((app) {
                final volume = (app['volume'] as num? ?? 1).toDouble().clamp(
                  0.0,
                  1.0,
                );
                return MediaInfo(
                  target: NativeAppTarget(
                    bundleID: app['bundleID'] as String,
                    name: app['title'] as String,
                  ),
                  title: app['title'] as String,
                  kind: 'appAudio',
                  volume: volume,
                  muted: volume == 0,
                  controlAvailable: map['connection'] == 'ready',
                );
              })
              .toList(growable: false),
        );
      });
  Future<bool> authorize() async =>
      await _methods.invokeMethod<bool>('authorize') ?? false;
  @override
  Future<void> refresh() => _methods.invokeMethod<void>('refresh');
  @override
  Future<void> openSettings() async {
    await authorize();
  }

  @override
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) async {
    final target = media.target;
    if (target is! NativeAppTarget || !media.controlAvailable) {
      throw StateError('앱 오디오 접근을 확인해주세요.');
    }
    final gain = switch (action) {
      MediaAction.volume => volume,
      MediaAction.mute => 0.0,
      MediaAction.unmute => 1.0,
      _ => throw UnsupportedError('이 앱은 볼륨만 제어할 수 있습니다.'),
    };
    if (gain == null || !gain.isFinite || gain < 0 || gain > 1) {
      throw ArgumentError('볼륨 범위가 잘못되었습니다.');
    }
    await _methods.invokeMethod<void>('volume', {
      'bundleID': target.bundleID,
      'volume': gain,
    });
  }
}
