import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/media_info.dart';

/// 노치 상단의 미리보기와 제스처 영역입니다. 목록의 스크롤과 분리합니다.
class NotchHandle extends StatelessWidget {
  final double topInset, holeWidth;
  final MediaInfo? media;
  final bool hovered, expanded, reduceMotion;
  final VoidCallback onActivate, onOpen, onClose, onGestureStart, onGestureEnd;
  final ValueChanged<double> onPull;
  const NotchHandle({
    super.key,
    required this.topInset,
    required this.holeWidth,
    required this.media,
    required this.hovered,
    required this.expanded,
    required this.reduceMotion,
    required this.onActivate,
    required this.onOpen,
    required this.onClose,
    required this.onGestureStart,
    required this.onGestureEnd,
    required this.onPull,
  });

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent &&
          event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()) {
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (signal) => onPull((signal as PointerScrollEvent).scrollDelta.dy),
        );
      }
    },
    onPointerPanZoomStart: (_) => onGestureStart(),
    onPointerPanZoomUpdate: (event) => onPull(event.panDelta.dy),
    onPointerPanZoomEnd: (_) => onGestureEnd(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onGestureStart(),
      onVerticalDragUpdate: (event) => onPull(event.delta.dy),
      onVerticalDragEnd: (_) => onGestureEnd(),
      onVerticalDragCancel: onGestureEnd,
      child: Focus(
        onKeyEvent: (_, event) {
          final key = event.logicalKey;
          final action = key == LogicalKeyboardKey.arrowDown
              ? onOpen
              : key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.escape
              ? onClose
              : key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.space
              ? onActivate
              : null;
          if (action == null) return KeyEventResult.ignored;
          if (event is KeyDownEvent) action();
          return KeyEventResult.handled;
        },
        child: Semantics(
          button: true,
          label: expanded ? '노치 접기' : '노치 펼치기',
          onTap: onActivate,
          excludeSemantics: true,
          child: SizedBox(
            height: topInset,
            child: ClipRect(
              child: OverflowBox(
                minWidth: holeWidth + 92,
                maxWidth: holeWidth + 92,
                alignment: Alignment.topCenter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hovered || expanded) ...[
                      AnimatedScale(
                        scale: hovered ? 1.08 : 1,
                        curve: Curves.easeOutCubic,
                        duration: Duration(
                          milliseconds: reduceMotion ? 0 : 180,
                        ),
                        child: SizedBox(
                          width: 46,
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: AnimatedSwitcher(
                                duration: Duration(
                                  milliseconds: reduceMotion ? 0 : 240,
                                ),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: SizedBox(
                                  key: ValueKey(
                                    '${media?.identity}/${media?.thumbnailUrl}',
                                  ),
                                  width: 26,
                                  height: 26,
                                  child: media?.thumbnailUrl == null
                                      ? const Icon(Icons.graphic_eq, size: 19)
                                      : Image.network(
                                          media!.thumbnailUrl!,
                                          fit: BoxFit.cover,
                                          cacheWidth: 96,
                                          cacheHeight: 96,
                                          errorBuilder: (_, e, s) => const Icon(
                                            Icons.music_note,
                                            size: 19,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: holeWidth),
                      SizedBox(
                        width: 46,
                        child: AnimatedSwitcher(
                          duration: Duration(
                            milliseconds: reduceMotion ? 0 : 180,
                          ),
                          child: Icon(
                            media == null || media!.paused
                                ? Icons.music_note_rounded
                                : Icons.equalizer_rounded,
                            key: ValueKey(media?.paused),
                            size: 19,
                            color: const Color(0xFF88C59C),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
