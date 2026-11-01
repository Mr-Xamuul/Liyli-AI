import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'ai_routing_storage.dart';
import 'form_preference_storage.dart';
import 'supabase_config.dart';

/// UserAuthService
/// Manages local Google authentication state, student profiles, and multi-account switching.
/// Automatically synchronizes student subscription (Free vs Paid Tier) with App Routing.
class UserAuthService {
  UserAuthService._();
  static final UserAuthService instance = UserAuthService._();

  static const String _activeUserIdKey = 'leyli_active_user_id_v2';
  static const String _allUsersKey = 'leyli_all_user_profiles_v2';

  final ValueNotifier<UserProfile?> currentUserNotifier =
      ValueNotifier<UserProfile?>(null);
  final ValueNotifier<List<UserProfile>> savedAccountsNotifier =
      ValueNotifier<List<UserProfile>>([]);

  bool _initialized = false;

  bool get isLoggedIn => currentUserNotifier.value != null;
  bool get usesSupabase => SupabaseConfig.isInitialized;
  UserProfile? get currentUser => currentUserNotifier.value;
  String? get currentUserId => currentUserNotifier.value?.id;
  List<UserProfile> get savedAccounts => savedAccountsNotifier.value;

  /// Synchronize active user subscription with App Routing's activeTier ('free' vs 'paid')
  Future<void> syncTierWithRouting() async {
    // AI routing is shared admin configuration in Supabase. A student's
    // subscription state must not overwrite that global record.
    if (SupabaseConfig.isInitialized) return;
    try {
      final user = currentUserNotifier.value;
      const routingStorage = AiRoutingStorage();
      final config = await routingStorage.getConfig();
      final targetTier = (user != null && user.isSubscriptionActive)
          ? 'paid'
          : 'free';
      if (config.activeTier != targetTier) {
        await routingStorage.saveConfig(
          config.copyWith(activeTier: targetTier),
        );
      }
    } catch (_) {}
  }

