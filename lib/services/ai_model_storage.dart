import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/api_key_config.dart';
import '../models/ai_model_config.dart';
import 'ai_admin_settings_storage.dart';
import 'ai_api_key_resolver.dart';
import 'ai_gateway_client.dart';
import 'api_key_storage.dart';
import 'supabase_config.dart';

class AiModelStorage {
  const AiModelStorage({http.Client? client}) : _client = client;

  final http.Client? _client;
  final AiAdminSettingsStorage _settings = const AiAdminSettingsStorage();

  static const _modelsKey = 'saved_ai_models_v1';
  static const _modelsLegacyKeyMigrationKey =
      'saved_ai_models_legacy_google_key_purged_v1';
  static const _selectedModelIdKey = 'selected_ai_model_id_v1';
  static const _companiesKey = 'registered_ai_companies_v1';
  static const _ttsModelsKey = 'saved_tts_models_v1';
  static const _ttsLegacyKeyMigrationKey =
      'saved_tts_models_legacy_google_key_purged_v1';
  static const _selectedTtsModelIdKey = 'selected_tts_model_id_v1';

  static const List<String> defaultCompanies = [
    'Google',
    'OpenAI',
    'Groq',
    'DeepSeek',
    'Anthropic',
    'Mistral AI',
    'Meta / Llama',
    'Cohere',
  ];

  static final List<AiModelConfig> defaultSeedTtsModels = [
    AiModelConfig(
      id: 'default_gemini_3_8_flash_tts',
      displayName: 'Gemini 3.8 Flash TTS',
      modelId: 'gemini-3.8-flash-tts',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: '',
      company: 'Google',
      isFree: true,
      isVerified: true,
      isActive: true,
      createdAt: DateTime.now(),
      status: 'ready',
      isTts: true,
    ),
    AiModelConfig(
      id: 'default_gemini_3_8_flash_lite_tts',
      displayName: 'Gemini 3.8 Flash Lite TTS',
      modelId: 'gemini-3.8-flash-lite-tts',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: '',
      company: 'Google',
      isFree: true,
      isVerified: true,
      isActive: true,
      createdAt: DateTime.now(),
      status: 'ready',
      isTts: true,
    ),
    AiModelConfig(
      id: 'default_gemini_3_1_flash_tts_preview',
      displayName: 'Gemini 3.1 Flash TTS Preview',
      modelId: 'gemini-3.1-flash-tts-preview',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: '',
      company: 'Google',
      isFree: true,
      isVerified: true,
      isActive: true,
      createdAt: DateTime.now(),
      status: 'ready',
      isTts: true,
    ),
  ];

  static final List<AiModelConfig> defaultSeedModels = [
    AiModelConfig(
      id: 'default_gemini_2_5_flash',
      displayName: 'Gemini 2.5 Flash',
      modelId: 'gemini-2.5-flash',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: '',
      company: 'Google',
      isFree: true,
      isVerified: true,
      isActive: true,
      createdAt: DateTime.now(),
    ),
    AiModelConfig(
      id: 'default_gemini_2_5_pro',
      displayName: 'Gemini 2.5 Pro',
      modelId: 'gemini-2.5-pro',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: '',
      company: 'Google',
      isFree: false,
      isVerified: true,
      isActive: true,
      createdAt: DateTime.now(),
    ),
    AiModelConfig(
      id: 'default_openai_gpt_4o_mini',
      displayName: 'GPT-4o Mini',
      modelId: 'gpt-4o-mini',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      company: 'OpenAI',
      isFree: true,
      isVerified: false,
      isActive: true,
      createdAt: DateTime.now(),
    ),
    AiModelConfig(
      id: 'default_groq_llama_3_3_70b',
      displayName: 'Llama 3.3 70B (Groq)',
      modelId: 'llama-3.3-70b-versatile',
      baseUrl: 'https://api.groq.com/openai/v1',
      apiKey: '',
      company: 'Groq',
      isFree: true,
      isVerified: false,
      isActive: true,
      createdAt: DateTime.now(),
    ),
    AiModelConfig(
      id: 'default_deepseek_chat',
      displayName: 'DeepSeek Chat (V3)',
      modelId: 'deepseek-chat',
      baseUrl: 'https://api.deepseek.com',
      apiKey: '',
      company: 'DeepSeek',
      isFree: true,
      isVerified: false,
      isActive: true,
      createdAt: DateTime.now(),
    ),
  ];

