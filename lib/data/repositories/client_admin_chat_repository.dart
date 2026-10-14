import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_client_provider.dart';
import '../../models/client_admin_chat.dart';

class ClientAdminChatRepository {
  ClientAdminChatRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientProvider.client;

  final SupabaseClient _client;

  Future<String> getOrCreateClientConversation() async {
    final result = await _client.rpc('get_or_create_client_admin_conversation');
    if (result is! String || result.isEmpty) {
      throw const FormatException('Could not open the admin conversation.');
    }
    return result;
  }

  Future<ClientAdminConversation?> fetchMyExistingConversation() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('client_admin_conversations')
        .select(
          'id,client_id,client_last_read_at,admin_last_read_at,updated_at',
        )
        .eq('client_id', userId)
        .maybeSingle();
    return row == null ? null : ClientAdminConversation.fromJson(row);
  }

  Future<int> countUnreadClientMessages(
    ClientAdminConversation conversation,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final base = _client
        .from('client_admin_messages')
        .select('id')
        .eq('conversation_id', conversation.id)
        .neq('sender_id', userId);
    final rows = conversation.clientLastReadAt == null
        ? await base
        : await base.gt(
            'created_at',
            conversation.clientLastReadAt!.toIso8601String(),
          );
    return rows.length;
  }

  Future<List<ClientAdminMessage>> fetchMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final base = _client
        .from('client_admin_messages')
        .select('id,conversation_id,sender_id,body,created_at')
        .eq('conversation_id', conversationId);
    final rows = before == null
        ? await base
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(limit)
        : await base
              .lt('created_at', before.toUtc().toIso8601String())
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(limit);
    return rows
        .map((row) => ClientAdminMessage.fromJson(row))
        .toList()
        .reversed
        .toList();
  }

  Future<ClientAdminMessage> sendMessage({
    required String conversationId,
    required String messageId,
    required String body,
  }) async {
    final response = await _client.rpc(
      'send_client_admin_message',
      params: {
        'p_conversation_id': conversationId,
        'p_message_id': messageId,
        'p_body': body,
      },
    );
    if (response is List && response.isNotEmpty && response.first is Map) {
      return ClientAdminMessage.fromJson(
        Map<String, dynamic>.from(response.first as Map),
      );
    }
    throw const FormatException('The message was not returned by the server.');
  }

  Future<void> markRead(String conversationId) async {
    await _client.rpc(
      'mark_client_admin_conversation_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<List<ClientAdminConversation>> fetchAdminInbox() async {
    final response = await _client.rpc('get_admin_client_chat_inbox');
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map(
          (row) => ClientAdminConversation.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  RealtimeChannel watchMessages({
    required String conversationId,
    required VoidCallback onChange,
  }) =>
      _client
          .channel('client-admin-messages-$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'client_admin_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (_) => onChange(),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) onChange();
          });

  RealtimeChannel watchInbox({required VoidCallback onChange}) =>
      _client
          .channel('client-admin-inbox-${_client.auth.currentUser?.id ?? 'unknown'}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'client_admin_messages',
            callback: (_) => onChange(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'client_admin_conversations',
            callback: (_) => onChange(),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) onChange();
          });

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  static String newMessageId() {
    final random = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    random[6] = (random[6] & 0x0f) | 0x40;
    random[8] = (random[8] & 0x3f) | 0x80;
    final hex = random.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

final _secureRandom = Random.secure();
