import 'package:flutter/material.dart';

import '../../data/repositories/client_chatbot_repository.dart';
import '../../models/client_chat_message.dart';
import '../../theme/app_theme.dart';

class ClientChatScreen extends StatefulWidget {
  const ClientChatScreen({super.key});

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final _repository = ClientChatbotRepository();
  final List<ClientChatMessage> _messages = [];
  bool _sending = false;
  String? _error;
  bool _canRetry = false;
  String? _pendingMessage;
  List<ClientChatMessage> _pendingHistory = const [];

  static const _prompts = [
    'What massage services are available?',
    'How does the down payment work?',
    "What's my next booking?",
  ];

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit([String? suggested]) async {
    if (_sending) return;
    final message = (suggested ?? _composer.text).trim();
    if (message.isEmpty) return;
    final history = _messages.length <= 8
        ? List<ClientChatMessage>.of(_messages)
        : _messages.sublist(_messages.length - 8);

    setState(() {
      _composer.clear();
      _messages.add(ClientChatMessage(text: message, isAssistant: false));
      _pendingMessage = message;
      _pendingHistory = history;
      _error = null;
      _canRetry = false;
      _sending = true;
    });
    _scrollToBottom();
    await _requestReply(message, history);
  }

  Future<void> _retry() async {
    final message = _pendingMessage;
    if (message == null || _sending || !_canRetry) return;
    setState(() {
      _sending = true;
      _error = null;
      _canRetry = false;
    });
    await _requestReply(message, _pendingHistory);
  }

  Future<void> _requestReply(
    String message,
    List<ClientChatMessage> history,
  ) async {
    try {
      final answer = await _repository.reply(message: message, history: history);
      if (!mounted) return;
      setState(() {
        _messages.add(ClientChatMessage(text: answer, isAssistant: true));
        _pendingMessage = null;
        _pendingHistory = const [];
        _sending = false;
      });
    } on ClientChatbotException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _canRetry = error.retryable;
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
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
        title: const Text('E-Relax Assistant'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        );
                      }
                      return _buildMessage(_messages[index]);
                    },
                  ),
          ),
          if (_error != null) _buildError(),
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
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Type your question about E-Relax',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : _submit,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 24),
      const Icon(Icons.spa_outlined, size: 42, color: AppTheme.primary),
      const SizedBox(height: 12),
      Text(
        'How can I help?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Type any question about services, therapist availability, bookings, payments, or your account.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      for (final prompt in _prompts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            onPressed: _sending ? null : () => _submit(prompt),
            child: Text(prompt),
          ),
        ),
    ],
  );

  Widget _buildMessage(ClientChatMessage message) {
    final alignment = message.isAssistant
        ? Alignment.centerLeft
        : Alignment.centerRight;
    final background = message.isAssistant
        ? Theme.of(context).colorScheme.surface
        : AppTheme.primaryContainer;
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(message.text),
      ),
    );
  }

  Widget _buildError() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(_error!, style: const TextStyle(color: AppTheme.error)),
        ),
        if (_canRetry)
          TextButton(onPressed: _retry, child: const Text('Retry')),
      ],
    ),
  );
}
