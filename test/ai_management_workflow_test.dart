import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/ai_model_config.dart';
import 'package:leyli/models/api_key_config.dart';
import 'package:leyli/services/ai_model_storage.dart';
import 'package:leyli/services/api_key_storage.dart';
import 'package:leyli/services/ai_routing_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AI Management 5-Stage Workflow Tests', () {
    test('Stage 5: ApiKeyStorage can save, retrieve, and delete API keys', () async {
      final keyStorage = const ApiKeyStorage();
      final initialKeys = await keyStorage.getKeys();

      expect(initialKeys.isNotEmpty, isTrue);
      expect(initialKeys.any((k) => k.provider == 'Google'), isTrue);

      final newKey = ApiKeyConfig(
        id: 'test_custom_groq',
        name: 'My Custom Groq Key',
        provider: 'Groq',
        apiKey: 'gsk_1234567890abcdef',
        baseUrl: 'https://api.groq.com/openai/v1',
        isActive: true,
        createdAt: DateTime.now(),
      );

      await keyStorage.saveKey(newKey);
      final updated = await keyStorage.getKeys();
      expect(updated.any((k) => k.id == 'test_custom_groq'), isTrue);

      await keyStorage.deleteKey('test_custom_groq');
      final afterDelete = await keyStorage.getKeys();
      expect(afterDelete.any((k) => k.id == 'test_custom_groq'), isFalse);
    });

    test('Stage 1 -> Stage 2 -> Stage 3: Model transition from Draft to Testing to Ready', () async {
      final modelStorage = const AiModelStorage();

      final draftModel = AiModelConfig(
        id: 'test_model_v1',
        displayName: 'Test Llama 3.3',
        modelId: 'llama-3.3-70b',
        baseUrl: 'https://api.groq.com/openai/v1',
        apiKey: 'test_key',
        company: 'Groq',
        isFree: true,
        isVerified: false,
        isActive: true,
        createdAt: DateTime.now(),
        status: 'models', // Stage 1
      );

      await modelStorage.saveModel(draftModel);
      var models = await modelStorage.getModels();
      var stored = models.firstWhere((m) => m.id == 'test_model_v1');
      expect(stored.status, 'models');
      expect(stored.isDraft, isTrue);

      // Transition to Stage 2: Testing
      await modelStorage.sendModelToTesting(stored.id);
      models = await modelStorage.getModels();
      stored = models.firstWhere((m) => m.id == 'test_model_v1');
      expect(stored.status, 'testing');
      expect(stored.isTesting, isTrue);

      // Transition to Stage 3: Ready / Approved
      await modelStorage.promoteModelToReady(stored.id);
      models = await modelStorage.getModels();
      stored = models.firstWhere((m) => m.id == 'test_model_v1');
      expect(stored.status, 'ready');
      expect(stored.isReady, isTrue);
      expect(stored.isVerified, isTrue);
    });

    test('Stage 4: AiRoutingStorage handles priority pools and failover logging', () async {
      final routingStorage = const AiRoutingStorage();
      final initialConfig = await routingStorage.getConfig();

      expect(initialConfig.autoFallbackEnabled, isTrue);
      expect(initialConfig.hideModelPickerFromChat, isTrue);

      // Reorder or set priority pools
      final updated = initialConfig.copyWith(
        freeModelIds: ['model_a', 'model_b', 'model_c'],
        paidModelIds: ['premium_x', 'premium_y'],
        activeTier: 'free',
      );
      await routingStorage.saveConfig(updated);

      final reloaded = await routingStorage.getConfig();
      expect(reloaded.freeModelIds, ['model_a', 'model_b', 'model_c']);
      expect(reloaded.paidModelIds, ['premium_x', 'premium_y']);

      // Record automatic failover event
      await routingStorage.recordFailover(
        failedModelName: 'model_a',
        fallbackModelName: 'model_b',
        reason: 'HTTP 429 Quota Exceeded',
      );

      final withFailover = await routingStorage.getConfig();
      expect(withFailover.lastFailoverReason, contains('model_a ➔ model_b'));
    });
  });
}