  /// Initialize and load saved accounts from local storage
  Future<void> init() async {
    if (_initialized) return;
    if (SupabaseConfig.isInitialized) {
      _initialized = true;
      await _restoreSupabaseSession();
      SupabaseConfig.client.auth.onAuthStateChange.listen((_) {
        _restoreSupabaseSession();
      });
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final allRaw = prefs.getString(_allUsersKey);
      final activeId = prefs.getString(_activeUserIdKey);

      List<UserProfile> loadedProfiles = [];
      if (allRaw != null && allRaw.isNotEmpty) {
        final list = jsonDecode(allRaw) as List<dynamic>;
        loadedProfiles = list
            .map((item) => UserProfile.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      savedAccountsNotifier.value = loadedProfiles;

      if (activeId != null && loadedProfiles.isNotEmpty) {
        try {
          final active = loadedProfiles.firstWhere((p) => p.id == activeId);
          currentUserNotifier.value = active;
        } catch (_) {
          currentUserNotifier.value = loadedProfiles.first;
        }
      } else if (loadedProfiles.isNotEmpty) {
        currentUserNotifier.value = loadedProfiles.first;
      }

      await syncTierWithRouting();
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing UserAuthService: $e');
      _initialized = true;
    }
  }

  Future<bool> signInWithGoogle() async {
    if (!SupabaseConfig.isInitialized) {
      throw StateError(
        'Supabase lama habeyn. Ku bilow app-ka supabase.dev.json.',
      );
    }
    return SupabaseConfig.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.flutter://login-callback/',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  Future<void> _restoreSupabaseSession() async {
    final authUser = SupabaseConfig.client.auth.currentUser;
    if (authUser == null) {
      currentUserNotifier.value = null;
      savedAccountsNotifier.value = const [];
      await syncTierWithRouting();
      return;
    }

    try {
      Map<String, dynamic>? profile;
      try {
        profile = await SupabaseConfig.client
            .from('profiles')
            .select('id,email,display_name,selected_form,created_at')
            .eq('id', authUser.id)
            .maybeSingle();
      } catch (e) {
        // Keep the authenticated session usable even if the profile row is
        // temporarily unavailable; the profile can be repaired below.
        debugPrint('Could not load Supabase profile; using auth metadata: $e');
      }
      final metadata = authUser.userMetadata ?? const <String, dynamic>{};
      final values =
          profile ??
          {
            'id': authUser.id,
            'email': authUser.email,
            'display_name':
                metadata['full_name'] ?? metadata['name'] ?? 'Arday',
            'selected_form': 'Form 1',
            'created_at': authUser.createdAt,
          };
      if (profile == null) {
        try {
          await SupabaseConfig.client.from('profiles').upsert({
            'id': authUser.id,
            'email': authUser.email,
            'display_name': values['display_name'],
            'selected_form': 'Form 1',
            'role': 'student',
          });
        } catch (e) {
          debugPrint('Could not create Supabase profile: $e');
        }
      }
      final now = DateTime.now();
      final user = UserProfile(
        id: authUser.id,
        email: (values['email'] as String?) ?? authUser.email ?? '',
        displayName: (values['display_name'] as String?) ?? 'Arday',
        selectedForm: (values['selected_form'] as String?) ?? 'Form 1',
        createdAt: DateTime.tryParse('${values['created_at']}') ?? now,
        lastLoginAt: now,
        avatarColorValue: _generateColorForEmail(authUser.email ?? authUser.id),
        photoUrl: metadata['avatar_url'] as String?,
      );
      currentUserNotifier.value = user;
      savedAccountsNotifier.value = [user];
      await const FormPreferenceStorage().setSelectedForm(user.selectedForm);
      await syncTierWithRouting();
    } catch (e) {
      debugPrint('Error loading Supabase user profile: $e');
    }
  }

  /// Sign in or register a Google account locally
  Future<UserProfile> registerOrSignInGoogle({
    required String email,
    required String displayName,
    String? photoUrl,
    String? form,
    int? avatarColor,
  }) async {
    if (SupabaseConfig.isInitialized) {
      final current = currentUserNotifier.value;
      if (current == null) {
        throw StateError(
          'Marka hore ku soo gal Google si profile-ka loo kaydiyo.',
        );
      }
      await updateCurrentProfile(
        displayName: displayName,
        selectedForm: form,
        photoUrl: photoUrl,
      );
      return currentUserNotifier.value!;
    }
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim().isEmpty ? 'Arday' : displayName.trim();
    final chosenForm = form ?? 'Form 1';

    final accounts = List<UserProfile>.from(savedAccountsNotifier.value);
    final existingIndex = accounts.indexWhere(
      (a) => a.email.toLowerCase() == cleanEmail,
    );

    UserProfile user;
    if (existingIndex >= 0) {
      final existing = accounts[existingIndex];
      user = existing.copyWith(
        displayName: cleanName,
        photoUrl: photoUrl ?? existing.photoUrl,
        selectedForm: form ?? existing.selectedForm,
        lastLoginAt: DateTime.now(),
      );
      accounts[existingIndex] = user;
    } else {
      final color = avatarColor ?? _generateColorForEmail(cleanEmail);
      final id =
          'google_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      user = UserProfile(
        id: id,
        email: cleanEmail,
        displayName: cleanName,
        photoUrl: photoUrl,
        avatarColorValue: color,
        selectedForm: chosenForm,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      accounts.insert(0, user);
    }

    await _persistAccounts(accounts, activeUserId: user.id);

    // Sync active Form preference
    await const FormPreferenceStorage().setSelectedForm(user.selectedForm);

    currentUserNotifier.value = user;
    savedAccountsNotifier.value = accounts;

    await syncTierWithRouting();
    return user;
  }

  /// Switch the active student account locally
  Future<void> switchAccount(String userId) async {
    if (SupabaseConfig.isInitialized) return;
    final accounts = savedAccountsNotifier.value;
    try {
      final target = accounts.firstWhere((a) => a.id == userId);
      final updated = target.copyWith(lastLoginAt: DateTime.now());
      final index = accounts.indexWhere((a) => a.id == userId);
      final updatedList = List<UserProfile>.from(accounts);
      if (index >= 0) {
        updatedList[index] = updated;
      }
      await _persistAccounts(updatedList, activeUserId: userId);

      await const FormPreferenceStorage().setSelectedForm(updated.selectedForm);

      currentUserNotifier.value = updated;
      savedAccountsNotifier.value = updatedList;

      await syncTierWithRouting();
    } catch (_) {}
  }

  /// Update the current active profile (e.g. change name, class/form, avatar)
  Future<void> updateCurrentProfile({
    String? displayName,
    String? selectedForm,
    int? avatarColorValue,
    String? photoUrl,
  }) async {
    final current = currentUserNotifier.value;
    if (current == null) return;

    if (SupabaseConfig.isInitialized) {
      await SupabaseConfig.client
          .from('profiles')
          .update({
            if (displayName case final value?) 'display_name': value,
            if (selectedForm case final value?) 'selected_form': value,
          })
          .eq('id', current.id);
    }

    final updated = current.copyWith(
      displayName: displayName ?? current.displayName,
      selectedForm: selectedForm ?? current.selectedForm,
      avatarColorValue: avatarColorValue ?? current.avatarColorValue,
      photoUrl: photoUrl ?? current.photoUrl,
    );

    final accounts = List<UserProfile>.from(savedAccountsNotifier.value);
    final index = accounts.indexWhere((a) => a.id == current.id);
    if (index >= 0) {
      accounts[index] = updated;
    } else {
      accounts.add(updated);
    }

    await _persistAccounts(accounts, activeUserId: updated.id);

    if (selectedForm != null) {
      await const FormPreferenceStorage().setSelectedForm(selectedForm);
    }

    currentUserNotifier.value = updated;
    savedAccountsNotifier.value = accounts;
    await syncTierWithRouting();
  }

  /// Update any user profile directly (e.g. from Admin Dashboard)
  Future<void> updateUser(UserProfile user) async {
    if (SupabaseConfig.isInitialized) {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .update({
            'display_name': user.displayName,
            'selected_form': user.selectedForm,
          })
          .eq('id', user.id)
          .select('id');
      if (rows.isEmpty) {
        throw StateError(
          'Profile-ka ardayga lama helin ama lama cusboonaysiin.',
        );
      }
    }

    final accounts = List<UserProfile>.from(savedAccountsNotifier.value);
    final index = accounts.indexWhere((a) => a.id == user.id);
    if (index >= 0) {
      accounts[index] = user;
    } else {
      accounts.add(user);
    }

    final isActive = currentUserNotifier.value?.id == user.id;
    await _persistAccounts(
      accounts,
      activeUserId: isActive ? user.id : currentUserNotifier.value?.id,
    );

    if (isActive) {
      currentUserNotifier.value = user;
      await const FormPreferenceStorage().setSelectedForm(user.selectedForm);
      await syncTierWithRouting();
    }
    savedAccountsNotifier.value = accounts;
  }

  /// Activate student Paid Tier subscription
  Future<void> activateSubscription({
    required String userId,
    required String planName,
    required String paymentMethod,
    String? paymentPhone,
    int durationDays = 30,
  }) async {
    final accounts = List<UserProfile>.from(savedAccountsNotifier.value);
    final index = accounts.indexWhere((a) => a.id == userId);
    if (index < 0) return;

    final target = accounts[index];
    final updated = target.copyWith(
      isPaid: true,
      planName: planName,
      paymentMethod: paymentMethod,
      paymentPhone: paymentPhone,
      paidAt: DateTime.now(),
      subscriptionExpiresAt: DateTime.now().add(Duration(days: durationDays)),
    );
    accounts[index] = updated;

    final isActive = currentUserNotifier.value?.id == userId;
    await _persistAccounts(
      accounts,
      activeUserId: isActive ? userId : currentUserNotifier.value?.id,
    );

    if (isActive) {
      currentUserNotifier.value = updated;
      await syncTierWithRouting();
    }
    savedAccountsNotifier.value = accounts;
  }

  /// Cancel or revoke student Paid Tier subscription
  Future<void> cancelSubscription(String userId) async {
    final accounts = List<UserProfile>.from(savedAccountsNotifier.value);
    final index = accounts.indexWhere((a) => a.id == userId);
    if (index < 0) return;

    final target = accounts[index];
    final updated = target.copyWith(
      isPaid: false,
      planName: null,
      paymentMethod: null,
      subscriptionExpiresAt: DateTime.now().subtract(
        const Duration(seconds: 1),
      ),
    );
    accounts[index] = updated;

    final isActive = currentUserNotifier.value?.id == userId;
    await _persistAccounts(
      accounts,
      activeUserId: isActive ? userId : currentUserNotifier.value?.id,
    );

    if (isActive) {
      currentUserNotifier.value = updated;
      await syncTierWithRouting();
    }
    savedAccountsNotifier.value = accounts;
  }

  /// Get a single user by ID
  Future<UserProfile?> getUserById(String id) async {
    final all = await getAllUsers();
    return all.where((u) => u.id == id).firstOrNull;
  }

  /// Get and reload all saved users
  Future<List<UserProfile>> getAllUsers() async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      if (client.auth.currentUser == null) return const [];

      final cachedUsers = <String, UserProfile>{
        for (final user in savedAccountsNotifier.value) user.id: user,
      };
      // Keep locally cached subscription fields until subscriptions receive
      // their own database schema; profile and class data come from Supabase.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedJson = prefs.getString(_allUsersKey);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final list = jsonDecode(cachedJson) as List<dynamic>;
          for (final item in list.whereType<Map<String, dynamic>>()) {
            final cached = UserProfile.fromJson(item);
            cachedUsers[cached.id] = cached;
          }
        }
      } catch (_) {}

