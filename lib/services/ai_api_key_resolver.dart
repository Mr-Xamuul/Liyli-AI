import '../models/ai_model_config.dart';
import 'api_key_storage.dart';

/// Resolves model credentials from Admin > AI Manage > API Keys.
class AiApiKeyResolver {
  const AiApiKeyResolver({ApiKeyStorage storage = const ApiKeyStorage()})
    : _storage = storage;

  final ApiKeyStorage _storage;

  Future<String> resolve({
    AiModelConfig? model,
    required String provider,
  }) async {
    final keyId = model?.apiKeyId;
    if (keyId != null && keyId.isNotEmpty) {
      final managedKey = await _storage.getKeyById(keyId);
      if (managedKey != null &&
          managedKey.isActive &&
          managedKey.apiKey.trim().isNotEmpty) {
        return managedKey.apiKey.trim();
      }
      throw StateError(
        'Furaha API-ga model-kan lama helin ama waa dansan yahay. '
        'Ka hubi qaybta AI Manage > API Keys.',
      );
    }

    // Keep support for custom keys entered in the Admin model editor.
    final inlineKey = model?.apiKey.trim() ?? '';
    if (inlineKey.isNotEmpty) return inlineKey;

    final normalizedProvider = _normalizeProvider(provider);
    final keys = await _storage.getKeys();
    for (final key in keys) {
      if (key.isActive &&
          key.apiKey.trim().isNotEmpty &&
          _normalizeProvider(key.provider) == normalizedProvider) {
        return key.apiKey.trim();
      }
    }

    throw StateError(
      'Furaha API-ga $provider lama dejin. Ku dar ama daar furaha qaybta '
      'AI Manage > API Keys.',
    );
  }

  String _normalizeProvider(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('google') || normalized.contains('gemini')) {
      return 'google';
    }
    if (normalized.contains('openai')) return 'openai';
    if (normalized.contains('groq')) return 'groq';
    if (normalized.contains('deepseek')) return 'deepseek';
    if (normalized.contains('anthropic') || normalized.contains('claude')) {
      return 'anthropic';
    }
    if (normalized.contains('mistral')) return 'mistral';
    return normalized;
  }
}
