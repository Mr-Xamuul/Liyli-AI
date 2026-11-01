import 'dart:convert';

enum PreparedBookStatus { draft, review, ready, published }

class PreparedSection {
  const PreparedSection({
    required this.id,
    required this.title,
    required this.startPage,
    required this.endPage,
    this.startPosition = 0,
    this.endPosition = 1,
  });

  final String id;
  final String title;
  final int startPage;
  final int endPage;
  final double startPosition;
  final double endPosition;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startPage': startPage,
    'endPage': endPage,
    'startPosition': startPosition,
    'endPosition': endPosition,
  };

  factory PreparedSection.fromJson(Map<String, dynamic> json) =>
      PreparedSection(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        startPage: json['startPage'] as int? ?? 0,
        endPage: json['endPage'] as int? ?? 0,
        startPosition: (json['startPosition'] as num?)?.toDouble() ?? 0,
        endPosition: (json['endPosition'] as num?)?.toDouble() ?? 1,
      );
}

class PreparedLesson {
  const PreparedLesson({
    required this.id,
    required this.title,
    required this.startPage,
    required this.endPage,
    this.startPosition = 0,
    this.endPosition = 1,
    this.sections = const [],
  });

  final String id;
  final String title;
  final int startPage;
  final int endPage;
  final double startPosition;
  final double endPosition;
  final List<PreparedSection> sections;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startPage': startPage,
    'endPage': endPage,
    'startPosition': startPosition,
    'endPosition': endPosition,
    'sections': sections.map((section) => section.toJson()).toList(),
  };

  factory PreparedLesson.fromJson(Map<String, dynamic> json) => PreparedLesson(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    startPage: json['startPage'] as int? ?? 0,
    endPage: json['endPage'] as int? ?? 0,
    startPosition: (json['startPosition'] as num?)?.toDouble() ?? 0,
    endPosition: (json['endPosition'] as num?)?.toDouble() ?? 1,
    sections: (json['sections'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PreparedSection.fromJson)
        .toList(),
  );
}

class PreparedChapter {
  const PreparedChapter({
    required this.id,
    required this.title,
    required this.startPage,
    required this.endPage,
    this.lessons = const [],
  });

  final String id;
  final String title;
  final int startPage;
  final int endPage;
  final List<PreparedLesson> lessons;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startPage': startPage,
    'endPage': endPage,
    'lessons': lessons.map((lesson) => lesson.toJson()).toList(),
  };

  factory PreparedChapter.fromJson(Map<String, dynamic> json) =>
      PreparedChapter(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        startPage: json['startPage'] as int? ?? 0,
        endPage: json['endPage'] as int? ?? 0,
        lessons: (json['lessons'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PreparedLesson.fromJson)
            .toList(),
      );
}

class PreparedBook {
  const PreparedBook({
    required this.id,
    required this.title,
    required this.originalFileName,
    required this.pageCount,
    required this.chapters,
    this.status = PreparedBookStatus.draft,
    this.category = 'Form 1',
    this.originalPdfPath,
    this.verifiedItemIds = const [],
    this.ocrCompleted = false,
    this.ocrPageCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  static const categories = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  final String id;
  final String title;
  final String originalFileName;
  final int pageCount;
  final String category;
  final List<PreparedChapter> chapters;
  final PreparedBookStatus status;
  final String? originalPdfPath;
  final List<String> verifiedItemIds;
  final bool ocrCompleted;
  final int ocrPageCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPublished => status == PreparedBookStatus.published;
  bool get isReady => status == PreparedBookStatus.ready;
  bool get isReview => status == PreparedBookStatus.review;
  bool get isDraft => status == PreparedBookStatus.draft;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'originalFileName': originalFileName,
    'pageCount': pageCount,
    'category': category,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'status': status.name,
    'originalPdfPath': originalPdfPath,
    'verifiedItemIds': verifiedItemIds,
    'ocrCompleted': ocrCompleted,
    'ocrPageCount': ocrPageCount,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  factory PreparedBook.fromJson(Map<String, dynamic> json) => PreparedBook(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    originalFileName: json['originalFileName'] as String? ?? '',
    pageCount: json['pageCount'] as int? ?? 0,
    category: json['category'] as String? ?? 'Form 1',
    chapters: (json['chapters'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PreparedChapter.fromJson)
        .toList(),
    status: PreparedBookStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => PreparedBookStatus.draft,
    ),
    originalPdfPath: json['originalPdfPath'] as String?,
    verifiedItemIds: (json['verifiedItemIds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    ocrCompleted: json['ocrCompleted'] as bool? ?? false,
    ocrPageCount: json['ocrPageCount'] as int? ?? 0,
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  factory PreparedBook.decode(String value) =>
      PreparedBook.fromJson(jsonDecode(value) as Map<String, dynamic>);

  PreparedBook copyWith({
    String? title,
    String? category,
    int? pageCount,
    List<PreparedChapter>? chapters,
    PreparedBookStatus? status,
    String? originalPdfPath,
    List<String>? verifiedItemIds,
    bool? ocrCompleted,
    int? ocrPageCount,
    DateTime? updatedAt,
  }) => PreparedBook(
    id: id,
    title: title ?? this.title,
    originalFileName: originalFileName,
    pageCount: pageCount ?? this.pageCount,
    category: category ?? this.category,
    chapters: chapters ?? this.chapters,
    status: status ?? this.status,
    originalPdfPath: originalPdfPath ?? this.originalPdfPath,
    verifiedItemIds: verifiedItemIds ?? this.verifiedItemIds,
    ocrCompleted: ocrCompleted ?? this.ocrCompleted,
    ocrPageCount: ocrPageCount ?? this.ocrPageCount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  List<String> validate() {
    final errors = <String>[];
    if (title.trim().isEmpty) errors.add('Book title is required.');
    if (pageCount <= 0) errors.add('The PDF must have at least one page.');
    if (chapters.isEmpty) errors.add('At least one chapter is required.');

    _validateRanges(chapters, pageCount, 'Chapter', errors);
    for (final chapter in chapters) {
      _validateRanges(
        chapter.lessons,
        chapter.endPage,
        'Lesson in ${chapter.title}',
        errors,
        minimumPage: chapter.startPage,
      );
      for (final lesson in chapter.lessons) {
        _validateRanges(
          lesson.sections,
          lesson.endPage,
          'Section in ${lesson.title}',
          errors,
          minimumPage: lesson.startPage,
        );
      }
    }
    return errors;
  }

  static void _validateRanges(
    List<dynamic> items,
    int maximumPage,
    String label,
    List<String> errors, {
    int minimumPage = 1,
  }) {
    var previousEnd = minimumPage - 1;
    for (final item in items) {
      final title = item.title as String;
      if (title.trim().isEmpty) errors.add('$label name is required.');
      if (item.startPage < minimumPage || item.endPage > maximumPage) {
        errors.add('$label "$title" is outside its parent page range.');
      }
      if (item.startPage > item.endPage) {
        errors.add('$label "$title" has an invalid page range.');
      }
      if (item.startPage < previousEnd) {
        errors.add('$label ranges overlap or are out of order near "$title".');
      }
      previousEnd = item.endPage as int;
    }
  }

  static DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
}
