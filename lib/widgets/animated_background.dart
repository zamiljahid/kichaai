import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_gradients.dart';

class AnimatedBackground extends StatefulWidget {
  final Widget child;
  const AnimatedBackground({super.key, required this.child});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;

  @override
  void initState() {
    super.initState();
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(gradient: AppGradients.background(colors)),
        ),
        AnimatedBuilder(
          animation:
              Listenable.merge([_controller1, _controller2, _controller3]),
          builder: (context, _) {
            return CustomPaint(
              painter: _BlobPainter(
                t1: _controller1.value,
                t2: _controller2.value,
                t3: _controller3.value,
                primary: colors.primary,
                accent: colors.secondary,
              ),
              size: MediaQuery.of(context).size,
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t1, t2, t3;

  /// A painter has no BuildContext, so the two themed colours are passed in.
  /// They change with the active role, which is why shouldRepaint compares them.
  final Color primary;
  final Color accent;

  _BlobPainter({
    required this.t1,
    required this.t2,
    required this.t3,
    required this.primary,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Primary wash top-right — subtle on the light canvas
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.08),
          primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(
          w * (0.7 + 0.15 * math.sin(t1 * math.pi * 2)),
          h * (0.1 + 0.08 * math.cos(t1 * math.pi * 2)),
        ),
        radius: w * 0.5,
      ));
    canvas.drawCircle(
      Offset(
        w * (0.7 + 0.15 * math.sin(t1 * math.pi * 2)),
        h * (0.1 + 0.08 * math.cos(t1 * math.pi * 2)),
      ),
      w * 0.5,
      paint1,
    );

    // Accent wash bottom-left
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.09),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(
          w * (0.15 + 0.1 * math.cos(t2 * math.pi * 2)),
          h * (0.75 + 0.1 * math.sin(t2 * math.pi * 2)),
        ),
        radius: w * 0.45,
      ));
    canvas.drawCircle(
      Offset(
        w * (0.15 + 0.1 * math.cos(t2 * math.pi * 2)),
        h * (0.75 + 0.1 * math.sin(t2 * math.pi * 2)),
      ),
      w * 0.45,
      paint2,
    );

    // Primary wash centre — barely there
    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.05),
          primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(
          w * (0.5 + 0.05 * math.sin(t3 * math.pi * 2)),
          h * (0.45 + 0.05 * math.cos(t3 * math.pi * 2)),
        ),
        radius: w * 0.6,
      ));
    canvas.drawCircle(
      Offset(
        w * (0.5 + 0.05 * math.sin(t3 * math.pi * 2)),
        h * (0.45 + 0.05 * math.cos(t3 * math.pi * 2)),
      ),
      w * 0.6,
      paint3,
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.t1 != t1 ||
      old.t2 != t2 ||
      old.t3 != t3 ||
      old.primary != primary ||
      old.accent != accent;
}
