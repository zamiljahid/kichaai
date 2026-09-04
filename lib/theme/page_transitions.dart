import 'package:flutter/material.dart';

/// ki_chai's route transition: a 700ms easeOutCubic fade with the incoming page
/// rising the last 8% of a screen height.
///
/// ki_chai builds this inline in a PageRouteBuilder on its splash. Installing it
/// as a [PageTransitionsBuilder] on the theme applies the same feel to every
/// push in this app without touching a single route name, destination or
/// Navigator call.
class KiChaiPageTransitionsBuilder extends PageTransitionsBuilder {
  const KiChaiPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      // Without this the reverse leg replays easeOutCubic backwards, which
      // reads as the page hesitating before it leaves.
      reverseCurve: Curves.easeInCubic,
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
  }
}

/// Applied to every platform so the transition is the app's own, the way
/// ki_chai's hand-rolled route is, rather than deferring to Material's
/// per-platform defaults (zoom on Android, cupertino slide on iOS).
const kAppPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: KiChaiPageTransitionsBuilder(),
    TargetPlatform.iOS: KiChaiPageTransitionsBuilder(),
    TargetPlatform.macOS: KiChaiPageTransitionsBuilder(),
    TargetPlatform.windows: KiChaiPageTransitionsBuilder(),
    TargetPlatform.linux: KiChaiPageTransitionsBuilder(),
    TargetPlatform.fuchsia: KiChaiPageTransitionsBuilder(),
  },
);
