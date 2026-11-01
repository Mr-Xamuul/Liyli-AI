import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leyli/services/agent_tools/agent_orchestrator.dart';
import 'package:leyli/services/agent_tools/curriculum_search_tool.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Curriculum Clean TOC & Somali Aliases Tests', () {
    test(
      'CurriculumSearchMatch toCleanTitlesJson omits startPage, endPage, and score',
      () async {
        final searchTool = CurriculumSearchTool();
        final result = await searchTool.search(
          query: 'Unug',
          explicitFormLevel: 'Form 1',
        );

        expect(result.hasMatch, isTrue);
        final match = result.bestMatch!;
        final cleanJson = match.toCleanTitlesJson();

        // Verified: Must contain titles and IDs
        expect(cleanJson.containsKey('bookTitle'), isTrue);
        expect(cleanJson.containsKey('chapterTitle'), isTrue);
        expect(cleanJson.containsKey('lessonTitle'), isTrue);
        expect(cleanJson.containsKey('bookId'), isTrue);
        expect(cleanJson.containsKey('chapterId'), isTrue);
        expect(cleanJson.containsKey('lessonId'), isTrue);

        // Verified: Must omit noisy fields
        expect(cleanJson.containsKey('startPage'), isFalse);
        expect(cleanJson.containsKey('endPage'), isFalse);
        expect(cleanJson.containsKey('score'), isFalse);
        expect(cleanJson.containsKey('startPosition'), isFalse);
        expect(cleanJson.containsKey('endPosition'), isFalse);
        expect(cleanJson.containsKey('matchReason'), isFalse);
      },
    );

    test('Searching for a book name returns clean Table of Contents', () async {
      final searchTool = CurriculumSearchTool();
      // Form 1 sample has 'Sayniska Guud & Nolosha'
      final result = await searchTool.search(
        bookTitle: 'Sayniska Guud & Nolosha',
        explicitFormLevel: 'Form 1',
      );

      expect(result.hasMatch, isTrue);
      expect(result.tableOfContents, isNotNull);
      expect(result.tableOfContents!.isNotEmpty, isTrue);

      final firstChapter = result.tableOfContents!.first;
      expect(firstChapter.containsKey('chapterTitle'), isTrue);
      expect(firstChapter.containsKey('chapterId'), isTrue);
      expect(firstChapter.containsKey('lessons'), isTrue);

      final lessons = firstChapter['lessons'] as List;
      expect(lessons.isNotEmpty, isTrue);
      final firstLesson = lessons.first as Map<String, dynamic>;
      expect(firstLesson.containsKey('lessonTitle'), isTrue);
      expect(firstLesson.containsKey('lessonId'), isTrue);

      // Verified: No page numbers or scores in TOC
      expect(firstLesson.containsKey('startPage'), isFalse);
      expect(firstLesson.containsKey('score'), isFalse);
    });

    test(
      'AgentOrchestrator executeToolCall search_curriculum returns clean response and enables get_lesson_pdf',
      () async {
        final orchestrator = AgentOrchestrator();

        // 1. Search for curriculum using book title
        final searchResponse = await orchestrator.executeToolCall(
          'search_curriculum',
          {'bookTitle': 'Sayniska Guud & Nolosha'},
          formLevel: 'Form 1',
        );

        expect(searchResponse['found'], isTrue);
        expect(searchResponse.containsKey('tableOfContents'), isTrue);
        final toc = searchResponse['tableOfContents'] as List;
        expect(toc.isNotEmpty, isTrue);

        final firstChap = toc.first as Map<String, dynamic>;
        final firstLes =
            (firstChap['lessons'] as List).first as Map<String, dynamic>;

        final bookId = searchResponse['bookId'] as String;
        final chapterId = firstChap['chapterId'] as String;
        final lessonId = firstLes['lessonId'] as String;

        // 2. Call get_lesson_pdf with the selected lesson
        final pdfResponse = await orchestrator.executeToolCall(
          'get_lesson_pdf',
          {'bookId': bookId, 'chapterId': chapterId, 'lessonId': lessonId},
          formLevel: 'Form 1',
        );

        expect(pdfResponse['found'], isTrue);
        expect(pdfResponse.containsKey('match'), isTrue);
        final match = pdfResponse['match'] as Map<String, dynamic>;
        expect(match.containsKey('lessonTitle'), isTrue);
        expect(match.containsKey('startPage'), isFalse); // Clean titles output
      },
    );

    test(
      'Table of Contents includes sections inside lessons when sections exist',
      () async {
        final searchTool = CurriculumSearchTool();
        // Form 1 sample Sayniska book has sections in Lesson 1
        final result = await searchTool.search(
          bookTitle: 'Sayniska Guud & Nolosha',
          explicitFormLevel: 'Form 1',
        );

        expect(result.hasMatch, isTrue);
        expect(result.tableOfContents, isNotNull);

        // Check that at least one lesson has sections
        bool foundSection = false;
        for (final chap in result.tableOfContents!) {
          final lessons = chap['lessons'] as List;
          for (final les in lessons) {
            if (les.containsKey('sections')) {
              final sections = les['sections'] as List;
              if (sections.isNotEmpty) {
                foundSection = true;
                final firstSec = sections.first as Map<String, dynamic>;
                expect(firstSec.containsKey('sectionId'), isTrue);
                expect(firstSec.containsKey('sectionTitle'), isTrue);
                // Clean titles: no startPage or score
                expect(firstSec.containsKey('startPage'), isFalse);
                expect(firstSec.containsKey('score'), isFalse);
              }
            }
          }
        }
        expect(foundSection, isTrue);
      },
    );

    test(
      'Action get_table_of_contents returns full book outline unconditionally',
      () async {
        final orchestrator = AgentOrchestrator();
        final response = await orchestrator.executeToolCall(
          'search_curriculum',
          {
            'action': 'get_table_of_contents',
            'bookTitle': 'Sayniska Guud & Nolosha',
          },
          formLevel: 'Form 1',
        );

        expect(response['found'], isTrue);
        expect(response.containsKey('tableOfContents'), isTrue);
        final toc = response['tableOfContents'] as List;
        expect(toc.length, greaterThanOrEqualTo(1));
      },
    );

    test('Action get_chapter returns specific chapter outline', () async {
      final orchestrator = AgentOrchestrator();
      final response = await orchestrator.executeToolCall('search_curriculum', {
        'action': 'get_chapter',
        'bookTitle': 'Sayniska Guud & Nolosha',
        'chapter': '1',
      }, formLevel: 'Form 1');

      expect(response['found'], isTrue);
      expect(response.containsKey('tableOfContents'), isTrue);
      final toc = response['tableOfContents'] as List;
      expect(toc.length, 1);
      final chap = toc.first as Map<String, dynamic>;
      expect(chap['chapterTitle'], contains('Cutubka 1'));
    });

    test('Action search_topic pinpoints exact topic', () async {
      final orchestrator = AgentOrchestrator();
      final response = await orchestrator.executeToolCall('search_curriculum', {
        'action': 'search_topic',
        'bookTitle': 'Sayniska Guud & Nolosha',
        'topic': 'Unug',
      }, formLevel: 'Form 1');

      expect(response['found'], isTrue);
      expect(response.containsKey('bestMatch'), isTrue);
      final bestMatch = response['bestMatch'] as Map<String, dynamic>;
      expect(bestMatch['lessonTitle'], contains('Unug'));
    });
  });
}
