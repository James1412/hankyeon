import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/media_controller.dart';
import '../repositories/media_repository.dart';
import '../repositories/browser_media_repository.dart';
import '../repositories/native_audio_repository.dart';
import 'media_screen.dart';
import 'widgets/media_card.dart';
import 'widgets/notch_handle.dart';

/// 창의 물리 위치는 Swift에 맡기고, 펼침과 미디어 목록은 Flutter에서 관리합니다.
class NotchScreen extends StatefulWidget {
  final MediaRepository repository;
  final BrowserMediaRepository browsers;
  const NotchScreen({
    super.key,
    required this.repository,
    required this.browsers,
  });
  @override
  State<NotchScreen> createState() => _NotchScreenState();
}

class _NotchScreenState extends State<NotchScreen>
    with SingleTickerProviderStateMixin {
  static const _window = MethodChannel('hankyeon/window');
  late final _controller = MediaController(widget.repository);
  Timer? _collapse;
  bool _authorizing = false;
  String? _audioMessage;
  String? _previewArtwork;
  final _mediaScroll = ScrollController();
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 280),
  );
  bool _hovered = false,
      _inside = false,
      _dragging = false,
      _reduceMotion = false;
  double _dragDistance = 0;

  bool _nativeHover = false;
  bool _expanded = false, _pinned = false, _normal = false, _settings = false;
  double _top = 32, _hole = 160, _expandedHeight = 460;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_warmArtwork);
    _controller.start();
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
    _window.setMethodCallHandler((call) async {
      if (call.method == 'layoutChanged') _layout(call.arguments);
      if (call.method == 'settings') {
        _collapse?.cancel();
        setState(() {
          _settings = true;
          _pinned = true;
        });
        _expand(true, notifyNative: false);
      }
      if (call.method == 'hoverChanged') _hover(call.arguments == true);
      if (call.method == 'gesture') {
        if (call.arguments != true) _pinned = false;
        _expand(call.arguments == true, notifyNative: false);
      }
    });
    _window.invokeMethod('layout').then(_layout);
  }

  void _warmArtwork() {
    final list = _controller.snapshot.mediaList;
    final media =
        list.where((item) => !item.paused).firstOrNull ?? list.firstOrNull;
    final url = media?.thumbnailUrl;
    if (_previewArtwork == url) return;
    _previewArtwork = url;
    if (url == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        ResizeImage(NetworkImage(url), width: 96, height: 96),
        context,
        onError: (error, stack) {},
      );
    });
  }

  void _layout(dynamic value) {
    if (!mounted || value is! Map) return;
    setState(() {
      _top = (value['topInset'] as num).toDouble();
      _hole = (value['holeWidth'] as num).toDouble();
      _expandedHeight = (value['expandedHeight'] as num?)?.toDouble() ?? 460;
      _normal = value['normal'] == true;
      _nativeHover = value['nativeHover'] == true;
      _reduceMotion = value['reduceMotion'] == true;
    });
    _expand(value['expanded'] == true, notifyNative: false);
    if (_reduceMotion) {
      _reveal.stop();
      _reveal.value = _expanded ? 1 : 0;
    }
  }

  void _expand(bool value, {bool notifyNative = true}) {
    _collapse?.cancel();
    if (!mounted || _normal || _expanded == value) return;
    setState(() => _expanded = value);
    if (_reduceMotion) {
      _reveal.value = value ? 1 : 0;
    } else if (value) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
    if (notifyNative) _window.invokeMethod('expand', value);
  }

  void _hover(bool value) {
    _collapse?.cancel();
    _inside = value;
    if (_hovered != value) {
      setState(() => _hovered = value);
      _window.invokeMethod('hover', value);
    }
    if (!value) _scheduleCollapse();
  }

  void _scheduleCollapse() {
    if (!_inside && !_dragging && !_pinned && !_settings) {
      _collapse?.cancel();
      _collapse = Timer(
        const Duration(milliseconds: 650),
        () => _expand(false),
      );
    }
  }

  void _dragUpdate(double delta) {
    _dragDistance += delta;
    if (!_expanded && _dragDistance > 24) {
      _expand(true);
      _dragDistance = 0;
    } else if (_expanded && _dragDistance < -24 && !_settings) {
      _pinned = false;
      _expand(false);
      _dragDistance = 0;
    }
  }

  @override
  void dispose() {
    _collapse?.cancel();
    _reveal.dispose();
    _mediaScroll.dispose();
    _controller.dispose();
    _window.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_normal) return MediaScreen(repository: widget.repository);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final list = _controller.snapshot.mediaList;
        final playing =
            list.where((item) => !item.paused).firstOrNull ?? list.firstOrNull;
        return Align(
          alignment: Alignment.topCenter,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _reduceMotion ? 0 : 280),
            curve: Curves.easeOutCubic,
            width: _expanded ? 420 : _hole + (_hovered ? 100 : 0),
            height: _expanded ? _expandedHeight : _top,
            child: LayoutBuilder(
              builder: (context, constraints) => Listener(
                onPointerDown: (_) {
                  _dragging = true;
                  _collapse?.cancel();
                },
                onPointerUp: (_) {
                  _dragging = false;
                  _scheduleCollapse();
                },
                onPointerCancel: (_) {
                  _dragging = false;
                  _scheduleCollapse();
                },
                child: MouseRegion(
                  onEnter: (_) {
                    if (!_nativeHover) _hover(true);
                  },
                  onExit: (_) {
                    if (!_nativeHover) _hover(false);
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(26),
                      ),
                      child: ColoredBox(
                        color: _expanded || _reveal.value > 0
                            ? const Color(0x18121814)
                            : _hovered
                            ? Colors.black
                            : Colors.transparent,
                        child: Stack(
                          children: [
                            NotchHandle(
                              key: const ValueKey('notch-handle'),
                              topInset: _top,
                              holeWidth: _hole,
                              media: playing,
                              hovered: _hovered,
                              expanded: _expanded,
                              reduceMotion: _reduceMotion,
                              onActivate: () => _expand(!_expanded),
                              onOpen: () => _expand(true),
                              onClose: () {
                                _pinned = false;
                                _expand(false);
                              },
                              onGestureStart: () {
                                _dragging = true;
                                _dragDistance = 0;
                                _collapse?.cancel();
                              },
                              onGestureEnd: () {
                                _dragging = false;
                                _dragDistance = 0;
                                _scheduleCollapse();
                              },
                              onPull: _dragUpdate,
                            ),
                            if (_expanded || _reveal.value > 0)
                              Positioned(
                                top: _top,
                                left: 0,
                                right: 0,
                                height: _expandedHeight - _top,
                                child: OverflowBox(
                                  alignment: Alignment.topCenter,
                                  minWidth: 420,
                                  maxWidth: 420,
                                  minHeight: _expandedHeight - _top,
                                  maxHeight: _expandedHeight - _top,
                                  child: FadeTransition(
                                    opacity: _reveal,
                                    child: AnimatedSwitcher(
                                      duration: Duration(
                                        milliseconds: _reduceMotion ? 0 : 180,
                                      ),
                                      child: _settings
                                          ? _connectionSettings()
                                          : Column(
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        20,
                                                        8,
                                                        12,
                                                        8,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      const Text(
                                                        'hankyeon',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 17,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${list.length}',
                                                        style: const TextStyle(
                                                          color: Colors.white54,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      IconButton(
                                                        tooltip: '브라우저 연결',
                                                        onPressed: () =>
                                                            setState(() {
                                                              _collapse
                                                                  ?.cancel();
                                                              _settings = true;
                                                            }),
                                                        icon: const Icon(
                                                          Icons
                                                              .extension_outlined,
                                                          size: 18,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: _pinned
                                                            ? '고정 해제'
                                                            : '펼침 고정',
                                                        onPressed: () => setState(() {
                                                          _collapse?.cancel();
                                                          _pinned = !_pinned;
                                                          if (!_pinned) {
                                                            _scheduleCollapse();
                                                          }
                                                        }),
                                                        icon: Icon(
                                                          _pinned
                                                              ? Icons.push_pin
                                                              : Icons
                                                                    .push_pin_outlined,
                                                          size: 18,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (_controller.commandError !=
                                                    null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 20,
                                                        ),
                                                    child: Text(
                                                      _controller.commandError!,
                                                      maxLines: 2,
                                                      style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: list.isEmpty
                                                      ? Center(
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .headphones,
                                                                size: 36,
                                                                color: Colors
                                                                    .white38,
                                                              ),
                                                              const SizedBox(
                                                                height: 12,
                                                              ),
                                                              const Text(
                                                                '미디어를 재생해 보세요',
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Text(
                                                                _controller
                                                                    .snapshot
                                                                    .message,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .white54,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        )
                                                      : ListView.builder(
                                                          key: const PageStorageKey(
                                                            'notch-media-list',
                                                          ),
                                                          controller:
                                                              _mediaScroll,
                                                          padding:
                                                              const EdgeInsets.fromLTRB(
                                                                16,
                                                                0,
                                                                16,
                                                                8,
                                                              ),
                                                          itemCount:
                                                              list.length,
                                                          findChildIndexCallback: (key) =>
                                                              key
                                                                  is ValueKey<
                                                                    String
                                                                  >
                                                              ? list
                                                                    .indexWhere(
                                                                      (item) =>
                                                                          item.identity ==
                                                                          key.value,
                                                                    )
                                                                    .letIndex
                                                              : null,
                                                          itemBuilder: (context, index) {
                                                            final media =
                                                                list[index];
                                                            return MediaCard(
                                                              key: ValueKey(
                                                                media.identity,
                                                              ),
                                                              media: media,
                                                              enabled: _controller
                                                                  .snapshot
                                                                  .canControl,
                                                              busy: _controller
                                                                  .isBusy(
                                                                    media,
                                                                  ),
                                                              onCommand:
                                                                  _controller
                                                                      .control,
                                                            );
                                                          },
                                                        ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 10,
                                                      ),
                                                  child: Text(
                                                    _controller
                                                            .snapshot
                                                            .canControl
                                                        ? '미디어 & 앱 오디오'
                                                        : '연결을 확인해주세요',
                                                    style: const TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkAudioAccess() async {
    setState(() {
      _authorizing = true;
      _audioMessage = null;
    });
    try {
      final allowed = await NativeAudioRepository().authorize();
      await _controller.refresh();
      if (mounted) {
        setState(
          () => _audioMessage = allowed
              ? '앱 오디오가 연결됐어요. 소리가 나는 앱의 볼륨을 조절할 수 있어요.'
              : '시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 Hankyeon을 허용한 뒤 다시 확인해주세요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _audioMessage = '오디오 연결을 확인하지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  Widget _connectionSettings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _settings = false),
            icon: const Icon(Icons.arrow_back),
          ),
          const Text(
            '연결 설정',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FilledButton.tonal(
        onPressed: _controller.openSettings,
        child: const Text('Safari 확장 설정'),
      ),
      const SizedBox(height: 16),
      const Text('앱별 볼륨', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text(
        '시스템 오디오 접근을 허용하면 Apple Music, Discord 등 소리가 나는 앱의 볼륨을 따로 조절할 수 있어요.',
        style: TextStyle(color: Colors.white60, height: 1.5),
      ),
      FilledButton.tonalIcon(
        onPressed: _authorizing ? null : _checkAudioAccess,
        icon: const Icon(Icons.volume_up_rounded, size: 16),
        label: Text(_authorizing ? '권한 확인 중…' : '앱 오디오 접근 확인'),
      ),
      if (_audioMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _audioMessage!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      const SizedBox(height: 20),
      const Text(
        'Chrome · Edge · Brave · Firefox',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '개발용 확장을 설치한 뒤, 확장 옵션에 아래 주소와 연결 코드를 입력하세요. 첫 연결 뒤에는 자동으로 다시 연결됩니다.',
        style: TextStyle(color: Colors.white60, height: 1.6),
      ),
      const SizedBox(height: 12),
      SelectableText(widget.browsers.endpoint),
      TextButton.icon(
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: widget.browsers.endpoint)),
        icon: const Icon(Icons.copy, size: 16),
        label: const Text('주소 복사'),
      ),
      TextButton.icon(
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: widget.browsers.token)),
        icon: const Icon(Icons.key, size: 16),
        label: const Text('연결 코드 복사'),
      ),
      if (widget.browsers.startupError != null)
        Text(widget.browsers.startupError!),
      const SizedBox(height: 12),
      TextButton(onPressed: _controller.refresh, child: const Text('연결 다시 확인')),
      TextButton(
        onPressed: () => _window.invokeMethod('normal', true),
        child: const Text('일반 창으로 보기'),
      ),
    ],
  );
}

extension on int {
  int? get letIndex => this < 0 ? null : this;
}
