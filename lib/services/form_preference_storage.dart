import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

/// Service to persist and retrieve the student's selected academic Form (Form 1 - Form 4)
class FormPreferenceStorage {
  const FormPreferenceStorage();

  static const _prefKey = 'leyli_selected_form_level_v1';
  static const defaultForm = 'Form 1';

  static const availableForms = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  /// Returns the stored Form, or 'Form 1' as default if not previously set
  Future<String> getSelectedForm() async {
    final prefs = await SharedPreferences.getInstance();
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return defaultForm;
      final userCacheKey = '${_prefKey}_${user.id}';
      try {
        final row = await SupabaseConfig.client
            .from('profiles')
            .select('selected_form')
            .eq('id', user.id)
            .maybeSingle();
        final remoteForm = row?['selected_form'] as String?;
        if (remoteForm != null && availableForms.contains(remoteForm)) {
          await prefs.setString(userCacheKey, remoteForm);
          return remoteForm;
        }
      } catch (_) {
        // Use this device's last known value if the profile is temporarily
        // unreachable. Supabase remains the source of truth when online.
      }
      return _getLocalForm(prefs, key: userCacheKey);
    }

    final val = prefs.getString(_prefKey);
    if (val != null && availableForms.contains(val)) {
      return val;
    }
    return defaultForm;
  }

  /// Persists the selected Form
  Future<void> setSelectedForm(String form) async {
    if (!availableForms.contains(form)) return;
    final prefs = await SharedPreferences.getInstance();
    if (SupabaseConfig.isInitialized) {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      await SupabaseConfig.client
          .from('profiles')
          .update({'selected_form': form})
          .eq('id', user.id);
      await prefs.setString('${_prefKey}_${user.id}', form);
      return;
    }
    await prefs.setString(_prefKey, form);
  }

  String _getLocalForm(SharedPreferences prefs, {required String key}) {
    final val = prefs.getString(key);
    return val != null && availableForms.contains(val) ? val : defaultForm;
  }
}