  /// Get list of models (loads defaults if none saved yet)
  Future<List<AiModelConfig>> getModels() async {
    final raw = await _settings.getString(_modelsKey);
    if (raw == null || raw.trim().isEmpty) {
      if (!_settings.isCloudMode) {
        await saveAll(defaultSeedModels);
        await _settings.setBool(_modelsLegacyKeyMigrationKey, true);
      }
      return defaultSeedModels;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final models = list
          .map((item) => AiModelConfig.fromMap(item as Map<String, dynamic>))
          .toList();
      return _removeLegacySeedKeys(
        models,
        _settings,
        _modelsKey,
        _modelsLegacyKeyMigrationKey,
      );
    } catch (_) {
      if (!_settings.isCloudMode) {
        await saveAll(defaultSeedModels);
        await _settings.setBool(_modelsLegacyKeyMigrationKey, true);
      }
      return defaultSeedModels;
    }
  }

  /// Save full list of models
  Future<void> saveAll(List<AiModelConfig> models) async {
    final safeModels = <AiModelConfig>[];
    for (final model in models) {
      safeModels.add(await _prepareModelForSave(model));
    }
    final raw = jsonEncode(safeModels.map((m) => m.toMap()).toList());
    await _settings.setString(_modelsKey, raw);
  }

  /// Insert or update a model
  Future<void> saveModel(AiModelConfig model) async {
    final current = await getModels();
    final index = current.indexWhere((m) => m.id == model.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    await saveAll(current);
  }

  /// Delete a model by ID
  Future<void> deleteModel(String id) async {
    final current = await getModels();
    current.removeWhere((m) => m.id == id);
    await saveAll(current);

    // If active model was deleted, clear or fallback
    final activeId = await getSelectedModelId();
    if (activeId == id && current.isNotEmpty) {
      await setSelectedModelId(current.first.id);
    }
  }

  /// Get the ID of the selected/active model for Chat
  Future<String?> getSelectedModelId() async {
    final id = await _settings.getString(_selectedModelIdKey);
    if (id != null && id.isNotEmpty) return id;

    // Default to the first active model
    final models = await getModels();
    final active = models.where((m) => m.isActive).firstOrNull;
    if (active != null) {
      if (!_settings.isCloudMode) await setSelectedModelId(active.id);
      return active.id;
    }
    return models.firstOrNull?.id;
  }

  /// Set the active model for Chat
  Future<void> setSelectedModelId(String id) async {
    await _settings.setString(_selectedModelIdKey, id);
  }

  /// Get the full active model configuration (only verified and active)
  Future<AiModelConfig?> getActiveModel() async {
    final models = await getModels();
    final activeId = await getSelectedModelId();
    if (activeId != null) {
      final found = models.where((m) => m.id == activeId).firstOrNull;
      if (found != null && found.isVerified && found.isActive) return found;
    }
    return models.where((m) => m.isActive && m.isVerified).firstOrNull;
  }

  // ==================== TTS / Voice Models Storage ====================

  /// Get list of TTS models (loads defaults if none saved yet)
  Future<List<AiModelConfig>> getTtsModels() async {
    final raw = await _settings.getString(_ttsModelsKey);
    if (raw == null || raw.trim().isEmpty) {
      if (!_settings.isCloudMode) {
        await saveAllTts(defaultSeedTtsModels);
        await _settings.setBool(_ttsLegacyKeyMigrationKey, true);
      }
      return defaultSeedTtsModels;
    }
    try {
      final list = jsonDecode(raw) as List;
      final models = list
          .map(
            (item) => AiModelConfig.fromMap(
              item as Map<String, dynamic>,
            ).copyWith(isTts: true),
          )
          .toList();
      return _removeLegacySeedKeys(
        models,
        _settings,
        _ttsModelsKey,
        _ttsLegacyKeyMigrationKey,
      );
    } catch (_) {
      if (!_settings.isCloudMode) {
        await _settings.setBool(_ttsLegacyKeyMigrationKey, true);
      }
      return defaultSeedTtsModels;
    }
  }

  /// Save all TTS models
  Future<void> saveAllTts(List<AiModelConfig> models) async {
    final safeModels = <AiModelConfig>[];
    for (final model in models) {
      safeModels.add(await _prepareModelForSave(model));
    }
    final raw = jsonEncode(safeModels.map((m) => m.toMap()).toList());
    await _settings.setString(_ttsModelsKey, raw);
  }

  Future<AiModelConfig> _prepareModelForSave(AiModelConfig model) async {
    if (!_settings.isCloudMode) return model;
    final inlineKey = model.apiKey.trim();
    if (inlineKey.isEmpty) return model.copyWith(apiKey: '');
    final keyId = model.apiKeyId?.trim().isNotEmpty == true
        ? model.apiKeyId!.trim()
        : 'model_${model.id}';
    await const ApiKeyStorage().saveKey(
      ApiKeyConfig(
        id: keyId,
        name: '${model.displayName} API key',
        provider: model.company,
        apiKey: inlineKey,
        baseUrl: model.baseUrl,
        isActive: model.isActive,
        createdAt: model.createdAt,
        notes: 'Furaha waxaa laga maamulaa model-ka AI Manage.',
        hasSecret: true,
      ),
    );
    return model.copyWith(apiKey: '', apiKeyId: keyId);
  }

  Future<List<AiModelConfig>> _removeLegacySeedKeys(
    List<AiModelConfig> models,
    AiAdminSettingsStorage settings,
    String storageKey,
    String migrationKey,
  ) async {
    if (settings.isCloudMode) {
      return models.map((model) {
        return model.apiKey.isEmpty ? model : model.copyWith(apiKey: '');
      }).toList();
    }
    if (await settings.getBool(migrationKey) ?? false) return models;
    var changed = false;
    final sanitized = models.map((model) {
      if ((model.id.startsWith('default_gemini_') ||
              model.apiKeyId == 'default_key_google_gemini') &&
          (model.apiKey.isNotEmpty || model.apiKeyId != null)) {
        changed = true;
        return AiModelConfig.fromMap({
          ...model.toMap(),
          'apiKey': '',
          'apiKeyId': null,
        });
      }
      return model;
    }).toList();
    if (changed) {
      await settings.setString(
        storageKey,
        jsonEncode(sanitized.map((model) => model.toMap()).toList()),
      );
    }
    await settings.setBool(migrationKey, true);
    return sanitized;
  }

  /// Save or update a single TTS model
  Future<void> saveTtsModel(AiModelConfig model) async {
    final current = await getTtsModels();
    final idx = current.indexWhere((m) => m.id == model.id);
    if (idx != -1) {
      current[idx] = model;
    } else {
      current.insert(0, model);
    }
    await saveAllTts(current);
  }

  /// Delete a TTS model
  Future<void> deleteTtsModel(String id) async {
    final current = await getTtsModels();
    current.removeWhere((m) => m.id == id);
    await saveAllTts(current);

    final selected = await getSelectedTtsModelId();
    if (selected == id) {
      final next = current.firstOrNull;
      await setSelectedTtsModelId(next?.id ?? '');
    }
  }

  /// Get currently selected TTS model id
  Future<String?> getSelectedTtsModelId() async {
    final id = await _settings.getString(_selectedTtsModelIdKey);
    final models = await getTtsModels();
    if (id != null && models.any((m) => m.id == id)) {
      return id;
    }
    final active = models.where((m) => m.isActive).firstOrNull;
    if (active != null) {
      if (!_settings.isCloudMode) {
        await _settings.setString(_selectedTtsModelIdKey, active.id);
      }
      return active.id;
    }
    return models.firstOrNull?.id;
  }

  /// Set the active model for TTS
  Future<void> setSelectedTtsModelId(String id) async {
    await _settings.setString(_selectedTtsModelIdKey, id);
  }

  /// Get active TTS model configuration
  Future<AiModelConfig?> getActiveTtsModel() async {
    final models = await getTtsModels();
    final selectedId = await getSelectedTtsModelId();
    if (selectedId != null) {
      final found = models.where((m) => m.id == selectedId).firstOrNull;
      if (found != null && found.isActive) return found;
    }
    return models.where((m) => m.isActive).firstOrNull;
  }

  /// Verify TTS model connection by requesting audio output ping
  Future<({bool success, String message})> verifyTtsModelConnection(
    AiModelConfig config,
  ) async {
    if (SupabaseConfig.isInitialized) {
      try {
        final safeConfig = await _prepareModelForSave(config);
        final keyId = safeConfig.apiKeyId;
        if (keyId == null || keyId.isEmpty) {
          return (success: false, message: 'Ku xidh API key-ga model-kan.');
        }
        return const AiGatewayClient().verifyModel(
          modelId: safeConfig.modelId,
          provider: safeConfig.company,
          baseUrl: safeConfig.baseUrl,
          apiKeyId: keyId,
          isTts: true,
        );
      } catch (error) {
        return (
          success: false,
          message: 'Tijaabada TTS way fashilantay: $error',
        );
      }
    }
    final client = _client ?? http.Client();
    final shouldClose = _client == null;

    try {
      final apiKey = await const AiApiKeyResolver().resolve(
        model: config,
        provider: config.company,
      );
      final modelId = config.modelId.trim();
      final baseUrl = config.baseUrl.trim().isNotEmpty
          ? config.baseUrl.trim()
          : 'https://generativelanguage.googleapis.com';

      if (apiKey.isEmpty) {
        return (
          success: false,
          message: 'Fadlan geli API Key-ga ka hor inta aan la hubin.',
        );
      }
      if (modelId.isEmpty) {
        return (
          success: false,
          message:
              'Fadlan geli Model ID-ga codka (tusaale: gemini-3.8-flash-tts).',
        );
      }

      final uri = Uri.parse(
        '$baseUrl/v1beta/models/$modelId:generateContent?key=$apiKey',
      );

      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Hello'},
                  ],
                },
              ],
              'generationConfig': {
                'responseModalities': ['AUDIO'],
                'speechConfig': {
                  'voiceConfig': {
                    'prebuiltVoiceConfig': {'voiceName': 'Puck'},
                  },
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (
          success: true,
          message: 'Codka $modelId wuu guuleystay! Model-ku wuu shaqeynayaa.',
        );
      } else {
        String detailMessage = '';
        try {
          final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
          detailMessage =
              errorJson['error']?['message']?.toString() ?? response.body;
        } catch (_) {
          detailMessage = response.body;
        }

        if (response.statusCode == 404) {
          return (
            success: false,
            message:
                'Model ID-ga lama helin (404): "$modelId". Hubi inuu yahay mid taageera codka sida gemini-3.8-flash-tts.',
          );
        }
        if (response.statusCode == 400 || response.statusCode == 403) {
          return (
            success: false,
            message:
                'API Key-ga ama model-ka lama aqbalin (${response.statusCode}): $detailMessage',
          );
        }
        return (
          success: false,
          message: 'Khalad (${response.statusCode}): $detailMessage',
        );
      }
    } on TimeoutException {
      return (
        success: false,
        message:
            'Waqtigu wuu dhacay (Timeout). Fadlan hubi khadkaaga internet-ka.',
      );
    } catch (e) {
      return (
        success: false,
        message: 'Xiriirka codka lama xaqiijin karo: ${e.toString()}',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  /// Get registered companies (built-in + user registered)
  Future<List<String>> getCompanies() async {
    final custom = await _settings.getStringList(_companiesKey) ?? [];
    final set = <String>{...defaultCompanies, ...custom};
    return set.toList();
  }

  /// Register a new AI company
  Future<void> addCompany(String companyName) async {
    final trimmed = companyName.trim();
    if (trimmed.isEmpty) return;

    final custom = await _settings.getStringList(_companiesKey) ?? [];
    if (!custom.contains(trimmed) && !defaultCompanies.contains(trimmed)) {
      custom.add(trimmed);
      await _settings.setStringList(_companiesKey, custom);
    }
  }

  /// Suggest a base URL for a given company
  static String suggestBaseUrl(String company) {
    final c = company.trim().toLowerCase();
    if (c.contains('google')) {
      return 'https://generativelanguage.googleapis.com';
    } else if (c.contains('openai')) {
      return 'https://api.openai.com/v1';
    } else if (c.contains('groq')) {
      return 'https://api.groq.com/openai/v1';
    } else if (c.contains('deepseek')) {
      return 'https://api.deepseek.com';
    } else if (c.contains('anthropic')) {
      return 'https://api.anthropic.com/v1';
    } else if (c.contains('mistral')) {
      return 'https://api.mistral.ai/v1';
    }
    return 'https://api.openai.com/v1';
  }

  /// Verify model connection by making a minimal test call
  Future<({bool success, String message})> verifyModelConnection(
    AiModelConfig config,
  ) async {
    if (SupabaseConfig.isInitialized) {
      try {
        final safeConfig = await _prepareModelForSave(config);
        final keyId = safeConfig.apiKeyId;
        if (keyId == null || keyId.isEmpty) {
          return (success: false, message: 'Ku xidh API key-ga model-kan.');
        }
        return const AiGatewayClient().verifyModel(
          modelId: safeConfig.modelId,
          provider: safeConfig.company,
          baseUrl: safeConfig.baseUrl,
          apiKeyId: keyId,
          isTts: false,
        );
      } catch (error) {
        return (
          success: false,
          message: 'Tijaabada model-ka way fashilantay: $error',
        );
      }
    }
    final client = _client ?? http.Client();
    final shouldClose = _client == null;

    try {
      final modelId = config.modelId.trim();
      var baseUrl = config.baseUrl.trim();

      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      if (modelId.isEmpty) {
        return (
          success: false,
          message: 'Fadlan geli Model ID-ga ka hor inta aan la hubin.',
        );
      }

      // 1. Google Gemini Provider
      if (!config.isOpenAiCompatible) {
        final effectiveApiKey = await const AiApiKeyResolver().resolve(
          model: config,
          provider: config.company,
        );
        if (effectiveApiKey.isEmpty) {
          return (
            success: false,
            message:
                'Fadlan geli API Key-ga Google Gemini ka hor inta aan la hubin.',
          );
        }

        final uri = Uri.parse(
          '$baseUrl/v1beta/models/$modelId:generateContent',
        );

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'x-goog-api-key': effectiveApiKey,
        };

        final response = await client
            .post(
              uri,
              headers: headers,
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': 'Ping'},
                    ],
                  },
                ],
                'generationConfig': {'maxOutputTokens': 5},
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return (
            success: true,
            message:
                'Xiriirka Google Gemini wuu guuleystay! Model-ku wuu shaqeynayaa.',
          );
        } else {
          String detailMessage = '';
          try {
            final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
            detailMessage =
                errorJson['error']?['message']?.toString() ?? response.body;
          } catch (_) {
            detailMessage = response.body;
          }

          if (response.statusCode == 503) {
            return (
              success: false,
              message:
                  'Model-ku hadda wuu mashquulsan yahay (503 High Demand). Fadlan dooro model kale oo deggan sida Gemini 2.5 Flash.',
            );
          }
          if (response.statusCode == 404) {
            return (
              success: false,
              message:
                  'Model ID-ga lama helin (404 Not Found): "$modelId". Hubi magaca saxda ah ee Google (tusaale: gemini-2.5-flash).',
            );
          }
          if (response.statusCode == 400 || response.statusCode == 403) {
            return (
              success: false,
              message:
                  'Furaha API ama Model-ka lama aqbalin (${response.statusCode}): $detailMessage',
            );
          }
          return (
            success: false,
            message: 'Khalad (${response.statusCode}): $detailMessage',
          );
        }
      }

