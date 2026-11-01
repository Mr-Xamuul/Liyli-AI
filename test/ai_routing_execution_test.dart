import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/ai_model_config.dart';
import 'package:leyli/models/ai_routing_config.dart';
import 'package:leyli/services/ai_model_storage.dart';
import 'package:leyli/services/ai_routing_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('App Routing strictly orders tier models and excludes unrouted models', () async {
    final modelStorage = const AiModelStorage();
    final routingStorage = AiRoutingStorage(modelStorage: modelStorage);

    // Save custom routing: Llama first, Gemini second
    final customConfig = AiRoutingConfig(
      freeModelIds: [
        'default_groq_llama_3_3_70b',
        'default_gemini_2_5_flash',
      ],
      paidModelIds: ['default_gemini_2_5_pro'],
      autoFallbackEnabled: true,
      hideModelPickerFromChat: true,
      activeTier: 'free',
    );
    await routingStorage.saveConfig(customConfig);

    // Get active tier models
    final tierModels = await routingStorage.getActiveTierModels();

    // 1. Must contain ONLY the models configured in free tier
    expect(tierModels.length, 2);
    expect(tierModels[0].id, 'default_groq_llama_3_3_70b');
    expect(tierModels[1].id, 'default_gemini_2_5_flash');

    // 2. Models not in App Routing (like Gemini 2.5 Pro or unverified models) MUST NOT be present
    expect(tierModels.any((m) => m.id == 'default_gemini_2_5_pro'), false);
    expect(tierModels.any((m) => m.id == 'default_openai_gpt_4o_mini'), false);
  });
}
