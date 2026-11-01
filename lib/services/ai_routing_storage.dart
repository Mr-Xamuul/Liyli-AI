import 'package:flutter/foundation.dart';

import '../models/ai_model_config.dart';
import '../models/ai_routing_config.dart';
import 'ai_admin_settings_storage.dart';
import 'ai_model_storage.dart';

class AiRoutingStorage {
  const AiRoutingStorage({AiModelStorage? modelStorage})
    : _modelStorage = modelStorage ?? const AiModelStorage();

  final AiModelStorage _modelStorage;
  final AiAdminSettingsStorage _settings = const AiAdminSettingsStorage();

  static const _routingPrefKey = 'ai_model_routing_config_v1';

  static final ValueNotifier<AiRoutingConfig?> routingNotifier =
      ValueNotifier<AiRoutingConfig?>(null);

  Future<AiRoutingConfig> getConfig() async {
    final raw = await _settings.getString(_routingPrefKey);
    if (raw == null || raw.trim().isEmpty) {
      final initial = await _buildDefaultConfig();
      if (!_settings.isCloudMode) await saveConfig(initial);
      routingNotifier.value = initial;
      return initial;
    }
    try {
      final config = AiRoutingConfig.fromJson(raw);
      routingNotifier.value = config;
      return config;
    } catch (_) {
      final initial = await _buildDefaultConfig();
      routingNotifier.value = initial;
      return initial;
    }
  }

  Future<void> saveConfig(AiRoutingConfig config) async {
    await _settings.setString(_routingPrefKey, config.toJson());
    routingNotifier.value = config;
  }

  Future<AiRoutingConfig> _buildDefaultConfig() async {
    final all = await _modelStorage.getModels();
    final free = all.where((m) => m.isFree).map((m) => m.id).toList();
    final paid = all.where((m) => !m.isFree).map((m) => m.id).toList();
    final allTts = await _modelStorage.getTtsModels();
    final ttsIds = allTts.where((m) => m.isActive).map((m) => m.id).toList();

    return AiRoutingConfig(
      freeModelIds: free.isNotEmpty
          ? free
          : ['default_gemini_2_5_flash', 'default_groq_llama_3_3_70b'],
      paidModelIds: paid.isNotEmpty
          ? paid
          : ['default_gemini_2_5_pro', 'default_openai_gpt_4o_mini'],
      ttsModelIds: ttsIds.isNotEmpty
          ? ttsIds
          : [
              'default_gemini_3_8_flash_tts',
              'default_gemini_3_8_flash_lite_tts',
            ],
      autoFallbackEnabled: true,
      ttsAutoFallbackEnabled: true,
      hideModelPickerFromChat: true,
      activeTier: 'free',
    );
  }

  /// Get the ordered list of models for the active tier (Free or Paid)
  Future<List<AiModelConfig>> getActiveTierModels() async {
    final config = await getConfig();
    final all = await _modelStorage.getModels();
    final targetIds = config.activeTier == 'paid'
        ? config.paidModelIds
        : config.freeModelIds;

    final result = <AiModelConfig>[];
    for (final id in targetIds) {
      final found = all.where((m) => m.id == id).firstOrNull;
      if (found != null && found.isActive) {
        result.add(found);
      }
    }

    if (result.isEmpty) {
      final fallback = all.where((m) => m.isActive).toList();
      return fallback;
    }

    return result;
  }

  /// Get the ordered list of TTS models configured in App Routing
  /// Strictly unified for all students (no free/paid distinction)
  Future<List<AiModelConfig>> getActiveTtsModels() async {
    final config = await getConfig();
    final allTts = await _modelStorage.getTtsModels();

    final result = <AiModelConfig>[];
    for (final id in config.ttsModelIds) {
      final found = allTts.where((m) => m.id == id).firstOrNull;
      if (found != null && found.isActive) {
        result.add(found);
      }
    }

    // Fallback if routing list is empty or models deleted
    if (result.isEmpty) {
      return allTts.where((m) => m.isActive).toList();
    }

    return result;
  }

  /// Record an automatic fallback event when a model fails
  Future<void> recordFailover({
    required String failedModelName,
    required String fallbackModelName,
    required String reason,
  }) async {
    final config = await getConfig();
    final updated = config.copyWith(
      lastFailoverTimestamp: DateTime.now(),
      lastFailoverReason:
          'Failover: $failedModelName ➔ $fallbackModelName ($reason)',
    );
    await saveConfig(updated);
  }

  /// Record an automatic fallback event when a TTS voice model fails
  Future<void> recordTtsFailover({
    required String failedModelName,
    required String fallbackModelName,
    required String reason,
  }) async {
    final config = await getConfig();
    final updated = config.copyWith(
      lastTtsFailoverTimestamp: DateTime.now(),
      lastTtsFailoverReason:
          'TTS Failover: $failedModelName ➔ $fallbackModelName ($reason)',
    );
    await saveConfig(updated);
  }
}
