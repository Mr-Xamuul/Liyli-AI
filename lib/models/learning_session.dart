enum LearningScopeType { book, chapter, lesson, section }

/// The active, deliberately scoped learning flow within a chat.
///
/// A new instance is created whenever a learner changes the book, chapter,
/// lesson, or section they are studying. This keeps one lesson's context from
/// leaking into the next lesson.
class LearningSession {
  const LearningSession({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.scopeType,
    required this.scopeLabel,
    required this.startedAt,
    this.chapterId,
    this.chapterTitle,
    this.lessonId,
    this.lessonTitle,
    this.sectionId,
    this.sectionTitle,
    this.currentPartIndex = 0,
    this.partCount = 1,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final LearningScopeType scopeType;
  final String scopeLabel;
  final DateTime startedAt;
  final String? chapterId;
  final String? chapterTitle;
  final String? lessonId;
  final String? lessonTitle;
  final String? sectionId;
  final String? sectionTitle;
  final int currentPartIndex;
  final int partCount;

  bool get hasNextPart => currentPartIndex < partCount - 1;

  LearningSession copyWith({int? currentPartIndex}) => LearningSession(
    id: id,
    bookId: bookId,
    bookTitle: bookTitle,
    scopeType: scopeType,
    scopeLabel: scopeLabel,
    startedAt: startedAt,
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    lessonId: lessonId,
    lessonTitle: lessonTitle,
    sectionId: sectionId,
    sectionTitle: sectionTitle,
    currentPartIndex: currentPartIndex ?? this.currentPartIndex,
    partCount: partCount,
  );

  bool matches(LearningSession other) =>
      bookId == other.bookId &&
      scopeType == other.scopeType &&
      chapterId == other.chapterId &&
      lessonId == other.lessonId &&
      sectionId == other.sectionId;
}
