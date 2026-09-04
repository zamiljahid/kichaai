import 'package:flutter/material.dart';

/// The app mark on a circular plate.
///
/// Exists because `assets/images/logo.png` is a *squircle* — a rounded square
/// with transparent corners. Dropping it into a `ClipOval` clipped the circle
/// through those transparent corners, so the mark never reached the rim and the
/// ring around it showed four gaps at the diagonals. Every call site had its own
/// slightly different `ClipOval` + `Padding` combination, each wrong in its own
/// way; this centralises the correct one.
///
/// [kCircularLogoAsset] is a genuinely round render of the same mark, so it
/// fills the plate edge to edge with `BoxFit.cover` and no inner padding. Inner
/// padding is what caused the gap: it shrinks the image but not the clip.
const String kCircularLogoAsset = 'assets/images/logo_round.png';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    required this.size,
    this.borderWidth = 3,
    this.borderColor,
    this.glow = true,
  });

  /// Outside diameter, border included.
  final double size;

  /// 0 removes the ring entirely.
  final double borderWidth;

  /// Defaults to a translucent primary.
  final Color? borderColor;

  /// The soft primary-tinted drop shadow. Off for marks sitting on a busy or
  /// already-tinted surface.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ring = borderColor ?? colors.primary.withValues(alpha: 0.7);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surface,
        border: borderWidth > 0
            ? Border.all(color: ring, width: borderWidth)
            : null,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.30),
                  blurRadius: size * 0.22,
                  spreadRadius: 1,
                  offset: Offset(0, size * 0.07),
                ),
              ]
            : null,
      ),
      // No padding inside the clip — the asset is already circular, and any
      // inset here reintroduces the very gap this widget exists to remove.
      child: ClipOval(
        child: Image.asset(
          kCircularLogoAsset,
          fit: BoxFit.cover,
          width: size,
          height: size,
        ),
      ),
    );
  }
}
