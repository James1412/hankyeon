import 'package:flutter/material.dart';

import '../controllers/media_controller.dart';
import '../models/media_snapshot.dart';
import '../repositories/media_repository.dart';
import 'widgets/media_card.dart';

class MediaScreen extends StatefulWidget {
  final MediaRepository repository;
  const MediaScreen({super.key, required this.repository});
  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  late final MediaController _controller = MediaController(widget.repository);
  @override
  void initState() {
    super.initState();
    _controller.start();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final snapshot = _controller.snapshot;
      final items = snapshot.mediaList;
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF101412)
            : null,
        appBar: AppBar(
          title: const Text('hankyeon'),
          actions: [
            IconButton(
              tooltip: 'Safari 확장 설정',
              onPressed: _controller.openSettings,
              icon: const Icon(Icons.extension_outlined),
            ),
            IconButton(
              tooltip: '목록 새로고침',
              onPressed: _controller.refreshing ? null : _controller.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        snapshot.canControl
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: snapshot.canControl ? Colors.green : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(snapshot.message)),
                      Text('${items.length}개'),
                    ],
                  ),
                ),
                if (_controller.commandError case final String error)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '오류 닫기',
                          onPressed: _controller.dismissError,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                if (snapshot.updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '마지막 수신 ${TimeOfDay.fromDateTime(snapshot.updatedAt!.toLocal()).format(context)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (snapshot.errors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ExpansionTile(
                      title: Text(
                        '일부 페이지를 읽지 못했습니다 (${snapshot.errors.length})',
                      ),
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Text(snapshot.errors.join('\n')),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: snapshot.connection == MediaConnection.waiting
                              ? const CircularProgressIndicator()
                              : const Text(
                                  '감지된 미디어가 없습니다.\nSafari에서 영상을 열고 사이트 접근 권한을 확인해주세요.',
                                  textAlign: TextAlign.center,
                                ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: items.length,
                          findChildIndexCallback: (key) {
                            final index = items.indexWhere(
                              (media) => ValueKey(media.identity) == key,
                            );
                            return index < 0 ? null : index;
                          },
                          itemBuilder: (context, index) {
                            final media = items[index];
                            return MediaCard(
                              key: ValueKey(media.identity),
                              media: media,
                              enabled: snapshot.canControl,
                              busy: _controller.isBusy(media),
                              onCommand: _controller.control,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
