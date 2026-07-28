import 'dart:convert';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final String channel;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.channel,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> j) => NotificationModel(
        id: j['id'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        type: j['type'] as String? ?? 'system',
        channel: j['channel'] as String? ?? 'push',
        // The backend has no isRead field — read-state lives in status
        // ('pending'|'sent'|'delivered'|'read'|'failed').
        isRead: (j['status'] as String?) == 'read',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        // route/jobId/applicationId payload — persisted server-side as a JSON string.
        metadata: _parseMetadata(j['metadataJson']),
      );

  static Map<String, dynamic>? _parseMetadata(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        userId: userId,
        title: title,
        body: body,
        type: type,
        channel: channel,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        metadata: metadata,
      );
}

class NotificationPreference {
  final String userId;
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final bool jobUpdate;
  final bool payment;
  final bool marketing;
  final bool system;

  const NotificationPreference({
    required this.userId,
    required this.pushEnabled,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.jobUpdate,
    required this.payment,
    required this.marketing,
    required this.system,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> j) =>
      NotificationPreference(
        userId: j['userId'] as String? ?? '',
        pushEnabled: j['pushEnabled'] as bool? ?? true,
        emailEnabled: j['emailEnabled'] as bool? ?? true,
        smsEnabled: j['smsEnabled'] as bool? ?? false,
        jobUpdate: j['jobUpdate'] as bool? ?? true,
        payment: j['payment'] as bool? ?? true,
        marketing: j['marketing'] as bool? ?? false,
        system: j['system'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'pushEnabled': pushEnabled,
        'emailEnabled': emailEnabled,
        'smsEnabled': smsEnabled,
        'jobUpdate': jobUpdate,
        'payment': payment,
        'marketing': marketing,
        'system': system,
      };

  NotificationPreference copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? jobUpdate,
    bool? payment,
    bool? marketing,
    bool? system,
  }) =>
      NotificationPreference(
        userId: userId,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        emailEnabled: emailEnabled ?? this.emailEnabled,
        smsEnabled: smsEnabled ?? this.smsEnabled,
        jobUpdate: jobUpdate ?? this.jobUpdate,
        payment: payment ?? this.payment,
        marketing: marketing ?? this.marketing,
        system: system ?? this.system,
      );
}
