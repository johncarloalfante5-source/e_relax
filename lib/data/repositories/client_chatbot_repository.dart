import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_client_provider.dart';
import '../../models/client_chat_message.dart';

class ClientChatbotException implements Exception {
  const ClientChatbotException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

class ClientChatbotRepository {
  ClientChatbotRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientProvider.client;

  final SupabaseClient _client;

  Future<String> reply({
    required String message,
    required List<ClientChatMessage> history,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'client-chatbot',
        body: {
          'message': message,
          'history': history
              .map(
                (turn) => {
                  'role': turn.isAssistant ? 'model' : 'user',
                  'text': turn.text,
                },
              )
              .toList(growable: false),
        },
      );

      final data = response.data;
      if (data is Map && data['reply'] is String) {
        final text = (data['reply'] as String).trim();
        if (text.isNotEmpty) return text;
      }
      if (data is Map && data['error'] is String) {
        throw ClientChatbotException(
          data['error'] as String,
          retryable: data['retryable'] == true,
        );
      }
      throw const ClientChatbotException(
        'The assistant returned an unexpected response. Please try again.',
        retryable: true,
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw ClientChatbotException(
          details['error'] as String,
          retryable: details['retryable'] == true || error.status >= 500,
        );
      }
      throw ClientChatbotException(
        error.status == 401
            ? 'Please sign in again to use the assistant.'
            : 'The assistant is unavailable right now. Please try again.',
        retryable: error.status >= 500 || error.status == 429,
      );
    } on ClientChatbotException {
      rethrow;
    } catch (_) {
      throw const ClientChatbotException(
        'Could not connect to the assistant. Please try again.',
        retryable: true,
      );
    }
  }
}
