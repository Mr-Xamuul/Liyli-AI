import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Leyli App launches into AI Chat with Topbar navigation and no bottom navbar', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LeyliApp());
    await tester.pumpAndSettle();

    // 1. Verify app launches into AI Chat directly
    expect(find.text('Leyli'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byTooltip('Chat Cusub'), findsOneWidget);
    expect(find.byTooltip('Maktabadda'), findsOneWidget);
    expect(find.byTooltip('Editor-ka'), findsOneWidget);

    // 2. Verify bottom navigation bar is removed
    expect(find.byType(NavigationBar), findsNothing);

    // 3. Navigate to Maktabadda via Topbar icon
    await tester.tap(find.byTooltip('Maktabadda'));
    await tester.pumpAndSettle();

    // Verify 4 shelves in Maktabadda
    expect(find.text('Form 1'), findsWidgets);
    expect(find.text('Form 2'), findsWidgets);
    expect(find.text('Form 3'), findsWidgets);
    expect(find.text('Form 4'), findsWidgets);

    // 4. Return to AI Chat via back button
    await tester.tap(find.byTooltip('Ku noqo Chat-ka'));
    await tester.pumpAndSettle();
    expect(find.text('Leyli'), findsOneWidget);

    // 5. Open Menu Drawer and verify Chat History
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Taariikhda Sheekooyinka'), findsOneWidget);
    expect(find.text('Chat Cusub (New Chat)'), findsOneWidget);
  });
}
