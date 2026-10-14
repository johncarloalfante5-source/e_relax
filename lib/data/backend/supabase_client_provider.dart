import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseClientProvider {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (url.isEmpty || publishableKey.isEmpty) {
      throw StateError(
        'Supabase is not configured. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY with --dart-define-from-file.',
      );
    }
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}
