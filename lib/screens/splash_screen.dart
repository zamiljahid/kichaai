import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'main_navigation.dart';
import 'onboarding_screen.dart';

/// Placeholder while the real design is pending — routing/session-bootstrap logic
/// only, no visual design. Do not add a logo/animation here without new direction.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Route by session:
  //  • logged in            → straight into the app (provider toggle preserved)
  //  • seen the intro before → straight to login (no re-watching the carousel)
  //  • first ever launch     → the intro carousel
  Future<void> _bootstrap() async {
    final token = await ApiClient.getAccessToken();
    final seenIntro = await ApiClient.getOnboardingSeen();
    if (token != null && token.isNotEmpty) {
      ApiClient.isLoggedIn.value = true;
      // Register/refresh the FCM token whenever the app starts logged in —
      // the last-known device may have gone through a token rotation.
      PushService.instance.registerCurrentToken();
    }
    if (!mounted) return;
    final Widget next = (token != null && token.isNotEmpty)
        ? const MainNavigation()
        : (seenIntro ? const AuthScreen() : const OnboardingScreen());
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SizedBox.shrink(),
    );
  }
}
