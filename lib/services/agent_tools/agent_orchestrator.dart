import 'dart:convert';
import 'dart:math';

import '../../models/agent_execution_trace.dart';
import '../../models/ai_model_config.dart';
import '../agent_trace_storage.dart';
import '../ai_model_storage.dart';
import '../ai_routing_storage.dart';
import '../form_preference_storage.dart';
import '../gemini_book_chat_service.dart';
import 'curriculum_search_tool.dart';
import 'pdf_retriever_tool.dart';
import 'verification_gate_tool.dart';

class AgentOrchestratorResponse {
  const AgentOrchestratorResponse({
    required this.traceId,
    required this.displayMessage,
    required this.status,
    this.matchedMatch,
    this.retrieverResult,
    this.verificationResult,
    this.suggestedReplies = const [],
    this.continueWithChat = false,
    required this.internalThought,
  });

  final String traceId;
  final String displayMessage;
  final AgentVerificationStatus status;
  final CurriculumSearchMatch? matchedMatch;
  final PdfRetrieverResult? retrieverResult;
  final VerificationGateResult? verificationResult;
  final List<String> suggestedReplies;

  /// True when the student is chatting or following up and curriculum tools
  /// are not needed for this turn.
  final bool continueWithChat;
  final String internalThought;
}

class AgentFeedbackResolution {
  const AgentFeedbackResolution({
    required this.traceId,
    required this.isConfirmed,
    required this.feedbackText,
    required this.responseText,
    this.matchedMatch,
    this.alternativeLessons = const [],
  });

  final String traceId;
  final bool isConfirmed;
  final String feedbackText;
  final String responseText;
  final CurriculumSearchMatch? matchedMatch;
  final List<CurriculumSearchMatch> alternativeLessons;
}

class _FeedbackAiEvaluation {
  const _FeedbackAiEvaluation({
    required this.isConfirmed,
    required this.intent,
    required this.teacherResponse,
    required this.reasoning,
  });

  final bool isConfirmed;
  final String intent;
  final String teacherResponse;
  final String reasoning;
}

class AgentOrchestrator {
  AgentOrchestrator({
    CurriculumSearchTool? searchTool,
    PdfRetrieverTool? retrieverTool,
    AgentTraceStorage? traceStorage,
    FormPreferenceStorage? formStorage,
    GeminiBookChatService? chatService,
    AiModelStorage? modelStorage,
    AiRoutingStorage? routingStorage,
  }) : _searchTool = searchTool ?? CurriculumSearchTool(),
       _retrieverTool = retrieverTool ?? PdfRetrieverTool(),
       _traceStorage = traceStorage ?? AgentTraceStorage.instance,
       _formStorage = formStorage ?? const FormPreferenceStorage(),
       _chatService = chatService ?? GeminiBookChatService(),
       _modelStorage = modelStorage ?? const AiModelStorage(),
       _routingStorage = routingStorage ?? const AiRoutingStorage();

  final CurriculumSearchTool _searchTool;
  final PdfRetrieverTool _retrieverTool;
  final AgentTraceStorage _traceStorage;
  final FormPreferenceStorage _formStorage;
  final GeminiBookChatService _chatService;
  final AiModelStorage _modelStorage;
  final AiRoutingStorage _routingStorage;
  final Map<String, CurriculumSearchMatch> _toolMatches = {};
  CurriculumSearchMatch? _lastToolMatch;

  CurriculumSearchMatch? get lastToolMatch => _lastToolMatch;

  void beginToolTurn() {
    _toolMatches.clear();
    _lastToolMatch = null;
  }

