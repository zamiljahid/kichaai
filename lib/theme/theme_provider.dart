import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'page_transitions.dart';

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

/// The persisted shape of the user's theme settings, read once before the first
/// frame so the app never paints one theme and then snaps to another.
class ThemeSettings {
  const ThemeSettings({this.color, this.mode = ThemeMode.system});
  final AppThemeColor? color;
  final ThemeMode mode;
}

class ThemeProvider with ChangeNotifier {
  /// Same key ki_chai writes, so a shared preferences store stays readable by
  /// both apps. 0 means "no explicit pick — follow the role".
  static const _themePreferenceKey = 'appThemeCode';
  static const _themeModeKey = 'appThemeMode';

  AppThemeColor? _override;
  ThemeMode _themeMode;

  ThemeProvider({ThemeSettings settings = const ThemeSettings()})
      : _override = settings.color,
        _themeMode = settings.mode;

  /// The user's explicit colour pick, or null when they have never chosen one
  /// and the active role should decide.
  AppThemeColor? get override => _override;

  /// system / light / dark.
  ThemeMode get themeMode => _themeMode;

  /// The colour actually in force: an explicit pick wins, otherwise the role's
  /// default. ki_chai persists a pick but then derives the theme from the role
  /// anyway, so its picker can never take effect — this resolves that while
  /// keeping the role default for anyone who never opens the picker.
  AppThemeColor effectiveColor({required bool isProvider}) =>
      _override ?? (isProvider ? AppThemeColor.blue : AppThemeColor.purple);

  static Future<ThemeSettings> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemeSettings(
      color: themeColorFromCode(prefs.getInt(_themePreferenceKey)),
      mode: _modeFromName(prefs.getString(_themeModeKey)),
    );
  }

  /// null (follow the role) unless an explicit 1/2 was stored.
  static AppThemeColor? themeColorFromCode(int? themeCode) {
    switch (themeCode) {
      case 1:
        return AppThemeColor.purple;
      case 2:
        return AppThemeColor.blue;
      default:
        return null;
    }
  }

  static ThemeMode _modeFromName(String? name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// Sets an explicit colour, or clears back to the role default with null.
  Future<void> setThemeColor(AppThemeColor? themeColor) async {
    if (_override != themeColor) {
      _override = themeColor;
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _themePreferenceKey,
      themeColor == null ? 0 : (themeColor == AppThemeColor.blue ? 2 : 1),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  /// Builds the [ThemeData] for a given [AppThemeColor]. Kept static so the
  /// app can derive the theme directly from the active role.
  static ThemeData themeDataFor(
    AppThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: themeColor.seedColor,
      brightness: brightness,
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
      textTheme: _textThemeFor(colorScheme, brightness),
      pageTransitionsTheme: kAppPageTransitionsTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // ki_chai's app-bar silhouette: a primary-filled bar with its bottom
        // corners rounded off by 30. Set on the theme rather than per screen so
        // all ~56 AppBars pick it up without touching a single call site.
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
        ),
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
  static TextTheme _textThemeFor(ColorScheme colors, Brightness brightness) {
    final base = Typography.material2021(platform: TargetPlatform.android);
    // .black is the dark-on-light set, .white the light-on-dark one. Picking
    // the wrong one leaves every unstyled string invisible in that mode.
    return (brightness == Brightness.dark ? base.white : base.black)
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

}
