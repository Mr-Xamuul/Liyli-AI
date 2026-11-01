import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilStable(WidgetTester tester, [int steps = 15]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('Leyli App launches into AI Chat with Topbar navigation and no bottom navbar', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LeyliApp());
    await pumpUntilStable(tester);

    // 1. Verify app launches into AI Chat directly
    expect(find.text('Leyli'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byTooltip('Chat Cusub'), findsOneWidget);
    expect(find.byTooltip('Maktabadda'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);

    // 2. Verify bottom navigation bar is removed
    expect(find.byType(NavigationBar), findsNothing);

    // 3. Navigate to Maktabadda via Topbar icon
    await tester.tap(find.byTooltip('Maktabadda'));
    await pumpUntilStable(tester);

    // Verify 4 shelves in Maktabadda
    expect(find.text('Form 1'), findsWidgets);
    expect(find.text('Form 2'), findsWidgets);
    expect(find.text('Form 3'), findsWidgets);
    expect(find.text('Form 4'), findsWidgets);

    // 4. Return to AI Chat via back button
    await tester.tap(find.byTooltip('Ku noqo Chat-ka'));
    await pumpUntilStable(tester);
    expect(find.text('Leyli'), findsOneWidget);

    // 5. Open Menu Drawer and verify Chat History
    await tester.tap(find.byTooltip('Menu'));
    await pumpUntilStable(tester);
    expect(find.textContaining('Chat History'), findsOneWidget);
    expect(find.text('New Chat'), findsOneWidget);
  });
}