  /// Executes only the tools declared to the model. Returned PDF bytes are
  /// passed back to Gemini as inline PDF data and are stripped from trace JSON.
  Future<Map<String, dynamic>> executeToolCall(
    String name,
    Map<String, dynamic> arguments, {
    required String formLevel,
    String conversationContext = '',
  }) async {
    if (!await _traceStorage.isToolEnabled(name)) {
      throw GeminiBookChatException(
        'Tool-ka $name waxaa damiyay maamulka app-ka.',
      );
    }
    if (name == 'search_curriculum') {
      final action = arguments['action']?.toString().trim();
      final bookTitle = (arguments['bookTitle'] ?? arguments['book'])
          ?.toString()
          .trim();
      final chapter = (arguments['chapter'] ??
              arguments['chapterTitle'] ??
              arguments['chapterNumber'])
          ?.toString()
          .trim();
      final topic = (arguments['topic'] ?? arguments['searchTopic'])
          ?.toString()
          .trim();
      final query = arguments['query']?.toString().trim() ?? '';

      if (query.isEmpty &&
          (bookTitle == null || bookTitle.isEmpty) &&
          (action == null || action.isEmpty) &&
          (topic == null || topic.isEmpty)) {
        return {'found': false, 'summary': 'Search parameters were empty'};
      }
      final result = await _searchTool.search(
        action: action,
        bookTitle: bookTitle,
        chapter: chapter,
        topic: topic,
        query: query,
        explicitFormLevel: formLevel,
        conversationContext: conversationContext,
      );
      final matches = [
        if (result.bestMatch != null) result.bestMatch!,
        ...result.alternatives,
        ...result.allDiscoveredMatches,
      ];
      for (final match in matches) {
        _toolMatches[_toolMatchKey(match)] = match;
      }
      _lastToolMatch = result.bestMatch ??
          (result.allDiscoveredMatches.isNotEmpty
              ? result.allDiscoveredMatches.first
              : null);
      return result.toAgentResponse();
    }

    if (name == 'get_lesson_pdf') {
      final bookId = arguments['bookId']?.toString().trim() ?? '';
      final chapterId = arguments['chapterId']?.toString().trim() ?? '';
      final lessonId = arguments['lessonId']?.toString().trim() ?? '';
      final sectionId = arguments['sectionId']?.toString().trim();
      final bookTitle = (arguments['bookTitle'] ?? arguments['book'])
          ?.toString()
          .trim()
          .toLowerCase();
      final lessonTitle = (arguments['lessonTitle'] ?? arguments['lesson'])
          ?.toString()
          .trim()
          .toLowerCase();
      final sectionTitle = (arguments['sectionTitle'] ?? arguments['section'])
          ?.toString()
          .trim()
          .toLowerCase();

      CurriculumSearchMatch? match;
      for (final candidate in _toolMatches.values) {
        final bMatch = (bookId.isNotEmpty && candidate.book.id == bookId) ||
            (bookTitle != null &&
                bookTitle.isNotEmpty &&
                candidate.book.title.toLowerCase().contains(bookTitle));
        final lMatch =
            (lessonId.isNotEmpty && candidate.lesson.id == lessonId) ||
                (lessonTitle != null &&
                    lessonTitle.isNotEmpty &&
                    candidate.lesson.title.toLowerCase().contains(lessonTitle));
        final cMatch =
            chapterId.isEmpty || candidate.chapter.id == chapterId;
        final sMatch = (sectionId == null ||
                sectionId.isEmpty ||
                candidate.section?.id == sectionId) &&
            (sectionTitle == null ||
                sectionTitle.isEmpty ||
                (candidate.section?.title.toLowerCase().contains(sectionTitle) ??
                    false));

        if (bMatch && lMatch && cMatch && sMatch) {
          match = candidate;
          break;
        }
      }

      // If not in _toolMatches, search directly in curriculum catalog
      match ??= await _searchTool.findDirectMatch(
        bookId: bookId,
        chapterId: chapterId,
        lessonId: lessonId,
        sectionId: sectionId,
        bookTitle: bookTitle,
        lessonTitle: lessonTitle,
        sectionTitle: sectionTitle,
      );

      if (match == null) {
        return {
          'found': false,
          'summary':
              'Ma helin casharka la codsaday. Fadlan marka hore wac search_curriculum si aad u hesho Table of Contents ama casharka saxda ah.',
        };
      }
      _toolMatches[_toolMatchKey(match)] = match;

      final retrieved = await _retrieverTool.retrieveContent(
        book: match.book,
        startPage: match.startPage,
        endPage: match.endPage,
        lessonId: match.lesson.id,
        startPosition:
            match.section?.startPosition ?? match.lesson.startPosition,
        endPosition: match.section?.endPosition ?? match.lesson.endPosition,
      );
      _lastToolMatch = match;
      return {
        'found': true,
        'summary': retrieved.summaryReason,
        'match': match.toCleanTitlesJson(),
        'extractedText': retrieved.extractedTextSummary ?? '',
        'pdfAvailable': retrieved.isPdfSourceAvailable,
        '_pdfBytes': retrieved.slicedPdfBytes,
      };
    }

    throw GeminiBookChatException('Tool aan la aqoon: $name');
  }

