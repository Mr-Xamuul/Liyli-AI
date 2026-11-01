import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/agent_execution_trace.dart';
import 'package:leyli/models/agent_tool_config.dart';
import 'package:leyli/services/agent_trace_storage.dart';
import 'package:leyli/widgets/agent_admin/agent_observability_workspace.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AgentObservabilityWorkspace Widget Tests', () {
    testWidgets('Renders KPI cards, tab switcher, and tools registry', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Seed a sample trace
      await AgentTraceStorage.instance.recordTrace(AgentExecutionTrace(
        id: 'trace_widget_test_1',
        timestamp: DateTime.now(),
        userMessage: 'I bar unugyada nolosha',
        studentForm: 'Form 1',
        internalThought: 'Thought: User is asking for cells in Form 1 Biology.',
        status: AgentVerificationStatus.accepted,
        matchedBookId: 'sample_form1_bio',
        matchedBookTitle: 'Sayniska Guud & Nolosha',
        matchedCategory: 'Form 1',
        matchedChapterTitle: 'Cutubka 1: Unugyada & Nolosha',
        matchedLessonTitle: 'Casharka 1: Waa Maxay Unug?',
        startPage: 1,
        endPage: 5,
        concisePreviewAnswer: 'Unuggu waa xubinta ugu yar ee nolosha.',
        verificationQuestion: 'Ma casharkan ayaad u jeeddaa?',
        studentFeedback: 'Haa, sax weeye',
        totalLatencyMs: 240,
        toolCalls: [
          AgentToolCallLog(
            toolId: 'curriculum_search',
            toolName: 'Curriculum Catalog Search',
            arguments: {'query': 'unugyada'},
            outputSummary: 'Match found',
            latencyMs: 35,
            isSuccess: true,
            timestamp: DateTime.now(),
          ),
          AgentToolCallLog(
            toolId: 'pdf_retriever',
            toolName: 'PDF Slice Content Retriever',
            arguments: {'startPage': 1, 'endPage': 5},
            outputSummary: 'Sliced 5 pages',
            latencyMs: 180,
            isSuccess: true,
            timestamp: DateTime.now(),
          ),
        ],
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AgentObservabilityWorkspace(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify KPI metrics are visible
      expect(find.text('Wadarta Codsiyada'), findsOneWidget);
      expect(find.text('Heerka Xaqiijinta'), findsOneWidget);
      expect(find.text('Tools-ka Shidan'), findsOneWidget);

      // Verify the trace is displayed in the list
      expect(find.text('I bar unugyada nolosha'), findsWidgets);
      expect(find.text('Casharka 1: Waa Maxay Unug?'), findsWidgets);
      expect(find.textContaining('Behind-The-Scenes Trace'), findsOneWidget);
      expect(find.textContaining('Thought: User is asking for cells'), findsOneWidget);

      // Switch to Tools Registry Tab
      await tester.tap(find.text('Tools-ka Agent-ka'));
      await tester.pumpAndSettle();

      // Verify tools registry list
      expect(find.text('Baaraha Manhajka Fasalka'), findsOneWidget);
      expect(find.text('Soo Saare & Gooye PDF'), findsOneWidget);
      expect(find.text('Albaabka Hubinta & Koobidda'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Macallinka Qotada Dheer'), findsOneWidget);
    });
  });
}
