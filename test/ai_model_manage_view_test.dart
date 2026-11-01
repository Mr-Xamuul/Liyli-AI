import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/screens/prepared_book_editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PreparedBookEditorScreen shows Book Manage and AI Manage tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PreparedBookEditorScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify tabs exist
    expect(find.text('Book Manage'), findsOneWidget);
    expect(find.text('AI Manage'), findsOneWidget);

    // Switch to AI Manage tab
    await tester.tap(find.text('AI Manage'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify AI Workspace 5 Stages are present
    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Diyaar ah'), findsOneWidget);
    expect(find.text('App Routing'), findsOneWidget);
    expect(find.text('API Keys'), findsOneWidget);

    // Verify Stage 1 Model actions
    expect(find.text('Ku dar Model Cusub'), findsOneWidget);

    // Tap "Ku dar Model Cusub" to open Create Dialog
    await tester.tap(find.text('Ku dar Model Cusub'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Create Dialog opened with model fields
    expect(find.text('Ku dar Model Cusub (Stage 1)'), findsOneWidget);
    expect(find.text('Magaca Model-ka (Display Name)'), findsOneWidget);
    expect(find.text('Model ID (API Identifier)'), findsOneWidget);
    expect(find.text('Company / Bixiye'), findsOneWidget);
    expect(find.text('Furaha API-ga (Stage 5 API Keys)'), findsOneWidget);
  });
}
