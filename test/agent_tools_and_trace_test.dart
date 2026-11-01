import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/agent_execution_trace.dart';
import 'package:leyli/models/agent_tool_config.dart';
import 'package:leyli/services/agent_trace_storage.dart';
import 'package:leyli/services/agent_tools/agent_orchestrator.dart';
import 'package:leyli/services/agent_tools/curriculum_search_tool.dart';
import 'package:leyli/services/agent_tools/pdf_retriever_tool.dart';
import 'package:leyli/services/agent_tools/verification_gate_tool.dart';
import 'package:leyli/models/prepared_book.dart';
import 'package:leyli/services/prepared_book_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AgentToolConfig & Trace Models', () {
    test('Default tools list contains expected built-in tools', () {
      final defaults = AgentToolConfig.defaultTools;
      expect(defaults.length, 5);
      final ids = defaults.map((t) => t.id).toList();
      expect(ids, contains('curriculum_search'));
      expect(ids, contains('pdf_retriever'));
      expect(ids, contains('verification_gate'));
      expect(ids, contains('deep_tutor'));
      expect(ids, contains('clarification_guide'));
    });

    test('AgentExecutionTrace serializes and deserializes correctly', () {
      final trace = AgentExecutionTrace(
        id: 'trace_test_1',
        timestamp: DateTime(2026, 10, 14, 10, 0),
        userMessage: 'Unugyada nolosha ii sharax',
        studentForm: 'Form 1',
        internalThought: 'Testing internal reasoning thought',
        status: AgentVerificationStatus.pendingConfirmation,
        matchedBookId: 'sample_form1_bio',
        matchedBookTitle: 'Sayniska Guud & Nolosha',
        matchedCategory: 'Form 1',
        matchedChapterTitle: 'Cutubka 1: Unugyada & Nolosha',
        matchedLessonTitle: 'Casharka 1: Waa Maxay Unug?',
        startPage: 1,
        endPage: 5,
        concisePreviewAnswer: 'Unuggu waa xubinta ugu yar ee nolosha.',
        verificationQuestion: 'Ma casharkan ayaad u jeeddaa?',
        totalLatencyMs: 350,
        toolCalls: [
          AgentToolCallLog(
            toolId: 'curriculum_search',
            toolName: 'Curriculum Search',
            arguments: {'query': 'Unugyada'},
            outputSummary: 'Found lesson',
            latencyMs: 40,
            isSuccess: true,
            timestamp: DateTime(2026, 10, 14, 10, 0),
          ),
        ],
      );

      final encoded = trace.encode();
      final decoded = AgentExecutionTrace.decode(encoded);

      expect(decoded.id, 'trace_test_1');
      expect(decoded.studentForm, 'Form 1');
      expect(decoded.matchedLessonTitle, 'Casharka 1: Waa Maxay Unug?');
      expect(decoded.toolCalls.length, 1);
      expect(decoded.toolCalls.first.toolId, 'curriculum_search');
    });
  });

  group('CurriculumSearchTool with Strict Form Constraint', () {
    test('Searches strictly within Form 1 when Form 1 is active', () async {
      final tool = CurriculumSearchTool();
      final result = await tool.search(
        query: 'Unug',
        explicitFormLevel: 'Form 1',
      );

      expect(result.searchedFormLevel, 'Form 1');
      expect(result.hasMatch, isTrue);
      expect(result.bestMatch?.book.category, 'Form 1');
      expect(result.bestMatch?.lesson.title, contains('Unug'));
    });

    test('Searches strictly within Form 2 when Form 2 is active', () async {
      final tool = CurriculumSearchTool();
      final result = await tool.search(
        query: 'Atom',
        explicitFormLevel: 'Form 2',
      );

      expect(result.searchedFormLevel, 'Form 2');
      expect(result.hasMatch, isTrue);
      expect(result.bestMatch?.book.category, 'Form 2');
      expect(result.bestMatch?.lesson.title, contains('Atom'));
    });

    test('Resolves colloquial query: "waxaan rabaa ibarto buuga business casharkiisa 1aad" with exact boundary', () async {
      // Save a Form 2 Business Studies book
      const businessBook = PreparedBook(
        id: 'form2_business_test',
        title: 'Business Studies - Fasalka 2aad',
        originalFileName: 'business_f2.pdf',
        pageCount: 50,
        category: 'Form 2',
        status: PreparedBookStatus.published,
        chapters: [
          PreparedChapter(
            id: 'c1',
            title: 'Cutubka 1: Hordhaca Ganacsiga',
            startPage: 1,
            endPage: 20,
            lessons: [
              PreparedLesson(
                id: 'c1_l1',
                title: 'Casharka 1: Macnaha & Ujeedooyinka Ganacsiga',
                startPage: 1,
                endPage: 10,
                startPosition: 0.0,
                endPosition: 1.0,
              ),
              PreparedLesson(
                id: 'c1_l2',
                title: 'Casharka 2: Noocyada Ganacsiga',
                startPage: 11,
                endPage: 20,
              ),
            ],
          ),
        ],
      );

      await const PreparedBookStorage().save(businessBook);

      final tool = CurriculumSearchTool();
      final result = await tool.search(
        query: 'waxaan rabaa ibarto buuga business casharkiisa 1aad',
        explicitFormLevel: 'Form 2',
      );

      expect(result.hasMatch, isTrue);
      expect(result.bestMatch?.book.id, 'form2_business_test');
      expect(result.bestMatch?.chapter.title, 'Cutubka 1: Hordhaca Ganacsiga');
      expect(result.bestMatch?.lesson.title, 'Casharka 1: Macnaha & Ujeedooyinka Ganacsiga');
      expect(result.bestMatch?.startPage, 1);
      expect(result.bestMatch?.endPage, 10);
    });

    test('Does not match topics from other forms when not present in current form', () async {
      final tool = CurriculumSearchTool();
      // 'Atomic Structure' or chemistry topic searched in Form 4 history
      final result = await tool.search(
        query: 'Falgalada Kiimikada',
        explicitFormLevel: 'Form 4',
      );

      expect(result.searchedFormLevel, 'Form 4');
      // In sample data, Form 4 is History, so Chemistry will not match
      expect(result.hasMatch, isFalse);
      expect(result.internalThought, contains('Form 4'));
    });
  });

  group('VerificationGateTool', () {
    test('Builds concise preview, page numbers and Somali verification question', () async {
      final searchTool = CurriculumSearchTool();
      final searchResult = await searchTool.search(
        query: 'Unug',
        explicitFormLevel: 'Form 1',
      );

      expect(searchResult.hasMatch, isTrue);
      final match = searchResult.bestMatch!;

      final retrieverTool = PdfRetrieverTool();
      final retrieverResult = await retrieverTool.retrieveContent(
        book: match.book,
        startPage: match.startPage,
        endPage: match.endPage,
      );

      const gateTool = VerificationGateTool();
      final gateResult = gateTool.formulateVerification(
        match: match,
        retrieverResult: retrieverResult,
        userQuery: 'Unug',
      );

      expect(gateResult.bookTitle, contains('Sayniska'));
      expect(gateResult.lessonTitle, contains('Unug'));
      expect(
        gateResult.verificationQuestion,
        'Ma casharkan ayaad u jeeddaa si aan si faahfaahsan kuugu sharaxo?',
      );
      expect(gateResult.fullVerificationMessage, contains('📖 **Waxaan helay casharka aad codsatay:**'));
      expect(gateResult.suggestedReplies, contains('Haa, si buuxda ii sharax'));
      expect(gateResult.suggestedReplies, contains('Maya, ma aha kan'));
    });
  });

  group('AgentOrchestrator & Feedback Loop', () {
    test('End-to-end process input, log trace, and handle positive confirmation', () async {
      final orchestrator = AgentOrchestrator();

      // Process input without manual book selection
      final response = await orchestrator.processStudentInput(
        userMessage: 'Waxaan rabaa casharka unugyada nolosha',
        explicitFormLevel: 'Form 1',
      );

      expect(response.status, AgentVerificationStatus.pendingConfirmation);
      expect(response.traceId.isNotEmpty, isTrue);
      expect(response.displayMessage, contains('Unug'));
      expect(response.matchedMatch?.book.category, 'Form 1');

      // Check that trace was recorded in storage
      final traces = await AgentTraceStorage.instance.getTraces();
      expect(traces.length, 1);
      expect(traces.first.id, response.traceId);
      expect(traces.first.status, AgentVerificationStatus.pendingConfirmation);
      expect(traces.first.toolCalls.length, 3); // search, retriever, gate

      // Student says "Haa, sax weeye"
      final feedback = await orchestrator.handleStudentFeedback(
        traceId: response.traceId,
        feedbackText: 'Haa, sax weeye ii sharax',
        currentMatch: response.matchedMatch,
      );

      expect(feedback.isConfirmed, isTrue);
      expect(feedback.responseText, contains('Aad baa u fiican'));

      // Check that trace updated status to accepted
      final updatedTraces = await AgentTraceStorage.instance.getTraces();
      expect(updatedTraces.first.status, AgentVerificationStatus.accepted);
      expect(updatedTraces.first.studentFeedback, 'Haa, sax weeye ii sharax');
    });

    test('Handles student rejection and returns clarification guide', () async {
      final orchestrator = AgentOrchestrator();

      final response = await orchestrator.processStudentInput(
        userMessage: 'Unugyada',
        explicitFormLevel: 'Form 1',
      );

      // Student rejects
      final feedback = await orchestrator.handleStudentFeedback(
        traceId: response.traceId,
        feedbackText: 'Maya, kan ma aha',
        currentMatch: response.matchedMatch,
      );

      expect(feedback.isConfirmed, isFalse);
      expect(feedback.responseText, contains('Waa fahmay'));

      final updatedTraces = await AgentTraceStorage.instance.getTraces();
      expect(updatedTraces.first.status, AgentVerificationStatus.rejected);
    });

    test('Handles natural colloquial affirmation like "waa isaga casharka aan rabo" as confirmed', () async {
      final orchestrator = AgentOrchestrator();

      final response = await orchestrator.processStudentInput(
        userMessage: 'Unugyada',
        explicitFormLevel: 'Form 1',
      );

      final feedback = await orchestrator.handleStudentFeedback(
        traceId: response.traceId,
        feedbackText: 'waa isaga casharka aan rabo',
        currentMatch: response.matchedMatch,
      );

      expect(feedback.isConfirmed, isTrue);
      expect(feedback.responseText, contains('Aad baa u fiican'));

      final updatedTraces = await AgentTraceStorage.instance.getTraces();
      expect(updatedTraces.first.status, AgentVerificationStatus.accepted);
      expect(updatedTraces.first.studentFeedback, 'waa isaga casharka aan rabo');
    });

    test('AgentTraceStorage computes summary statistics correctly', () async {
      await AgentTraceStorage.instance.recordTrace(AgentExecutionTrace(
        id: 'trace_summary_test',
        timestamp: DateTime.now(),
        userMessage: 'Test',
        studentForm: 'Form 1',
        internalThought: 'Test thought',
        status: AgentVerificationStatus.accepted,
        totalLatencyMs: 120,
        toolCalls: [
          AgentToolCallLog(
            toolId: 'curriculum_search',
            toolName: 'Curriculum Search',
            arguments: {},
            latencyMs: 30,
            isSuccess: true,
            timestamp: DateTime.now(),
          ),
          AgentToolCallLog(
            toolId: 'pdf_retriever',
            toolName: 'PDF Retriever',
            arguments: {},
            latencyMs: 50,
            isSuccess: true,
            timestamp: DateTime.now(),
          ),
          AgentToolCallLog(
            toolId: 'verification_gate',
            toolName: 'Verification Gate',
            arguments: {},
            latencyMs: 10,
            isSuccess: true,
            timestamp: DateTime.now(),
          ),
        ],
      ));

      final summary = await AgentTraceStorage.instance.getSummary();
      expect(summary.totalTraces, greaterThanOrEqualTo(1));
      expect(summary.toolUsageCounts, contains('curriculum_search'));
      expect(summary.toolUsageCounts, contains('pdf_retriever'));
      expect(summary.toolUsageCounts, contains('verification_gate'));
    });
  });
}