      final rows = await client
          .from('profiles')
          .select('id,email,display_name,selected_form,created_at,role')
          .eq('role', 'student')
          .order('created_at', ascending: false);
      final users = rows.map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString() ?? '';
        final cached = cachedUsers[id];
        final email = row['email']?.toString() ?? cached?.email ?? '';
        final createdAt =
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            cached?.createdAt ??
            DateTime.now();
        return UserProfile(
          id: id,
          email: email,
          displayName:
              row['display_name']?.toString() ?? cached?.displayName ?? 'Arday',
          photoUrl: cached?.photoUrl,
          avatarColorValue:
              cached?.avatarColorValue ?? _generateColorForEmail(email),
          selectedForm: row['selected_form']?.toString() ?? 'Form 1',
          createdAt: createdAt,
          lastLoginAt: cached?.lastLoginAt ?? createdAt,
          isPaid: cached?.isPaid ?? false,
          planName: cached?.planName,
          paymentMethod: cached?.paymentMethod,
          paymentPhone: cached?.paymentPhone,
          paidAt: cached?.paidAt,
          subscriptionExpiresAt: cached?.subscriptionExpiresAt,
        );
      }).toList();
      savedAccountsNotifier.value = users;
      return users;
    }

    final prefs = await SharedPreferences.getInstance();
    final allRaw = prefs.getString(_allUsersKey);
    if (allRaw != null && allRaw.isNotEmpty) {
      try {
        final list = jsonDecode(allRaw) as List<dynamic>;
        final loaded = list
            .map((item) => UserProfile.fromJson(item as Map<String, dynamic>))
            .toList();
        savedAccountsNotifier.value = loaded;
        return loaded;
      } catch (_) {}
    }
    return savedAccountsNotifier.value;
  }

  /// Sign out current student account
  Future<void> signOut() async {
    if (SupabaseConfig.isInitialized) {
      await SupabaseConfig.client.auth.signOut();
    }
    currentUserNotifier.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeUserIdKey);
    await syncTierWithRouting();
  }

  /// Remove an account completely
  Future<void> removeAccount(String userId) async {
    final accounts = List<UserProfile>.from(savedAccountsNotifier.value)
      ..removeWhere((a) => a.id == userId);

    String? nextActiveId;
    UserProfile? nextUser;

    if (currentUserNotifier.value?.id == userId) {
      if (accounts.isNotEmpty) {
        nextUser = accounts.first;
        nextActiveId = nextUser.id;
      } else {
        nextUser = null;
        nextActiveId = null;
      }
    } else {
      nextUser = currentUserNotifier.value;
      nextActiveId = nextUser?.id;
    }

    await _persistAccounts(accounts, activeUserId: nextActiveId);
    currentUserNotifier.value = nextUser;
    savedAccountsNotifier.value = accounts;

    if (nextUser != null) {
      await const FormPreferenceStorage().setSelectedForm(
        nextUser.selectedForm,
      );
    }
    await syncTierWithRouting();
  }

  Future<void> _persistAccounts(
    List<UserProfile> accounts, {
    String? activeUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_allUsersKey, raw);
    if (activeUserId != null) {
      await prefs.setString(_activeUserIdKey, activeUserId);
    } else {
      await prefs.remove(_activeUserIdKey);
    }
  }

  int _generateColorForEmail(String email) {
    const colors = [
      0xFF1A73E8, // Google Blue
      0xFF34A853, // Google Green
      0xFFEA4335, // Google Red
      0xFFFBBC05, // Google Yellow
      0xFF673AB7, // Deep Purple
      0xFF009688, // Teal
      0xFFE91E63, // Pink
      0xFFFF6D00, // Deep Orange
    ];
    int hash = 0;
    for (int i = 0; i < email.length; i++) {
      hash = (hash + email.codeUnitAt(i)) % colors.length;
    }
    return colors[hash];
  }
}
