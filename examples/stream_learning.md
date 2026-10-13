# Stream 학습 코드

실제 앱은 `lib/repositories/safari_media_repository.dart`의 채널을 사용합니다.
아래는 서비스 분리를 공부하던 단계의 코드이며 현재 앱의 실행 경로가 아닙니다.

## lib/screens/stream_practice.dart

```dart
import 'package:flutter/material.dart';

import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/services/stream_service.dart';

class StreamPracticeScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<StreamPracticeScreen> createState() => _StreamPracticeScreenState();
}

class _StreamPracticeScreenState extends State<StreamPracticeScreen> {
  final mediaStream = MediaService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<MediaInfo>>(
        stream: mediaStream.mediaStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }

          final mediaList = snapshot.data;
          if (mediaList == null) {
            return const Center(child: Text('미디어 목록 기다리는 중…'));
          }

          if (mediaList.isEmpty) {
            return const Center(child: Text('감지된 미디어 없음'));
          }

          return ListView.builder(
            itemCount: mediaList.length,
            itemBuilder: (context, index) {
              final media = mediaList[index];

              return ListTile(
                title: Text(media.title),
                subtitle: Text(
                  '${media.paused ? '일시정지' : '재생 중'}'
                  ' · 볼륨 ${(media.volume * 100).round()}%',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

```

## lib/services/stream_service.dart

```dart
import 'package:flutter/services.dart';

import '../models/media_info.dart';

class MediaService {
  static const _channel = EventChannel('hankyeon/media_practice');

  late final Stream<List<MediaInfo>> mediaStream = _channel
      .receiveBroadcastStream()
      .map((event) {
        final list = event as List;

        return list.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return MediaInfo.fromMap(map);
        }).toList();
      });
}

```
