import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_snapshot.dart';

import 'media_test_support.dart';

void main() {
  test('missing metadata and non-finite values have safe defaults', () {
    final media = MediaInfo.fromMap({
      ...mediaMap(),
      'title': null,
      'volume': double.nan,
      'duration': double.infinity,
      'thumbnailUrl': 'javascript:alert(1)',
    });
    expect(media.title, '제목 없는 미디어');
    expect(media.volume, 1);
    expect(media.duration, isNull);
    expect(media.thumbnailUrl, isNull);
  });
  test('bad target identities cannot reach controls', () {
    expect(
      () => MediaInfo.fromMap({...mediaMap(), 'tabId': 1.5}),
      throwsFormatException,
    );
    expect(
      () => MediaInfo.fromMap({...mediaMap(), 'frameId': -1}),
      throwsFormatException,
    );
    expect(
      () => MediaInfo.fromMap({...mediaMap(), 'mediaUrl': 'file:///tmp/x'}),
      throwsFormatException,
    );
  });
  test(
    'snapshot deduplicates only identical targets and excludes invalid entries',
    () {
      final snapshot = MediaSnapshot.fromMap({
        'status': 'ready',
        'mediaList': [
          mediaMap(),
          mediaMap(),
          mediaMap(id: 'b'),
          {'title': 'invalid'},
        ],
      });
      expect(snapshot.mediaList.length, 2);
      expect(snapshot.errors.single, contains('1개'));
      expect(snapshot.canControl, isTrue);
    },
  );
  test('seek chooses a valid range instead of the gap between ranges', () {
    final media = MediaInfo.fromMap({
      ...mediaMap(),
      'seekable': [
        {'start': 0, 'end': 40},
        {'start': 60, 'end': 100},
      ],
    });
    expect(media.seekPosition(55), 60);
    expect(media.seekPosition(-1), 0);
    expect(media.seekPosition(101), 100);
  });
}
