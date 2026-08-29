import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a Google Meet link in the Meet app (if installed) or the browser —
/// `LaunchMode.externalApplication` is what lets Android/iOS hand the
/// `meet.google.com` URL to the Meet app via its registered App/Universal
/// Links instead of Flutter trying to render it in-app. Falls back to a
/// snackbar if nothing on the device can open it at all.
Future<void> openMeetLink(BuildContext context, String meetLink) async {
  try {
    final ok = await launchUrl(Uri.parse(meetLink), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) _fail(context);
  } catch (_) {
    if (context.mounted) _fail(context);
  }
}

void _fail(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('মিটিং লিংক খোলা যায়নি — লিংকটি কপি করে ব্রাউজারে পেস্ট করুন', style: TextStyle(color: Colors.white)),
    backgroundColor: Color(0xFFEF4444),
    behavior: SnackBarBehavior.floating,
  ));
}
