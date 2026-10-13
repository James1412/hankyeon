import 'media_info.dart';

enum MediaConnection { waiting, ready, unavailable, error }

/// 목록과 연결 상태를 함께 전달합니다. 연결이 끊기면 마지막 목록은 읽기 전용으로 남깁니다.
class MediaSnapshot {
  final List<MediaInfo> mediaList;
  final List<String> errors;
  final MediaConnection connection;
  final String message;
  final DateTime? updatedAt;

  const MediaSnapshot({
    this.mediaList = const [],
    this.errors = const [],
    this.connection = MediaConnection.waiting,
    this.message = 'Safari 연결을 기다리고 있습니다.',
    this.updatedAt,
  });

  bool get canControl => connection == MediaConnection.ready;

  factory MediaSnapshot.fromMap(Map<String, dynamic> map) {
    final list = map['mediaList'];
    if (list is! List || list.length > 2000) {
      throw const FormatException('미디어 목록의 형식이 올바르지 않습니다.');
    }
    final media = <MediaInfo>[];
    final seen = <String>{};
    var invalid = 0;
    for (final value in list) {
      try {
        if (value is! Map) throw const FormatException();
        final item = MediaInfo.fromMap(Map<String, dynamic>.from(value));
        if (seen.add(item.identity)) media.add(item);
      } on FormatException {
        invalid++;
      }
    }
    final errors = map['errors'] is List
        ? (map['errors'] as List).whereType<String>().take(100).toList()
        : <String>[];
    if (invalid > 0) errors.add('형식이 올바르지 않은 미디어 $invalid개를 제외했습니다.');
    return MediaSnapshot(
      mediaList: List.unmodifiable(media),
      errors: List.unmodifiable(errors),
      connection: switch (map['status']) {
        'ready' => MediaConnection.ready,
        'unavailable' => MediaConnection.unavailable,
        'error' => MediaConnection.error,
        _ => MediaConnection.waiting,
      },
      message: map['message'] is String
          ? map['message'] as String
          : 'Safari 연결을 기다리고 있습니다.',
      updatedAt: map['updatedAt'] is String
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }
}
