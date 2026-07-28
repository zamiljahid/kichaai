import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(gradient: AppColors.bgGradient),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([_controller1, _controller2, _controller3]),
          builder: (context, _) {
            return CustomPaint(
              painter: _BlobPainter(
                t1: _controller1.value,
                t2: _controller2.value,
                t3: _controller3.value,
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

  _BlobPainter({required this.t1, required this.t2, required this.t3});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Pine wash top-right — subtle on the light canvas
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.deepBlue.withOpacity(0.08),
          AppColors.deepBlue.withOpacity(0.0),
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

    // Marigold wash bottom-left — subtle warmth
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.fuchsia.withOpacity(0.09),
          AppColors.fuchsia.withOpacity(0.0),
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

    // Pine wash centre — barely there
    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.deepBlue.withOpacity(0.05),
          AppColors.deepBlue.withOpacity(0.0),
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
  bool shouldRepaint(_BlobPainter old) => true;
}
