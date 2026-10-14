class ClientAdminConversation {
  const ClientAdminConversation({
    required this.id,
    required this.clientId,
    this.clientName = 'Client',
    this.latestBody,
    this.latestMessageAt,
    this.clientLastReadAt,
    this.adminLastReadAt,
    this.unreadCount = 0,
    this.updatedAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String? latestBody;
  final DateTime? latestMessageAt;
  final DateTime? clientLastReadAt;
  final DateTime? adminLastReadAt;
  final int unreadCount;
  final DateTime? updatedAt;

  factory ClientAdminConversation.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value)?.toUtc() : null;
    }

    return ClientAdminConversation(
      id: (json['conversation_id'] ?? json['id']) as String,
      clientId: json['client_id'] as String,
      clientName: json['client_name'] as String? ?? 'Client',
      latestBody: json['latest_body'] as String?,
      latestMessageAt: date('latest_message_at'),
      clientLastReadAt: date('client_last_read_at'),
      adminLastReadAt: date('admin_last_read_at'),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      updatedAt: date('updated_at'),
    );
  }
}

class ClientAdminMessage {
  const ClientAdminMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  factory ClientAdminMessage.fromJson(Map<String, dynamic> json) =>
      ClientAdminMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
