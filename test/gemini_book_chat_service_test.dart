import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leyli/models/learning_session.dart';
import 'package:leyli/models/prepared_book.dart';
import 'package:leyli/services/gemini_book_chat_service.dart';

void main() {
  final book = PreparedBook(
    id: 'physics-4',
    title: 'Physics Form 4',
    originalFileName: 'physics.pdf',
    pageCount: 3,
    chapters: [
      PreparedChapter(
        id: 'chapter-motion',
        title: 'Motion',
        startPage: 1,
        endPage: 3,
        lessons: [
          PreparedLesson(
            id: 'lesson-periodic',
            title: 'Periodic motion',
            startPage: 1,
            endPage: 3,
            sections: [
              PreparedSection(
                id: 'section-frequency',
                title: 'Frequency',
                startPage: 2,
                endPage: 2,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<String> requestBodyFor(LearningScopeType scopeType) async {
    String? body;
    final client = MockClient((request) async {
      body = request.body;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Jawaab tijaabo ah'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final service = GeminiBookChatService(client: client, apiKey: 'test-key');
    await service.ask(
      book: book,
      question: 'I caawi',
      focusChapter: 'Motion',
      focusLesson: scopeType == LearningScopeType.book
          ? null
          : 'Periodic motion',
      focusSection: scopeType == LearningScopeType.section ? 'Frequency' : null,
      learningScopeType: scopeType,
    );
    return body!;
  }

  test('section prompt requests paired English and Somali teaching', () async {
    final body = await requestBodyFor(LearningScopeType.section);

    expect(body, contains('QAABKA CASHARKA LABA-LUQADOODKA AH'));
    expect(body, contains('English from the lesson'));
    expect(body, contains('Sharaxaadda macallinka'));
  });

  test('chapter prompt asks for an overview before choosing a lesson', () async {
    final body = await requestBodyFor(LearningScopeType.chapter);

    expect(body, contains('QAABKA JAWAABTA CHAPTER-KA'));
    expect(body, contains('Lessons in this chapter'));
    expect(body, contains('Periodic motion'));
  });

  test('final lesson part requests a review and short self-check', () async {
    String? body;
    final client = MockClient((request) async {
      body = request.body;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Jawaab tijaabo ah'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    await GeminiBookChatService(client: client, apiKey: 'test-key').ask(
      book: book,
      question: 'Sii wad',
      focusChapter: 'Motion',
      focusLesson: 'Periodic motion',
      learningScopeType: LearningScopeType.lesson,
      learningPartNumber: 2,
      learningPartCount: 2,
      priorLearningContext: 'Qaybtii hore waxay sharaxday frequency.',
      isLessonCompletion: true,
    );

    expect(body, contains('Casharkii hore ee isla session-kan'));
    expect(body, contains('Casharka waa dhammaystiran yahay'));
    expect(body, contains('Erayada muhiimka ah'));
  });

  test('visual analysis asks for diagram pages and bilingual labels', () async {
    String? body;
    final client = MockClient((request) async {
      body = request.body;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Jawaab tijaabo ah'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    await GeminiBookChatService(client: client, apiKey: 'test-key').ask(
      book: book,
      question: 'Sharax jaantusyada',
      focusChapter: 'Motion',
      focusLesson: 'Periodic motion',
      mode: TutorMode.visuals,
      learningScopeType: LearningScopeType.lesson,
    );

    expect(body, contains('Bogga PDF-ka'));
    expect(body, contains('Labels & Parts'));
    expect(body, contains('magaca English-ka'));
  });

  test('returns short offline message when network fails or device is offline', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Failed host lookup: generativelanguage.googleapis.com');
    });

    final answer = await GeminiBookChatService(
      client: client,
      apiKey: 'test-key',
    ).ask(
      book: book,
      question: 'I caawi',
      focusChapter: 'Motion',
      focusLesson: 'Periodic motion',
    );

    expect(answer, equals(GeminiBookChatService.offlineMessage));
    expect(answer, contains('internet'));
  });
}
