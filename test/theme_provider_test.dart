import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kichaai/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('effectiveColor', () {
    test('follows the active role when nothing is picked', () {
      final p = ThemeProvider();
      expect(p.override, isNull);
      expect(p.effectiveColor(isProvider: false), AppThemeColor.purple);
      expect(p.effectiveColor(isProvider: true), AppThemeColor.blue);
    });

    test('an explicit pick wins over the role', () {
      final p = ThemeProvider(
        settings: const ThemeSettings(color: AppThemeColor.purple),
      );
      // The bug in ki_chai is precisely this case: it stores the pick and then
      // ignores it because the theme is derived from the role.
      expect(p.effectiveColor(isProvider: true), AppThemeColor.purple);
    });
  });

  group('persisted code', () {
    test('absent or 0 means "follow the role", not a colour', () {
      expect(ThemeProvider.themeColorFromCode(null), isNull);
      expect(ThemeProvider.themeColorFromCode(0), isNull);
    });

    test('1 and 2 map to ki_chai\'s two seeds', () {
      expect(ThemeProvider.themeColorFromCode(1), AppThemeColor.purple);
      expect(ThemeProvider.themeColorFromCode(2), AppThemeColor.blue);
    });

    test('a pick round-trips, and clearing restores role-following', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ThemeProvider();

      await p.setThemeColor(AppThemeColor.blue);
      expect((await ThemeProvider.loadPersisted()).color, AppThemeColor.blue);

      await p.setThemeColor(null);
      expect((await ThemeProvider.loadPersisted()).color, isNull);
    });

    test('theme mode round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ThemeProvider();
      expect(p.themeMode, ThemeMode.system);

      await p.setThemeMode(ThemeMode.dark);
      expect((await ThemeProvider.loadPersisted()).mode, ThemeMode.dark);
    });
  });

  group('themeDataFor', () {
    test('builds both brightnesses from one seed', () {
      final light = ThemeProvider.themeDataFor(AppThemeColor.purple);
      final dark = ThemeProvider.themeDataFor(
        AppThemeColor.purple,
        brightness: Brightness.dark,
      );
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    });

    test('dark mode flips the INHERITED text colour', () {
      final light = ThemeProvider.themeDataFor(AppThemeColor.purple);
      final dark = ThemeProvider.themeDataFor(
        AppThemeColor.purple,
        brightness: Brightness.dark,
      );
      // Must assert on a style _textThemeFor does NOT override. bodyLarge and
      // friends get an explicit colors.onSurface, which is brightness-aware on
      // its own — so testing those passes even if the Typography base is wrong,
      // and proves nothing. labelSmall inherits straight from the base, which
      // is the thing that has to switch .black/.white.
      final lightLabel = light.textTheme.labelSmall!.color!;
      final darkLabel = dark.textTheme.labelSmall!.color!;
      expect(lightLabel, isNot(darkLabel));
      expect(lightLabel.computeLuminance(),
          lessThan(darkLabel.computeLuminance()));
    });

    test('keeps the Bengali font in both modes', () {
      for (final b in Brightness.values) {
        final t = ThemeProvider.themeDataFor(AppThemeColor.blue, brightness: b);
        expect(t.textTheme.bodyLarge!.fontFamily, kBengaliFont);
      }
    });

    test('the two seeds produce different primaries', () {
      expect(
        ThemeProvider.themeDataFor(AppThemeColor.purple).colorScheme.primary,
        isNot(ThemeProvider.themeDataFor(AppThemeColor.blue)
            .colorScheme
            .primary),
      );
    });
  });
}
