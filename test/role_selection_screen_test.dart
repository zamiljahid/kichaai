import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kichaai/core/utils/app_strings.dart';
import 'package:kichaai/screens/role_selection_screen.dart';
import 'package:kichaai/theme/active_role_provider.dart';
import 'package:kichaai/theme/theme_provider.dart';

/// The role picker packs a badge, a 60px icon plate, a title, a two-line blurb,
/// a three-item checklist and a radio row into each of two side-by-side cards.
/// On a narrow phone that is the layout most likely to overflow, and an
/// overflow here is a red-striped banner across the first screen after login.
void main() {
  Widget harness({required Size size, required Brightness brightness}) {
    final role = ActiveRoleProvider();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ActiveRoleProvider>.value(value: role),
        ChangeNotifierProvider(create: (_) => LanguageNotifier()),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 44)),
        child: MaterialApp(
          theme: ThemeProvider.themeDataFor(AppThemeColor.purple,
              brightness: brightness),
          home: const RoleSelectionScreen(),
        ),
      ),
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 320x568 is the smallest phone still in the wild (iPhone SE 1st gen);
  // 360x640 is the commonest low-end Android.
  for (final size in const [Size(320, 568), Size(360, 640), Size(414, 896)]) {
    for (final brightness in Brightness.values) {
      testWidgets('lays out without overflow at $size (${brightness.name})',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(size: size, brightness: brightness));
        await tester.pump(const Duration(milliseconds: 1600)); // entrance done

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opens with no role picked, so no Continue button', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        harness(size: const Size(360, 640), brightness: Brightness.light));
    await tester.pump(const Duration(milliseconds: 1600));

    expect(find.textContaining('চালিয়ে যান'), findsNothing);
  });

  testWidgets('picking a role reveals Continue and previews that role\'s theme',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        harness(size: const Size(360, 640), brightness: Brightness.light));
    await tester.pump(const Duration(milliseconds: 1600));

    final context = tester.element(find.byType(RoleSelectionScreen));
    final role = Provider.of<ActiveRoleProvider>(context, listen: false);
    expect(role.isProvider, isFalse);

    // Card 0 is Provider — ki_chai's left-hand card.
    await tester.tap(find.text('প্রোভাইডার'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(role.isProvider, isTrue);
    expect(find.textContaining('চালিয়ে যান'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
