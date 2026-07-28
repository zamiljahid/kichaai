class ThreadParticipant {
  final String userId;
  final String? name;
  // No backend data source yet for these two — messaging-service's ThreadParticipant has no
  // avatar/online-presence fields (online status would need UserSocketSession, never joined
  // in; avatar would need a cross-service call to auth-service's ProviderProfile). Kept with
  // safe defaults so existing UI conditionals don't break; will just never show as online/have
  // an avatar until that's wired.
  final String? avatarUrl;
  final bool isOnline;

  const ThreadParticipant({
    required this.userId,
    this.name,
    this.avatarUrl,
    this.isOnline = false,
  });

  factory ThreadParticipant.fromJson(Map<String, dynamic> json) =>
      ThreadParticipant(
        userId: json['userId'] as String,
        name: json['userNameSnapshot'] as String?,
      );
}

class MessageModel {
  final String id;
  final String threadId;
  final String senderId;
  final String? body;
  final String type;
  final DateTime createdAt;
  final String? senderName;

  const MessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    this.body,
    this.type = 'text',
    required this.createdAt,
    this.senderName,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        threadId: json['threadId'] as String,
        senderId: json['senderUserId'] as String? ?? '',
        body: json['body'] as String?,
        type: json['messageType'] as String? ?? 'text',
        createdAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
        senderName: json['senderNameSnapshot'] as String?,
      );
}

class ThreadModel {
  final String id;
  final String contextChunk;
  final List<ThreadParticipant> participants;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final int messageCount;
  final String? dispatchJobId;
  final String? bookingId;
  final String? orderId;
  final String? serviceRequestId;
  final DateTime createdAt;

  const ThreadModel({
    required this.id,
    required this.contextChunk,
    this.participants = const [],
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.dispatchJobId,
    this.bookingId,
    this.orderId,
    this.serviceRequestId,
    required this.createdAt,
  });

  factory ThreadModel.fromJson(Map<String, dynamic> json) => ThreadModel(
        id: json['id'] as String,
        contextChunk: json['contextChunk'] as String? ?? '',
        participants: (json['participants'] as List<dynamic>?)
                ?.map((e) => ThreadParticipant.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        lastMessagePreview: json['lastMessagePreview'] as String?,
        lastMessageAt: json['lastMessageAt'] != null
            ? DateTime.tryParse(json['lastMessageAt'] as String)
            : null,
        unreadCount: json['unreadCount'] as int? ?? 0,
        messageCount: json['messageCount'] as int? ?? 0,
        dispatchJobId: (json['dispatchCtx'] as Map<String, dynamic>?)?['dispatchJobId'] as String?,
        bookingId: (json['bookingCtx'] as Map<String, dynamic>?)?['bookingId'] as String?,
        orderId: (json['commerceOrderCtx'] as Map<String, dynamic>?)?['orderId'] as String?,
        serviceRequestId: (json['matchmakingCtx'] as Map<String, dynamic>?)?['serviceRequestId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  // Returns the other participant's name (not the current user)
  String otherParticipantName(String currentUserId) {
    final other = participants.where((p) => p.userId != currentUserId).firstOrNull;
    return other?.name ?? 'অজানা ব্যবহারকারী';
  }

  String otherParticipantAvatar(String currentUserId) {
    final other = participants.where((p) => p.userId != currentUserId).firstOrNull;
    return other?.avatarUrl ?? '';
  }
}
