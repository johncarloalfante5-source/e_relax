import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/client_admin_chat_repository.dart';
import '../../data/stores/auth_session_store.dart';
import '../../models/client_admin_chat.dart';
import '../../models/profile.dart';
import '../../theme/app_theme.dart';

class ClientAdminChatThreadScreen extends StatefulWidget {
  const ClientAdminChatThreadScreen({
    super.key,
    required this.conversationId,
    this.clientName,
  });

  final String conversationId;
  final String? clientName;

  @override
  State<ClientAdminChatThreadScreen> createState() =>
      _ClientAdminChatThreadScreenState();
}

class _ClientAdminChatThreadScreenState
    extends State<ClientAdminChatThreadScreen> {
  final _repository = ClientAdminChatRepository();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final List<ClientAdminMessage> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  bool _sending = false;
  String? _error;
  String? _pendingMessageId;
  String? _pendingBody;

  bool get _isAdmin => AuthSessionStore.instance.profile?.role == AppRole.admin;
  String? get _userId => AuthSessionStore.instance.profile?.id;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _channel = _repository.watchMessages(
      conversationId: widget.conversationId,
      onChange: () => unawaited(_refreshMessages(markRead: true)),
    );
    unawaited(_refreshMessages(markRead: true));
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    final channel = _channel;
    if (channel != null) unawaited(_repository.removeChannel(channel));
    super.dispose();
  }

  Future<void> _refreshMessages({required bool markRead}) async {
    final wasNearBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            120;
    late final List<ClientAdminMessage> loaded;
    try {
      loaded = await _repository.fetchMessages(
        widget.conversationId,
        limit: 50,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load messages. Check your connection and retry.';
      });
      return;
    }

    if (!mounted) return;
    final merged = <String, ClientAdminMessage>{
      for (final message in _messages) message.id: message,
      for (final message in loaded) message.id: message,
    }.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
      _loading = false;
      _error = null;
      _hasOlder = loaded.length == 50;
    });
    if (markRead) {
      try {
        await _repository.markRead(widget.conversationId);
      } catch (_) {
        // Read state can be reconciled when the thread refreshes again.
      }
    }
    if (wasNearBottom) _scrollToBottom();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels < 120 &&
        !_loading &&
        !_loadingOlder &&
        _hasOlder &&
        _messages.isNotEmpty) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    final firstMessage = _messages.first;
    final previousPixels = _scrollController.position.pixels;
    final previousExtent = _scrollController.position.maxScrollExtent;
    setState(() => _loadingOlder = true);
    try {
      final older = await _repository.fetchMessages(
        widget.conversationId,
        limit: 50,
        before: firstMessage.createdAt,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _messages.map((message) => message.id).toSet();
        _messages.insertAll(
          0,
          older.where((message) => !existingIds.contains(message.id)),
        );
        _hasOlder = older.length == 50;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - previousExtent;
        _scrollController.jumpTo(previousPixels + addedExtent);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send({bool retry = false}) async {
    if (_sending) return;
    final body = (retry ? _pendingBody : _composer.text)?.trim() ?? '';
    if (body.isEmpty || body.length > 2000) return;
    final messageId = retry
        ? _pendingMessageId
        : ClientAdminChatRepository.newMessageId();
    if (messageId == null) return;

    setState(() {
      _sending = true;
      _error = null;
      _pendingMessageId = messageId;
      _pendingBody = body;
    });

    try {
      final message = await _repository.sendMessage(
        conversationId: widget.conversationId,
        messageId: messageId,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item.id == message.id);
        _messages.add(message);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _composer.clear();
        _pendingMessageId = null;
        _pendingBody = null;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Message not sent. Your text is saved here; tap Retry.';
      });
      return;
    }

    try {
      await _repository.markRead(widget.conversationId);
    } catch (_) {
      // The sent message is persisted; a later refresh can retry its receipt.
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isAdmin ? (widget.clientName ?? 'Client') : 'Message Admin'),
            const Text(
              'E-Relax Support',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Send a message to contact the E-Relax admin.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_loadingOlder && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        );
                      }
                      final messageIndex =
                          index - (_loadingOlder ? 1 : 0);
                      return _messageBubble(_messages[messageIndex]);
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  if (_pendingMessageId != null)
                    TextButton(
                      onPressed: _sending ? null : () => _send(retry: true),
                      child: const Text('Retry'),
                    )
                  else
                    TextButton(
                      onPressed: () => _refreshMessages(markRead: true),
                      child: const Text('Reload'),
                    ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _isAdmin
                            ? 'Write a reply to the client'
                            : 'Write a message to the admin',
                        border: OutlineInputBorder(),
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ClientAdminMessage message) {
    final mine = message.senderId == _userId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? AppTheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  mine ? 'Admin' : (widget.clientName ?? 'Client'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            SelectableText(message.body),
            const SizedBox(height: 4),
            Text(
              TimeOfDay.fromDateTime(message.createdAt.toLocal()).format(context),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
