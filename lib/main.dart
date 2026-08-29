import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/app_routes.dart';
import 'core/utils/app_strings.dart';
import 'services/deep_link_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/ai_chat_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase is Android-only for now. iOS plist ships but the Xcode target
  // hasn't been wired to APNs yet — skipping there avoids a boot crash.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      await PushService.instance.setupHandlers();
    } catch (_) {}
  }

  DeepLinkService.instance.init(PushService.instance.navigatorKey);

  runApp(const KichaaiApp());
}

class KichaaiApp extends StatelessWidget {
  const KichaaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LanguageNotifier(),
      child: MaterialApp(
        title: 'Kichaai | কিচাই',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        navigatorKey: PushService.instance.navigatorKey,
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.routes,
        builder: (context, child) => AiChatOverlay(child: child!),
      ),
    );
  }
}
