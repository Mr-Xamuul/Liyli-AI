import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/ai_model_config.dart';
import 'package:leyli/services/ai_model_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AiModelConfig', () {
    test('serialization and copyWith', () {
      final now = DateTime.now();
      final model = AiModelConfig(
        id: 'test_model_1',
        displayName: 'Test Model',
        modelId: 'test-gpt',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-12345',
        company: 'OpenAI',
        isFree: false,
        isVerified: true,
        isActive: true,
        createdAt: now,
      );

      expect(model.isOpenAiCompatible, isTrue);

      final jsonStr = model.toJson();
      final fromJson = AiModelConfig.fromJson(jsonStr);

      expect(fromJson.id, 'test_model_1');
      expect(fromJson.displayName, 'Test Model');
      expect(fromJson.modelId, 'test-gpt');
      expect(fromJson.baseUrl, 'https://api.openai.com/v1');
      expect(fromJson.apiKey, 'sk-12345');
      expect(fromJson.company, 'OpenAI');
      expect(fromJson.isFree, isFalse);
      expect(fromJson.isVerified, isTrue);
      expect(fromJson.isActive, isTrue);

      final geminiModel = model.copyWith(
        company: 'Google',
        baseUrl: 'https://generativelanguage.googleapis.com',
      );
      expect(geminiModel.isOpenAiCompatible, isFalse);
    });
  });

  group('AiModelStorage', () {
    test('loads default seed models when empty', () async {
      const storage = AiModelStorage();
      final models = await storage.getModels();
      expect(models.isNotEmpty, isTrue);
      expect(models.any((m) => m.company == 'Google'), isTrue);
      expect(models.any((m) => m.company == 'OpenAI'), isTrue);
    });

    test('can save, retrieve and delete model', () async {
      const storage = AiModelStorage();
      final newModel = AiModelConfig(
        id: 'custom_groq',
        displayName: 'Custom Groq',
        modelId: 'llama-3.3-70b',
        baseUrl: 'https://api.groq.com/openai/v1',
        apiKey: 'gsk_123',
        company: 'Groq',
        isFree: true,
        isVerified: true,
        isActive: true,
        createdAt: DateTime.now(),
      );

      await storage.saveModel(newModel);
      final models = await storage.getModels();
      expect(models.any((m) => m.id == 'custom_groq'), isTrue);

      final retrieved = models.firstWhere((m) => m.id == 'custom_groq');
      expect(retrieved.displayName, 'Custom Groq');

      await storage.deleteModel('custom_groq');
      final updated = await storage.getModels();
      expect(updated.any((m) => m.id == 'custom_groq'), isFalse);
    });

    test('can register a new custom company', () async {
      const storage = AiModelStorage();
      final initial = await storage.getCompanies();
      expect(initial.contains('xAI-Custom'), isFalse);

      await storage.addCompany('xAI-Custom');
      final after = await storage.getCompanies();
      expect(after.contains('xAI-Custom'), isTrue);
    });

    test('verifyModelConnection succeeds for OpenAI compatible API on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/chat/completions'));
        expect(request.headers['authorization'], 'Bearer sk-test');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Hello from AI'},
              }
            ],
          }),
          200,
        );
      });

      final storage = AiModelStorage(client: mockClient);
      final model = AiModelConfig(
        id: 'test_openai',
        displayName: 'Test OpenAI',
        modelId: 'gpt-4o-mini',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        company: 'OpenAI',
        createdAt: DateTime.now(),
      );

      final res = await storage.verifyModelConnection(model);
      expect(res.success, isTrue);
      expect(res.message, contains('wuu guuleystay'));
    });

    test('verifyModelConnection succeeds for Google Gemini API on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('generateContent'));
        expect(request.headers['x-goog-api-key'], 'gemini-key');
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Hello from Gemini'}
                  ],
                },
              }
            ],
          }),
          200,
        );
      });

      final storage = AiModelStorage(client: mockClient);
      final model = AiModelConfig(
        id: 'test_gemini',
        displayName: 'Test Gemini',
        modelId: 'gemini-2.5-flash',
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiKey: 'gemini-key',
        company: 'Google',
        createdAt: DateTime.now(),
      );

      final res = await storage.verifyModelConnection(model);
      expect(res.success, isTrue);
      expect(res.message, contains('Google Gemini wuu guuleystay'));
    });

    test('verifyModelConnection fails on error response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Invalid API Key'},
          }),
          401,
        );
      });

      final storage = AiModelStorage(client: mockClient);
      final model = AiModelConfig(
        id: 'test_bad_key',
        displayName: 'Bad Key',
        modelId: 'gpt-4o',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'invalid',
        company: 'OpenAI',
        createdAt: DateTime.now(),
      );

      final res = await storage.verifyModelConnection(model);
      expect(res.success, isFalse);
      expect(res.message, contains('API Key-ga lama aqbalin'));
    });
  });
}
