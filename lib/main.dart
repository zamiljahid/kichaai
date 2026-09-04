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
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      await PushService.instance.setupHandlers();
    } catch (_) {}
  }

  DeepLinkService.instance.init(PushService.instance.navigatorKey);

  final themeSettings = await ThemeProvider.loadPersisted();

  runApp(KichaaiApp(themeSettings: themeSettings));
}

class KichaaiApp extends StatelessWidget {
  const KichaaiApp({super.key, this.themeSettings = const ThemeSettings()});

  final ThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageNotifier()),
        ChangeNotifierProvider(create: (_) => ActiveRoleProvider()),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(settings: themeSettings),
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
    // The active role drives the palette by default — customer → purple,
    // provider → blue, the same rule as ki_chai — unless the user has picked a
    // colour explicitly in Settings, which wins. Either way it resolves to a
    // seed, which is why every colour is read from the ColorScheme.
    final isProvider = context.watch<ActiveRoleProvider>().isProvider;
    final themeState = context.watch<ThemeProvider>();
    final themeColor = themeState.effectiveColor(isProvider: isProvider);

    return MaterialApp(
      title: 'Kichaai | কিচাই',
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.themeDataFor(themeColor),
      darkTheme: ThemeProvider.themeDataFor(
        themeColor,
        brightness: Brightness.dark,
      ),
      // Defaults to ThemeMode.system, so the app follows the device setting
      // until the user overrides it in Settings.
      themeMode: themeState.themeMode,
      navigatorKey: PushService.instance.navigatorKey,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      // The system bars have to track the RESOLVED brightness — a fixed style
      // leaves the status-bar icons invisible in one mode or the other. This
      // context is below MaterialApp, so Theme.of here is the active theme.
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: scheme.surface,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: AiChatOverlay(child: child!),
        );
      },
    );
  }
}
