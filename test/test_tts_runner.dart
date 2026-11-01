import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.trim().isEmpty) {
    throw StateError('Set GEMINI_API_KEY before running this manual test.');
  }
  final models = [
    'gemini-3.8-flash-tts',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
  ];

  for (final model in models) {
    print('Testing model: $model');
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': 'Hello, say one word'}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': 'Puck',
            }
          }
        }
      }
    };

    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      print('Status: ${res.statusCode}');
      if (res.statusCode != 200) {
        print('Body: ${res.body.substring(0, res.body.length.clamp(0, 300))}');
      } else {
        final data = jsonDecode(res.body);
        final candidates = data['candidates'] as List?;
        final parts = candidates?[0]?['content']?['parts'] as List?;
        final inlineData = parts?[0]?['inlineData'];
        print('Success! inlineData mimeType: ${inlineData?['mimeType']}, data length: ${inlineData?['data']?.toString().length}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
