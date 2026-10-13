import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/media_info.dart';
import '../models/media_snapshot.dart';
import '../models/media_target.dart';
import 'media_repository.dart';

/// 다른 브라우저 확장과 loopback에서만 통신합니다. 연결별 인증과 명령 응답을 분리합니다.
class BrowserMediaRepository implements MediaRepository {
  final _events = StreamController<MediaSnapshot>.broadcast();
  final _peers = <String, WebSocket>{};
  final _lists = <String, List<MediaInfo>>{};
  final _pending = <String, Completer<void>>{};
  final int port;
  final bool persistToken;
  BrowserMediaRepository({this.port = 43127, this.persistToken = true});
  HttpServer? _server;
  int _sequence = 0;
  String token = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String get endpoint => 'ws://127.0.0.1:${_server?.port ?? 43127}';
  String? startupError;
  @override
  Stream<MediaSnapshot> get snapshots => _events.stream;

  Future<void> start() async {
    try {
      if (persistToken) {
        final directory = await const MethodChannel('hankyeon/window')
            .invokeMethod<String>('connectionDirectory');
        if (directory != null) {
          final file = File('$directory/browser-token');
          if (await file.exists()) {
            final saved = (await file.readAsString()).trim();
            if (RegExp(r'^[a-f0-9]{64}$').hasMatch(saved)) {
              token = saved;
            }
          }
          await file.parent.create(recursive: true);
          await file.writeAsString(token, flush: true);
        }
      }
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server!.listen(_accept);
    } catch (error) {
      startupError = '브라우저 연결 서버를 열 수 없습니다: $error';
      _publish();
    }
  }

  Future<void> _accept(HttpRequest request) async {
    final origin = request.headers.value('origin') ?? '';
    if (!WebSocketTransformer.isUpgradeRequest(request) ||
        !(origin.startsWith('chrome-extension://') ||
            origin.startsWith('moz-extension://'))) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    String? peer;
    final authTimeout = Timer(const Duration(seconds: 5), () {
      if (peer == null) socket.close();
    });
    socket.listen(
      (data) {
        try {
          if (data is! String || data.length > 1024 * 1024) {
            throw const FormatException();
          }
          final message = jsonDecode(data) as Map<String, dynamic>;
          if (peer == null) {
            final id = message['clientId'];
            if (message['type'] != 'hello' ||
                message['token'] != token ||
                id is! String ||
                !RegExp(r'^[a-zA-Z0-9-]{8,100}$').hasMatch(id)) {
              socket.close(1008);
              return;
            }
            peer = id;
            authTimeout.cancel();
            _peers[id]?.close();
            _peers[id] = socket;
            socket.add(jsonEncode({'type': 'connected'}));
            _publish();
            return;
          }
          if (message['type'] == 'ping') {
            socket.add(jsonEncode({'type': 'pong'}));
          } else if (message['type'] == 'snapshot') {
            final list = message['mediaList'];
            if (list is! List || list.length > 2000) {
              throw const FormatException();
            }
            final name =
                [
                  'Chrome',
                  'Edge',
                  'Brave',
                  'Firefox',
                ].contains(message['browser'])
                ? message['browser'] as String
                : 'Browser';
            _lists[peer!] = list
                .whereType<Map>()
                .map(
                  (item) => MediaInfo.fromMap({
                    ...Map<String, dynamic>.from(item),
                    'browserClient': peer,
                    'browserName': name,
                  }),
                )
                .toList();
            _publish();
          } else if (message['type'] == 'result') {
            final completer = _pending.remove('$peer/${message['requestId']}');
            if (completer != null) {
              if (message['ok'] == true) {
                completer.complete();
              } else {
                completer.completeError(
                  StateError(message['error']?.toString() ?? '브라우저 명령 실패'),
                );
              }
            }
          }
        } catch (_) {
          socket.close(1008, 'Invalid message');
        }
      },
      onDone: () {
        authTimeout.cancel();
        if (peer != null && identical(_peers[peer], socket)) {
          _peers.remove(peer);
          _lists.remove(peer);
          for (final key
              in _pending.keys
                  .where((key) => key.startsWith('$peer/'))
                  .toList()) {
            _pending.remove(key)?.completeError(StateError('브라우저 연결이 끊겼습니다.'));
          }
          _publish();
        }
      },
      onError: (Object _) {
        socket.close();
      },
    );
  }

  void _publish() => _events.add(
    MediaSnapshot(
      mediaList: _lists.values.expand((list) => list).toList(),
      connection: _peers.isEmpty
          ? MediaConnection.waiting
          : MediaConnection.ready,
      message: startupError ?? '${_peers.length}개 브라우저 연결됨',
      updatedAt: DateTime.now(),
    ),
  );
  Future<void> _command(String client, Map<String, Object> command) async {
    final socket = _peers[client];
    if (socket == null) throw StateError('브라우저가 연결되지 않았습니다.');
    final id = '${++_sequence}';
    final key = '$client/$id';
    final completer = Completer<void>();
    _pending[key] = completer;
    socket.add(jsonEncode({'type': 'command', 'requestId': id, ...command}));
    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _pending.remove(key);
    }
  }

  @override
  Future<void> refresh() async {
    await Future.wait(
      _peers.keys.map((client) => _command(client, {'action': 'refresh'})),
    );
  }

  @override
  Future<void> openSettings() async {}
  @override
  Future<void> control(
    MediaInfo media,
    MediaAction action, {
    double? volume,
    double? position,
  }) async {
    final target = media.target as BrowserMediaTarget;
    if (action == MediaAction.volume &&
        (volume == null || !volume.isFinite || volume < 0 || volume > 1)) {
      throw ArgumentError('잘못된 볼륨');
    }
    await _command(target.clientId, {
      ...target.toMap(),
      'action': action.name,
      if (action == MediaAction.volume) 'volume': volume!,
      if (action == MediaAction.seek) 'position': media.seekPosition(position!),
    });
  }

  Future<void> dispose() async {
    for (final peer in _peers.values) {
      await peer.close();
    }
    await _server?.close(force: true);
    await _events.close();
  }
}
