import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/widgets/rich_tutor_markdown.dart';

void main() {
  testWidgets('Test RichTutorMarkdown with exact user raw_msg.txt', (tester) async {
    final raw = File('C:/Users/hp/.gemini/antigravity-ide/brain/d267d1ff-64b5-49f6-b217-11aba4e34faa/scratch/raw_msg.txt').readAsStringSync();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichTutorMarkdown(text: raw),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RichTutorMarkdown), findsOneWidget);
  });
}
