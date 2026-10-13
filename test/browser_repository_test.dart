import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/repositories/browser_media_repository.dart';
import 'package:hankyeon/repositories/media_repository.dart';
import 'package:hankyeon/models/media_target.dart';

import 'media_test_support.dart';

void main() {
  test(
    'loopback rejects unauthenticated peers and routes acknowledged control',
    () async {
      final repository = BrowserMediaRepository(port: 0, persistToken: false);
      await repository.start();
      expect(repository.startupError, isNull);
      final stream = StreamIterator(repository.snapshots);
      final bad = await WebSocket.connect(
        repository.endpoint,
        headers: {'Origin': 'https://evil.example'},
      ).then<Object?>((socket) => socket, onError: (Object e) => e);
      expect(bad, isA<WebSocketException>());
      final socket = await WebSocket.connect(
        repository.endpoint,
        headers: {'Origin': 'chrome-extension://test'},
      );
      final replies = StreamIterator(socket);
      final initial = stream.moveNext();
      socket.add(
        jsonEncode({
          'type': 'hello',
          'token': repository.token,
          'clientId': 'test-client-123',
        }),
      );
      expect(
        await replies.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(jsonDecode(replies.current as String)['type'], 'connected');
      await initial.timeout(const Duration(seconds: 3));
      final update = stream.moveNext();
      socket.add(
        jsonEncode({
          'type': 'snapshot',
          'browser': 'Chrome',
          'mediaList': [mediaMap()],
        }),
      );
      await update.timeout(const Duration(seconds: 3));
      final media = stream.current.mediaList.single;
      expect(media.target, isA<BrowserMediaTarget>());
      final command = repository.control(
        media,
        MediaAction.volume,
        volume: 0.2,
      );
      await replies.moveNext().timeout(const Duration(seconds: 3));
      final message = jsonDecode(replies.current as String);
      expect(message['volume'], 0.2);
      expect(message['tabId'], 12);
      socket.add(
        jsonEncode({
          'type': 'result',
          'requestId': message['requestId'],
          'ok': true,
        }),
      );
      await command.timeout(const Duration(seconds: 3));
      await replies.cancel();
      await socket.close();
      await stream.cancel();
      await repository.dispose().timeout(const Duration(seconds: 3));
    },
  );
}