  String _toolMatchKey(CurriculumSearchMatch match) =>
      '${match.book.id}:${match.chapter.id}:${match.lesson.id}:${match.section?.id ?? ''}';

  /// Reads the student turn, chooses between direct tutoring and curriculum
  /// lookup, then retrieves the exact published curriculum scope when needed.
  Future<AgentOrchestratorResponse> processStudentInput({
    required String userMessage,
    String? explicitFormLevel,
    String conversationContext = '',
    AiModelConfig? modelConfig,
  }) async {
    final overallStopwatch = Stopwatch()..start();
    final traceId =
        'trace_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final studentForm =
        explicitFormLevel ?? await _formStorage.getSelectedForm();

    final toolCalls = <AgentToolCallLog>[];
    final thoughts = <String>[];

    final routeStopwatch = Stopwatch()..start();
    final shouldSearch = await _shouldSearchCurriculum(
      userMessage: userMessage,
      conversationContext: conversationContext,
      formLevel: studentForm,
      modelConfig: modelConfig,
    );
    routeStopwatch.stop();
    final routeCall = AgentToolCallLog(
      toolId: 'intent_router',
      toolName: 'Model-Driven Intent Router',
      arguments: {'form': studentForm, 'message': userMessage},
      outputSummary: shouldSearch
          ? 'AI chose curriculum search tools'
          : 'AI chose direct conversation',
      rawOutput: {'curriculumLookup': shouldSearch},
      latencyMs: routeStopwatch.elapsedMilliseconds,
      isSuccess: true,
      timestamp: DateTime.now(),
    );
    if (!shouldSearch) {
      final thought =
          'AI-gu wuxuu doortay wada-hadal toos ah; raadinta manhajka looma baahna.';
      await _traceStorage.recordTrace(
        AgentExecutionTrace(
          id: traceId,
          timestamp: DateTime.now(),
          userMessage: userMessage,
          studentForm: studentForm,
          internalThought: thought,
          status: AgentVerificationStatus.accepted,
          totalLatencyMs: routeStopwatch.elapsedMilliseconds,
          toolCalls: [routeCall],
          isSuccess: true,
        ),
      );
      return AgentOrchestratorResponse(
        traceId: traceId,
        displayMessage: '',
        status: AgentVerificationStatus.searching,
        internalThought: thought,
        continueWithChat: true,
      );
    }
    toolCalls.add(routeCall);
    thoughts.add('AI-gu wuxuu doortay in manhajka app-ka laga raadiyo.');

    thoughts.add(
      'Ardaygu wuxuu soo qoray: "$userMessage". Fasalka xiran waa $studentForm. Waxaan baarayaa buugaagta manhajka ee fasalkaas.',
    );

    // 1. Tool Execution: Curriculum Catalog Search
    final searchStopwatch = Stopwatch()..start();
    final searchResult = await _searchTool.search(
      query: userMessage,
      explicitFormLevel: studentForm,
      conversationContext: conversationContext,
    );
    searchStopwatch.stop();

    toolCalls.add(
      AgentToolCallLog(
        toolId: 'curriculum_search',
        toolName: 'Curriculum Catalog Search',
        arguments: {'query': userMessage, 'form': studentForm},
        outputSummary: searchResult.hasMatch
            ? 'Match: ${searchResult.bestMatch?.lesson.title} (${searchResult.bestMatch?.book.title})'
            : 'No match in $studentForm',
        rawOutput: searchResult.toJson(),
        latencyMs: searchStopwatch.elapsedMilliseconds,
        isSuccess: true,
        timestamp: DateTime.now(),
      ),
    );

    thoughts.add(searchResult.internalThought);

    // If no match found in this Form
    if (!searchResult.hasMatch || searchResult.bestMatch == null) {
      overallStopwatch.stop();
      final trace = AgentExecutionTrace(
        id: traceId,
        timestamp: DateTime.now(),
        userMessage: userMessage,
        studentForm: studentForm,
        internalThought: thoughts.join(' -> '),
        status: AgentVerificationStatus.accepted,
        totalLatencyMs: overallStopwatch.elapsedMilliseconds,
        toolCalls: toolCalls,
        isSuccess: true,
      );

      await _traceStorage.recordTrace(trace);

      return AgentOrchestratorResponse(
        traceId: traceId,
        displayMessage: '',
        status: AgentVerificationStatus.searching,
        internalThought: thoughts.join(' -> '),
        continueWithChat: true,
      );
    }

    final match = searchResult.bestMatch!;

    // 2. Tool Execution: PDF Content Retriever
    final retrieverStopwatch = Stopwatch()..start();
    final retrieverResult = await _retrieverTool.retrieveContent(
      book: match.book,
      startPage: match.startPage,
      endPage: match.endPage,
      lessonId: match.lesson.id,
      startPosition: match.section?.startPosition ?? match.lesson.startPosition,
      endPosition: match.section?.endPosition ?? match.lesson.endPosition,
    );
    retrieverStopwatch.stop();

    toolCalls.add(
      AgentToolCallLog(
        toolId: 'pdf_retriever',
        toolName: 'PDF Slice Content Retriever',
        arguments: {
          'bookId': match.book.id,
          'startPage': match.startPage,
          'endPage': match.endPage,
        },
        outputSummary: retrieverResult.summaryReason,
        rawOutput: retrieverResult.toJson(),
        latencyMs: retrieverStopwatch.elapsedMilliseconds,
        isSuccess: true,
        timestamp: DateTime.now(),
      ),
    );

    thoughts.add(
      'PDF-ka bogagga ${match.startPage}-${match.endPage} waa la gooyay/helay (${retrieverResult.latencyMs}ms).',
    );

    thoughts.add(
      'Casharka saxda ah iyo xogta PDF-ka waa la helay; ardayga si toos ah ayaa loogu gudbinayaa macallinka AI-ga.',
    );

    overallStopwatch.stop();

    // 4. Record Trace in Storage
    final trace = AgentExecutionTrace(
      id: traceId,
      timestamp: DateTime.now(),
      userMessage: userMessage,
      studentForm: studentForm,
      internalThought: thoughts.join(' -> '),
      status: AgentVerificationStatus.accepted,
      matchedBookId: match.book.id,
      matchedBookTitle: match.book.title,
      matchedCategory: match.book.category,
      matchedChapterTitle: match.chapter.title,
      matchedLessonTitle: match.lesson.title,
      startPage: match.startPage,
      endPage: match.endPage,
      concisePreviewAnswer: retrieverResult.extractedTextSummary,
      totalLatencyMs: overallStopwatch.elapsedMilliseconds,
      toolCalls: toolCalls,
      isSuccess: true,
    );

    await _traceStorage.recordTrace(trace);

    return AgentOrchestratorResponse(
      traceId: traceId,
      displayMessage: '',
      status: AgentVerificationStatus.accepted,
      matchedMatch: match,
      retrieverResult: retrieverResult,
      internalThought: thoughts.join(' -> '),
    );
  }

