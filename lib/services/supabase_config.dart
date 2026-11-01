import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client configuration supplied at build/run time.
///
/// Example:
/// flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
  static bool get isInitialized => _initialized;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || !isConfigured) return;
    // The SDK calls this argument anonKey; Supabase publishable keys are
    // accepted here as the client-side key value.
    await Supabase.initialize(url: url, anonKey: publishableKey);
    _initialized = true;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'Supabase is not initialized. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY when starting the app.',
      );
    }
    return Supabase.instance.client;
  }

  static void logConfigurationStatus() {
    if (!isConfigured) {
      debugPrint(
        'Supabase is not configured. Set SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY using --dart-define.',
      );
    }
  }
}
