import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/models/learning_session.dart';

void main() {
  LearningSession session({
    required LearningScopeType type,
    String? chapterId,
    String? lessonId,
    String? sectionId,
  }) =>
      LearningSession(
        id: 'session',
        bookId: 'book-1',
        bookTitle: 'Physics',
        scopeType: type,
        scopeLabel: 'Scope',
        startedAt: DateTime(2026),
        chapterId: chapterId,
        lessonId: lessonId,
        sectionId: sectionId,
      );

  test('matches only the same book and selected learning scope', () {
    final sectionOne = session(
      type: LearningScopeType.section,
      chapterId: 'chapter-1',
      lessonId: 'lesson-1',
      sectionId: 'section-1',
    );
    final sameSection = session(
      type: LearningScopeType.section,
      chapterId: 'chapter-1',
      lessonId: 'lesson-1',
      sectionId: 'section-1',
    );
    final differentSection = session(
      type: LearningScopeType.section,
      chapterId: 'chapter-1',
      lessonId: 'lesson-1',
      sectionId: 'section-2',
    );

    expect(sectionOne.matches(sameSection), isTrue);
    expect(sectionOne.matches(differentSection), isFalse);
  });

  test('tracks whether a later lesson part is available', () {
    final firstPart = LearningSession(
      id: 'session',
      bookId: 'book-1',
      bookTitle: 'Physics',
      scopeType: LearningScopeType.lesson,
      scopeLabel: 'Motion',
      startedAt: DateTime(2026),
      partCount: 3,
    );

    expect(firstPart.hasNextPart, isTrue);
    expect(firstPart.copyWith(currentPartIndex: 2).hasNextPart, isFalse);
  });
}
