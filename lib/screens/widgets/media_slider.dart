import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OverlayPortal을 사용하지 않는 미디어 슬라이더입니다.
/// Flutter 3.47의 데스크톱 Slider 접근성 트리 오류를 피하면서 키보드·스크린리더를 지원합니다.
class MediaSlider extends StatefulWidget {
  final double height;
  final double value;
  final double min;
  final double max;
  final double step;
  final String label;
  final String valueText;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const MediaSlider({
    super.key,
    this.height = 44,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.valueText,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<MediaSlider> createState() => _MediaSliderState();
}

class _MediaSliderState extends State<MediaSlider> {
  final _focusNode = FocusNode();
  double? _draft;
  bool _focused = false;
  bool _hovered = false;
  bool get enabled => widget.onChanged != null && widget.max > widget.min;
  double get current =>
      (_draft ?? widget.value).clamp(widget.min, widget.max).toDouble();

  void change(double value) {
    if (!enabled) return;
    _draft = value.clamp(widget.min, widget.max).toDouble();
    widget.onChanged!(_draft!);
  }

  void commit() {
    if (_draft == null) return;
    final value = _draft!;
    _draft = null;
    widget.onChangeEnd?.call(value);
  }

  void accessibilityStep(double direction) {
    change(current + direction * widget.step);
    commit();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fraction = widget.max > widget.min
        ? (current - widget.min) / (widget.max - widget.min)
        : 0.0;
    return Semantics(
      container: true,
      excludeSemantics: true,
      slider: true,
      label: widget.label,
      value: widget.valueText,
      enabled: enabled,
      focusable: enabled,
      focused: _focused,
      increasedValue: enabled
          ? '${(current + widget.step).clamp(widget.min, widget.max)}'
          : null,
      decreasedValue: enabled
          ? '${(current - widget.step).clamp(widget.min, widget.max)}'
          : null,
      onIncrease: enabled ? () => accessibilityStep(1) : null,
      onDecrease: enabled ? () => accessibilityStep(-1) : null,
      onTap: enabled ? _focusNode.requestFocus : null,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: enabled,
        includeSemantics: false,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (!enabled) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
            if (event is KeyDownEvent) {
              change(key == LogicalKeyboardKey.home ? widget.min : widget.max);
              commit();
            }
            return KeyEventResult.handled;
          }
          final direction =
              key == LogicalKeyboardKey.arrowRight ||
                  key == LogicalKeyboardKey.arrowUp
              ? 1
              : key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowDown
              ? -1
              : 0;
          if (direction == 0) return KeyEventResult.ignored;
          if (event is KeyUpEvent) {
            commit();
          } else {
            change(current + direction * widget.step);
          }
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                void move(double dx) {
                  _focusNode.requestFocus();
                  change(
                    widget.min +
                        dx / constraints.maxWidth * (widget.max - widget.min),
                  );
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapDown: enabled
                      ? (event) => move(event.localPosition.dx)
                      : null,
                  onTapUp: enabled ? (_) => commit() : null,
                  onHorizontalDragStart: enabled
                      ? (event) => move(event.localPosition.dx)
                      : null,
                  onHorizontalDragUpdate: enabled
                      ? (event) => move(event.localPosition.dx)
                      : null,
                  onHorizontalDragEnd: enabled ? (_) => commit() : null,
                  onHorizontalDragCancel: enabled ? commit : null,
                  child: SizedBox(
                    height: widget.height,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _GlassBarPainter(
                          fraction: fraction,
                          color: enabled ? colors.primary : colors.outline,
                          track: colors.onSurface.withValues(alpha: .12),
                          active: _hovered || _focused,
                        ),
                        size: Size(constraints.maxWidth, widget.height),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A small optical highlight and a white capsule grip keep the artwork dominant.
class _GlassBarPainter extends CustomPainter {
  final double fraction;
  final Color color, track;
  final bool active;
  const _GlassBarPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.active,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, (size.height - 7) / 2, size.width, 7);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(shape, Paint()..color = track);
    if (fraction > 0) {
      final fill = Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width * fraction,
        rect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(8)),
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: .65), color],
          ).createShader(rect),
      );
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = Colors.white.withValues(alpha: .10),
    );
    final x = (size.width * fraction).clamp(3.0, size.width - 3);
    final grip = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: active ? 5 : 3,
      height: active ? 16 : 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(grip, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: active ? 1 : .88),
    );
  }

  @override
  bool shouldRepaint(_GlassBarPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.active != active;
}
