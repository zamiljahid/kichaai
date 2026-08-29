import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Loud, hard-to-miss alert for events that need IMMEDIATE attention — a new
/// job broadcast to online providers, or a scheduled consultation about to
/// start. Two independent pieces, because Android and iOS give apps very
/// different amounts of control over "how loud":
///
/// - System tray notification (via flutter_local_notifications) — the thing
///   that shows/sounds when the push arrives in the BACKGROUND or with the
///   app killed. On Android this rides `content://settings/system/alarm_alert`
///   (the user's own chosen alarm-clock sound) on a max-importance channel —
///   no bundled audio needed, and it's louder/more attention-grabbing than
///   any per-app notification sound could be. iOS has no equivalent API for
///   third-party apps to reuse the system alarm sound; the best available
///   without Apple's Critical Alerts entitlement (a special grant Apple
///   reviews case-by-case, see note on `init()`) is a Time-Sensitive
///   notification with the default system sound.
/// - Foreground ringing loop (via audioplayers) — the thing that plays while
///   the app is OPEN and on screen, which is the case that actually matters
///   most for a provider staring at their phone. This works identically on
///   both platforms because it's just an app-owned audio player looping a
///   bundled clip (assets/sounds/alarm_ring.wav — a synthesized two-tone
///   siren, not a fetched/licensed sound file), and on iOS it's set to the
///   AVAudioSession "playback" category so it plays through the mute/silent
///   switch without needing any special entitlement.
class AlarmNotificationService {
  static final AlarmNotificationService instance = AlarmNotificationService._();
  AlarmNotificationService._();

  static const _channelId = 'job_offers_alarm';
  static const _channelName = 'নতুন কাজ ও রিমাইন্ডার';
  static const _channelDesc = 'নতুন কাজের অনুরোধ এবং নির্ধারিত মিটিং শুরুর সতর্কতা';
  static const _ringAsset = 'sounds/alarm_ring.wav';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _player = AudioPlayer();
  bool _ready = false;
  bool _ringing = false;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    _ready = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // `requestCriticalPermission` only has an effect once the app carries
    // Apple's `com.apple.developer.usernotifications.critical-alerts`
    // entitlement — a separate, manual request/approval from Apple, not
    // something togglable in code. Without it iOS just ignores the flag and
    // treats these as normal (Time-Sensitive) notifications, so this is
    // forward-compatible rather than load-bearing today.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
        enableVibration: true,
        // Long, repeating buzz-pause pattern — reads as "something urgent",
        // not the single quick tap of a normal notification.
        vibrationPattern: Int64List.fromList(
            [0, 800, 400, 800, 400, 800, 400, 800]),
        enableLights: true,
      ));
      await androidImpl.requestNotificationsPermission();
    }

    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    ));
  }

  Timer? _autoStopTimer;

  /// Show the tray notification AND start the foreground ringing loop.
  /// Safe to call repeatedly for the same offer (e.g. once from a push and
  /// again when the dashboard's own poll discovers it) — a second call while
  /// already ringing just refreshes the tray notification and the auto-stop
  /// window, not a second overlapping sound. Always pair with [stopRinging]
  /// once the user responds (accepts/rejects/opens the job); a 30s auto-stop
  /// is also armed as a safety net so an ignored offer doesn't ring forever.
  Future<void> startRinging({required String title, required String body, String? payload}) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    await _showTrayNotification(title: title, body: body, payload: payload);

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 30), stopRinging);

    if (_ringing) return;
    _ringing = true;
    try {
      await _player.play(AssetSource(_ringAsset));
    } catch (_) {
      _ringing = false;
    }
  }

  Future<void> stopRinging() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    if (!_ringing) return;
    _ringing = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _showTrayNotification({required String title, required String body, String? payload}) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList(
              [0, 800, 400, 800, 400, 800, 400, 800]),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
          sound: 'default',
          // Upgrades to true system-alarm behaviour (bypasses silent switch
          // and Do Not Disturb) automatically once/if the Critical Alerts
          // entitlement above is granted; degrades gracefully to
          // Time-Sensitive until then.
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: payload,
    );
  }
}
