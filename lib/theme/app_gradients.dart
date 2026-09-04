import 'package:flutter/material.dart';

/// Gradients derived from the active [ColorScheme].
///
/// These replace the old `AppColors.*Gradient` static getters, which baked in
/// the pine/marigold palette and so could not follow the role-driven theme
/// switch. Names map 1:1 onto the originals to keep diffs readable:
///   blueGradient    → [AppGradients.primary]
///   fuchsiaGradient → [AppGradients.accent]
///   bgGradient      → [AppGradients.background]
///   cardGradient    → [AppGradients.card]
class AppGradients {
  const AppGradients._();

  /// Filled primary surfaces: mode pills, active nav items, CTA buttons.
  ///
  /// Runs primary → onPrimaryContainer rather than primary → primaryContainer:
  /// everything painted with this carries `onPrimary` (white) text, and the
  /// container tone is a light tint that white cannot sit on. Both ends of this
  /// ramp clear 4.5:1 against white.
  static LinearGradient primary(ColorScheme colors) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.primary, colors.onPrimaryContainer],
      );

  /// Secondary accent, used sparingly (badges, highlight chips).
  static LinearGradient accent(ColorScheme colors) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.secondary, colors.onSecondaryContainer],
      );

  /// The app canvas behind `AnimatedBackground`.
  static LinearGradient background(ColorScheme colors) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.surfaceContainerLowest,
          colors.surfaceContainerLow,
          colors.surfaceContainerLowest,
        ],
        stops: const [0.0, 0.5, 1.0],
      );

  /// Card fill — a near-flat wash so cards read as solid, not glassy.
  static LinearGradient card(ColorScheme colors) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.surface, colors.surfaceContainerLow],
      );
}
