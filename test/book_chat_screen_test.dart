import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/models/prepared_book.dart';
import 'package:leyli/screens/book_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleBook = PreparedBook(
    id: 'test_phy_4',
    title: 'f4-Phyiscs',
    category: 'Form 4',
    originalFileName: 'f4-physics.pdf',
    pageCount: 15,
    chapters: [
      PreparedChapter(
        id: 'ch_1',
        title: 'Chapter 1: Mechanics',
        startPage: 1,
        endPage: 10,
        lessons: [
          PreparedLesson(
            id: 'ls_1',
            title: 'Lesson 1.1: Motion',
            startPage: 1,
            endPage: 5,
            sections: [
              PreparedSection(
                id: 'sec_1',
                title: 'frequency and period',
                startPage: 2,
                endPage: 3,
                startPosition: 0.35,
                endPosition: 0.65,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpUntilStable(WidgetTester tester, [int steps = 15]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets(
    'BookChatScreen with no book starts in clean empty state without auto-loading',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const MaterialApp(home: BookChatScreen(book: null)),
      );
      await pumpUntilStable(tester);

      // Verify app bar title
      expect(find.text('Leyli'), findsOneWidget);

      // Verify topbar action icons
      expect(find.byTooltip('Chat Cusub'), findsOneWidget);
      expect(find.byTooltip('Maktabadda'), findsOneWidget);
      expect(find.byTooltip('Editor-ka'), findsOneWidget);

      // Verify empty state welcome
      expect(find.text('Leyli AI'), findsOneWidget);

      // Verify input bar is present for free chat
      expect(find.text('Weydii Leyli AI su\'aal kasta...'), findsOneWidget);

      // Verify Send button is present inside the input (suffix icon)
      expect(find.byTooltip('Dir fariinta'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      // Verify menu drawer opens and contains Chat History, but NO Gemini API key
      await tester.tap(find.byTooltip('Menu'));
      await pumpUntilStable(tester);

      expect(find.textContaining('Chat History'), findsOneWidget);
      expect(find.text('New Chat'), findsWidgets);
      expect(find.text('Gemini API Key'), findsNothing);
    },
  );

  testWidgets(
    'BookChatScreen displays library PopupMenuButton inside input',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'leyli_selected_form_level_v1': 'Form 4',
      });

      await tester.pumpWidget(
        MaterialApp(home: BookChatScreen(book: sampleBook)),
      );
      await pumpUntilStable(tester);

      // Verify library icon button is a PopupMenuButton with tooltip
      expect(find.byTooltip('Buugaagta'), findsOneWidget);

      // Tap library icon inside input to open PopupMenuButton
      await tester.tap(find.byTooltip('Buugaagta'));
      await pumpUntilStable(tester);

      // PopupMenu shows Form title
      expect(find.text('Form 4'), findsWidgets);
    },
  );
}
