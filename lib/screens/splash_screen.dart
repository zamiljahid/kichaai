import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/push_service.dart';
import 'auth_screen.dart';
import 'main_navigation.dart';
import 'onboarding_screen.dart';

/// ki_chai's animated splash: a gradient whose corners sweep continuously
/// behind a stacked-circle logo, which then slides away into the next screen.
///
/// The session bootstrap below is unchanged — same reads, same three-way
/// routing, same FCM re-registration. The animation runs *alongside* it; the
/// decision is simply not acted on until the intro has played.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// How long the logo holds before sliding away. ki_chai uses 4s, which it
  /// spends overlapping a /auth/me round trip; this app's bootstrap is two
  /// SharedPreferences reads and resolves almost immediately, so this is very
  /// nearly pure intro time. Lower it here if it feels long on a warm start.
  static const _introDuration = Duration(seconds: 4);

  late final AnimationController _bgController;
  late final Animation<Alignment> _topAlignmentAnimation;
  late final Animation<Alignment> _bottomAlignmentAnimation;

  late final AnimationController _slideController;
  Animation<Offset>? _slideAnimation;

  /// Held so dispose() can cancel it. ki_chai's original fires a bare Timer
  /// that outlives the widget and can navigate on a dead context.
  Timer? _introTimer;

  bool _navigationScheduled = false;

  /// Started in initState so the session resolves while the intro plays.
  late final Future<Widget> _destination;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _topAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
        weight: 1,
      ),
    ]).animate(_bgController);

    _bottomAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
        weight: 1,
      ),
    ]).animate(_bgController);

    _bgController.repeat();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _destination = _bootstrap();
  }

  // Route by session:
  //  • logged in            → straight into the app (provider toggle preserved)
  //  • seen the intro before → straight to login (no re-watching the carousel)
  //  • first ever launch     → the intro carousel
  Future<Widget> _bootstrap() async {
    final token = await ApiClient.getAccessToken();
    final seenIntro = await ApiClient.getOnboardingSeen();
    if (token != null && token.isNotEmpty) {
      ApiClient.isLoggedIn.value = true;
      // Register/refresh the FCM token whenever the app starts logged in —
      // the last-known device may have gone through a token rotation.
      PushService.instance.registerCurrentToken();
    }
    return (token != null && token.isNotEmpty)
        ? const MainNavigation()
        : (seenIntro ? const AuthScreen() : const OnboardingScreen());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final isMobile = MediaQuery.sizeOf(context).width < 800;
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero, // centered
      end: isMobile ? const Offset(0, -2) : const Offset(1.5, 0),
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInOut),
    );

    if (_navigationScheduled) return;
    _navigationScheduled = true;
    _introTimer = Timer(_introDuration, () {
      unawaited(_slideOutAndNavigate());
    });
  }

  /// Slides the logo away, then leaves for whatever [_bootstrap] decided.
  Future<void> _slideOutAndNavigate() async {
    await _slideController.forward();
    if (!mounted) return;

    final next = await _destination;
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionDuration: const Duration(milliseconds: 700),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _bgController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Widget _buildLogoAndWelcome() {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.24),
                    offset: const Offset(8, 8),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: colors.surface.withValues(alpha: 0.56),
                    offset: const Offset(-8, -8),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.70),
                  width: 8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.28),
                    blurRadius: 20,
                    spreadRadius: 4,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text(
          isBn ? 'স্বাগতম\nকিচাই' : 'Welcome to\nKichaai',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.onPrimaryContainer,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slide = _slideAnimation;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, _) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primaryContainer, colors.primary],
                begin: _topAlignmentAnimation.value,
                end: _bottomAlignmentAnimation.value,
              ),
            ),
            child: Center(
              child: slide == null
                  ? _buildLogoAndWelcome()
                  : SlideTransition(
                      position: slide,
                      child: FadeTransition(
                        opacity: Tween<double>(begin: 1, end: 0).animate(
                          CurvedAnimation(
                            parent: _slideController,
                            curve: Curves.easeIn,
                          ),
                        ),
                        child: _buildLogoAndWelcome(),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
