import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';
import '../screens/active_job_screen.dart';
import '../screens/job_tracking_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/provider_dashboard_screen.dart';
import 'alarm_notification_service.dart';
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

  // Mirrors fcm.service.ts's FcmService.LOUD_ALERT_TYPES — 'job_offer' (new job/consultation
  // broadcast), 'schedule_confirmed' (a picked slot just locked in), 'schedule_reminder' (that
  // scheduled consultation starts in ~10 min). All three ring loud; everything else stays quiet.
  static const _loudAlertTypes = {'job_offer', 'schedule_confirmed', 'schedule_reminder'};

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

    await AlarmNotificationService.instance.init();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      foregroundPushTick.value++;
      // Rings loud for job offers and consultation-scheduling moments — see
      // alarm_notification_service.dart. For a fresh job offer specifically, the provider
      // dashboard's own poll loop also stops the ring once they actually accept/reject; this
      // call is what covers them being on some OTHER screen when the push arrives, where that
      // poll loop isn't running. schedule_confirmed/schedule_reminder have no such second path —
      // they're one-shot, and the 30s auto-stop in AlarmNotificationService covers being ignored.
      if (_loudAlertTypes.contains(message.data['alertType'])) {
        final title = message.notification?.title ?? 'নতুন কাজের অনুরোধ';
        final body = message.notification?.body ?? 'একটি নতুন অনুরোধ এসেছে — গ্রহণ করতে ট্যাপ করুন।';
        AlarmNotificationService.instance.startRinging(
          title: title,
          body: body,
          payload: message.data['jobId'] as String?,
        );
      }
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
    // The user is now looking at it — whatever screen they land on next
    // (dashboard's own accept/reject dialog, if it's still open) takes over
    // from here, so the ring itself has done its job.
    if (_loudAlertTypes.contains(data['alertType'])) {
      AlarmNotificationService.instance.stopRinging();
    }
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
        // ActiveJobScreen is the post-accept tracking view (map/OTP/confirm) —
        // it has no accept/reject action of its own. A "new job nearby" push
        // fires while the job is still searching/assigned (this provider
        // hasn't responded yet), so landing there directly showed a dead-end
        // read-only screen with no way to accept. Route those to the
        // dashboard instead, whose existing poll loop picks up the pending
        // assignment and shows the real accept/reject dialog.
        if (job.status == 'searching' || job.status == 'assigned') {
          await navigator.push(MaterialPageRoute(
              builder: (_) => const ProviderDashboardScreen()));
        } else {
          await navigator.push(
              MaterialPageRoute(builder: (_) => ActiveJobScreen(job: job)));
        }
      } catch (_) {
        // Job gone/unreachable — stay put.
      }
    } else {
      await navigator.push(
          MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: jobId)));
    }
  }
}
