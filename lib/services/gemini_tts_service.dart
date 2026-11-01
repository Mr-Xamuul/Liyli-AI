import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_model_config.dart';
import 'ai_api_key_resolver.dart';
import 'ai_gateway_client.dart';
import 'ai_model_storage.dart';
import 'ai_routing_storage.dart';
import 'supabase_config.dart';

enum TtsStatus { idle, loading, playing, paused, stopped }

class TtsPlaybackState {
  const TtsPlaybackState({
    this.status = TtsStatus.idle,
    this.activeId,
    this.errorMessage,
  });

  final TtsStatus status;
  final String? activeId;
  final String? errorMessage;

  bool isPlayingFor(String id) => status == TtsStatus.playing && activeId == id;
  bool isLoadingFor(String id) => status == TtsStatus.loading && activeId == id;
  bool isPausedFor(String id) => status == TtsStatus.paused && activeId == id;
  bool isActiveFor(String id) => activeId == id;
}

class GeminiTtsService {
  GeminiTtsService({http.Client? client, AudioPlayer? player})
    : _client = client ?? http.Client(),
      _player = player ?? AudioPlayer() {
    _initPlayerListeners();
  }

  static const String defaultTtsModelId = 'gemini-3.8-flash-tts';

  static const List<String> candidateTtsModels = [
    'gemini-3.8-flash-tts',
    'gemini-3.8-flash-lite-tts',
    'gemini-3.1-flash-tts-preview',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  static const String _voicePrefKey = 'gemini_tts_voice_pref_v1';
  static const String _speedPrefKey = 'gemini_tts_speed_pref_v1';

  static const List<Map<String, String>> availableVoices = [
    {
      'id': 'Puck',
      'title': 'Puck',
      'description': 'Cod lab oo firfircoon oo cad',
      'type': 'Lab (Male)',
    },
    {
      'id': 'Aoede',
      'title': 'Aoede',
      'description': 'Cod dhedig oo dabiici ah oo macallimad',
      'type': 'Dhedig (Female)',
    },
    {
      'id': 'Kore',
      'title': 'Kore',
      'description': 'Cod dhedig oo deggan oo qabow',
      'type': 'Dhedig (Female)',
    },
    {
      'id': 'Fenrir',
      'title': 'Fenrir',
      'description': 'Cod lab oo qoto dheer oo waayeel ah',
      'type': 'Lab (Male)',
    },
    {
      'id': 'Charon',
      'title': 'Charon',
      'description': 'Cod lab oo deggan oo xasiloon',
      'type': 'Lab (Male)',
    },
  ];

  static Future<String> getSavedVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_voicePrefKey) ?? 'Puck';
    } catch (_) {
      return 'Puck';
    }
  }

  static Future<void> saveVoice(String voiceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_voicePrefKey, voiceId);
    } catch (_) {}
  }

  static Future<double> getSavedSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_speedPrefKey) ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  static Future<void> saveSpeed(double speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_speedPrefKey, speed);
    } catch (_) {}
  }

  final http.Client _client;
  final AudioPlayer _player;

  final ValueNotifier<TtsPlaybackState> stateNotifier =
      ValueNotifier<TtsPlaybackState>(const TtsPlaybackState());

  final Map<String, Uint8List> _audioMemoryCache = {};

  void _initPlayerListeners() {
    _player.onPlayerComplete.listen((_) {
      stateNotifier.value = const TtsPlaybackState(
        status: TtsStatus.stopped,
        activeId: null,
      );
    });

    _player.onPlayerStateChanged.listen((state) {
      final current = stateNotifier.value;
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        stateNotifier.value = const TtsPlaybackState(
          status: TtsStatus.stopped,
          activeId: null,
        );
      } else if (state == PlayerState.playing) {
        stateNotifier.value = TtsPlaybackState(
          status: TtsStatus.playing,
          activeId: current.activeId,
        );
      } else if (state == PlayerState.paused) {
        stateNotifier.value = TtsPlaybackState(
          status: TtsStatus.paused,
          activeId: current.activeId,
        );
      }
    });
  }

  /// Clean text from Markdown symbols, LaTeX math expressions, and visual crop tags
  static String cleanTextForSpeech(String raw) {
    if (raw.trim().isEmpty) return '';

    var clean = raw;

    // 1. Remove [[LEYLI_VISUAL ...]] tags
    clean = clean.replaceAll(
      RegExp(r'\[\[LEYLI_VISUAL\s+.*?\]\]', caseSensitive: false, dotAll: true),
      '',
    );

    // 2. Remove markdown code blocks ```...```
    clean = clean.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // 3. Remove inline code `...`
    clean = clean.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');

    // 4. Clean common LaTeX commands to plain readable words
    clean = clean.replaceAllMapped(
      RegExp(r'\\?frac\{([^}]+)\}\{([^}]+)\}'),
      (m) => '${m[1]} loo qaybiyay ${m[2]}',
    );
    clean = clean.replaceAll(RegExp(r'\\?times'), ' lagu dhuftay ');
    clean = clean.replaceAll(RegExp(r'\\?div'), ' loo qaybiyay ');
    clean = clean.replaceAll(RegExp(r'\\?pm'), ' lagu daray ama laga jaray ');
    clean = clean.replaceAllMapped(
      RegExp(r'\\?sqrt\{([^}]+)\}'),
      (m) => 'xididka laba-laaban ee ${m[1]}',
    );
    clean = clean.replaceAll(RegExp(r'\\?approx'), ' waxay u dhowdahay ');
    clean = clean.replaceAll(RegExp(r'\\?(ne|neq)'), ' ma leka ');
    clean = clean.replaceAll(RegExp(r'\\?(le|leq)'), ' ka yar ama la eg ');
    clean = clean.replaceAll(RegExp(r'\\?(ge|geq)'), ' ka weyn ama la eg ');
    clean = clean.replaceAll(
      RegExp(r'\\[a-zA-Z]+'),
      '',
    ); // remove other backslash commands

    // Clean LaTeX blocks $$...$$ and $...$
    clean = clean.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$'),
      (m) => m[1] ?? '',
    );
    clean = clean.replaceAllMapped(RegExp(r'\$([^\$]+)\$'), (m) => m[1] ?? '');
    clean = clean.replaceAll(RegExp(r'[{}]'), '');

    // 5. Remove Markdown headings (#, ##, ###, etc.)
    clean = clean.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // 6. Remove bold/italics markers (*, **, _, __)
    clean = clean.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (m) => m[1] ?? '',
    );
    clean = clean.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1] ?? '');
    clean = clean.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1] ?? '');
    clean = clean.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1] ?? '');
    clean = clean.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m[1] ?? '');

    // 7. Remove markdown links [title](url) -> title
    clean = clean.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m[1] ?? '',
    );

    // 8. Remove blockquotes and list bullet symbols
    clean = clean.replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '');
    clean = clean.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    clean = clean.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // 9. Remove multiple consecutive newlines and spaces
    clean = clean.replaceAll(RegExp(r'\n{2,}'), '\n');
    clean = clean.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

    return clean.trim();
  }

  /// Ensure audio bytes have a valid 44-byte RIFF/WAV header if raw PCM
  static Uint8List ensureWavHeader(
    Uint8List rawBytes, {
    int sampleRate = 24000,
    int channels = 1,
    int bitDepth = 16,
  }) {
    if (rawBytes.length >= 4) {
      final headerStr = String.fromCharCodes(rawBytes.sublist(0, 4));
      if (headerStr == 'RIFF') {
        return rawBytes;
      }
    }

    final byteRate = sampleRate * channels * (bitDepth ~/ 8);
    final blockAlign = channels * (bitDepth ~/ 8);
    final dataSize = rawBytes.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitDepth, Endian.little);

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, rawBytes);
    return wav;
  }

  static String formatFriendlyError(dynamic error) {
    final str = error.toString().toLowerCase();
    if (str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('network') ||
        str.contains('timed out') ||
        str.contains('connection refused')) {
      return '⚠️ Xiriirka internet-ka ayaa go\'an ama aad u gaabiya. Fadlan hubi khadkaaga.';
    }
    if (str.contains('api_key_invalid') ||
        str.contains('api key not valid') ||
        str.contains('403')) {
      return '⚠️ API Key-ga Gemini ma saxna ama ma shaqeynayo. Fadlan hubi API Key-gaaga.';
    }
    if (str.contains('quota') ||
        str.contains('rate limit') ||
        str.contains('resource_exhausted') ||
        str.contains('429')) {
      return '⚠️ Xadka isticmaalka API-ga ayaa buuxsamay (Quota limit). Fadlan cabbaar sug.';
    }
    return 'Qalad ayaa dhacay xilliga diyaarinta codka: $error';
  }

  Future<String> _resolveApiKey([AiModelConfig? modelConfig]) async {
    final config =
        modelConfig ?? await const AiModelStorage().getActiveTtsModel();
    final provider = config?.company.trim().isNotEmpty == true
        ? config!.company
        : 'Google';
    return const AiApiKeyResolver().resolve(model: config, provider: provider);
  }

  /// Request TTS speech audio bytes from Google Gemini API
  /// Follows the priority order established in Stage 4 (App Routing) TTS pool
  Future<Uint8List> generateSpeechBytes({
    required String text,
    AiModelConfig? modelConfig,
    String voiceName = 'Puck',
  }) async {
    final cleaned = cleanTextForSpeech(text);
    if (cleaned.isEmpty) {
      throw Exception('Qoraalku waa maran yahay.');
    }

    // Check memory cache first
    final cacheKey = '${cleaned.hashCode}_$voiceName';
    if (_audioMemoryCache.containsKey(cacheKey)) {
      return _audioMemoryCache[cacheKey]!;
    }

    const routingStorage = AiRoutingStorage();
    final routingConfig = await routingStorage.getConfig();
    final orderedTtsModels = await routingStorage.getActiveTtsModels();

    // Determine candidate model configs to try in exact priority sequence
    final List<AiModelConfig> modelsToTry = [];

    // If explicit TTS model is provided (e.g. from Stage 2 model tester)
    if (modelConfig != null && modelConfig.isTts) {
      modelsToTry.add(modelConfig);
    }

    // Add configured models from App Routing in priority order
    for (final m in orderedTtsModels) {
      if (!modelsToTry.any(
        (existing) => existing.id == m.id || existing.modelId == m.modelId,
      )) {
        modelsToTry.add(m);
      }
    }

    // Fallback if no models are configured in routing
    if (modelsToTry.isEmpty) {
      final activeTts = await const AiModelStorage().getActiveTtsModel();
      if (activeTts != null) {
        modelsToTry.add(activeTts);
      }
    }

    if (modelsToTry.isEmpty) {
      throw Exception(
        'Ma jiro model codka ah (TTS) oo loo diyaariyay App Routing-ka. '
        'Fadlan fur AI Management ➔ App Routing si aad ugu darto moodellada codka.',
      );
    }

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': cleaned},
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voiceName},
          },
        },
      },
    };

    dynamic lastError;

    for (int i = 0; i < modelsToTry.length; i++) {
      final config = modelsToTry[i];
      final modelId = config.modelId.trim();
      final apiKey = SupabaseConfig.isInitialized
          ? ''
          : await _resolveApiKey(config);
      final baseUrl = config.baseUrl.trim().isNotEmpty
          ? config.baseUrl.trim()
          : 'https://generativelanguage.googleapis.com';

      if (!SupabaseConfig.isInitialized && apiKey.isEmpty) {
        lastError = 'API key ma helna model-ka ${config.displayName}';
        continue;
      }

      try {
        final http.Response res;
        if (SupabaseConfig.isInitialized) {
          res = await const AiGatewayClient()
              .generate(modelId: config.id, operation: 'tts', body: payload)
              .timeout(const Duration(minutes: 3));
        } else {
          final uri = Uri.parse(
            '$baseUrl/v1beta/models/$modelId:generateContent?key=$apiKey',
          );
          res = await _client
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(minutes: 10));
        }

        if (res.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final firstCandidate = candidates.first as Map<String, dynamic>;
            final content = firstCandidate['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              for (final part in parts) {
                final inlineData =
                    (part as Map<String, dynamic>)['inlineData']
                        as Map<String, dynamic>?;
                if (inlineData != null) {
                  final base64Audio = inlineData['data'] as String?;
                  if (base64Audio != null && base64Audio.isNotEmpty) {
                    final rawBytes = base64Decode(base64Audio);
                    final wavBytes = ensureWavHeader(rawBytes);
                    _audioMemoryCache[cacheKey] = wavBytes;
                    return wavBytes;
                  }
                }
              }
            }
          }
          lastError = 'Qoraalka codka lama helin (response empty) - $modelId';
        } else {
          lastError = 'HTTP ${res.statusCode}: ${res.body}';
          debugPrint(
            '[GeminiTTS] Failed $modelId with HTTP ${res.statusCode}: ${res.body}',
          );
        }
      } catch (e) {
        lastError = e;
        debugPrint('[GeminiTTS] Error $modelId: $e');
      }

      // Check if automatic fallback to next configured model is enabled
      if (routingConfig.ttsAutoFallbackEnabled && i < modelsToTry.length - 1) {
        final nextModel = modelsToTry[i + 1];
        await routingStorage.recordTtsFailover(
          failedModelName: config.displayName,
          fallbackModelName: nextModel.displayName,
          reason: 'Cillad/Mashquul: ${lastError.toString()}',
        );
        debugPrint(
          '[GeminiTTS] Fallback trigger: ${config.displayName} -> ${nextModel.displayName}',
        );
        continue;
      } else if (!routingConfig.ttsAutoFallbackEnabled) {
        break;
      }
    }

    throw Exception('Codka lama soo saari karin: $lastError');
  }

  /// Play audio for a specific message / text
  Future<void> speak({
    required String id,
    required String text,
    AiModelConfig? modelConfig,
    String? voiceName,
  }) async {
    // If already playing this ID, stop it
    if (stateNotifier.value.isPlayingFor(id)) {
      await stop();
      return;
    }

    // Stop any previous playing audio
    await _player.stop();

    stateNotifier.value = TtsPlaybackState(
      status: TtsStatus.loading,
      activeId: id,
    );

    try {
      final activeVoice = voiceName ?? await getSavedVoice();
      final speed = await getSavedSpeed();

      final audioBytes = await generateSpeechBytes(
        text: text,
        modelConfig: modelConfig,
        voiceName: activeVoice,
      );

      // Write to temporary WAV file for reliable desktop and mobile playback
      try {
        final tempDir = await getTemporaryDirectory();
        final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        final tempFile = File('${tempDir.path}/leyli_tts_$safeId.wav');
        await tempFile.writeAsBytes(audioBytes, flush: true);
        await _player.play(DeviceFileSource(tempFile.path));
      } catch (_) {
        await _player.play(BytesSource(audioBytes));
      }

      try {
        await _player.setPlaybackRate(speed);
      } catch (_) {}

      stateNotifier.value = TtsPlaybackState(
        status: TtsStatus.playing,
        activeId: id,
      );
    } catch (e) {
      final friendly = formatFriendlyError(e);
      stateNotifier.value = TtsPlaybackState(
        status: TtsStatus.idle,
        activeId: id,
        errorMessage: friendly,
      );
      rethrow;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    stateNotifier.value = TtsPlaybackState(
      status: TtsStatus.paused,
      activeId: stateNotifier.value.activeId,
    );
  }

  Future<void> resume() async {
    await _player.resume();
    stateNotifier.value = TtsPlaybackState(
      status: TtsStatus.playing,
      activeId: stateNotifier.value.activeId,
    );
  }

  Future<void> stop() async {
    await _player.stop();
    stateNotifier.value = const TtsPlaybackState(status: TtsStatus.stopped);
  }

  void dispose() {
    _player.dispose();
    stateNotifier.dispose();
  }
}
