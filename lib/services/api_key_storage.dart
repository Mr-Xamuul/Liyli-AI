import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_key_config.dart';
import 'supabase_config.dart';

class ApiKeyStorage {
  const ApiKeyStorage({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _apiKeysPrefKey = 'saved_ai_api_keys_v1';
  static const _legacyGoogleKeyMigrationKey =
      'saved_ai_api_keys_legacy_google_key_purged_v1';

  static final List<ApiKeyConfig> defaultSeedKeys = [
    ApiKeyConfig(
      id: 'default_key_google_gemini',
      name: 'Google Gemini API Key',
      provider: 'Google',
      apiKey: '',
      baseUrl: 'https://generativelanguage.googleapis.com',
      isActive: true,
      createdAt: DateTime.now(),
      notes: 'Furaha geli halkan, lagama horreysiinin code-ka.',
    ),
    ApiKeyConfig(
      id: 'default_key_groq',
      name: 'Groq Cloud API Key',
      provider: 'Groq',
      apiKey: '',
      baseUrl: 'https://api.groq.com/openai/v1',
      isActive: true,
      createdAt: DateTime.now(),
      notes: 'Groq ultra-fast Llama & Mixtral models',
    ),
    ApiKeyConfig(
      id: 'default_key_openai',
      name: 'OpenAI API Key',
      provider: 'OpenAI',
      apiKey: '',
      baseUrl: 'https://api.openai.com/v1',
      isActive: true,
      createdAt: DateTime.now(),
      notes: 'OpenAI GPT-4o & embeddings',
    ),
  ];

  Future<List<ApiKeyConfig>> getKeys() async {
    if (SupabaseConfig.isInitialized) {
      var remote = await _getRemoteKeys();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_apiKeysPrefKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final local = _decodeKeys(raw);
        var migratedAll = true;
        final remoteById = {for (final item in remote) item.id: item};
        for (final key in local.where(
          (item) => item.apiKey.trim().isNotEmpty,
        )) {
          if (remoteById[key.id]?.hasSecret == true) continue;
          try {
            await _saveRemoteKey(key);
          } catch (_) {
            migratedAll = false;
            break;
          }
        }
        if (migratedAll) await prefs.remove(_apiKeysPrefKey);
        remote = await _getRemoteKeys();
      }
      return remote.isEmpty ? defaultSeedKeys : remote;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_apiKeysPrefKey);
    if (raw == null || raw.trim().isEmpty) {
      await saveAll(defaultSeedKeys);
      await prefs.setBool(_legacyGoogleKeyMigrationKey, true);
      return defaultSeedKeys;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final loadedKeys = list
          .map((item) => ApiKeyConfig.fromMap(item as Map<String, dynamic>))
          .toList();
      // Purge the legacy seeded credential once, while preserving the editable
      // API key entry for admins to replace it with their own key.
      if (!(prefs.getBool(_legacyGoogleKeyMigrationKey) ?? false)) {
        final keys = loadedKeys.map((key) {
          if (key.id == 'default_key_google_gemini' && key.apiKey.isNotEmpty) {
            return key.copyWith(apiKey: '');
          }
          return key;
        }).toList();
        if (keys.any(
          (key) => key.id == 'default_key_google_gemini' && key.apiKey.isEmpty,
        )) {
          await saveAll(keys);
        }
        await prefs.setBool(_legacyGoogleKeyMigrationKey, true);
        return keys;
      }
      return loadedKeys;
    } catch (_) {
      await prefs.setBool(_legacyGoogleKeyMigrationKey, true);
      return defaultSeedKeys;
    }
  }

  Future<void> saveAll(List<ApiKeyConfig> keys) async {
    if (SupabaseConfig.isInitialized) {
      for (final key in keys) {
        await _saveRemoteKey(key);
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(keys.map((k) => k.toMap()).toList());
    await prefs.setString(_apiKeysPrefKey, raw);
  }

  Future<void> saveKey(ApiKeyConfig key) async {
    if (SupabaseConfig.isInitialized) {
      await _saveRemoteKey(key);
      return;
    }
    final current = await getKeys();
    final idx = current.indexWhere((k) => k.id == key.id);
    if (idx >= 0) {
      current[idx] = key;
    } else {
      current.insert(0, key);
    }
    await saveAll(current);
  }

  Future<void> deleteKey(String id) async {
    if (SupabaseConfig.isInitialized) {
      await SupabaseConfig.client.functions.invoke(
        'ai-gateway',
        body: {'action': 'delete_key', 'id': id},
      );
      return;
    }
    final current = await getKeys();
    current.removeWhere((k) => k.id == id);
    await saveAll(current);
  }

  Future<ApiKeyConfig?> getKeyById(String id) async {
    final current = await getKeys();
    return current.where((k) => k.id == id).firstOrNull;
  }

  /// Verify connection for a specific API Key
  Future<({bool success, String message})> verifyApiKey(
    ApiKeyConfig keyConfig,
  ) async {
    if (SupabaseConfig.isInitialized) {
      try {
        final response = await SupabaseConfig.client.functions.invoke(
          'ai-gateway',
          body: {'action': 'verify_key', 'id': keyConfig.id},
        );
        final data = response.data as Map<String, dynamic>;
        return (
          success: data['success'] == true,
          message:
              data['message']?.toString() ??
              'Xaqiijinta furaha way fashilantay.',
        );
      } catch (error) {
        return (
          success: false,
          message: 'Xaqiijinta server-ka way fashilantay: $error',
        );
      }
    }
    final client = _client ?? http.Client();
    final provider = keyConfig.provider.trim().toLowerCase();
    final key = keyConfig.apiKey.trim();

    if (key.isEmpty) {
      return (
        success: false,
        message: 'Furaha API-ga waa eber (Empty). Fadlan geli furaha saxda ah.',
      );
    }

    try {
      if (provider.contains('google')) {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$key',
        );
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          return (
            success: true,
            message: 'Furaha Google Gemini waa mid sax ah oo diyaar ah!',
          );
        } else {
          String err = 'Error ${response.statusCode}';
          try {
            final data = jsonDecode(response.body);
            err = data['error']?['message'] ?? err;
          } catch (_) {}
          return (success: false, message: 'Xaqiijintu way fashilantay: $err');
        }
      } else {
        // OpenAI / Groq / OpenAI-compatible
        final baseUrl = keyConfig.baseUrl.trim().isNotEmpty
            ? keyConfig.baseUrl.trim()
            : (provider.contains('groq')
                  ? 'https://api.groq.com/openai/v1'
                  : 'https://api.openai.com/v1');

        final uri = Uri.parse(
          baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models',
        );

        final response = await client
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          return (
            success: true,
            message: 'Furaha ${keyConfig.name} waa mid sax ah oo firfircoon!',
          );
        } else {
          String err = 'HTTP ${response.statusCode}';
          try {
            final data = jsonDecode(response.body);
            err = data['error']?['message'] ?? err;
          } catch (_) {}
          return (
            success: false,
            message: 'Xiriirka furaha wuu fashilmay: $err',
          );
        }
      }
    } catch (e) {
      return (success: false, message: 'Khalad xagga xiriirka ah: $e');
    }
  }

