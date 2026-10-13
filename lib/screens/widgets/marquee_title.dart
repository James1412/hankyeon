import 'package:flutter/material.dart';

/// Keeps the full accessible title stable while only the painted text moves.
class MarqueeTitle extends StatefulWidget {
  final String title;
  const MarqueeTitle({super.key, required this.title});
  @override
  State<MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<MarqueeTitle>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this);
  double _distance = 0;
  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        final distance = width > constraints.maxWidth ? width + 32 : 0.0;
        if (distance != _distance || reduced) {
          _distance = distance;
          _motion.stop();
          _motion.value = 0;
          if (distance > 0 && !reduced) {
            _motion.duration = Duration(
              milliseconds: (distance / 28 * 1000 + 2400).round(),
            );
            _motion.repeat();
          }
        }
        if (distance == 0 || reduced) {
          return Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        return Semantics(
          label: widget.title,
          excludeSemantics: true,
          child: RepaintBoundary(
            child: ClipRect(
              child: SizedBox(
                height: 20,
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, child) {
                    final pause = 1200 / _motion.duration!.inMilliseconds;
                    final progress = ((_motion.value - pause) / (1 - 2 * pause))
                        .clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(-distance * progress, 0),
                      child: child,
                    );
                  },
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, style: style),
                        const SizedBox(width: 32),
                        Text(widget.title, style: style),
                      ],
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
}
