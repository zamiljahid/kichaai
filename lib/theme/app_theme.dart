import 'package:flutter/material.dart';

import 'theme_provider.dart';

export 'theme_provider.dart' show kBengaliFont;

/// TRANSITIONAL SHIM — being deleted.
///
/// The app's colors now come from the seeded [ColorScheme] built in
/// [ThemeProvider.themeDataFor], read at each call site as
/// `Theme.of(context).colorScheme`. That is what lets the whole app re-colour
/// when the active role flips the seed (purple ⇄ blue); static constants
/// cannot, because their values are fixed at compile time.
///
/// The constants below are the *purple* scheme's real values, so screens that
/// have not been converted yet still render in the new palette instead of the
/// retired pine/marigold one. They do not follow the role switch. Each screen
/// loses its `AppColors` references as it is converted, and this class is
/// removed once the last one is gone.
///
/// Mapping used by the conversion — apply it consistently:
///
/// | AppColors        | ColorScheme role                |
/// |------------------|---------------------------------|
/// | deepBlue         | primary                         |
/// | ivory            | onPrimary                       |
/// | bgMid            | surface                         |
/// | glassWhite       | surface                         |
/// | bgDark           | surfaceContainerHighest         |
/// | glassBorder      | outlineVariant                  |
/// | textPrimary      | onSurface                       |
/// | textSecondary    | onSurfaceVariant                |
/// | textMuted        | outline                         |
/// | fuchsia          | secondary                       |
/// | softRed          | error                           |
/// | glassBlue        | primary @ 8%                    |
/// | glassBorderBlue  | primary @ 20%                   |
/// | blueGradient     | AppGradients.primary(colors)    |
/// | fuchsiaGradient  | AppGradients.accent(colors)     |
/// | bgGradient       | AppGradients.background(colors) |
/// | cardGradient     | AppGradients.card(colors)       |
///
/// `softAmber` and `softBlue` stay literal: they encode status semantics
/// (pending / informational), not brand colour, and must not shift with the
/// theme or two different statuses would render identically.
@Deprecated('Read Theme.of(context).colorScheme instead. See the table above.')
class AppColors {
  static const Color black = Color(0xFF000000);

  static const Color deepBlue = Color(0xFF65558F); // → colorScheme.primary
  static const Color fuchsia = Color(0xFF625B71); // → colorScheme.secondary
  static const Color ivory = Color(0xFFFFFFFF); // → colorScheme.onPrimary

  static const Color bgDark = Color(0xFFE6E0E9); // → surfaceContainerHighest
  static const Color bgMid = Color(0xFFFDF7FF); // → colorScheme.surface
  static const Color glassWhite = Color(0xFFFDF7FF); // → colorScheme.surface
  static const Color glassBorder = Color(0xFFCAC4CF); // → outlineVariant
  static const Color glassBlue = Color(0x1465558F); // → primary @ 8%
  static const Color glassBorderBlue = Color(0x3365558F); // → primary @ 20%

  static const Color textPrimary = Color(0xFF1D1B20); // → onSurface
  static const Color textSecondary = Color(0xFF49454E); // → onSurfaceVariant
  static const Color textMuted = Color(0xFF7A757F); // → outline

  // Status tokens. These are NOT theme colours — they stay fixed so "pending"
  // and "failed" never collapse into the same hue when the seed changes.
  static const Color softAmber = Color(0xFFB27107);
  static const Color softRed = Color(0xFFBA1A1A); // → colorScheme.error
  static const Color softBlue = Color(0xFF2563EB);

  static LinearGradient get bgGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF8F2FA), Color(0xFFFFFFFF)],
        stops: [0.0, 0.5, 1.0],
      );

  static LinearGradient get blueGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF65558F), Color(0xFF4D3D75)],
      );

  static LinearGradient get fuchsiaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF625B71), Color(0xFF4A4458)],
      );

  static LinearGradient get cardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFDF7FF), Color(0xFFF8F2FA)],
      );
}

/// Kept so `MaterialApp` and any remaining callers keep compiling while the
/// screens are converted. The real theme is [ThemeProvider.themeDataFor].
class AppTheme {
  @Deprecated('Use ThemeProvider.themeDataFor(role-derived AppThemeColor).')
  static ThemeData get darkTheme =>
      ThemeProvider.themeDataFor(AppThemeColor.purple);
}
