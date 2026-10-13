import 'dart:async';

import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_target.dart';
import 'package:hankyeon/models/media_snapshot.dart';
import 'package:hankyeon/repositories/media_repository.dart';

Map<String, dynamic> mediaMap({String id = 'a', String title = '영상 A'}) => {
  'mediaId': id,
  'tabId': 12,
  'frameId': 0,
  'tabUrl': 'https://example.com/watch',
  'mediaUrl': 'https://example.com/watch',
  'title': title,
  'paused': false,
  'volume': 0.5,
  'currentTime': 12,
  'duration': 100,
  'seekable': [
    {'start': 0, 'end': 100},
  ],
};

class FakeMediaRepository implements MediaRepository {
  final events = StreamController<MediaSnapshot>.broadcast(sync: true);
  final commands = <Map<String, Object?>>[];
  Completer<void>? pendingCommand;
  @override
  Stream<MediaSnapshot> get snapshots => events.stream;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) async {
    commands.add({
      'id': media.target is WebMediaTarget
          ? (media.target as WebMediaTarget).mediaId
          : media.identity,
      'action': action,
      'volume': volume,
      'position': position,
    });
    if (pendingCommand != null) await pendingCommand!.future;
  }

  void send(
    List<MediaInfo> media, {
    MediaConnection connection = MediaConnection.ready,
  }) {
    events.add(
      MediaSnapshot(
        mediaList: media,
        connection: connection,
        message: 'Safari 연결됨',
      ),
    );
  }
}