  Future<bool> _shouldSearchCurriculum({
    required String userMessage,
    required String conversationContext,
    required String formLevel,
    AiModelConfig? modelConfig,
  }) async {
    try {
      final targetModel = modelConfig ?? await _getActiveModel();
      final prompt =
          '''
Waxaad tahay macallin AI go'aaminaya tallaabada xigta ee Leyli.
Fasalka ardayga: $formLevel
Wada-hadalkii dhowaa:
${conversationContext.isEmpty ? '(ma jiro)' : conversationContext}

Fariinta hadda:
$userMessage

Go'aami in fariintan ay u baahan tahay in buug/cutub/cashar/qayb laga raadiyo manhajka app-ka.
- curriculumLookup=true marka ardaygu raadinayo cashar ama buug gaar ah, ama codsigiisu u baahan yahay xogta buugga manhajka.
- curriculumLookup=false marka ay tahay su'aal guud, jawaab/follow-up ku saabsan sharaxaad hore, codsi ah in si kale loo sharaxo, ama sheeko aan u baahnayn in cashar cusub la helo.
Ha ku khasbin raadinta cashar fariin dabagal ah oo macnaheedu caddaanayo wada-hadalka.
Soo celi KELIYA JSON: {"curriculumLookup": true|false}
''';
      final raw = await _chatService.ask(
        question: prompt,
        conversationContext: conversationContext,
        modelConfig: targetModel,
      );
      final json = _extractJson(raw);
      if (json == null) return true;
      final value =
          (jsonDecode(json) as Map<String, dynamic>)['curriculumLookup'];
      return value is bool ? value : true;
    } catch (_) {
      // Keep discovery available if the intent model is unavailable.
      return true;
    }
  }

