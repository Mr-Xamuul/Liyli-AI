import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/app_telemetry_log.dart';
import 'package:leyli/services/app_telemetry_storage.dart';
import 'package:leyli/widgets/telemetry_admin/app_monitoring_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppTelemetryLog model serialization and properties test', () {
    final now = DateTime.now();
    final log = AppTelemetryLog(
      id: 'test_1',
      timestamp: now,
      userMessage: 'Waa maxay unug?',
      bookId: 'bio_1',
      bookTitle: 'Biology Form 1',
      bookCategory: 'Form 1',
      focusChapter: 'Cutubka 1',
      focusLesson: 'Casharka 2',
      answeredModelName: 'Gemini 2.5 Flash',
      answeredModelId: 'gemini-2.5-flash',
      responseTimeMs: 1450,
      isSuccess: true,
      attempts: [
        ModelAttemptLog(
          modelName: 'Gemini 2.5 Flash',
          modelId: 'gemini-2.5-flash',
          isSuccess: true,
          latencyMs: 1450,
          timestamp: now,
        ),
      ],
    );

    final json = log.toJson();
    final reconstructed = AppTelemetryLog.fromJson(json);

    expect(reconstructed.id, 'test_1');
    expect(reconstructed.userMessage, 'Waa maxay unug?');
    expect(reconstructed.bookTitle, 'Biology Form 1');
    expect(reconstructed.answeredModelName, 'Gemini 2.5 Flash');
    expect(reconstructed.responseTimeMs, 1450);
    expect(reconstructed.isSuccess, true);
    expect(reconstructed.failedAttemptsCount, 0);
    expect(reconstructed.hadFailover, false);
    expect(reconstructed.bookAndScopeSummary, contains('Biology Form 1'));
  });

  test('AppTelemetryStorage records logs and computes summary correctly', () async {
    final storage = AppTelemetryStorage.instance;
    await storage.clearLogs();

    final now = DateTime.now();

    // 1. Success log with no fallback
    await storage.recordLog(
      AppTelemetryLog(
        id: 'msg_1',
        timestamp: now.subtract(const Duration(minutes: 5)),
        userMessage: 'Sharax photosynthesis',
        bookTitle: 'Biology Form 1',
        focusLesson: 'Photosynthesis',
        answeredModelName: 'Gemini 2.5 Flash',
        responseTimeMs: 1200,
        isSuccess: true,
        attempts: [
          ModelAttemptLog(
            modelName: 'Gemini 2.5 Flash',
            modelId: 'gemini-2.5-flash',
            isSuccess: true,
            latencyMs: 1200,
            timestamp: now,
          ),
        ],
      ),
    );

    // 2. Success log WITH fallback (model A failed, model B succeeded)
    await storage.recordLog(
      AppTelemetryLog(
        id: 'msg_2',
        timestamp: now.subtract(const Duration(minutes: 2)),
        userMessage: 'Xisaabi xawaaraha baabuurka',
        bookTitle: 'Physics Form 2',
        focusLesson: 'Motion',
        answeredModelName: 'Llama 3.3 70B',
        responseTimeMs: 800,
        isSuccess: true,
        attempts: [
          ModelAttemptLog(
            modelName: 'Gemini 2.5 Flash',
            modelId: 'gemini-2.5-flash',
            isSuccess: false,
            latencyMs: 1500,
            errorMessage: '503 High Demand',
            timestamp: now,
          ),
          ModelAttemptLog(
            modelName: 'Llama 3.3 70B',
            modelId: 'llama-3.3-70b',
            isSuccess: true,
            latencyMs: 800,
            timestamp: now,
          ),
        ],
      ),
    );

    // 3. Complete failure log (all models failed)
    await storage.recordLog(
      AppTelemetryLog(
        id: 'msg_3',
        timestamp: now,
        userMessage: 'Su\'aal guud oo offline ah',
        isSuccess: false,
        finalErrorMessage: 'No internet connection',
        attempts: [
          ModelAttemptLog(
            modelName: 'Gemini 2.5 Flash',
            modelId: 'gemini-2.5-flash',
            isSuccess: false,
            latencyMs: 300,
            errorMessage: 'SocketException',
            timestamp: now,
          ),
        ],
      ),
    );

    final logs = await storage.getLogs();
    expect(logs.length, 3);

    final summary = await storage.getSummary();

    // 1. Total messages sent
    expect(summary.totalMessages, 3);
    expect(summary.totalSuccess, 2);
    expect(summary.totalFailed, 1);

    // 2. Model that answered & latency
    expect(summary.modelSuccessCounts['Gemini 2.5 Flash'], 1);
    expect(summary.modelSuccessCounts['Llama 3.3 70B'], 1);
    expect(summary.modelAvgLatencies['Gemini 2.5 Flash'], 1200.0);
    expect(summary.modelAvgLatencies['Llama 3.3 70B'], 800.0);
    expect(summary.avgLatencyMs, 1000.0); // (1200 + 800) / 2

    // 3. Model failure counts and breakdown
    expect(summary.totalModelFailures, 2);
    expect(summary.modelFailureCounts['Gemini 2.5 Flash'], 2);

    // 4. Books breakdown
    expect(summary.bookUsageCounts['Biology Form 1'], 1);
    expect(summary.bookUsageCounts['Physics Form 2'], 1);
    expect(summary.bookUsageCounts['Guud (General Chat)'], 1);
  });

  testWidgets('AppMonitoringWorkspace renders KPIs and table', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final storage = AppTelemetryStorage.instance;
    await storage.clearLogs();

    await storage.recordLog(
      AppTelemetryLog(
        id: 'test_msg_1',
        timestamp: DateTime.now(),
        userMessage: 'Waa maxay gravitiga?',
        bookTitle: 'Physics Form 1',
        focusChapter: 'Cutubka 3',
        focusLesson: 'Gravity',
        answeredModelName: 'Gemini 2.5 Flash',
        responseTimeMs: 1100,
        isSuccess: true,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppMonitoringWorkspace(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kormeerka Shaqada App-ka (App Telemetry & Analytics)'), findsOneWidget);
    expect(find.text('Wadarta Fariimaha La Diray'), findsOneWidget);
    expect(find.text('Celceliska Xawaaraha'), findsOneWidget);
    expect(find.text('Fashilaadaha Moodellada'), findsOneWidget);
    expect(find.text('Waa maxay gravitiga?'), findsOneWidget);
  });
}
