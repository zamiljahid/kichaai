import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/app_strings.dart';
import '../theme/active_role_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/animated_background.dart';

/// ki_chai's theme picker: a segmented colour control over two large swatches
/// that animate their selection ring.
///
/// Two things are deliberately different from the original:
///  * ki_chai's picker writes to SharedPreferences but its MaterialApp derives
///    the theme from the active role regardless, so the control has no visible
///    effect. Here the pick genuinely wins, with an explicit "follow my role"
///    option to get the role-driven default back.
///  * a light/dark/system control, which ki_chai has no equivalent for — it is
///    light-only. This is what makes the dark theme reachable.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;
    final theme = context.watch<ThemeProvider>();
    final isProvider = context.watch<ActiveRoleProvider>().isProvider;
    final active = theme.effectiveColor(isProvider: isProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isBn ? 'থিম' : 'Theme')),
      body: AnimatedBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel(
                colors, isBn ? 'রঙ বেছে নিন' : 'Choose Theme Color'),
            const SizedBox(height: 14),
            SegmentedButton<AppThemeColor>(
              segments: AppThemeColor.values
                  .map(
                    (c) => ButtonSegment<AppThemeColor>(
                      value: c,
                      label: Text(_colorLabel(c, isBn)),
                      icon: Icon(
                        c == AppThemeColor.purple
                            ? Icons.palette_rounded
                            : Icons.water_drop_rounded,
                      ),
                    ),
                  )
                  .toList(),
              selected: {active},
              onSelectionChanged: (s) =>
                  context.read<ThemeProvider>().setThemeColor(s.first),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AppThemeColor.values
                  .map((c) => _Swatch(
                        themeColor: c,
                        isSelected: active == c,
                        onTap: () =>
                            context.read<ThemeProvider>().setThemeColor(c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // The escape hatch back to the role-driven default. Without this an
            // explicit pick is permanent and the role could never colour the
            // app again.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: theme.override == null
                    ? null
                    : () => context.read<ThemeProvider>().setThemeColor(null),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(
                  isBn
                      ? 'আমার ভূমিকা অনুসরণ করুন'
                      : 'Follow my role',
                ),
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(colors, isBn ? 'উজ্জ্বলতা' : 'Appearance'),
            const SizedBox(height: 14),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(isBn ? 'সিস্টেম' : 'System'),
                  icon: const Icon(Icons.brightness_auto_rounded),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(isBn ? 'হালকা' : 'Light'),
                  icon: const Icon(Icons.light_mode_rounded),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(isBn ? 'গাঢ়' : 'Dark'),
                  icon: const Icon(Icons.dark_mode_rounded),
                ),
              ],
              selected: {theme.themeMode},
              onSelectionChanged: (s) =>
                  context.read<ThemeProvider>().setThemeMode(s.first),
            ),
            const SizedBox(height: 16),
            Text(
              isBn
                  ? 'সিস্টেম নির্বাচন করলে আপনার ডিভাইসের সেটিং অনুসরণ করা হবে।'
                  : 'System follows your device setting.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  static String _colorLabel(AppThemeColor c, bool isBn) {
    if (!isBn) return c.label;
    return c == AppThemeColor.purple ? 'বেগুনি' : 'নীল';
  }

  Widget _sectionLabel(ColorScheme colors, String text) => Text(
        text,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.themeColor,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemeColor themeColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: themeColor.seedColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? colors.onSurface : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: themeColor.seedColor.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: isSelected
            // The seed colours are dark in both modes, so white reads on them
            // whichever brightness is active.
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : null,
      ),
    );
  }
}