  Future<AiModelConfig?> _getActiveModel() async {
    final routed = await _routingStorage.getActiveTierModels();
    if (routed.isNotEmpty) return routed.first;
    final models = await _modelStorage.getModels();
    return models.where((m) => m.isActive && m.isVerified).firstOrNull;
  }

  /// Evaluates student feedback using active AI Model intelligence,
  /// with a robust fallback to natural Somali affirmative expressions.
  Future<AgentFeedbackResolution> handleStudentFeedback({
    required String traceId,
    required String feedbackText,
    CurriculumSearchMatch? currentMatch,
    List<CurriculumSearchMatch> alternatives = const [],
    AiModelConfig? modelConfig,
  }) async {
    final clean = feedbackText.trim().toLowerCase();

    // 1. First, attempt to evaluate dynamically with the AI Model
    final aiEval = await _evaluateFeedbackWithAiModel(
      feedbackText: feedbackText,
      currentMatch: currentMatch,
      modelConfig: modelConfig,
    );

    final bool isConfirmed;
    final String responseText;
    final String reasoning;

    if (aiEval != null) {
      isConfirmed = aiEval.isConfirmed;
      reasoning = 'AI Model (${aiEval.intent}): ${aiEval.reasoning}';
      if (aiEval.teacherResponse.trim().isNotEmpty) {
        responseText = aiEval.teacherResponse.trim();
      } else if (isConfirmed) {
        final lessonTitle = currentMatch?.lesson.title ?? 'casharka';
        responseText =
            'Aad baa u fiican! Aan guda galno faahfaahinta buuxda ee **$lessonTitle**.\n\n'
            'Ugu horreyn, dulucda ugu weyn ee aad u baahan tahay inaad fahamto waa qodobbada soo socda...';
      } else {
        responseText = _buildRejectionResponse(alternatives);
      }
    } else {
      // 2. Intelligent Heuristic Fallback
      isConfirmed = _isPositiveConfirmation(clean);
      reasoning = isConfirmed
          ? 'Aqoonsi hordhac ah: Ardaygu wuxuu muujiyay ogolaansho buuxa ("$feedbackText").'
          : 'Aqoonsi hordhac ah: Ardaygu ma aqbalin casharkan ("$feedbackText").';

      if (isConfirmed) {
        final lessonTitle = currentMatch?.lesson.title ?? 'casharka';
        final bookTitle = currentMatch?.book.title ?? '';
        final chapterTitle = currentMatch?.chapter.title ?? '';
        final pagesStr = (currentMatch != null)
            ? ' (Bogagga ${currentMatch.startPage}-${currentMatch.endPage})'
            : '';
        responseText =
            'Aad baa u fiican! Aan si toos ah u guda galno barashada casharka **$lessonTitle** ee buugga *$bookTitle*$pagesStr.\n\n'
            '### Hordhaca & Dulucda Casharka:\n'
            'Casharkani wuxuu si toos ah uga tirsan yahay cutubka **$chapterTitle** ee manhajka rasmiga ah ee dawladda.\n\n'
            'Waxaan ku baran doonaa qodobada ugu muhiimsan, macnaha fikradaha, iyo tusaalooyinka buugga ku jira. Qoraalka rasmiga ah ee PDF-ka waxaad ka heli kartaa qoraalka hoose ee "MANHAJKA DOOWLADA".';
      } else {
        responseText = _buildRejectionResponse(alternatives);
      }
    }

    await _traceStorage.updateTraceFeedback(
      traceId: traceId,
      isConfirmed: isConfirmed,
      studentFeedback: feedbackText,
      reasoningUpdate: reasoning,
    );

    return AgentFeedbackResolution(
      traceId: traceId,
      isConfirmed: isConfirmed,
      feedbackText: feedbackText,
      responseText: responseText,
      matchedMatch: currentMatch,
      alternativeLessons: isConfirmed ? const [] : alternatives,
    );
  }

