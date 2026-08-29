import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../screens/join_meal_group_screen.dart';

/// Handles kichaai://meal/join/<code> — Phase 1 custom-scheme deep link, opens the
/// join screen one-tap when the app is already installed. Real https Android App
/// Links / iOS Universal Links need domain verification, out of scope for now.
class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial, navigatorKey);
    } catch (_) {}

    _sub = _appLinks.uriLinkStream.listen((uri) => _handle(uri, navigatorKey));
  }

  void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    // kichaai://meal/join/AB23CD — host is "meal", path segments are ["join", "AB23CD"].
    if (uri.scheme != 'kichaai' || uri.host != 'meal') return;
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'join') return;
    final code = segments[1];
    if (code.isEmpty) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => JoinMealGroupScreen(initialCode: code)),
    );
  }

  void dispose() {
    _sub?.cancel();
  }
}
