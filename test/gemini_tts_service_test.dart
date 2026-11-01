import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leyli/services/gemini_tts_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GeminiTtsService Tests', () {
    test('cleanTextForSpeech strips Markdown, LaTeX, and tags properly', () {
      const raw = r'''
### 1. Hordhac
Tani waa **muhiim** oo *aad u fiican*.
Eeg qaaciddada: $\frac{a}{b}$ iyo $$x \times y = z$$.
Eeg sawirka: [[LEYLI_VISUAL page=1; x=0.1; y=0.2; width=0.5; height=0.5; title=Shax]]
- Qodobka 1
- Qodobka 2
```dart
void main() {}
```
''';

      final cleaned = GeminiTtsService.cleanTextForSpeech(raw);

      expect(cleaned.contains('###'), isFalse);
      expect(cleaned.contains('**'), isFalse);
      expect(cleaned.contains('[['), isFalse);
      expect(cleaned.contains('```'), isFalse);
      expect(cleaned.contains('a loo qaybiyay b'), isTrue);
      expect(cleaned.contains('lagu dhuftay'), isTrue);
      expect(cleaned.contains('Tani waa muhiim oo aad u fiican.'), isTrue);
    });

    test('ensureWavHeader leaves existing RIFF WAV alone', () {
      final riffBytes = Uint8List.fromList('RIFF1234WAVEfmt '.codeUnits);
      final result = GeminiTtsService.ensureWavHeader(riffBytes);
      expect(result, equals(riffBytes));
    });

    test('ensureWavHeader attaches 44-byte RIFF header to raw PCM', () {
      final rawPcm = Uint8List.fromList(List.generate(100, (i) => i % 256));
      final wav = GeminiTtsService.ensureWavHeader(rawPcm);

      expect(wav.length, equals(44 + 100));
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));
    });

    test('generateSpeechBytes parses Gemini API audio inlineData response correctly', () async {
      final mockRawAudio = Uint8List.fromList('RIFFtestaudiodata'.codeUnits);
      final mockBase64 = base64Encode(mockRawAudio);

      final mockClient = MockClient((request) async {
        expect(request.url.toString().contains('generativelanguage.googleapis.com'), isTrue);
        final bodyJson = jsonDecode(request.body) as Map<String, dynamic>;
        expect(bodyJson['generationConfig']['responseModalities'], equals(['AUDIO']));

        final responseJson = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'inlineData': {
                      'mimeType': 'audio/wav',
                      'data': mockBase64,
                    }
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(responseJson), 200);
      });

      final tts = GeminiTtsService(client: mockClient);
      final bytes = await tts.generateSpeechBytes(text: 'Kani waa tijaabo');

      expect(bytes, isNotEmpty);
      expect(bytes, equals(mockRawAudio));
    });
  });
}
