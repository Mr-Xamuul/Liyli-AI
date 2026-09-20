import 'package:shared_preferences/shared_preferences.dart';

/// Service to persist and retrieve the student's selected academic Form (Form 1 - Form 4)
class FormPreferenceStorage {
  const FormPreferenceStorage();

  static const _prefKey = 'leyli_selected_form_level_v1';
  static const defaultForm = 'Form 1';

  static const availableForms = [
    'Form 1',
    'Form 2',
    'Form 3',
    'Form 4',
  ];

  /// Returns the stored Form, or 'Form 1' as default if not previously set
  Future<String> getSelectedForm() async {
    final prefs = await SharedPreferences.getInstance();
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
    await prefs.setString(_prefKey, form);
  }
}
