import 'dart:typed_data';

class ChatVisualModel {
  const ChatVisualModel({
    required this.page,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.title,
    this.thumbnailBytes,
    this.thumbnailPath,
  });

  final int page;
  final double left;
  final double top;
  final double width;
  final double height;
  final String title;

  /// Kept while the current chat is open for immediate rendering.
  final Uint8List? thumbnailBytes;
  final String? thumbnailPath;

  ChatVisualModel withThumbnail(Uint8List? bytes, {String? path}) =>
      ChatVisualModel(
        page: page,
        left: left,
        top: top,
        width: width,
        height: height,
        title: title,
        thumbnailBytes: bytes,
        thumbnailPath: path ?? thumbnailPath,
      );

  Map<String, dynamic> toJson() => {
    'page': page,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'title': title,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
  };

  factory ChatVisualModel.fromJson(Map<String, dynamic> json) =>
      ChatVisualModel(
        page: json['page'] as int? ?? 1,
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 1,
        height: (json['height'] as num?)?.toDouble() ?? 1,
        title: json['title'] as String? ?? 'Sawirka casharka',
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.text,
    required this.isUser,
    this.scopeLabel,
    this.pagesLabel,
    this.hasPdf = false,
    this.canContinue = false,
    this.partIndex,
    this.isLessonComplete = false,
    this.visuals = const [],
  });

  final String text;
  final bool isUser;
  final String? scopeLabel;
  final String? pagesLabel;
  final bool hasPdf;
  final bool canContinue;
  final int? partIndex;
  final bool isLessonComplete;
  final List<ChatVisualModel> visuals;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    if (scopeLabel != null) 'scopeLabel': scopeLabel,
    if (pagesLabel != null) 'pagesLabel': pagesLabel,
    'hasPdf': hasPdf,
    'canContinue': canContinue,
    if (partIndex != null) 'partIndex': partIndex,
    'isLessonComplete': isLessonComplete,
    if (visuals.isNotEmpty)
      'visuals': visuals.map((visual) => visual.toJson()).toList(),
  };

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) =>
      ChatMessageModel(
        text: json['text'] as String? ?? '',
        isUser: json['isUser'] as bool? ?? false,
        scopeLabel: json['scopeLabel'] as String?,
        pagesLabel: json['pagesLabel'] as String?,
        hasPdf: json['hasPdf'] as bool? ?? false,
        canContinue: json['canContinue'] as bool? ?? false,
        partIndex: json['partIndex'] as int?,
        isLessonComplete: json['isLessonComplete'] as bool? ?? false,
        visuals: (json['visuals'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatVisualModel.fromJson)
            .toList(),
      );
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.bookId,
    this.bookTitle,
    this.focusChapter,
    this.focusLesson,
    this.focusSection,
    this.focusChapterId,
    this.focusLessonId,
    this.focusSectionId,
    this.learningSessionId,
    this.learningScopeType,
    this.currentPartIndex = 0,
    this.partCount = 1,
    required this.messages,
  });

  final String id;
  String title;
  DateTime updatedAt;
  final String? bookId;
  final String? bookTitle;
  final String? focusChapter;
  final String? focusLesson;
  final String? focusSection;
  final String? focusChapterId;
  final String? focusLessonId;
  final String? focusSectionId;
  final String? learningSessionId;
  final String? learningScopeType;
  final int currentPartIndex;
  final int partCount;
  final List<ChatMessageModel> messages;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    if (bookId != null) 'bookId': bookId,
    if (bookTitle != null) 'bookTitle': bookTitle,
    if (focusChapter != null) 'focusChapter': focusChapter,
    if (focusLesson != null) 'focusLesson': focusLesson,
    if (focusSection != null) 'focusSection': focusSection,
    if (focusChapterId != null) 'focusChapterId': focusChapterId,
    if (focusLessonId != null) 'focusLessonId': focusLessonId,
    if (focusSectionId != null) 'focusSectionId': focusSectionId,
    if (learningSessionId != null) 'learningSessionId': learningSessionId,
    if (learningScopeType != null) 'learningScopeType': learningScopeType,
    'currentPartIndex': currentPartIndex,
    'partCount': partCount,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Sheeko Cusub',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    bookId: json['bookId'] as String?,
    bookTitle: json['bookTitle'] as String?,
    focusChapter: json['focusChapter'] as String?,
    focusLesson: json['focusLesson'] as String?,
    focusSection: json['focusSection'] as String?,
    focusChapterId: json['focusChapterId'] as String?,
    focusLessonId: json['focusLessonId'] as String?,
    focusSectionId: json['focusSectionId'] as String?,
    learningSessionId: json['learningSessionId'] as String?,
    learningScopeType: json['learningScopeType'] as String?,
    currentPartIndex: json['currentPartIndex'] as int? ?? 0,
    partCount: json['partCount'] as int? ?? 1,
    messages: (json['messages'] as List<dynamic>? ?? [])
        .map((m) => ChatMessageModel.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    String? bookId,
    String? bookTitle,
    String? focusChapter,
    String? focusLesson,
    String? focusSection,
    String? focusChapterId,
    String? focusLessonId,
    String? focusSectionId,
    String? learningSessionId,
    String? learningScopeType,
    int? currentPartIndex,
    int? partCount,
    List<ChatMessageModel>? messages,
  }) => ChatSession(
    id: id ?? this.id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    bookId: bookId ?? this.bookId,
    bookTitle: bookTitle ?? this.bookTitle,
    focusChapter: focusChapter ?? this.focusChapter,
    focusLesson: focusLesson ?? this.focusLesson,
    focusSection: focusSection ?? this.focusSection,
    focusChapterId: focusChapterId ?? this.focusChapterId,
    focusLessonId: focusLessonId ?? this.focusLessonId,
    focusSectionId: focusSectionId ?? this.focusSectionId,
    learningSessionId: learningSessionId ?? this.learningSessionId,
    learningScopeType: learningScopeType ?? this.learningScopeType,
    currentPartIndex: currentPartIndex ?? this.currentPartIndex,
    partCount: partCount ?? this.partCount,
    messages: messages ?? this.messages,
  );
}
