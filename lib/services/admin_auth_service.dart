import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

/// AdminAuthService
/// Handles local admin authentication state and role permissions.
/// Designed to seamlessly connect with future remote database/backend auth (Firebase/Supabase/REST).
class AdminAuthService {
  AdminAuthService._();
  static final AdminAuthService instance = AdminAuthService._();

  static const String _storageKeyIsAdmin = 'leyli_is_admin_mode';
  static const String _storageKeyAdminName = 'leyli_admin_name';

  final ValueNotifier<bool> isAdminNotifier = ValueNotifier<bool>(true);

  String _adminName = 'Admin / Tafatire';
  final String _adminRole = 'Super Admin';
  bool _initialized = false;

  bool get isAdmin => isAdminNotifier.value;
  String get adminName => _adminName;
  String get adminRole => _adminRole;

  /// Permissions list ready for future database role-based access control (RBAC)
  final Set<String> _permissions = {
    'manage_books',
    'edit_markers',
    'manage_ai_models',
    'access_editor',
    'publish_content',
  };

  /// Initialize from local preferences
  Future<void> init() async {
    if (_initialized) return;
    if (SupabaseConfig.isInitialized) {
      isAdminNotifier.value = await _hasSupabaseAdminRole();
      SupabaseConfig.client.auth.onAuthStateChange.listen((_) async {
        isAdminNotifier.value = await _hasSupabaseAdminRole();
      });
      _initialized = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAdmin =
          prefs.getBool(_storageKeyIsAdmin) ??
          true; // Default true for local development
      final savedName = prefs.getString(_storageKeyAdminName);
      if (savedName != null && savedName.isNotEmpty) {
        _adminName = savedName;
      }
      isAdminNotifier.value = savedAdmin;
      _initialized = true;
    } catch (_) {
      isAdminNotifier.value = true;
    }
  }

  /// Toggle admin mode (useful for testing admin vs normal student view locally)
  Future<void> toggleAdminMode() async {
    await setAdminMode(!isAdminNotifier.value);
  }

  /// Explicitly set admin status
  Future<void> setAdminMode(bool enabled) async {
    if (SupabaseConfig.isInitialized) {
      isAdminNotifier.value = enabled && await _hasSupabaseAdminRole();
      return;
    }
    isAdminNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKeyIsAdmin, enabled);
    } catch (_) {}
  }

  /// Update admin display name
  Future<void> setAdminName(String name) async {
    _adminName = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKeyAdminName, name);
    } catch (_) {}
  }

  /// Check permission for fine-grained authorization
  bool hasPermission(String permission) {
    if (!isAdmin) return false;
    return _permissions.contains(permission);
  }

  /// Hook for future remote database login
  Future<bool> loginWithCredentials({
    required String emailOrUsername,
    required String password,
  }) async {
    if (SupabaseConfig.isInitialized) {
      final allowed = await _hasSupabaseAdminRole();
      isAdminNotifier.value = allowed;
      return allowed;
    }
    // Local mock for now. When database is connected, query users collection / auth endpoint.
    await setAdminMode(true);
    return true;
  }

  /// Hook for logout
  Future<void> logout() async {
    await setAdminMode(false);
  }

  Future<bool> _hasSupabaseAdminRole() async {
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;
    if (user == null) return false;
    try {
      final row = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return row?['role'] == 'admin';
    } catch (error) {
      debugPrint('Could not verify Supabase admin role: $error');
      return false;
    }
  }
}
