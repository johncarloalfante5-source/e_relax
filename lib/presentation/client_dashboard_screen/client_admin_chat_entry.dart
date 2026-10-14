import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/client_admin_chat_repository.dart';
import '../../models/client_admin_chat.dart';
import '../../routes/app_routes.dart';

class ClientAdminChatEntry extends StatefulWidget {
  const ClientAdminChatEntry({super.key});

  @override
  State<ClientAdminChatEntry> createState() => _ClientAdminChatEntryState();
}

class _ClientAdminChatEntryState extends State<ClientAdminChatEntry> {
  final _repository = ClientAdminChatRepository();
  ClientAdminConversation? _conversation;
  RealtimeChannel? _channel;
  int _unreadCount = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnread());
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) unawaited(_repository.removeChannel(channel));
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final conversation = await _repository.fetchMyExistingConversation();
      if (!mounted) return;
      if (_conversation?.id != conversation?.id) {
        final oldChannel = _channel;
        _channel = null;
        if (oldChannel != null) unawaited(_repository.removeChannel(oldChannel));
        _conversation = conversation;
        if (conversation != null) {
          _channel = _repository.watchMessages(
            conversationId: conversation.id,
            onChange: () => unawaited(_loadUnread()),
          );
        }
      }
      final count = conversation == null
          ? 0
          : await _repository.countUnreadClientMessages(conversation);
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      // Keep the dashboard usable when unread state is temporarily unavailable.
    }
  }

  Future<void> _openChat() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final id = await _repository.getOrCreateClientConversation();
      if (!mounted) return;
      await context.push('${AppRoutes.clientAdminChatThreadBase}/$id');
      await _loadUnread();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the admin chat. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    heroTag: 'client-admin-chat-fab',
    tooltip: 'Message Admin',
    onPressed: _opening ? null : _openChat,
    icon: Badge(
      isLabelVisible: _unreadCount > 0,
      label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
      child: const Icon(Icons.support_agent_rounded),
    ),
    label: Text(_opening ? 'Opening chat' : 'Message Admin'),
  );
}