  Future<_FeedbackAiEvaluation?> _evaluateFeedbackWithAiModel({
    required String feedbackText,
    CurriculumSearchMatch? currentMatch,
    AiModelConfig? modelConfig,
  }) async {
    try {
      AiModelConfig? targetModel = modelConfig;
      if (targetModel == null) {
        final tierModels = await _routingStorage.getActiveTierModels();
        if (tierModels.isNotEmpty) {
          targetModel = tierModels.first;
        } else {
          final all = await _modelStorage.getModels();
          targetModel = all
              .where((m) => m.isActive && m.isVerified)
              .firstOrNull;
        }
      }

      final lessonTitle = currentMatch?.lesson.title ?? 'casharka';
      final chapterTitle = currentMatch?.chapter.title ?? '';
      final bookTitle = currentMatch?.book.title ?? '';
      final grade = currentMatch?.book.category ?? '';

      final prompt =
          '''
Waxaad tahay Leyli Educational Autonomous AI Teacher.
Arday fasalka $grade ah ayaa hore wax loo weydiiyay, waxaana la soo hordhigay casharka:
- Buugga: $bookTitle
- Cutubka: $chapterTitle
- Casharka: $lessonTitle

Su'aashii xaqiijinta ee ardayga hore loo weydiiyay waxay ahayd:
"Ma casharkan ayaad u jeeddaa?"

Ardaygu hadda wuxuu soo qoray jawaabtan:
"$feedbackText"

SHAQADAADA:
1. Fasir Jawaabta Ardayga (Intent):
   - Ardaygu ma aqbalay oo ma doonayaa casharkan? (Haddii uu qoray: "haa", "sax", "waa isaga casharka aan rabo", "kan baan rabay", "haye bilow", "fadlan iigu dhaqaaq", "isaga weeye", "kan uun", ama weedh kasta oo ogolaansho muujinaysa -> CONFIRMED).
   - Ardaygu ma diiday oo ma wuxuu doonayaa cashar/wax kale? (Haddii uu yiri: "maya", "maaha kan", "wax kale ayaan rabay", "beddel", iwm -> REJECTED).
   - Ardaygu ma su'aal hordhac ah ayuu weydiiyay ama faahfaahin dheeraad ah ayuu codsaday? (-> QUESTION).

2. Qor jawaab macallinnimo oo Soomaali ah oo ardayga loogu jawaabo:
   - Haddii uu CONFIRMED yahay: Ku bishaaree si diirran, una sheeg inaad toos u guda galaysaan casharka "$lessonTitle", una qor horudhac kooban oo dhiirrigelin leh.
   - Haddii uu REJECTED yahay: Si asluub leh u sheeg inaad fahamtay inuusan kani ahayn kii uu rabay, kuna dhiirrigeli inuu kuu sheego mawduuca ama cutubka uu rabo.

Ku soo celi KELIYA JSON sax ah oo qaabkan ah (wax kale ha soo raacin):
{
  "isConfirmed": true,
  "intent": "CONFIRMED",
  "teacherResponse": "Jawaabtaada tooska ah ee ardayga...",
  "reasoning": "Sharaxaadda sababta go'aankan loo gaaray"
}
''';

      final rawResponse = await _chatService.ask(
        question: prompt,
        modelConfig: targetModel,
      );

      final cleanJson = _extractJson(rawResponse);
      if (cleanJson == null) return null;

      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
      final isConfirmed = parsed['isConfirmed'] as bool? ?? false;
      final intent =
          parsed['intent'] as String? ??
          (isConfirmed ? 'CONFIRMED' : 'REJECTED');
      final teacherResponse = parsed['teacherResponse'] as String? ?? '';
      final reasoning = parsed['reasoning'] as String? ?? '';

      return _FeedbackAiEvaluation(
        isConfirmed: isConfirmed,
        intent: intent,
        teacherResponse: teacherResponse,
        reasoning: reasoning,
      );
    } catch (_) {
      return null;
    }
  }

