import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/screens/book_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BookChatScreen shows AI model picker button and bottom sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BookChatScreen(hideModelPicker: false),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify model picker pill is displayed in the AppBar
    expect(find.byIcon(Icons.smart_toy_rounded), findsWidgets);

    // Tap on the model selector in the AppBar
    final modelPill = find.text('Gemini 2.5 Flash');
    expect(modelPill, findsOneWidget);
    await tester.tap(modelPill);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify bottom sheet opened
    expect(find.text('Dooro AI Model'), findsOneWidget);
    expect(find.text('Dooro model-ka aad rabto in Leyli kuugu jawaabto'), findsOneWidget);
    expect(find.text('Maaree ama Ku dar Model Cusub (Editor-ka)'), findsOneWidget);

    // Verify models list inside sheet
    expect(find.text('Gemini 2.5 Pro'), findsOneWidget);

    // Tap to select another verified model (Gemini 2.5 Pro)
    await tester.tap(find.text('Gemini 2.5 Pro'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify active model in AppBar updated
    expect(find.text('Gemini 2.5 Pro'), findsOneWidget);
  });
}