      // 2. OpenAI-compatible Provider (OpenAI, Groq, DeepSeek, etc.)
      final effectiveApiKey = await const AiApiKeyResolver().resolve(
        model: config,
        provider: config.company,
      );
      if (effectiveApiKey.isEmpty) {
        return (
          success: false,
          message:
              'Fadlan geli API Key-ga ${config.company} ka hor inta aan la hubin.',
        );
      }

      final chatUrl = baseUrl.endsWith('/chat/completions')
          ? baseUrl
          : '$baseUrl/chat/completions';

      final uri = Uri.parse(chatUrl);
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $effectiveApiKey',
      };

      final response = await client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'model': modelId,
              'messages': [
                {'role': 'user', 'content': 'Ping'},
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (
          success: true,
          message:
              'Xiriirka ${config.company} wuu guuleystay! Model-ku waa diyaar.',
        );
      } else {
        String detailMessage = '';
        try {
          final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
          detailMessage =
              errorJson['error']?['message']?.toString() ?? response.body;
        } catch (_) {
          detailMessage = response.body;
        }

        if (response.statusCode == 401) {
          return (
            success: false,
            message:
                'API Key-ga lama aqbalin (401 Unauthorized). Hubi furaha ${config.company}.',
          );
        }
        if (response.statusCode == 404) {
          return (
            success: false,
            message:
                'Model ID-ga lama helin (404 Not Found): "$modelId". Hubi magaca saxda ah ee ${config.company}.',
          );
        }
        if (response.statusCode == 429) {
          return (
            success: false,
            message:
                'Xadkii codsiyada waa la gaaray (429 Rate Limit / Quota Exceeded).',
          );
        }
        return (
          success: false,
          message: 'Khalad (${response.statusCode}): $detailMessage',
        );
      }
    } on TimeoutException {
      return (
        success: false,
        message:
            'Waqtigu wuu dhacay (Timeout). Fadlan hubi khadka internet-ka ama URL-ka.',
      );
    } catch (e) {
      return (
        success: false,
        message: 'Xiriirka lama xaqiijin karo: ${e.toString()}',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  /// Transition model to Stage 2: Testing
  Future<void> sendModelToTesting(String modelId, {bool isTts = false}) async {
    final ttsList = await getTtsModels();
    final ttsIdx = ttsList.indexWhere((m) => m.id == modelId);
    if (isTts || ttsIdx >= 0) {
      if (ttsIdx >= 0) {
        ttsList[ttsIdx] = ttsList[ttsIdx].copyWith(
          status: 'testing',
          isTts: true,
        );
        await saveAllTts(ttsList);
        return;
      }
    }

    final list = await getModels();
    final idx = list.indexWhere((m) => m.id == modelId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(status: 'testing');
      await saveAll(list);
    }
  }

  /// Promote model to Stage 3: Ready / Approved
  Future<void> promoteModelToReady(String modelId, {bool isTts = false}) async {
    final ttsList = await getTtsModels();
    final ttsIdx = ttsList.indexWhere((m) => m.id == modelId);
    if (isTts || ttsIdx >= 0) {
      if (ttsIdx >= 0) {
        ttsList[ttsIdx] = ttsList[ttsIdx].copyWith(
          status: 'ready',
          isVerified: true,
          isActive: true,
          isTts: true,
        );
        await saveAllTts(ttsList);
        return;
      }
    }

    final list = await getModels();
    final idx = list.indexWhere((m) => m.id == modelId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(
        status: 'ready',
        isVerified: true,
        isActive: true,
      );
      await saveAll(list);
    }
  }

  /// Revert model back to Stage 1: Models (draft)
  Future<void> revertModelToDraft(String modelId, {bool isTts = false}) async {
    final ttsList = await getTtsModels();
    final ttsIdx = ttsList.indexWhere((m) => m.id == modelId);
    if (isTts || ttsIdx >= 0) {
      if (ttsIdx >= 0) {
        ttsList[ttsIdx] = ttsList[ttsIdx].copyWith(
          status: 'models',
          isTts: true,
        );
        await saveAllTts(ttsList);
        return;
      }
    }

    final list = await getModels();
    final idx = list.indexWhere((m) => m.id == modelId);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(status: 'models');
      await saveAll(list);
    }
  }
}
