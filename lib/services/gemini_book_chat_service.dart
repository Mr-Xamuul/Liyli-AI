import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/book_knowledge.dart';
import '../models/learning_session.dart';
import '../models/prepared_book.dart';
import '../models/ai_model_config.dart';
import '../models/agent_execution_trace.dart';
import 'ai_api_key_resolver.dart';
import 'ai_gateway_client.dart';
import 'ai_model_storage.dart';
import 'supabase_config.dart';

typedef AgentToolExecutor =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> arguments,
    );
typedef AgentToolCallObserver = void Function(AgentToolCallLog call);
typedef AgentModelCallObserver = void Function(AgentModelCallLog modelCall);

const _openAiAgentToolDeclarations = [
  {
    'type': 'function',
    'function': {
      'name': 'search_curriculum',
      'description':
          'Raadi buugaagta manhajka ee fasalka ardayga adigoo isticmaalaya amarro cad: "get_table_of_contents" (si aad 1-mar u hesho geedka buugga oo dhan), "get_chapter" (cutub gaar ah), ama "search_topic" (mowduuc gaar ah).',
      'parameters': {
        'type': 'object',
        'properties': {
          'bookTitle': {
            'type': 'string',
            'description':
                'Magaca buugga manhajka ee laga raadinayo (tusaale "Physics", "Business Studies", "Biology", iwm).',
          },
          'action': {
            'type': 'string',
            'description':
                'Amarka: "get_table_of_contents" (si loo soo saaro geedka buugga oo dhan oo wata cutubyada, casharrada, iyo qaybaha), "get_chapter" (si loo helo cutub gaar ah), ama "search_topic" (si loo raadiyo mowduuc gaar ah).',
            'enum': ['get_table_of_contents', 'get_chapter', 'search_topic'],
          },
          'chapter': {
            'type': 'string',
            'description':
                'Ikhtiyaari: Magaca ama lambarka cutubka la rabo (tusaale "Measurement ll" ama "1").',
          },
          'topic': {
            'type': 'string',
            'description':
                'Ikhtiyaari: Mawduuca ama erayada gaarka ah ee la raadinayo (tusaale "Measuring instruments", "Vernier Callipers").',
          },
          'query': {
            'type': 'string',
            'description': 'Ikhtiyaari: Qoraalka raadinta guud.',
          },
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_lesson_pdf',
      'description': 'Soo saar qoraalka iyo qaybta PDF ee casharka la doortay.',
      'parameters': {
        'type': 'object',
        'properties': {
          'bookId': {
            'type': 'string',
            'description': 'ID-ga buugga ama Magaca buugga',
          },
          'chapterId': {
            'type': 'string',
            'description': 'ID-ga cutubka ama Magaca cutubka',
          },
          'lessonId': {
            'type': 'string',
            'description': 'ID-ga casharka ama Magaca casharka',
          },
          'sectionId': {
            'type': 'string',
            'description': 'Ikhtiyaari: ID-ga qaybta hoose (section)',
          },
        },
        'required': ['bookId', 'lessonId'],
      },
    },
  },
];

enum TutorMode {
  teach, // Baro qaybtaan: Cashar nidaamsan oo tillaabo-tillaabo ah
  visuals, // Sharax Sawirrada & Jaantusyada: Si gaar ah u falanqee jaantusyada, shaxannada, iyo sawirrada PDF-ka ku jira
  explain, // I sharax: Sharaxaad fudud iyo tusaalooyin dhab ah
  quiz, // Is-tijaabi: Su'aalo xulasho iyo is-qiimeyn ah
  summary, // Dulucda: Qodobada muhiimka ah ee la koobay
  freeChat, // Su'aasha furan ee ardaygu soo qorto
}

class GeminiBookChatService {
  GeminiBookChatService({http.Client? client, String? apiKey})
    : _customClient = client,
      _apiKey = apiKey;

  static const candidateModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
  ];

  static const offlineMessage =
      '⚠️ Ma jiro xiriir internet. Fadlan hubi khadkaaga internet-ka.';

  static const timeoutMessage =
      '⚠️ Waqtigii jawaabta ayaa dhacay (Timeout ka badan 3 daqiiqo). Model-ka AI ayaa aad ugu raagay diyaarinta jawaabta ama wuxuu la kulmay culeys. Fadlan guji "Isku day markale" si aad dib ugu dirto.';

  static const defaultRequestTimeout = Duration(minutes: 3);

  static const _geminiAgentToolDeclarations = [
    {
      'name': 'search_curriculum',
      'description':
          'Raadi buugaagta manhajka ee fasalka ardayga adigoo isticmaalaya amarro cad: "get_table_of_contents" (si aad 1-mar u hesho geedka buugga oo dhan), "get_chapter" (cutub gaar ah), ama "search_topic" (mowduuc gaar ah).',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'bookTitle': {
            'type': 'STRING',
            'description':
                'Magaca buugga manhajka ee laga raadinayo (tusaale "Physics", "Business Studies", "Biology", iwm).',
          },
          'action': {
            'type': 'STRING',
            'description':
                'Amarka: "get_table_of_contents" (si loo soo saaro geedka buugga oo dhan oo wata cutubyada, casharrada, iyo qaybaha), "get_chapter" (si loo helo cutub gaar ah), ama "search_topic" (si loo raadiyo mowduuc gaar ah).',
            'enum': ['get_table_of_contents', 'get_chapter', 'search_topic'],
          },
          'chapter': {
            'type': 'STRING',
            'description':
                'Ikhtiyaari: Magaca ama lambarka cutubka la rabo (tusaale "Measurement ll" ama "1").',
          },
          'topic': {
            'type': 'STRING',
            'description':
                'Ikhtiyaari: Mawduuca ama erayada gaarka ah ee la raadinayo (tusaale "Measuring instruments", "Vernier Callipers").',
          },
          'query': {
            'type': 'STRING',
            'description': 'Ikhtiyaari: Qoraalka raadinta guud.',
          },
        },
      },
    },
    {
      'name': 'get_lesson_pdf',
      'description': 'Soo saar qoraalka iyo qaybta PDF ee casharka la doortay.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'bookId': {
            'type': 'STRING',
            'description': 'ID-ga buugga ama Magaca buugga',
          },
          'chapterId': {
            'type': 'STRING',
            'description': 'ID-ga cutubka ama Magaca cutubka',
          },
          'lessonId': {
            'type': 'STRING',
            'description': 'ID-ga casharka ama Magaca casharka',
          },
          'sectionId': {
            'type': 'STRING',
            'description': 'Ikhtiyaari: ID-ga qaybta hoose (section)',
          },
        },
        'required': ['bookId', 'lessonId'],
      },
    },
  ];

  static Map<String, dynamic> _traceSafeToolOutput(
    Map<String, dynamic> output,
  ) {
    final safe = Map<String, dynamic>.from(output)..remove('_pdfBytes');
    final extractedText = safe['extractedText'];
    if (extractedText is String && extractedText.length > 3000) {
      safe['extractedText'] = '${extractedText.substring(0, 3000)}…';
      safe['extractedTextTruncated'] = true;
    }
    return safe;
  }

  static bool isCongestionOrBusyError(dynamic error) {
    if (error == null) return false;
    if (error is GeminiModelBusyException) return true;
    final str = error.toString().toLowerCase();
    return str.contains('503') ||
        str.contains('429') ||
        str.contains('high demand') ||
        str.contains('resource_exhausted') ||
        str.contains('overloaded') ||
        str.contains('mashquul') ||
        str.contains('ciriiri') ||
        str.contains('rate limit') ||
        str.contains('quota') ||
        str.contains('too many requests') ||
        str.contains('unavailable') ||
        str.contains('temporarily unavailable') ||
        str.contains('timeout') ||
        str.contains('deadline') ||
        str.contains('502') ||
        str.contains('504') ||
        str.contains('server error') ||
        str.contains('clientexception') ||
        str.contains('connection refused') ||
        str.contains('failed to connect');
  }

  static bool isTimeoutError(dynamic error) {
    if (error == null) return false;
    if (error is GeminiTimeoutException) return true;
    final str = error.toString().toLowerCase();
    return error is TimeoutException ||
        str.contains('timeoutexception') ||
        str.contains('connection timed out') ||
        str.contains('timeout') ||
        str.contains('timed out');
  }

  static bool isNetworkOrOfflineError(dynamic error) {
    if (error == null) return false;
    if (isTimeoutError(error)) return false;
    final str = error.toString().toLowerCase();
    return error is SocketException ||
        error is http.ClientException ||
        error is HandshakeException ||
        str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('network is unreachable') ||
        str.contains('no address associated with hostname') ||
        str.contains('clientexception') ||
        str.contains('connection refused') ||
        str.contains('connection closed') ||
        str.contains('connection reset') ||
        str.contains('network error') ||
        str.contains('offline');
  }

  final http.Client? _customClient;
  final String? _apiKey;

  Future<String> _resolveApiKey([AiModelConfig? modelConfig]) async {
    // Explicit constructor keys are kept for injected clients and tests.
    final key = _apiKey;
    if (key != null && key.isNotEmpty) return key;
    final config = modelConfig ?? await const AiModelStorage().getActiveModel();
    return const AiApiKeyResolver().resolve(model: config, provider: 'Google');
  }

  Future<String> ask({
    PreparedBook? book,
    BookKnowledge? knowledge,
    required String question,
    String? focusChapter,
    String? focusLesson,
    String? focusSection,
    double startPosition = 0.0,
    double endPosition = 1.0,
    Uint8List? slicedPdfBytes,
    TutorMode mode = TutorMode.freeChat,
    LearningScopeType? learningScopeType,
    int? learningPartNumber,
    int? learningPartCount,
    String priorLearningContext = '',
    String conversationContext = '',
    AgentToolExecutor? toolExecutor,
    AgentToolCallObserver? onToolCall,
    AgentModelCallObserver? onModelCall,
    void Function({required String systemPrompt, required String userPrompt})?
    onPromptGenerated,
    String? studentFormLevel,
    List<String>? availableBookTitles,
    bool isLessonCompletion = false,
    AiModelConfig? modelConfig,
    void Function(String message, int step)? onProgress,
    CancellationToken? cancellationToken,
    AgentTurnContext? turnContext,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }
    if (modelConfig != null &&
        !modelConfig.isVerified &&
        !modelConfig.isTesting) {
      throw GeminiBookChatException(
        'Model-ka "${modelConfig.displayName}" lama fasixin sababtoo ah ma shaqeynayo ama lama xaqiijin. Fadlan tag Editor > AI Manage si aad u hubiso.',
      );
    }
    onProgress?.call('Diyaarinta xogta & falanqaynta su\'aasha...', 1);
    final baseSystemPrompt = _buildSystemPrompt(mode, learningScopeType);

    final catalogSection =
        (availableBookTitles != null && availableBookTitles.isNotEmpty)
        ? '''

BUUGAAGTA MANHAJKA EE FASALKA ARDAYGA (${studentFormLevel ?? 'Fasalka Hadda'}):
Buugaagta manhajka ee app-ka ugu diiwaangashan fasalkan waa:
${availableBookTitles.map((t) => '- $t').join('\n')}

HABKA AMARADA CAD EE RAADINTA MANHAJKA (Structured Action Commands):
Tallaabada 1 (Dalbashada Geedka Manhajka):
Marka ardaygu su'aal manhaj ah weydiiyo, wac "search_curriculum" adigoo isticmaalaya amarka ku habboon:
• Soo saarista buugga oo dhan (Table of Contents):
  search_curriculum(bookTitle: "Magaca Buugga", action: "get_table_of_contents")
  (Tool-ku wuxuu 1-mar si shuruud la'aan ah kuugu soo celinayaa dhammaan Cutubyada, Casharrada, iyo Qaybaha Sections ee buugga).

• Soo saarista cutub gaar ah:
  search_curriculum(bookTitle: "Magaca Buugga", action: "get_chapter", chapter: "Cutubka")

• Raadinta mawduuc gaar ah:
  search_curriculum(bookTitle: "Magaca Buugga", action: "search_topic", topic: "Mawduuca")

Tallaabada 2 (Soo Qaadashada Qoraalka & PDF-ka):
Geedka aad hesho ka dhex dooro casharka ama qaybta (section) saxda ah, kadibna toos u wac:
get_lesson_pdf(bookId: "...", chapterId: "...", lessonId: "...", sectionId: "...")
App-ku wuxuu kuu soo saari doonaa qoraalka rasmiga ah iyo PDF-ka si aad ardayga ugu sharaxdo.
Ha dhex gelin wareeg dheer; labadaas tallaabo toos u raac.
'''
        : '';

    final systemPrompt = toolExecutor == null
        ? baseSystemPrompt
        : '''
$baseSystemPrompt
$catalogSection
Marka ardaygu u baahan yahay xogta buugga, adigu wac qalabka ku habboon:
- search_curriculum: isticmaal "action": "get_table_of_contents" ama "get_chapter" ama "search_topic".
- get_lesson_pdf: soo qaado qoraalka iyo PDF-ka qaybta la helay.
Sheeko caadi ah iyo dabagal cashar hore si toos ah uga jawaab; ha wicin tool haddii aan xog cusub loo baahnayn.
Haddii aad sharaxaad manhaj ku salaysan bixinayso, raadi oo akhri PDF-ka ka hor intaadan jawaabin.
''';

    if (book == null) {
      final userPrompt =
          '''
${conversationContext.isEmpty ? '' : 'Wada-hadalkii dhowaa ee ardayga iyo macallinka (xasuuso macnaha iyo casharka hadda socda):\n$conversationContext\n\n'}
Fariinta ardayga: $question
''';
      onPromptGenerated?.call(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
      if (modelConfig != null) {
        onProgress?.call(
          'Xiriirinta ${modelConfig.company} (${modelConfig.displayName})...',
          2,
        );
        try {
          final res = modelConfig.isOpenAiCompatible
              ? await _callOpenAiCompatibleApi(
                  config: modelConfig,
                  systemPrompt: systemPrompt,
                  userPrompt: userPrompt,
                  cancellationToken: cancellationToken,
                  toolExecutor: toolExecutor,
                  onToolCall: onToolCall,
                  onModelCall: onModelCall,
                  turnContext: turnContext,
                )
              : await _callGeminiApi(
                  model: modelConfig.modelId,
                  apiKey: SupabaseConfig.isInitialized
                      ? ''
                      : await _resolveApiKey(modelConfig),
                  systemPrompt: systemPrompt,
                  userPrompt: userPrompt,
                  baseUrl: modelConfig.baseUrl,
                  cancellationToken: cancellationToken,
                  toolExecutor: toolExecutor,
                  onToolCall: onToolCall,
                  onModelCall: onModelCall,
                  turnContext: turnContext,
                );
          onProgress?.call('Habaynta sharraxaadda aqooneed ee Leyli AI...', 3);
          return res;
        } on GeminiCancelledException {
          rethrow;
        } catch (e) {
          if (cancellationToken?.isCancelled == true) {
            throw const GeminiCancelledException();
          }
          if (isTimeoutError(e)) {
            throw const GeminiTimeoutException();
          }
          if (isNetworkOrOfflineError(e)) {
            return offlineMessage;
          }
          if (e is GeminiBookChatException) rethrow;
          throw GeminiBookChatException(
            'Khalad ${modelConfig.displayName}: $e',
          );
        }
      }

      final apiKey = SupabaseConfig.isInitialized ? '' : await _resolveApiKey();
      onProgress?.call('Xiriirinta Google Gemini AI...', 2);
      String? lastError;
      for (final model in candidateModels) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        try {
          final res = await _callGeminiApi(
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            pdfBytes: null,
            cancellationToken: cancellationToken,
            toolExecutor: toolExecutor,
            onToolCall: onToolCall,
            onModelCall: onModelCall,
          );
          if (cancellationToken?.isCancelled == true) {
            throw const GeminiCancelledException();
          }
          onProgress?.call('Habaynta sharraxaadda aqooneed ee Leyli AI...', 3);
          return res;
        } on GeminiCancelledException {
          rethrow;
        } catch (e) {
          if (cancellationToken?.isCancelled == true) {
            throw const GeminiCancelledException();
          }
          lastError = e.toString();
        }
      }

      if (cancellationToken?.isCancelled == true) {
        throw const GeminiCancelledException();
      }

      if (isTimeoutError(lastError)) {
        return timeoutMessage;
      }

      if (isNetworkOrOfflineError(lastError)) {
        return offlineMessage;
      }

      onProgress?.call('Habaynta sharraxaadda aqooneed ee Leyli AI...', 3);
      return '''
### 🤖 Leyli AI

Soo dhawoow! Waxaan ahay Macallinkaaga Leyli AI.

Su'aashaada: *"$question"*

Waxaad i weydiin kartaa su'aal kasta oo ku saabsan maadooyinkaaga iyo casharradaada. Haddii aad rabto inaad buug manhajka ah barato, fadlan **Maktabadda** ka dooro buug si aynu casharradiisa iyo jaantusyadiisa toos u dhuuxno!
''';
    }

    onProgress?.call(
      slicedPdfBytes != null && slicedPdfBytes.isNotEmpty
          ? 'Akhrinta bogagga PDF-ka ee la gooyay...'
          : 'Dhuuxista bogagga casharka ee buugga...',
      1,
    );

    final activeKnowledge =
        knowledge ?? BookKnowledge(bookId: book.id, pages: const {});
    final excerpts = _findRelevantPages(
      book,
      activeKnowledge,
      question,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
    );

    final context = StringBuffer()
      ..writeln('Book: ${book.title}')
      ..writeln('Target Grade: ${book.category}')
      ..writeln('Current Scope:')
      ..writeln('- Chapter: ${focusChapter ?? 'Dhammaan'}')
      ..writeln('- Lesson: ${focusLesson ?? 'Dhammaan'}')
      ..writeln('- Section: ${focusSection ?? 'Dhammaan'}')
      ..writeln('\nRelevant book text fallback/context:');

    for (final page in excerpts) {
      context.writeln('--- Page $page ---');
      context.writeln(activeKnowledge.pages[page] ?? '');
    }
    context.writeln(
      _buildScopeNavigation(
        book,
        learningScopeType,
        focusChapter: focusChapter,
        focusLesson: focusLesson,
      ),
    );
    if (priorLearningContext.isNotEmpty) {
      context
        ..writeln(
          '\nCasharkii hore ee isla session-kan (u adeegso xasuus kooban; ha ku celcelin):',
        )
        ..writeln(priorLearningContext);
    }
    if (conversationContext.isNotEmpty) {
      context
        ..writeln(
          '\nWada-hadalkii dhowaa (xasuuso macnaha iyo ujeeddada ardayga):',
        )
        ..writeln(conversationContext);
    }

    final userPrompt = _buildUserPrompt(
      question: question,
      mode: mode,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
      startPosition: startPosition,
      endPosition: endPosition,
      hasPdf: slicedPdfBytes != null && slicedPdfBytes.isNotEmpty,
      context: context.toString(),
      learningScopeType: learningScopeType,
      learningPartNumber: learningPartNumber,
      learningPartCount: learningPartCount,
      isLessonCompletion: isLessonCompletion,
    );

    onPromptGenerated?.call(systemPrompt: systemPrompt, userPrompt: userPrompt);

    // Attempt call with custom model or fallback candidate models
    if (modelConfig != null) {
      onProgress?.call(
        'Weydiinta ${modelConfig.company} (${modelConfig.displayName})...',
        2,
      );
      try {
        final effectivePdf = slicedPdfBytes ?? turnContext?.discoveredPdfBytes;
        final res = modelConfig.isOpenAiCompatible
            ? await _callOpenAiCompatibleApi(
                config: modelConfig,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                cancellationToken: cancellationToken,
                toolExecutor: toolExecutor,
                onToolCall: onToolCall,
                onModelCall: onModelCall,
                turnContext: turnContext,
              )
            : await _callGeminiApi(
                model: modelConfig.modelId,
                apiKey: SupabaseConfig.isInitialized
                    ? ''
                    : await _resolveApiKey(modelConfig),
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                baseUrl: modelConfig.baseUrl,
                pdfBytes: effectivePdf,
                cancellationToken: cancellationToken,
                toolExecutor: toolExecutor,
                onToolCall: onToolCall,
                onModelCall: onModelCall,
                turnContext: turnContext,
              );
        onProgress?.call('Habaynta sharraxaadda aqooneed & koodhka...', 3);
        return res;
      } on GeminiCancelledException {
        rethrow;
      } catch (e) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        if (isTimeoutError(e)) {
          throw const GeminiTimeoutException();
        }
        if (isNetworkOrOfflineError(e)) {
          return offlineMessage;
        }
        if (e is GeminiBookChatException) rethrow;
        throw GeminiBookChatException('Khalad ${modelConfig.displayName}: $e');
      }
    }

    final apiKey = SupabaseConfig.isInitialized ? '' : await _resolveApiKey();
    onProgress?.call('Weydiinta Google Gemini AI & dhuuxista maaddada...', 2);
    String? lastError;
    for (final model in candidateModels) {
      if (cancellationToken?.isCancelled == true) {
        throw const GeminiCancelledException();
      }
      try {
        final res = await _callGeminiApi(
          model: model,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          pdfBytes: slicedPdfBytes,
          cancellationToken: cancellationToken,
          toolExecutor: toolExecutor,
          onToolCall: onToolCall,
          onModelCall: onModelCall,
        );
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        onProgress?.call('Habaynta sharraxaadda aqooneed & koodhka...', 3);
        return res;
      } on GeminiCancelledException {
        rethrow;
      } catch (e) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        lastError = e.toString();
      }
    }

    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }

    if (isTimeoutError(lastError)) {
      return timeoutMessage;
    }

    if (isNetworkOrOfflineError(lastError)) {
      return offlineMessage;
    }

    // High-fidelity local tutor fallback if online Gemini calls were unavailable
    onProgress?.call(
      'Habaynta sharraxaadda aqooneed ee Macallinka Leyli...',
      3,
    );
    return _generateLocalTutorResponse(
      book: book,
      knowledge: activeKnowledge,
      pages: excerpts,
      question: question,
      mode: mode,
      focusChapter: focusChapter,
      focusLesson: focusLesson,
      focusSection: focusSection,
      learningScopeType: learningScopeType,
      apiErrorMessage: lastError,
    );
  }

  String _buildSystemPrompt(
    TutorMode mode,
    LearningScopeType? learningScopeType,
  ) {
    if (mode == TutorMode.freeChat) {
      return '''
Waxaad tahay Leyli, macallin AI ah oo ardayga ula sheekaysta si dabiici ah.
Faham fariinta adigoo adeegsanaya macnaha wada-hadalka. Jawaab su'aasha hadda taagan si toos ah, Af-Soomaali cadna ku jawaab. Haddii xog gaar ah oo manhajka app-ka looga baahan yahay ay maqan tahay, dalbo tool-ka ku habboon; haddii kale jawaab adigoon tool wicin. Ha ku celin cashar dhan marka ardaygu weydiiyo dabagal kooban.
''';
    }
    return '''
Waxaad tahay Leyli AI, macallin Soomaaliyeed oo caqli badan, saaxiibtinimo leh, kuna takhasusay buugaagta manhajka dugsiyada (Form 1 - Form 4).
Hawshaada:
1. Waxaad wax u dhigaysaa arday dugsiga sare ah oo buuggiisu English ku qoran yahay. Marka lesson ama section la baranayo, English-ka iyo Af-Soomaaliga isku lammaanee si ardaygu u fahmo luqadda buugga iyo macnaha casharka labadaba.
2. Marka laguu soo diro qayb PDF ah (la jaray oo ah casharka la doortay oo keliya), dhuux oo si buuxda u aqri dhammaan bogaggeeda:
   - Qoraalka, cinwaannada, qeexitaannada, iyo qodobada ugu muhiimsan.
   - Sawirrada, jaantusyada (diagrams), shaxannada, qaababka (shapes), tusaalooyinka iyo qaacidooyinka ku xusan bogaggaas.
3. Haddii casharka ay ku jiraan jaantusyo ama sawirro (sida unugyada, wareegyada, hab-dhisyada, shaxanka, tijaabooyinka cilmiga ah), si gaar ah u sharax qaybaha jaantuska, waxa calaamad kasta u taagan tahay, iyo sida loogu adeegsado fahamka casharka.
4. Jawaabahaaga u habee qaab qurux badan: adeegso cinwaanno cadcad (###), qodobbo (bullet points), tusaalooyin fudud oo la xiriira nolosha Soomaalida, iyo su'aalo dhiirigelin ah.
5. Haddii xogta la weydiiyay aysan ku jirin qaybta PDF-ka ee la soo diray, si xushmad leh u sheeg in qaybtaan hadda la doortay aysan xogtaas wadan.
6. Ha samayn xigasho dheer oo buugga ah. Adeegso weedho English ah oo gaagaaban, erayo muhiim ah, iyo sharaxaaddaada waxbarasho.
7. ${_scopeRule(learningScopeType)}
8. Haddii PDF-ka qaybta la doortay leeyahay sawir, diagram, shaxan ama graph waxbarasho oo casharka fahankiisa muhiim u ah, ku sharax halka uu ku habboon yahay jawaabta. Ha xusin sawir qurxin ah ama aan waxbarasho lahayn.
9. Qaacidooyinka iyo Xisaabta (Math & Physics Formulas):
   - QAACIDOOYINKA KALI-TAAGAN EE WAAWEYN (Display Math): Ku qor qaabka LaTeX ee \$\$...\$\$, tusaale:
     \$\$y = A \\sin(2\\pi f t)\$\$
     \$\$v = u + at\$\$
     Marnaba ha gelin qaacidooyinka xisaabta iyo fiisigiska code blocks (```).
   - ERAYADA & CALAAMADAHA DHEX-YAALKA AH (Inline Math): Ku qor hal dollar sign \$x\$, sida \$t = 3.1\\text{ s}\$.
   - CINWAANNADA: Markaad cinwaan qorayso, isticmaal `### Magaca Cinwaanka` adigoo xariiq madhan ka hor marinaya cinwaanka, kana fogaanaya meelo bannaan oo u dhexeeya astaamaha (# # #).
''';
  }

  String _buildUserPrompt({
    required String question,
    required TutorMode mode,
    required String? focusChapter,
    required String? focusLesson,
    required String? focusSection,
    double startPosition = 0.0,
    double endPosition = 1.0,
    required bool hasPdf,
    required String context,
    LearningScopeType? learningScopeType,
    int? learningPartNumber,
    int? learningPartCount,
    bool isLessonCompletion = false,
  }) {
    final scopeName =
        focusSection ??
        focusLesson ??
        focusChapter ??
        (learningScopeType == LearningScopeType.book
            ? 'Buugga oo dhan'
            : 'Qaybtaan');
    final hasBoundaryCrop = (startPosition > 0.03) || (endPosition < 0.97);
    final boundaryDetail = (hasPdf && hasBoundaryCrop)
        ? '\n⚠️ XUDUUDDA GAARKA AH EE CASHARKAN: PDF-ka sare waxaa lagu soo gooyay oo lagu xaddiday kaliya inta u dhaxeysa xariiqda ${(startPosition * 100).toInt()}% ilaa ${(endPosition * 100).toInt()}% ee bogagga calaamadeysan. Qoraallada kale ee ka baxsan xariiqahaas (sida qaybta ka horreysa ama qaybta ka dambeysa) KUMA JIRAAN casharkan, fadlan kaliya sharax inta xadkaas ku dhex jirta.\n'
        : '';
    final pdfNotice = hasPdf
        ? 'Lifaaqa sare waa PDF-ka rasmiga ah ee qaybta "$scopeName" oo kaliya (waxaa ku jira qoraalka, sawirrada, jaantusyada, iyo qaababka casharka).$boundaryDetail'
        : 'Fiiro gaar ah: Halkan waxaa ku lifaaqan qoraalka buugga ee qaybta "$scopeName".';
    final learningFormat = _learningFormat(
      learningScopeType,
      scopeName,
      learningPartNumber: learningPartNumber,
      learningPartCount: learningPartCount,
      isLessonCompletion: isLessonCompletion,
    );

    switch (mode) {
      case TutorMode.teach:
        final studentNote =
            (question.trim().isNotEmpty &&
                question.trim().toLowerCase() != 'haa' &&
                question.trim().toLowerCase() != 'sax')
            ? '\nCodsiga/Su\'aasha gaarka ah ee Ardayga: "$question"\n'
            : '';
        return '''
$pdfNotice
$context

ARAGTIDA MACALLINKA (DEEP LESSON):
$learningFormat
$studentNote
Fadlan ardayga si faahfaahsan, hufan oo xiiso leh ugu dhig casharka/qaybta "$scopeName":
1. Ku bilow horudhac gaaban oo soo jiidasho leh.
2. Qodob-qodob oo tallaabo-tallaabo ah u sharax fikradaha ugu muhiimsan ee ku yaal bogaggaas.
3. Haddii ay casharkan ku jiraan jaantusyo (diagrams), sawirro ama shaxanno ku yaal PDF-ka, si cad u sharax qaybahooda iyo waxa ay muujinayaan.
4. Bixi ugu yaraan 1 tusaale oo la taaban karo oo nolosha dhabta ah ama deegaanka Soomaaliya ku saabsan.
5. Ku soo xir su'aal furan ama layli kooban oo ardaygu kaga fikiro casharka.
''';

      case TutorMode.visuals:
        return '''
$pdfNotice
$context

ARAGTIDA JAANTUSYADA & SAWIRRADA (VISUALS & DIAGRAMS):
Fadlan qaybta "$scopeName" ee PDF-ka ku jira si gaar ah uga soo saar dhammaan jaantusyada, sawirrada, shaxannada, ama jaantusyada cilmiga ah:
1. Jaantus kasta ku bixi cinwaan gaar ah oo ah `### [Magaca diagram-ka]` iyo `**Bogga PDF-ka:** [lambarka bogga ee lifaaqa]`.
2. Magacow ama sheeg sawir kasta / jaantus kasta oo bogagga casharkan ku yaal (haddii uu yahay jaantuska unugga, xubnaha, wareegga walxaha, shaxan xog ah, iwm).
3. Qodob-qodob u qor Labels & Parts: marka hore magaca English-ka ee label-ka, kadib micnihiisa iyo shaqadiisa Af-Soomaali.
4. Sharax dulucda cilmiyeed ee sawirkaas laga baranayo iyo sida uu ula xiriiro casharka.
5. Ku dhammee hal talo oo imtixaan: waxa ardaygu sawirka ka xafido ama ku calaamadiyo.
(Haddii bogaggaas aysan lahayn sawir ama jaantus cad, si cad u sheeg una bixi sharaxaad muuqaal-maskaxeed ah oo uu ardaygu wax ku sawiran karo).
''';

      case TutorMode.explain:
        return '''
$pdfNotice
$context

ARAGTIDA SHARAXAADDA FUDUD:
Fadlan qaybta "$scopeName" u sharax ardayga si aad u fudud oo qof kasta fahami karo.
- Adeegso luqad fudud iyo masaal ama sarbeeb nolosha maalinlaha ah laga fahmi karo.
- Haddii ay jiraan ereyo cilmiyeed adag, ku micnee ereyo Soomaali ah oo fudud.
''';

      case TutorMode.quiz:
        return '''
$pdfNotice
$context

ARAGTIDA QUIZ-KA:
Fadlan samee 3 ilaa 4 su'aalood oo is-tijaabin ah oo ku saabsan "$scopeName" (haddii ay jiraan sawirro ama jaantusyo, ku dar ugu yaraan 1 su'aal oo jaantus ku saabsan):
- Su'aal kasta ha lahaato 4 xulasho oo kala duwan (A, B, C, D).
- Dhamaadka qaybta quiz-ka ku qor jawaabaha saxda ah iyo sababta ay sax u yihiin si ardaygu isu saxo una barto qaladkiisa.
''';

      case TutorMode.summary:
        return '''
$pdfNotice
$context

ARAGTIDA DULOCDA (SUMMARY):
$learningFormat
Fadlan soo koob dhammaan qodobada ugu muhiimsan ee qaybta "$scopeName".
- Ku soo bandhig 4-5 qodob oo xusuusashada iyo imtixaanka u fiican.
- Xus erey-bixinnada muhiimka ah (Key Terms) iyo macnahooda.
''';

      case TutorMode.freeChat:
        return '''
$pdfNotice
$context

Fariinta ardayga: $question
Wada-hadalkii dhowaa iyo xogta buugga kore u adeegso marka ay su'aasha khuseeyaan. Jawaab fariinta ardayga si dabiici ah oo toos ah; sharax xogta PDF-ka marka codsigu u baahan yahay.
''';
    }
  }

  String _scopeRule(LearningScopeType? scopeType) {
    switch (scopeType) {
      case LearningScopeType.book:
        return 'Buugga oo dhan ayaa la doortay: bixi guudmar kooban oo buugga ah, sheeg chapters-ka ku jira, kadibna weydii chapter-ka ama lesson-ka ardaygu rabo. Ha bilaabin sharaxaad buug dhan ah.';
      case LearningScopeType.chapter:
        return 'Chapter ayaa la doortay: bixi guudmar chapter-ka, dulucdiisa, iyo lessons/sections-ka ku jira, kadibna weydii qaybta uu ardaygu rabo. Ha daadin sharaxaad chapter-ka oo dhan hal jawaab.';
      case LearningScopeType.lesson:
      case LearningScopeType.section:
        return 'Lesson ama section ayaa la doortay: jawaabta u habeey hordhac, English-ka muhiimka ah, sharaxaad Soomaali/English isku lammaan, tusaale ama jaantus haddii uu jiro, kadibna fahamsiin kooban oo Soomaali ah.';
      case null:
        return 'Haddii scope la doortay uu jiro, ku koob jawaabta scope-kaas oo ha isku darin casharro kale.';
    }
  }

  String _learningFormat(
    LearningScopeType? scopeType,
    String scopeName, {
    int? learningPartNumber,
    int? learningPartCount,
    bool isLessonCompletion = false,
  }) {
    switch (scopeType) {
      case LearningScopeType.book:
        return '''
QAABKA JAWAABTA BUUGGA:
1. ### Guudmar buugga
2. Chapters-ka iyo mawduuca mid kasta oo kooban
3. Ku soo xir su'aal cad: “Chapter ama lesson kee rabtaa inaan ku bilowno?”
''';
      case LearningScopeType.chapter:
        return '''
QAABKA JAWAABTA CHAPTER-KA:
1. ### Guudmar: $scopeName
2. Dulucda iyo erayada muhiimka ah
3. Lessons/sections-ka ku jira
4. Ku soo xir su'aal cad oo ardayga ka codsanaysa inuu doorto qayb uu baranayo
''';
      case LearningScopeType.lesson:
      case LearningScopeType.section:
        final partInstruction =
            learningPartNumber != null &&
                learningPartCount != null &&
                learningPartCount > 1
            ? 'Waxaad hadda sharxaysaa Qaybta $learningPartNumber/$learningPartCount oo keliya. Ha uga gudbin qayb kale; ardaygu isagaa dalbanaya qaybta xigta.'
            : '';
        final completionInstruction = isLessonCompletion
            ? '''
Waa qaybta ugu dambaysa. Ka dib sharaxaadda ku dar ### Casharka waa dhammaystiran yahay, ### Erayada muhiimka ah (English → Soomaali), iyo ### Is-tijaabi oo leh 3 su'aalood oo gaagaaban. Ha soo bandhigin batoon ama ha sheegin qayb xigta.
'''
            : '';
        return '''
QAABKA CASHARKA LABA-LUQADOODKA AH:
1. ### Hordhac kooban — waxa ardaygu baranayo.
2. ### English from the lesson — dooro 1 ilaa 3 weedhood ama fikrado English ah oo gaagaaban oo muhiim ah; ha koobiyeeyn bogag dheer.
3. ### Sharaxaadda macallinka — fikrad kasta kadib ku bixi sharaxaad Af-Soomaali ah, adigoo ilaalinaya erayga English-ka ee buugga.
4. ### Tusaale / Formula / Diagram — kaliya haddii ay ku jirto qaybta la doortay.
5. ### Soo koobid Af-Soomaali ah iyo hal su'aal oo faham hubin ah.
$partInstruction
$completionInstruction
''';
      case null:
        return '''
Haddii ardaygu doortay lesson ama section, u adeegso qaab laba-luqadood ah: English-ka muhiimka ah kadib sharaxaad Soomaali ah.
''';
    }
  }

  String _buildScopeNavigation(
    PreparedBook book,
    LearningScopeType? scopeType, {
    String? focusChapter,
    String? focusLesson,
  }) {
    if (scopeType == LearningScopeType.book || scopeType == null) {
      final chapters = book.chapters
          .map((chapter) => '- ${chapter.title}')
          .join('\n');
      return '\nAvailable chapters:\n${chapters.isEmpty ? '- Lama diyaarin' : chapters}';
    }

    if (scopeType == LearningScopeType.chapter) {
      final chapter = book.chapters.where((item) => item.title == focusChapter);
      final lessons = chapter.isEmpty
          ? const <PreparedLesson>[]
          : chapter.first.lessons;
      return '\nLessons in this chapter:\n${lessons.isEmpty ? '- Lama diyaarin' : lessons.map((lesson) => '- ${lesson.title}').join('\n')}';
    }

    if (scopeType == LearningScopeType.lesson) {
      PreparedLesson? lesson;
      for (final chapter in book.chapters) {
        for (final item in chapter.lessons) {
          if (item.title == focusLesson) {
            lesson = item;
            break;
          }
        }
      }
      final sections = lesson?.sections ?? const <PreparedSection>[];
      return '\nSections in this lesson:\n${sections.isEmpty ? '- Lama diyaarin' : sections.map((section) => '- ${section.title}').join('\n')}';
    }

    return '';
  }

  Future<String> _callGeminiApi({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    String? baseUrl,
    Uint8List? pdfBytes,
    CancellationToken? cancellationToken,
    AgentToolExecutor? toolExecutor,
    AgentToolCallObserver? onToolCall,
    AgentModelCallObserver? onModelCall,
    AgentTurnContext? turnContext,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }
    final client = _customClient ?? http.Client();
    final shouldClose = _customClient == null;
    cancellationToken?.attachClient(client);

    try {
      final parts = <Map<String, dynamic>>[];

      // If sliced PDF is available, attach it as application/pdf inline data
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        parts.add({
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': base64Encode(pdfBytes),
          },
        });
      }

      parts.add({'text': userPrompt});

      var base = baseUrl?.trim();
      if (base == null || base.isEmpty) {
        base = 'https://generativelanguage.googleapis.com';
      }
      if (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }

      final contents =
          (turnContext != null && turnContext.geminiContents.isNotEmpty)
          ? List<Map<String, dynamic>>.from(turnContext.geminiContents)
          : <Map<String, dynamic>>[
              {'role': 'user', 'parts': parts},
            ];

      for (var turn = 0; turn < 5; turn++) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        final request = <String, dynamic>{
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': contents,
          if (toolExecutor != null) ...{
            'tools': [
              {'functionDeclarations': _geminiAgentToolDeclarations},
            ],
            'toolConfig': {
              'functionCallingConfig': {'mode': 'AUTO'},
            },
          },
        };
        final modelStopwatch = Stopwatch()..start();
        http.Response response;
        try {
          if (SupabaseConfig.isInitialized) {
            final models = await const AiModelStorage().getModels();
            AiModelConfig? configuredModel;
            for (final candidate in models) {
              if (candidate.modelId == model &&
                  candidate.isActive &&
                  candidate.isVerified &&
                  !candidate.isOpenAiCompatible) {
                configuredModel = candidate;
                break;
              }
            }
            if (configuredModel == null) {
              throw GeminiBookChatException(
                'Model-ka $model kama jiro dejinta AI Manage ee cloud-ka.',
              );
            }
            response = await const AiGatewayClient()
                .generate(
                  modelId: configuredModel.id,
                  operation: 'chat',
                  body: request,
                )
                .timeout(defaultRequestTimeout);
          } else {
            response = await client
                .post(
                  Uri.parse('$base/v1beta/models/$model:generateContent'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-goog-api-key': apiKey,
                  },
                  body: jsonEncode(request),
                )
                .timeout(defaultRequestTimeout);
          }
        } catch (postErr) {
          modelStopwatch.stop();
          onModelCall?.call(
            AgentModelCallLog(
              stepIndex: turn + 1,
              callType: turn == 0
                  ? 'Codsiga 1aad ee Model-ka (Initial Analysis)'
                  : 'Codsiga ${turn + 1}aad ee Model-ka',
              latencyMs: modelStopwatch.elapsedMilliseconds,
              isSuccess: false,
              modelName: model,
              errorMessage: postErr.toString(),
              timestamp: DateTime.now(),
            ),
          );
          if (isTimeoutError(postErr)) {
            throw const GeminiTimeoutException();
          }
          rethrow;
        }
        modelStopwatch.stop();
        final modelLatencyMs = modelStopwatch.elapsedMilliseconds;

        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          String errDetail = response.body;
          try {
            final errJson = jsonDecode(response.body) as Map<String, dynamic>;
            errDetail =
                errJson['error']?['message']?.toString() ?? response.body;
          } catch (_) {}
          onModelCall?.call(
            AgentModelCallLog(
              stepIndex: turn + 1,
              callType: 'Codsiga ${turn + 1}aad ee Model-ka ($model)',
              latencyMs: modelLatencyMs,
              isSuccess: false,
              modelName: model,
              errorMessage: 'HTTP ${response.statusCode}: $errDetail',
              timestamp: DateTime.now(),
            ),
          );
          if (response.statusCode == 503 ||
              errDetail.toLowerCase().contains('high demand') ||
              errDetail.toLowerCase().contains('overloaded')) {
            throw const GeminiModelBusyException(
              'Model-ku hadda wuu mashquulsan yahay (503 High Demand / Ciriiri).',
              statusCode: 503,
            );
          }
          if (response.statusCode == 429 ||
              errDetail.toLowerCase().contains('resource_exhausted') ||
              errDetail.toLowerCase().contains('quota')) {
            throw const GeminiModelBusyException(
              'Model-ku wuxuu gaaray xadka codsiyada (429 Rate Limit / Quota Exceeded).',
              statusCode: 429,
            );
          }
          if (response.statusCode == 404) {
            throw GeminiBookChatException(
              'Model-ka lama helin (404 Not Found): "$model". Fadlan hubi magaca saxda ah ee Google Model-ka.',
            );
          }
          throw GeminiBookChatException(
            'API Khalad (${response.statusCode}): $errDetail',
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        final firstCandidate = candidates?.isNotEmpty == true
            ? candidates!.first as Map<String, dynamic>?
            : null;
        final content = firstCandidate?['content'] as Map<String, dynamic>?;
        final resParts = content?['parts'] as List<dynamic>? ?? const [];
        final calls = resParts
            .whereType<Map<String, dynamic>>()
            .map((part) => part['functionCall'])
            .whereType<Map<String, dynamic>>()
            .toList();

        onModelCall?.call(
          AgentModelCallLog(
            stepIndex: turn + 1,
            callType: calls.isNotEmpty
                ? 'Tallaabada ${turn + 1}: Falanqaynta & Codsashada Tool-ka (${calls.map((c) => c['name']).join(', ')})'
                : (turn == 0
                      ? 'Tallaabada 1: Jawaabta Tooska ah ee Model-ka'
                      : 'Tallaabada ${turn + 1}: Qorista Jawaabta Dhammaystiran'),
            latencyMs: modelLatencyMs,
            isSuccess: true,
            modelName: model,
            timestamp: DateTime.now(),
          ),
        );
        if (calls.isNotEmpty && toolExecutor != null && content != null) {
          contents.add(content);
          final functionResponses = <Map<String, dynamic>>[];
          for (final call in calls) {
            final name = call['name'] as String? ?? '';
            final rawArgs = call['args'];
            final args = rawArgs is Map
                ? rawArgs.map((key, value) => MapEntry(key.toString(), value))
                : <String, dynamic>{};
            final stopwatch = Stopwatch()..start();
            Map<String, dynamic> result;
            var succeeded = true;
            String? errorMessage;
            try {
              result = await toolExecutor(name, args);
            } catch (error) {
              succeeded = false;
              errorMessage = error.toString();
              result = {'error': errorMessage};
            }
            stopwatch.stop();
            final pdfBytes = result.remove('_pdfBytes');
            onToolCall?.call(
              AgentToolCallLog(
                toolId: name,
                toolName: name,
                arguments: args,
                outputSummary: succeeded
                    ? (result['summary']?.toString() ?? 'Tool completed')
                    : 'Tool failed',
                rawOutput: _traceSafeToolOutput(result),
                latencyMs: stopwatch.elapsedMilliseconds,
                isSuccess: succeeded,
                errorMessage: errorMessage,
                timestamp: DateTime.now(),
              ),
            );
            functionResponses.add({
              'functionResponse': {'name': name, 'response': result},
            });
            if (pdfBytes is Uint8List && pdfBytes.isNotEmpty) {
              turnContext?.discoveredPdfBytes = pdfBytes;
              functionResponses.add({
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Encode(pdfBytes),
                },
              });
            }
          }
          contents.add({'role': 'user', 'parts': functionResponses});
          turnContext?.geminiContents = List<Map<String, dynamic>>.from(
            contents,
          );
          continue;
        }

        final buffer = StringBuffer();
        for (final part in resParts.whereType<Map<String, dynamic>>()) {
          if (part['thought'] == true) continue;
          final partText = part['text'] as String?;
          if (partText != null && partText.isNotEmpty) buffer.write(partText);
        }
        final text = buffer.toString().trim();
        if (text.isEmpty) {
          throw const GeminiBookChatException(
            'Jawaab madhan ayaa soo noqotay.',
          );
        }
        return text;
      }
      throw const GeminiBookChatException(
        'Tool-ku wuxuu dhaafay tirada isku-dayada la oggol yahay.',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  Future<String> _callOpenAiCompatibleApi({
    required AiModelConfig config,
    required String systemPrompt,
    required String userPrompt,
    CancellationToken? cancellationToken,
    AgentToolExecutor? toolExecutor,
    AgentToolCallObserver? onToolCall,
    AgentModelCallObserver? onModelCall,
    AgentTurnContext? turnContext,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const GeminiCancelledException();
    }
    final apiKey = SupabaseConfig.isInitialized
        ? ''
        : await const AiApiKeyResolver().resolve(
            model: config,
            provider: config.company,
          );
    final client = _customClient ?? http.Client();
    final shouldClose = _customClient == null;
    cancellationToken?.attachClient(client);

    try {
      var baseUrl = config.baseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final chatUrl = baseUrl.endsWith('/chat/completions')
          ? baseUrl
          : '$baseUrl/chat/completions';

      final messages =
          (turnContext != null && turnContext.openAiMessages.isNotEmpty)
          ? List<Map<String, dynamic>>.from(turnContext.openAiMessages)
          : <Map<String, dynamic>>[
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ];
      for (var turn = 0; turn < 5; turn++) {
        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }
        final request = <String, dynamic>{
          'model': config.modelId,
          'messages': messages,
          if (toolExecutor != null) ...{
            'tools': _openAiAgentToolDeclarations,
            'tool_choice': 'auto',
          },
        };
        final modelStopwatch = Stopwatch()..start();
        http.Response response;
        try {
          if (SupabaseConfig.isInitialized) {
            response = await const AiGatewayClient()
                .generate(modelId: config.id, operation: 'chat', body: request)
                .timeout(defaultRequestTimeout);
          } else {
            response = await client
                .post(
                  Uri.parse(chatUrl),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $apiKey',
                  },
                  body: jsonEncode(request),
                )
                .timeout(defaultRequestTimeout);
          }
        } catch (postErr) {
          modelStopwatch.stop();
          onModelCall?.call(
            AgentModelCallLog(
              stepIndex: turn + 1,
              callType: turn == 0
                  ? 'Codsiga 1aad ee Model-ka (Initial Analysis)'
                  : 'Codsiga ${turn + 1}aad ee Model-ka',
              latencyMs: modelStopwatch.elapsedMilliseconds,
              isSuccess: false,
              modelName: config.displayName,
              errorMessage: postErr.toString(),
              timestamp: DateTime.now(),
            ),
          );
          if (isTimeoutError(postErr)) {
            throw const GeminiTimeoutException();
          }
          rethrow;
        }
        modelStopwatch.stop();
        final modelLatencyMs = modelStopwatch.elapsedMilliseconds;

        if (cancellationToken?.isCancelled == true) {
          throw const GeminiCancelledException();
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          String errDetail = response.body;
          try {
            final errJson = jsonDecode(response.body) as Map<String, dynamic>;
            errDetail =
                errJson['error']?['message']?.toString() ?? response.body;
          } catch (_) {}
          onModelCall?.call(
            AgentModelCallLog(
              stepIndex: turn + 1,
              callType:
                  'Codsiga ${turn + 1}aad ee Model-ka (${config.displayName})',
              latencyMs: modelLatencyMs,
              isSuccess: false,
              modelName: config.displayName,
              errorMessage: 'HTTP ${response.statusCode}: $errDetail',
              timestamp: DateTime.now(),
            ),
          );
          if (response.statusCode == 401) {
            throw GeminiBookChatException(
              'API Key-ga lama aqbalin (401 Unauthorized). Fadlan hubi furahaaga ${config.company}.',
            );
          }
          if (response.statusCode == 503 ||
              errDetail.toLowerCase().contains('overloaded') ||
              errDetail.toLowerCase().contains('high demand')) {
            throw GeminiModelBusyException(
              'Model-ka ${config.displayName} hadda wuu mashquulsan yahay (503 High Demand / Ciriiri).',
              statusCode: 503,
            );
          }
          if (response.statusCode == 429 ||
              errDetail.toLowerCase().contains('rate limit') ||
              errDetail.toLowerCase().contains('insufficient_quota') ||
              errDetail.toLowerCase().contains('quota')) {
            throw GeminiModelBusyException(
              'Model-ka ${config.displayName} wuxuu gaaray xadka codsiyada (429 Rate Limit / Quota).',
              statusCode: 429,
            );
          }
          if (response.statusCode == 404) {
            throw GeminiBookChatException(
              'Model-ka lama helin (404 Not Found): "${config.modelId}". Hubi magaca saxda ah.',
            );
          }
          throw GeminiBookChatException(
            'API Khalad (${response.statusCode}): $errDetail',
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        final first = choices?.isNotEmpty == true
            ? choices!.first as Map<String, dynamic>?
            : null;
        final message = first?['message'] as Map<String, dynamic>?;
        final toolCalls = message?['tool_calls'] as List<dynamic>? ?? const [];

        onModelCall?.call(
          AgentModelCallLog(
            stepIndex: turn + 1,
            callType: toolCalls.isNotEmpty
                ? 'Tallaabada ${turn + 1}: Falanqaynta & Codsashada Tool-ka (${toolCalls.length} calls)'
                : (turn == 0
                      ? 'Tallaabada 1: Jawaabta Tooska ah ee Model-ka'
                      : 'Tallaabada ${turn + 1}: Qorista Jawaabta Dhammaystiran'),
            latencyMs: modelLatencyMs,
            isSuccess: true,
            modelName: config.displayName,
            timestamp: DateTime.now(),
          ),
        );
        if (toolCalls.isNotEmpty && toolExecutor != null && message != null) {
          messages.add(message);
          for (final item in toolCalls.whereType<Map<String, dynamic>>()) {
            final call = item['function'] as Map<String, dynamic>? ?? const {};
            final name = call['name'] as String? ?? '';
            Map<String, dynamic> args = {};
            try {
              final parsed = jsonDecode(call['arguments'] as String? ?? '{}');
              if (parsed is Map) {
                args = parsed.map(
                  (key, value) => MapEntry(key.toString(), value),
                );
              }
            } catch (_) {}
            final stopwatch = Stopwatch()..start();
            Map<String, dynamic> result;
            var succeeded = true;
            String? errorMessage;
            try {
              result = await toolExecutor(name, args);
            } catch (error) {
              succeeded = false;
              errorMessage = error.toString();
              result = {'error': errorMessage};
            }
            stopwatch.stop();
            result.remove('_pdfBytes');
            onToolCall?.call(
              AgentToolCallLog(
                toolId: name,
                toolName: name,
                arguments: args,
                outputSummary: succeeded
                    ? (result['summary']?.toString() ?? 'Tool completed')
                    : 'Tool failed',
                rawOutput: _traceSafeToolOutput(result),
                latencyMs: stopwatch.elapsedMilliseconds,
                isSuccess: succeeded,
                errorMessage: errorMessage,
                timestamp: DateTime.now(),
              ),
            );
            messages.add({
              'role': 'tool',
              'tool_call_id': item['id'],
              'name': name,
              'content': jsonEncode(result),
            });
          }
          turnContext?.openAiMessages = List<Map<String, dynamic>>.from(
            messages,
          );
          continue;
        }
        final content = message?['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          throw const GeminiBookChatException(
            'Jawaab madhan ayaa soo noqotay.',
          );
        }
        return content.trim();
      }
      throw const GeminiBookChatException(
        'Tool-ku wuxuu dhaafay tirada isku-dayada la oggol yahay.',
      );
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  List<int> _findRelevantPages(
    PreparedBook book,
    BookKnowledge knowledge,
    String question, {
    String? focusChapter,
    String? focusLesson,
    String? focusSection,
  }) {
    final allowed = <int>{};
    for (final chapter in book.chapters) {
      final chapterMatch =
          focusChapter == null || chapter.title == focusChapter;
      for (final lesson in chapter.lessons) {
        final lessonMatch = focusLesson == null || lesson.title == focusLesson;
        for (final section in lesson.sections) {
          final sectionMatch =
              focusSection == null || section.title == focusSection;
          if (chapterMatch && lessonMatch && sectionMatch) {
            for (var p = section.startPage; p <= section.endPage; p++) {
              allowed.add(p);
            }
          }
        }
        if (focusSection == null && chapterMatch && lessonMatch) {
          for (var p = lesson.startPage; p <= lesson.endPage; p++) {
            allowed.add(p);
          }
        }
      }
      if (focusLesson == null && focusSection == null && chapterMatch) {
        for (var p = chapter.startPage; p <= chapter.endPage; p++) {
          allowed.add(p);
        }
      }
    }

    // If no specific scope filter was matched, allow all pages
    final targetPages = allowed.isNotEmpty
        ? allowed
        : knowledge.pages.keys.toSet();

    final terms = question
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 2)
        .toSet();

    if (terms.isEmpty) {
      final sorted = targetPages.toList()..sort();
      return sorted.take(6).toList();
    }

    final scored = targetPages.map((pageNumber) {
      final text = knowledge.pages[pageNumber] ?? '';
      final words = text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).toSet();
      final score = terms.where(words.contains).length;
      return (page: pageNumber, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    final matched = scored
        .where((s) => s.score > 0)
        .map((s) => s.page)
        .toList();
    if (matched.isNotEmpty) {
      return matched.take(6).toList();
    }

    final sorted = targetPages.toList()..sort();
    return sorted.take(6).toList();
  }

  /// High-value local tutor generator to ensure offline & demo reliability
  String _generateLocalTutorResponse({
    required PreparedBook book,
    required BookKnowledge knowledge,
    required List<int> pages,
    required String question,
    required TutorMode mode,
    required String? focusChapter,
    required String? focusLesson,
    required String? focusSection,
    LearningScopeType? learningScopeType,
    String? apiErrorMessage,
  }) {
    final scopeTitle =
        focusSection ?? focusLesson ?? focusChapter ?? book.title;
    final combinedText = pages
        .map((p) => knowledge.pages[p] ?? '')
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');

    final cleanExcerpt = combinedText.trim().isNotEmpty
        ? combinedText
        : _synthesizeFallbackKnowledge(
            book: book,
            scopeTitle: scopeTitle,
            question: question,
          );

    final errorNotice = apiErrorMessage != null
        ? '> ⚠️ *Fiiro gaar ah: ${_friendlyApiError(apiErrorMessage)} Jawaabtan waxaa kuu diyaariyay Leyli AI.*\n\n'
        : '';

    if (learningScopeType == LearningScopeType.book) {
      final chapters = book.chapters.isEmpty
          ? '- Chapters-ka buuggan weli lama diyaarin.'
          : book.chapters.map((chapter) => '- ${chapter.title}').join('\n');
      return '''
$errorNotice### 📚 Guudmar: ${book.title}

Buuggani waa **${book.title}** oo loogu talagalay **${book.category}**.

### Chapters-ka buugga
$chapters

Chapter ama lesson kee rabtaa inaan ku bilowno?
''';
    }

    if (learningScopeType == LearningScopeType.chapter) {
      final chapter = book.chapters.where((item) => item.title == focusChapter);
      final lessons = chapter.isEmpty
          ? const <PreparedLesson>[]
          : chapter.first.lessons;
      final lessonList = lessons.isEmpty
          ? '- Lessons-ka chapter-kan weli lama diyaarin.'
          : lessons.map((lesson) => '- ${lesson.title}').join('\n');
      return '''
$errorNotice### 📖 Guudmar: $scopeTitle

Chapter-kan wuxuu ka tirsan yahay **${book.title}** (${book.category}). Hoos waxaa ku qoran lessons-ka uu ka kooban yahay:

$lessonList

Lesson ama section kee rabtaa inaan kuu sharaxo?
''';
    }

    switch (mode) {
      case TutorMode.teach:
        return '''
$errorNotice### 📖 Casharka: $scopeTitle
Ku soo dhawoow barashada **$scopeTitle** ee buugga *${book.title}* (${book.category})!

#### 📌 Qodobada Muhiimka ah & Sharaxaadda:
$cleanExcerpt

#### 💡 Tusaale & Faham Dheeraad ah:
Fikradahan waxaa loogu talagalay inay ardayda fasalka **${book.category}** ka caawiyaan fahamka buuxa ee manhajka iyo sida casharku ugu xiran yahay nolosheenna dhabta ah.

Haddii aad qabto su'aal gaar ah ama faahfaahin dheeraad ah oo ku saabsan qaybtaan, fadlan qor si aan si qoto dheer kuugu sharaxo!
''';

      case TutorMode.visuals:
        return '''
$errorNotice### 🖼️ Sharaxaadda Sawirrada & Jaantusyada: $scopeTitle

Halkan waxaa ku yaal falanqaynta jaantusyada, shaxannada, iyo xogta sawirran ee qaybta **$scopeTitle**:

#### 🔍 Jaantusyada & Qaybaha Muhiimka ah:
$cleanExcerpt

#### 💡 Sida loo Fahmo Muuqaalka & Jaantuska:
- Jaantusyada casharkan waxay muujinayaan sida qaybaha kala duwan isugu xiran yihiin iyo habka wareegga/dhaqdhaqaaqa.
- Xusuuso calaamadaha, halbeegyada, iyo cinwaannada ku dul qoran si aad imtixaanka ugu faa'iidaysato.

*Haddii aad qabto su'aal gaar ah oo ku saabsan sawir ama jaantus gaar ah, fadlan hoos ku qor!*
''';

      case TutorMode.explain:
        return '''
$errorNotice### 💡 Sharaxaadda Fudud ee: $scopeTitle

Halkan waxaa ku yaal nuxurka ugu muhiimsan ee loo fududeeyay ardayga:

$cleanExcerpt

**Tusaale Sahal ah**: Markaad eegto mowduucan, u arag sidii dhisidda tallaabooyinka aasaasiga ah ee cilmigan. Qodob kasta wuxuu taageerayaa kan ku xiga!
''';

      case TutorMode.quiz:
        return '''
$errorNotice### 📝 Is-tijaabi (Quiz): $scopeTitle

**Su'aasha 1-aad:**
Maxay tahay dulucda ugu weyn ee looga hadlay $scopeTitle?
- A) Qeexidda guud iyo qaybaha muhiimka ah
- B) Taariikhda cilmiga oo keliya
- C) Xisaabinta caalamiga ah
- D) Ma jirto mid sax ah

**Su'aasha 2-aad:**
Qodobkee ayaa ugu muhiimsan nuxurka qoraalka kor ku xusan?
- A) Fahamka iyo adeegsiga saxda ah
- B) Kaliya xafididda ereyada
- C) Iska iloobidda xaqiiqooyinka
- D) Dhammaan waa sax

---
✅ **Jawaabaha Saxda ah:**
1. **A** - Sababtoo ah qoraalku wuxuu si toos ah u sharaxayaa qodobada aasaasiga ah.
2. **A** - Fahamka dhabta ah ayaa saldhig u ah barashada maadadan.
''';

      case TutorMode.summary:
        return '''
$errorNotice### 📌 Dulucda & Qodobada Muhiimka ah ($scopeTitle)

- **Maadada:** ${book.title} (${book.category})
- **Qaybta Diiradda:** $scopeTitle
- **Bogagga la xiriira:** ${pages.isEmpty ? 'Dhammaan' : pages.join(', ')}

**Qodobada Ugu Waaweyn:**
$cleanExcerpt
''';

      case TutorMode.freeChat:
        return '''
$errorNotice### 📚 Sharaxaadda Casharka: $scopeTitle

Waad ku mahadsan tahay su'aashaada ku saabsan **$scopeTitle** ee maaddada *${book.title} (${book.category})*.

Su'aashaada: *"$question"*

---
#### 🇬🇧 English from the lesson:
$cleanExcerpt

#### 🇸🇴 Sharaxaadda Macallinka:
Qoraalka kore wuxuu ka hadlayaa fikradaha muhiimka ah ee **$scopeTitle**. Akhri erayada English-ka ah, kadibna ku xiriiri qeexitaannada, qaacidooyinka, iyo tusaalooyinka casharka.

#### 💡 Hubin Faham:
Maxay tahay fikradda ugu muhiimsan ee aad ka fahamtay qaybtaan?
''';
    }
  }

  String _friendlyApiError(String error) {
    if (error.contains('503')) return 'Gemini hadda wuu mashquulsan yahay.';
    if (error.contains('429')) {
      return 'Codsiyo badan ayaa jira; fadlan mar kale isku day wax yar kadib.';
    }
    if (error.contains('401') || error.contains('403')) {
      return 'Furaha Gemini lama aqbalin.';
    }
    return 'Xiriirka Google Gemini ma suuroobin xilligan.';
  }

  String _synthesizeFallbackKnowledge({
    required PreparedBook book,
    required String scopeTitle,
    required String question,
  }) {
    final lowerScope = scopeTitle.toLowerCase();
    final isPhysics =
        book.title.toLowerCase().contains('phy') ||
        lowerScope.contains('motion') ||
        lowerScope.contains('frequency') ||
        lowerScope.contains('period') ||
        lowerScope.contains('wave');

    if (isPhysics) {
      return '''
1. **Qeexidda Guud:**
   - **Periodic Motion (Dhaqdhaqaaqa Xilliga ah)**: Waa dhaqdhaqaaq kasta oo dib isugu soo laabta muddooyin waqti oo is le'eg ka dib (sida lulashada pendulum-ka, wareegga meerayaasha, ama gariirka xadhigga gitaarka).
   - **Period (\\\$T\\\$ / Xilli)**: Waa waqtiga ay ku qaadato hal wareeg ama hal lulasho oo buuxda (Complete Cycle). Waxaa lagu cabbiraa ilbiriqsi (s).
   - **Frequency (\\\$f\\\$ / Jeer-jeer)**: Waa tirada wareegyada ama lulashada ee dhacda hal ilbiriqsi gudaheed. Waxaa lagu cabbiraa Hertz (Hz ama 1/s).

2. **Xiriirka Xisaabeed & Qaacidooyinka:**
   - f = 1 / T  *(Frequency-gu waa rogganka Period-ka)*
   - T = 1 / f  *(Period-ku waa rogganka Frequency-ga)*
   - Haddii xilligu (T) kordho, jeer-jeerku (f) wuu yaraadaa, waana xiriir rogganta ah (Inverse Relationship).

3. **Tusaale Faham ah:**
   - Haddii lulashadu sameyso 20 wareeg 4 ilbiriqsi gudaheed:
     - Period (T) = 4 / 20 = 0.2 ilbiriqsi.
     - Frequency (f) = 1 / 0.2 = 5 Hz.
''';
    }

    return '''
Mowduuca **$scopeTitle** ee maaddada *${book.title} (${book.category})* wuxuu xambaarsan yahay fikradaha saldhigga u ah cutubkan:
- **Dulucda Koowaad:** Fahamka qeexitaannada, erey-bixinnada, iyo sharciyada la xiriira $scopeTitle.
- **Dulucda Labaad:** Sida casharkani ugu xiran yahay qaybaha kale ee manhajka fasalka ${book.category}.
- **Qodobada Xusuusta:** Dib-u-eegista qaababka, tusaalooyinka, iyo su'aalaha caadiga ah ee imtixaanka lagu weydiin karo.
''';
  }
}

class GeminiBookChatException implements Exception {
  const GeminiBookChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GeminiModelBusyException extends GeminiBookChatException {
  const GeminiModelBusyException(super.message, {this.statusCode});
  final int? statusCode;
}

class GeminiCancelledException implements Exception {
  const GeminiCancelledException([this.message = 'Shaqada waa la joojiyay']);
  final String message;

  @override
  String toString() => message;
}

class CancellationToken {
  bool _isCancelled = false;
  http.Client? _activeClient;

  bool get isCancelled => _isCancelled;

  void attachClient(http.Client client) {
    _activeClient = client;
  }

  void cancel() {
    _isCancelled = true;
    try {
      _activeClient?.close();
    } catch (_) {}
  }
}

class GeminiTimeoutException extends GeminiBookChatException {
  const GeminiTimeoutException([
    super.message =
        '⚠️ Waqtigii jawaabta ayaa dhacay (Timeout ka badan 3 daqiiqo). Model-ku wuu raagay ama culeys ayaa jira.',
  ]);
}

class AgentTurnContext {
  AgentTurnContext({
    List<Map<String, dynamic>>? geminiContents,
    List<Map<String, dynamic>>? openAiMessages,
    this.discoveredPdfBytes,
  }) : geminiContents = geminiContents ?? [],
       openAiMessages = openAiMessages ?? [];

  List<Map<String, dynamic>> geminiContents;
  List<Map<String, dynamic>> openAiMessages;
  Uint8List? discoveredPdfBytes;

  bool get hasPriorTurnHistory =>
      geminiContents.length > 1 || openAiMessages.length > 2;
}
