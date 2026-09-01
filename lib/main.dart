import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/app_routes.dart';
import 'core/utils/app_strings.dart';
import 'services/deep_link_service.dart';
import 'services/push_service.dart';
import 'theme/active_role_provider.dart';
import 'theme/theme_provider.dart';
import 'widgets/ai_chat_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Light theme: the status/nav bar icons have to be DARK to stay visible.
  // These were set for the retired dark palette and would render invisible
  // white-on-white against the seeded light surfaces.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      await PushService.instance.setupHandlers();
    } catch (_) {}
  }

  DeepLinkService.instance.init(PushService.instance.navigatorKey);

  // Read the persisted colour choice before the first frame so the app never
  // paints one theme and then snaps to another.
  final themeColor = await ThemeProvider.loadPersisted();

  runApp(KichaaiApp(initialThemeColor: themeColor));
}

class KichaaiApp extends StatelessWidget {
  const KichaaiApp({super.key, this.initialThemeColor = AppThemeColor.purple});

  final AppThemeColor initialThemeColor;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageNotifier()),
        ChangeNotifierProvider(create: (_) => ActiveRoleProvider()),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(initialThemeColor: initialThemeColor),
        ),
      ],
      child: const _KichaaiMaterialApp(),
    );
  }
}

class _KichaaiMaterialApp extends StatelessWidget {
  const _KichaaiMaterialApp();

  @override
  Widget build(BuildContext context) {
    // The active role drives the palette: customer → purple, provider → blue.
    // Same rule as ki_chai, and the reason every colour is read from the
    // ColorScheme rather than a constant.
    final isProvider = context.watch<ActiveRoleProvider>().isProvider;
    final themeColor = isProvider ? AppThemeColor.blue : AppThemeColor.purple;

    return MaterialApp(
      title: 'Kichaai | কিচাই',
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.themeDataFor(themeColor),
      navigatorKey: PushService.instance.navigatorKey,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      builder: (context, child) => AiChatOverlay(child: child!),
    );
  }
}
