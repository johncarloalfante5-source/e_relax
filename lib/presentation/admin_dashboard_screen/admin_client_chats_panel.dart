import 'package:flutter/material.dart';

import '../../models/client_admin_chat.dart';
import '../../theme/app_theme.dart';

class AdminClientChatsPanel extends StatelessWidget {
  const AdminClientChatsPanel({
    super.key,
    required this.conversations,
    required this.loading,
    required this.error,
    required this.onOpenConversation,
    required this.onRetry,
  });

  final List<ClientAdminConversation> conversations;
  final bool loading;
  final String? error;
  final ValueChanged<ClientAdminConversation> onOpenConversation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && conversations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }
    if (error != null && conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (conversations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('Client conversations will appear here.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
          ),
        for (var index = 0; index < conversations.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          _conversationTile(context, conversations[index]),
        ],
      ],
    );
  }

  Widget _conversationTile(
    BuildContext context,
    ClientAdminConversation conversation,
  ) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryContainer,
          foregroundColor: AppTheme.primary,
          child: Text(
            conversation.clientName.trim().isEmpty
                ? 'C'
                : conversation.clientName.trim()[0].toUpperCase(),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                conversation.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: conversation.unreadCount > 0
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            if (conversation.unreadCount > 0)
              Badge.count(count: conversation.unreadCount),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            conversation.latestBody ?? 'No messages yet',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: conversation.latestMessageAt == null
            ? const Icon(Icons.chevron_right_rounded)
            : Text(
                TimeOfDay.fromDateTime(
                  conversation.latestMessageAt!.toLocal(),
                ).format(context),
                style: Theme.of(context).textTheme.labelSmall,
              ),
        onTap: () => onOpenConversation(conversation),
      );
}
