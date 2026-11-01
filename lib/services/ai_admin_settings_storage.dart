import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_key_config.dart';
import 'api_key_storage.dart';
import 'supabase_config.dart';

/// Persists non-secret AI administration settings to Supabase when configured.
/// API credentials are deliberately excluded and belong in the Edge Function
/// backed Vault flow.
class AiAdminSettingsStorage {
  const AiAdminSettingsStorage();

  bool get isCloudMode => SupabaseConfig.isInitialized;

  Future<String?> getString(String key) async {
    if (!isCloudMode) {
      return (await SharedPreferences.getInstance()).getString(key);
    }
    final client = SupabaseConfig.client;
    if (client.auth.currentSession == null) return null;
    final row = await client
        .from('ai_admin_settings')
        .select('setting_value')
        .eq('setting_key', key)
        .maybeSingle();
    final value = row?['setting_value'];
    if (value is String) {
      await _purgeLegacyLocalModelSecrets(key, value);
      return value;
    }
    if (value != null) return value.toString();
    return _migrateLegacyString(key);
  }

  Future<void> setString(String key, String value) async {
    if (!isCloudMode) {
      await (await SharedPreferences.getInstance()).setString(key, value);
      return;
    }
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Waa inaad gashaa akoonkaaga.');
    await client.from('ai_admin_settings').upsert({
      'setting_key': key,
      'setting_value': value,
      'updated_by': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool?> getBool(String key) async {
    if (!isCloudMode) {
      return (await SharedPreferences.getInstance()).getBool(key);
    }
    final value = await _getValue(key);
    return value is bool ? value : null;
  }

  Future<void> setBool(String key, bool value) async {
    if (!isCloudMode) {
      await (await SharedPreferences.getInstance()).setBool(key, value);
      return;
    }
    await _setValue(key, value);
  }

  Future<List<String>?> getStringList(String key) async {
    if (!isCloudMode) {
      return (await SharedPreferences.getInstance()).getStringList(key);
    }
    var value = await _getValue(key);
    if (value == null && await _isAdmin()) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(key);
      if (legacy != null) {
        await setStringList(key, legacy);
        await prefs.remove(key);
        value = legacy;
      }
    }
    return value is List ? value.map((item) => item.toString()).toList() : null;
  }

  Future<void> setStringList(String key, List<String> value) async {
    if (!isCloudMode) {
      await (await SharedPreferences.getInstance()).setStringList(key, value);
      return;
    }
    await _setValue(key, value);
  }

  Future<dynamic> _getValue(String key) async {
    final client = SupabaseConfig.client;
    if (client.auth.currentSession == null) return null;
    final row = await client
        .from('ai_admin_settings')
        .select('setting_value')
        .eq('setting_key', key)
        .maybeSingle();
    return row?['setting_value'];
  }

  Future<String?> _migrateLegacyString(String key) async {
    if (!await _isAdmin()) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    var valueToSave = raw;
    if (key == 'saved_ai_models_v1' || key == 'saved_tts_models_v1') {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        // First migrate saved API key records to the server-side vault.
        await const ApiKeyStorage().getKeys();
        final safeModels = <Map<String, dynamic>>[];
        for (final item in decoded.whereType<Map<String, dynamic>>()) {
          final model = Map<String, dynamic>.from(item);
          final inlineKey = model['apiKey']?.toString().trim() ?? '';
          if (inlineKey.isNotEmpty) {
            final keyId =
                (model['apiKeyId']?.toString().trim().isNotEmpty ?? false)
                ? model['apiKeyId'].toString()
                : 'migrated_${model['id']}';
            await const ApiKeyStorage().saveKey(
              ApiKeyConfig(
                id: keyId,
                name: '${model['displayName'] ?? model['modelId'] ?? 'AI'} key',
                provider: model['company']?.toString() ?? 'Google',
                apiKey: inlineKey,
                baseUrl: model['baseUrl']?.toString() ?? '',
                isActive: model['isActive'] as bool? ?? true,
                createdAt:
                    DateTime.tryParse(model['createdAt']?.toString() ?? '') ??
                    DateTime.now(),
                notes: 'Furaha waxaa laga raray model-ka AI Manage.',
                hasSecret: true,
              ),
            );
            model['apiKeyId'] = keyId;
          }
          model['apiKey'] = '';
          safeModels.add(model);
        }
        valueToSave = jsonEncode(safeModels);
      } catch (error) {
        throw StateError('Dejinta AI-ga maxalliga ah lama rari karin: $error');
      }
    }

    // Write the sanitized value remotely before removing the local copy.
    await setString(key, valueToSave);
    await prefs.remove(key);
    return valueToSave;
  }

  Future<void> _purgeLegacyLocalModelSecrets(
    String key,
    String cloudValue,
  ) async {
    if (key != 'saved_ai_models_v1' && key != 'saved_tts_models_v1') return;
    if (!await _isAdmin()) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final localModels = jsonDecode(raw) as List<dynamic>;
      final cloudModels = jsonDecode(cloudValue) as List<dynamic>;
      final cloudById = <String, Map<String, dynamic>>{
        for (final item in cloudModels.whereType<Map<String, dynamic>>())
          item['id']?.toString() ?? '': Map<String, dynamic>.from(item),
      };
      var cloudChanged = false;
      for (final item in localModels.whereType<Map<String, dynamic>>()) {
        final model = Map<String, dynamic>.from(item);
        final inlineKey = model['apiKey']?.toString().trim() ?? '';
        final modelId = model['id']?.toString() ?? '';
        final keyId = (model['apiKeyId']?.toString().trim().isNotEmpty ?? false)
            ? model['apiKeyId'].toString()
            : 'migrated_$modelId';
        if (inlineKey.isNotEmpty) {
          final storedKey = await const ApiKeyStorage().getKeyById(keyId);
          if (storedKey?.hasSecret != true) {
            await const ApiKeyStorage().saveKey(
              ApiKeyConfig(
                id: keyId,
                name: '${model['displayName'] ?? model['modelId'] ?? 'AI'} key',
                provider: model['company']?.toString() ?? 'Google',
                apiKey: inlineKey,
                baseUrl: model['baseUrl']?.toString() ?? '',
                isActive: model['isActive'] as bool? ?? true,
                createdAt:
                    DateTime.tryParse(model['createdAt']?.toString() ?? '') ??
                    DateTime.now(),
                notes: 'Furaha waxaa laga raray dejintii maxalliga ahayd.',
                hasSecret: true,
              ),
            );
          }
          model['apiKeyId'] = keyId;
          model['apiKey'] = '';
        }
        final cloudModel = cloudById[modelId];
        if (cloudModel == null) {
          cloudById[modelId] = model;
          cloudChanged = true;
        } else if (inlineKey.isNotEmpty && cloudModel['apiKeyId'] == null) {
          cloudModel['apiKeyId'] = keyId;
          cloudModel['apiKey'] = '';
          cloudChanged = true;
        }
      }
      if (cloudChanged) {
        await setString(key, jsonEncode(cloudById.values.toList()));
      }
      await prefs.remove(key);
    } catch (error) {
      throw StateError(
        'Furayaasha AI-ga maxalliga ah lama nadiifin karin: $error',
      );
    }
  }

  Future<bool> _isAdmin() async {
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;
    if (user == null) return false;
    final row = await client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    return row?['role'] == 'admin';
  }

  Future<void> _setValue(String key, dynamic value) async {
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Waa inaad gashaa akoonkaaga.');
    await client.from('ai_admin_settings').upsert({
      'setting_key': key,
      'setting_value': value,
      'updated_by': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