  String _buildRejectionResponse(List<CurriculumSearchMatch> alternatives) {
    final buffer = StringBuffer();
    buffer.writeln('Waa fahmay inuusan kani ahayn casharkii aad raadinaysay.');

    if (alternatives.isNotEmpty) {
      buffer.writeln(
        '\nMa kuwan kale ee ku dhow fasalkaaga midkood ayaad u jeedday?',
      );
      for (var i = 0; i < alternatives.length; i++) {
        final alt = alternatives[i];
        buffer.writeln('${i + 1}. **${alt.lesson.title}** (${alt.book.title})');
      }
    } else {
      buffer.writeln(
        '\nFadlan ii sheeg cinwaanka saxda ah ama buugga iyo cutubka aad doonayso si aan toos kuugu geeyo.',
      );
    }
    return buffer.toString();
  }

  String? _extractJson(String text) {
    var clean = text.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('```')) {
      clean = clean.substring(3);
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    clean = clean.trim();

    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return clean.substring(start, end + 1);
    }
    return null;
  }

  bool _isPositiveConfirmation(String text) {
    final clean = text.trim().toLowerCase();

    // Direct negative checks first (prevent false positive if student says "maya haa ma dhihin")
    const explicitNegativePhrases = [
      'maya',
      'ma aha',
      'maaha',
      'ma rabo',
      'ma doonayo',
      'kale',
      'wax kale',
      'kuma jiro',
      'beddel',
      'qalad',
      'khalad',
    ];

    if (explicitNegativePhrases.any(
      (neg) => clean.startsWith(neg) || clean == neg,
    )) {
      return false;
    }

    const positiveKeywords = [
      'haa',
      'sax',
      'waa kaas',
      'waa sax',
      'ok',
      'yes',
      'sii wad',
      'ii sharax',
      'sharax',
      'run',
      'sax weeye',
      'saxbaa',
      // Natural Somali confirmation phrases
      'waa isaga',
      'isaga',
      'aan rabo',
      'aan rabay',
      'kan baan rabaa',
      'kan baan rabay',
      'waa kan',
      'kan uun',
      'isaga weeye',
      'wuu yahay',
      'haye',
      'waayahay',
      'bilow',
      'dhaqaaq',
      'guda gal',
      'iiga bilow',
      'fadlan',
      'dhab',
      'kaas weeye',
      'kaas waaye',
      'kan waaye',
      'waa iska cadahay',
      'waa taa',
      'waa taas',
    ];

    for (final kw in positiveKeywords) {
      if (clean.contains(kw)) return true;
    }
    return false;
  }
}
