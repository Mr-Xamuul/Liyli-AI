import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/main.dart';
import 'package:leyli/services/admin_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilStable(WidgetTester tester, [int steps = 15]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('Admin button is visible when admin mode is true and opens Admin Dashboard', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'leyli_is_admin_mode': true});
    await AdminAuthService.instance.init();
    await AdminAuthService.instance.setAdminMode(true);

    await tester.pumpWidget(const LeyliApp());
    await pumpUntilStable(tester);

    // 1. Verify Admin button is present in Topbar
    final adminButton = find.text('Admin');
    expect(adminButton, findsOneWidget);

    // 2. Tap Admin button and verify Admin Dashboard appears
    await tester.tap(adminButton);
    await pumpUntilStable(tester);

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.textContaining('Book Manage'), findsWidgets);
    expect(find.textContaining('AI Manage'), findsWidgets);
  });

  testWidgets('Admin button is hidden when admin mode is toggled off', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'leyli_is_admin_mode': false});
    await AdminAuthService.instance.setAdminMode(false);

    await tester.pumpWidget(const LeyliApp());
    await pumpUntilStable(tester);

    // Verify Admin button is NOT visible for regular students
    expect(find.text('Admin'), findsNothing);

    // Maktabadda is still visible
    expect(find.byTooltip('Maktabadda'), findsOneWidget);

    // Restore admin mode for subsequent usage
    await AdminAuthService.instance.setAdminMode(true);
  });
}
