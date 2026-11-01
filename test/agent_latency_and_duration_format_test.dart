import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/models/agent_execution_trace.dart';
import 'package:leyli/services/agent_tools/curriculum_search_tool.dart';
import 'package:leyli/services/gemini_book_chat_service.dart';

void main() {
  group('formatTraceDuration unit tests', () {
    test('formats sub-second durations to seconds', () {
      expect(formatTraceDuration(0), '0s');
      expect(formatTraceDuration(50), '0.05s');
      expect(formatTraceDuration(450), '0.45s');
      expect(formatTraceDuration(999), '1.00s');
    });

    test('formats multi-second durations to seconds', () {
      expect(formatTraceDuration(1000), '1.0s');
      expect(formatTraceDuration(4200), '4.2s');
      expect(formatTraceDuration(15500), '15.5s');
      expect(formatTraceDuration(59999), '60.0s');
    });

    test('formats 1 minute or more to minutes and seconds', () {
      expect(formatTraceDuration(60000), '1min');
      expect(formatTraceDuration(65000), '1min 5s');
      expect(formatTraceDuration(120000), '2min');
      // User specific duration from screenshot: 381069ms -> 6min 21s!
      expect(formatTraceDuration(381069), '6min 21s');
    });
  });

  group('AgentExecutionTrace latency breakdown', () {
    test('computes resolvedModelLatencyMs and percentages accurately', () {
      final now = DateTime.now();
      final trace = AgentExecutionTrace(
        id: 'trace_test_1',
        timestamp: now,
        userMessage: 'Test prompt',
        studentForm: 'Form 2',
        internalThought: 'Testing latency',
        totalLatencyMs: 381069,
        toolCalls: [
          AgentToolCallLog(
            toolId: 'search_curriculum',
            toolName: 'Search',
            arguments: const {},
            latencyMs: 80,
            isSuccess: true,
            timestamp: now,
          ),
          AgentToolCallLog(
            toolId: 'get_lesson_pdf',
            toolName: 'PDF',
            arguments: const {},
            latencyMs: 120,
            isSuccess: true,
            timestamp: now,
          ),
        ],
      );

      expect(trace.totalLatencyMs, 381069);
      expect(trace.totalToolLatencyMs, 200);
      expect(trace.resolvedModelLatencyMs, 380869);
      expect(trace.modelTimePercentage, greaterThan(99.0));
      expect(trace.toolsTimePercentage, lessThan(1.0));
    });

    test('serializes and deserializes modelLatencyMs and modelCalls', () {
      final now = DateTime.now();
      final trace = AgentExecutionTrace(
        id: 'trace_test_2',
        timestamp: now,
        userMessage: 'Test prompt',
        studentForm: 'Form 2',
        internalThought: 'Testing serialization',
        totalLatencyMs: 5000,
        modelLatencyMs: 4800,
        modelCalls: [
          AgentModelCallLog(
            stepIndex: 1,
            callType: 'Tallaabada 1: Doorashada Tool-ka',
            latencyMs: 2000,
            isSuccess: true,
            modelName: 'gemini-2.5-flash',
            timestamp: now,
          ),
          AgentModelCallLog(
            stepIndex: 2,
            callType: 'Tallaabada 2: Jawaabta Dhammaystiran',
            latencyMs: 2800,
            isSuccess: true,
            modelName: 'gemini-2.5-flash',
            timestamp: now,
          ),
        ],
        toolCalls: [
          AgentToolCallLog(
            toolId: 'search_curriculum',
            toolName: 'Search',
            arguments: const {},
            latencyMs: 200,
            isSuccess: true,
            timestamp: now,
          ),
        ],
      );

      final json = trace.toJson();
      final restored = AgentExecutionTrace.fromJson(json);

      expect(restored.totalLatencyMs, 5000);
      expect(restored.modelLatencyMs, 4800);
      expect(restored.resolvedModelLatencyMs, 4800);
      expect(restored.modelCalls.length, 2);
      expect(
        restored.modelCalls.first.callType,
        'Tallaabada 1: Doorashada Tool-ka',
      );
      expect(restored.modelCalls.first.latencyMs, 2000);
      expect(restored.totalToolLatencyMs, 200);
    });
  });

  group('GeminiBookChatService Timeout & Physics Alias Tests', () {
    test('defaultRequestTimeout is set to 5 minutes', () {
      expect(
        GeminiBookChatService.defaultRequestTimeout,
        const Duration(minutes: 5),
      );
    });

    test(
      'isTimeoutError detects timeouts and distinguishes from offline error',
      () {
        final timeoutErr = TimeoutException('Future not completed');
        expect(GeminiBookChatService.isTimeoutError(timeoutErr), isTrue);
        // Timeout must NOT be treated as a no-internet offline error
        expect(
          GeminiBookChatService.isNetworkOrOfflineError(timeoutErr),
          isFalse,
        );

        expect(
          GeminiBookChatService.timeoutMessage,
          contains('Timeout ka badan 5 daqiiqo'),
        );
      },
    );

    test('curriculumSubjectAliases contains Somali aliases for physics', () {
      final physicsAliases = curriculumSubjectAliases['physics']!;
      expect(physicsAliases.contains('fiisigis'), isTrue);
      expect(physicsAliases.contains('fiisigis-ka'), isTrue);
      expect(physicsAliases.contains('fiisigiska'), isTrue);
      expect(physicsAliases.contains('fiisikis'), isTrue);
      expect(physicsAliases.contains('physics'), isTrue);
    });
  });
}
