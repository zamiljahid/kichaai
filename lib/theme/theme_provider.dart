import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bundled locally as assets/fonts/NotoSansBengali-Regular.ttf (see pubspec.yaml) instead of
// google_fonts' runtime CDN fetch — that fetch depends on the VIEWER's browser reaching
// fonts.googleapis.com at paint time; any network restriction there (corporate firewall, DNS
// block, offline dev) makes every Bengali glyph app-wide render as tofu ("????").
//
// The seeded ColorScheme below comes from the ki_chai design system; the type scale does NOT.
// ki_chai is English-only and defines no textTheme at all, so adopting its theme verbatim
// would drop NotoSansBengali and tofu every Bengali string in this app.
const String kBengaliFont = 'NotoSansBengali';

/// The app's two seed colors. Ported from ki_chai verbatim — same enum name,
/// same member names, same values — so future diffs between the two codebases
/// stay readable.
enum AppThemeColor {
  purple('Purple', Color(0xFF6750A4)),
  blue('Blue', Color(0xFF0B57D0));

  const AppThemeColor(this.label, this.seedColor);

  final String label;
  final Color seedColor;
}

class ThemeProvider with ChangeNotifier {
  static const _themePreferenceKey = 'appThemeCode';

  AppThemeColor _themeColor = AppThemeColor.purple;

  AppThemeColor get themeColor => _themeColor;
  int get themeCode => _themeColor == AppThemeColor.blue ? 2 : 1;
  Color get seedColor => _themeColor.seedColor;
  bool get isBlueTheme => _themeColor == AppThemeColor.blue;

  ThemeProvider({AppThemeColor initialThemeColor = AppThemeColor.purple})
      : _themeColor = initialThemeColor;

  ThemeData get themeData => themeDataFor(_themeColor);

  /// Reads the persisted selection written by [setThemeColor]. Returns the
  /// default (purple) when nothing has been stored yet.
  static Future<AppThemeColor> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    return themeColorFromCode(prefs.getInt(_themePreferenceKey));
  }

  static AppThemeColor themeColorFromCode(int? themeCode) {
    switch (themeCode) {
      case 2:
        return AppThemeColor.blue;
      case 1:
      default:
        return AppThemeColor.purple;
    }
  }

  /// Builds the [ThemeData] for a given [AppThemeColor]. Kept static so the
  /// app can derive the theme directly from the active role.
  static ThemeData themeDataFor(AppThemeColor themeColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: themeColor.seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      primaryColor: colorScheme.primary,
      primaryColorLight: colorScheme.primaryContainer,
      primaryColorDark: colorScheme.primary,
      secondaryHeaderColor: colorScheme.secondaryContainer,
      fontFamily: kBengaliFont,
      textTheme: _textThemeFor(colorScheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: kBengaliFont,
          color: colorScheme.onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        iconColor: colorScheme.primary,
        suffixIconColor: colorScheme.primary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: kBengaliFont,
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          fontFamily: kBengaliFont,
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
    );
  }

  /// This app's existing type scale, re-pointed at the seeded scheme. Sizes and
  /// weights are unchanged from the previous theme; only the hardcoded colors
  /// became [ColorScheme] roles.
  static TextTheme _textThemeFor(ColorScheme colors) {
    return Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(fontFamily: kBengaliFont)
        .copyWith(
          displayLarge: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
          headlineLarge: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
          headlineMedium: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          bodySmall: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
          labelLarge: TextStyle(
            fontFamily: kBengaliFont,
            color: colors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        );
  }

  void setThemeColor(AppThemeColor themeColor) async {
    if (_themeColor != themeColor) {
      _themeColor = themeColor;
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themePreferenceKey, themeCode);
  }

  void toggleThemeColor() {
    setThemeColor(isBlueTheme ? AppThemeColor.purple : AppThemeColor.blue);
  }

  void setSeedColor(Color color) {
    setThemeColor(_themeFromSeedValue(color.toARGB32()));
  }

  AppThemeColor _themeFromSeedValue(int? colorValue) {
    if (colorValue == null) return AppThemeColor.purple;

    final color = Color(colorValue);
    final blueDistance = _colorDistance(color, AppThemeColor.blue.seedColor);
    final purpleDistance = _colorDistance(
      color,
      AppThemeColor.purple.seedColor,
    );

    return blueDistance < purpleDistance
        ? AppThemeColor.blue
        : AppThemeColor.purple;
  }

  int _colorDistance(Color a, Color b) {
    final red = _channelValue(a.r) - _channelValue(b.r);
    final green = _channelValue(a.g) - _channelValue(b.g);
    final blue = _channelValue(a.b) - _channelValue(b.b);
    return red * red + green * green + blue * blue;
  }

  int _channelValue(double value) {
    return (value * 255).round().clamp(0, 255);
  }
}