  Future<List<ApiKeyConfig>> _getRemoteKeys() async {
    final response = await SupabaseConfig.client.functions.invoke(
      'ai-gateway',
      body: const {'action': 'list_keys'},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = data['keys'] as List<dynamic>? ?? const [];
    return rows.whereType<Map<String, dynamic>>().map((row) {
      return ApiKeyConfig(
        id: row['id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        provider: row['provider'] as String? ?? 'Google',
        apiKey: '',
        baseUrl: row['base_url'] as String? ?? '',
        isActive: row['is_active'] as bool? ?? true,
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now(),
        notes: row['notes'] as String? ?? '',
        hasSecret: row['has_secret'] as bool? ?? false,
      );
    }).toList();
  }

  Future<void> _saveRemoteKey(ApiKeyConfig key) async {
    await SupabaseConfig.client.functions.invoke(
      'ai-gateway',
      body: {
        'action': 'save_key',
        'key': {
          'id': key.id,
          'name': key.name,
          'provider': key.provider,
          'apiKey': key.apiKey,
          'baseUrl': key.baseUrl,
          'isActive': key.isActive,
          'notes': key.notes,
        },
      },
    );
  }

  List<ApiKeyConfig> _decodeKeys(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => ApiKeyConfig.fromMap(item as Map<String, dynamic>))
        .toList();
  }
}
