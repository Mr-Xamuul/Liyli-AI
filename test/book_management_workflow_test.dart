import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/widgets/book_admin/book_management_workspace.dart';
import 'package:leyli/widgets/book_admin/book_upload_stage_view.dart';
import 'package:leyli/widgets/book_admin/book_editor_stage_view.dart';
import 'package:leyli/widgets/book_admin/book_preview_stage_view.dart';
import 'package:leyli/widgets/book_admin/book_ready_stage_view.dart';
import 'package:leyli/widgets/book_admin/book_library_stage_view.dart';

void main() {
  testWidgets('BookManagementWorkspace renders 5-stage stepper and switches stages', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookManagementWorkspace(
            onOpenEditor: (book, {chapterIndex, lessonIndex, sectionIndex, returnToPreview = false}) {},
            onOpenChat: (book) {},
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    // Verify all 5 stage tabs are rendered
    expect(find.text('1. Upload'), findsOneWidget);
    expect(find.text('2. Editor'), findsOneWidget);
    expect(find.text('3. Preview (Hubinta)'), findsOneWidget);
    expect(find.text('4. Diyaar ah (Ready)'), findsOneWidget);
    expect(find.text('5. Maktabadda (Library)'), findsOneWidget);

    // Initial stage should be Upload
    expect(find.byType(BookUploadStageView), findsOneWidget);

    // Tap Stage 2 (Editor)
    await tester.tap(find.text('2. Editor'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BookEditorStageView), findsOneWidget);

    // Tap Stage 3 (Preview)
    await tester.tap(find.text('3. Preview (Hubinta)'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BookPreviewStageView), findsOneWidget);

    // Tap Stage 4 (Diyaar ah)
    await tester.tap(find.text('4. Diyaar ah (Ready)'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BookReadyStageView), findsOneWidget);

    // Tap Stage 5 (Maktabadda)
    await tester.tap(find.text('5. Maktabadda (Library)'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BookLibraryStageView), findsOneWidget);
  });
}
