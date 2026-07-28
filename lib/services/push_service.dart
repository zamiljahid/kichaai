import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';
import '../screens/active_job_screen.dart';
import '../screens/job_tracking_screen.dart';
import '../screens/notifications_screen.dart';
import 'dispatch_service.dart';
import 'notification_service.dart';

// Top-level so the runtime can re-enter it in a fresh isolate when the app
// is fully backgrounded. The system tray shows the notification either way —
// nothing to do beyond keeping FCM happy.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  static final PushService instance = PushService._();
  PushService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Bumped when a push arrives in the foreground so the bell can refetch.
  final ValueNotifier<int> foregroundPushTick = ValueNotifier<int>(0);

  static const _deviceIdKey = 'push_device_id';

  bool _handlersReady = false;

  Future<String> _stableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${identityHashCode(prefs).toRadixString(36)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  String _platform() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Called after login and on app-start when already logged in. Best-effort —
  /// push failures must not block auth.
  Future<void> registerCurrentToken() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      final userId = await ApiClient.getUserId();
      if (token == null || token.isEmpty) return;
      if (userId == null || userId.isEmpty) return;
      final deviceId = await _stableDeviceId();
      await NotificationService.instance
          .registerPushToken(userId, token, _platform(), deviceId: deviceId);
    } catch (_) {}
  }

  /// Must run BEFORE ApiClient.clearTokens() on logout — the DELETE call
  /// scopes the deactivation by the JWT's user.
  Future<void> deactivateCurrentToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await NotificationService.instance.deactivatePushToken(token);
    } catch (_) {}
  }

  /// Wire onMessage / onMessageOpenedApp / getInitialMessage. Safe to call
  /// more than once — subsequent calls are no-ops.
  Future<void> setupHandlers() async {
    if (kIsWeb || _handlersReady) return;
    _handlersReady = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((_) {
      foregroundPushTick.value++;
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      registerCurrentToken();
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((msg) => openTarget(msg.data));

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => openTarget(initial.data));
    }
  }

  /// Same deep-link contract as notifications_screen.dart's list-tap:
  /// route='provider' + jobId → ActiveJobScreen; jobId only → JobTrackingScreen;
  /// no jobId (chat pushes) → open the notification list.
  Future<void> openTarget(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final jobId = data['jobId'] as String?;
    if (jobId == null || jobId.isEmpty) {
      await navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationListScreen()));
      return;
    }

    final route = data['route'] as String?;
    if (route == 'provider') {
      try {
        final job = await DispatchService.instance.getJob(jobId);
        await navigator.push(
            MaterialPageRoute(builder: (_) => ActiveJobScreen(job: job)));
      } catch (_) {
        // Job gone/unreachable — stay put.
      }
    } else {
      await navigator.push(
          MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: jobId)));
    }
  }
}
