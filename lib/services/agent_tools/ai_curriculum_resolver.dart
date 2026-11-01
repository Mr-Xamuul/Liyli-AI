import 'dart:convert';

import '../../models/ai_model_config.dart';
import '../../models/prepared_book.dart';
import '../ai_model_storage.dart';
import '../ai_routing_storage.dart';
import '../gemini_book_chat_service.dart';
import 'curriculum_search_tool.dart';

class AiCurriculumResolution {
  const AiCurriculumResolution({
    required this.found,
    this.bookId,
    this.bookTitle,
    this.chapterId,
    this.chapterTitle,
    this.lessonId,
    this.lessonTitle,
    this.sectionTitle,
    this.startPage,
    this.endPage,
    this.startPosition = 0.0,
    this.endPosition = 1.0,
    required this.concisePreview,
    required this.reasoning,
    this.matchedBook,
    this.matchedChapter,
    this.matchedLesson,
    this.matchedSection,
  });

  final bool found;
  final String? bookId;
  final String? bookTitle;
  final String? chapterId;
  final String? chapterTitle;
  final String? lessonId;
  final String? lessonTitle;
  final String? sectionTitle;
  final int? startPage;
  final int? endPage;
  final double startPosition;
  final double endPosition;
  final String concisePreview;
  final String reasoning;
  final PreparedBook? matchedBook;
  final PreparedChapter? matchedChapter;
  final PreparedLesson? matchedLesson;
  final PreparedSection? matchedSection;

  Map<String, dynamic> toJson() => {
    'found': found,
    if (bookId != null) 'bookId': bookId,
    if (bookTitle != null) 'bookTitle': bookTitle,
    if (chapterTitle != null) 'chapterTitle': chapterTitle,
    if (lessonTitle != null) 'lessonTitle': lessonTitle,
    if (sectionTitle != null) 'sectionTitle': sectionTitle,
    if (startPage != null) 'startPage': startPage,
    if (endPage != null) 'endPage': endPage,
    'startPosition': startPosition,
    'endPosition': endPosition,
    'concisePreview': concisePreview,
    'reasoning': reasoning,
  };
}

class AiCurriculumResolver {
  AiCurriculumResolver({
    GeminiBookChatService? chatService,
    AiRoutingStorage? routingStorage,
    AiModelStorage? modelStorage,
  }) : _chatService = chatService ?? GeminiBookChatService(),
       _routingStorage = routingStorage ?? const AiRoutingStorage(),
       _modelStorage = modelStorage ?? const AiModelStorage();

  final GeminiBookChatService _chatService;
  final AiRoutingStorage _routingStorage;
  final AiModelStorage _modelStorage;

  /// Builds the verified curriculum hierarchy tree for the specified Form.
  List<Map<String, dynamic>> buildCurriculumTree(List<PreparedBook> books) {
    return books.map((book) {
      return {
        'bookId': book.id,
        'bookTitle': book.title,
        'category': book.category,
        'pageCount': book.pageCount,
        'chapters': book.chapters.map((chap) {
          return {
            'chapterId': chap.id,
            'chapterTitle': chap.title,
            'startPage': chap.startPage,
            'endPage': chap.endPage,
            'lessons': chap.lessons.map((les) {
              return {
                'lessonId': les.id,
                'lessonTitle': les.title,
                'startPage': les.startPage,
                'endPage': les.endPage,
                'startPosition': les.startPosition,
                'endPosition': les.endPosition,
                'sections': les.sections.map((sec) {
                  return {
                    'sectionId': sec.id,
                    'sectionTitle': sec.title,
                    'startPage': sec.startPage,
                    'endPage': sec.endPage,
                    'startPosition': sec.startPosition,
                    'endPosition': sec.endPosition,
                  };
                }).toList(),
              };
            }).toList(),
          };
        }).toList(),
      };
    }).toList();
  }

  /// Evaluates student input against the curriculum tree using AI Model semantic intelligence,
  /// with a robust fallback to intelligent structural parsing.
  Future<AiCurriculumResolution> resolve({
    required String userQuery,
    required String formLevel,
    required List<PreparedBook> formBooks,
    String conversationContext = '',
  }) async {
    if (formBooks.isEmpty) {
      return AiCurriculumResolution(
        found: false,
        concisePreview: '',
        reasoning: 'Ma jiraan buugaag u diiwaangashan fasalka $formLevel.',
      );
    }

    final tree = buildCurriculumTree(formBooks);

    // 1. Try AI-powered semantic resolution if model is available
    try {
      final aiResult = await _resolveWithAiModel(
        userQuery: userQuery,
        conversationContext: conversationContext,
        formLevel: formLevel,
        tree: tree,
        books: formBooks,
      );
      if (aiResult != null && aiResult.found) {
        return aiResult;
      }
    } catch (_) {
      // Fall through to smart hierarchical structural matcher
    }

    // 2. Intelligent Structural Matcher (Understands Book + Lesson Ordinals, Topics, and Sections)
    return _resolveStructurally(
      userQuery: userQuery,
      formLevel: formLevel,
      formBooks: formBooks,
    );
  }

  Future<AiCurriculumResolution?> _resolveWithAiModel({
    required String userQuery,
    required String conversationContext,
    required String formLevel,
    required List<Map<String, dynamic>> tree,
    required List<PreparedBook> books,
  }) async {
    final candidateModels = await _routingStorage.getActiveTierModels();
    AiModelConfig? targetModel;
    if (candidateModels.isNotEmpty) {
      targetModel = candidateModels.first;
    } else {
      final all = await _modelStorage.getModels();
      targetModel = all.where((m) => m.isActive && m.isVerified).firstOrNull;
    }

    final treeJson = jsonEncode(tree);

    final prompt =
        '''
Waxaad tahay Leyli Autonomous Educational Curriculum Agent.
Fasalka ardaygu ku jiro waa: $formLevel.
Codsiga ardaygu soo qoray waa: "$userQuery".
Wada-hadalkii dhowaa ee ka caawinaya inaad fahamto tilmaamaha sida "casharkaas" ama "qaybta xigta":
${conversationContext.isEmpty ? '(ma jiro)' : conversationContext}

Halkan waxaa kuugu jira Geedka Manhajka ee Fasalka $formLevel oo wata buugaagta, cutubyada, casharrada, iyo xuduudahooda rasmiga ah ee PDF-ka:
$treeJson

SHAQADAADA:
1. Faham waxa ardaygu u jeedo (tusaale haddii uu yiri "buuga business casharkiisa 1aad", micnaheedu waa buugga Business, casharka 1aad).
2. Dooro buugga, cutubka, iyo casharka (ama section-ka) saxda ah ee ku dhex jira geedka sare.
3. Soo celi ID-yada saxda ah ee geedka. Ha samayn ama ha qiyaasin ID, bog, ama xuduud PDF; app-ku xuduudaha wuxuu ka qaadanayaa diiwaanka buugga.
4. Jawaabta ku soo celi KALIYA JSON sax ah oo qaabkan ah (wax kale ha soo raacin):
{
  "found": true,
  "bookId": "id-ga buugga",
  "chapterId": "id-ga cutubka",
  "lessonId": "id-ga casharka",
  "sectionId": "id-ga section-ka ama null",
  "concisePreview": "1-2 sadar oo dulucda kooban ee casharka ah",
  "reasoning": "Sababta aad u dooratay casharkan"
}
Haddii codsigu uusan wax xiriir ah la lahayn manhajka fasalkan, soo celi:
{"found": false, "reasoning": "Mawduucan lagama helin fasalka $formLevel"}
''';

    final response = await _chatService.ask(
      question: prompt,
      modelConfig: targetModel,
    );

    // Parse JSON from response
    final cleanJson = _extractJson(response);
    if (cleanJson == null) return null;

    final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
    final found = parsed['found'] as bool? ?? false;
    if (!found) {
      return AiCurriculumResolution(
        found: false,
        concisePreview: '',
        reasoning: parsed['reasoning'] as String? ?? 'Mawduuca lama helin',
      );
    }

    final bookId = parsed['bookId'] as String?;
    final chapterId = parsed['chapterId'] as String?;
    final lessonId = parsed['lessonId'] as String?;
    final sectionId = parsed['sectionId'] as String?;

    // Resolve model choices back to the app's catalog. Page and crop limits
    // must always come from saved curriculum metadata, never generated JSON.
    PreparedBook? matchedBook;
    PreparedChapter? matchedChapter;
    PreparedLesson? matchedLesson;
    PreparedSection? matchedSection;
    for (final candidateBook in books) {
      if (candidateBook.id != bookId) continue;
      matchedBook = candidateBook;
      for (final candidateChapter in candidateBook.chapters) {
        if (candidateChapter.id != chapterId) continue;
        matchedChapter = candidateChapter;
        for (final candidateLesson in candidateChapter.lessons) {
          if (candidateLesson.id != lessonId) continue;
          matchedLesson = candidateLesson;
          if (sectionId != null) {
            for (final candidateSection in candidateLesson.sections) {
              if (candidateSection.id == sectionId) {
                matchedSection = candidateSection;
                break;
              }
            }
          }
          break;
        }
        break;
      }
      break;
    }

    if (matchedBook == null ||
        matchedChapter == null ||
        matchedLesson == null ||
        (sectionId != null && matchedSection == null)) {
      return AiCurriculumResolution(
        found: false,
        concisePreview: '',
        reasoning:
            'AI-gu ma dooran aqoonsi buug/cutub/cashar oo ku jira manhajka app-ka.',
      );
    }
    final startP = matchedSection?.startPage ?? matchedLesson.startPage;
    final rawEndP = matchedSection?.endPage ?? matchedLesson.endPage;
    final endP = rawEndP >= startP ? rawEndP : startP;
    final startPos =
        matchedSection?.startPosition ?? matchedLesson.startPosition;
    final endPos = matchedSection?.endPosition ?? matchedLesson.endPosition;

    return AiCurriculumResolution(
      found: true,
      bookId: matchedBook?.id ?? bookId,
      bookTitle: matchedBook?.title ?? parsed['bookTitle'],
      chapterId: matchedChapter?.id ?? chapterId,
      chapterTitle: matchedChapter?.title ?? parsed['chapterTitle'],
      lessonId: matchedLesson?.id ?? lessonId,
      lessonTitle: matchedLesson?.title ?? parsed['lessonTitle'],
      sectionTitle: matchedSection?.title,
      startPage: startP,
      endPage: endP,
      startPosition: startPos,
      endPosition: endPos,
      concisePreview: parsed['concisePreview'] as String? ?? '',
      reasoning:
          parsed['reasoning'] as String? ??
          'AI wuxuu si guul leh u helay casharka.',
      matchedBook: matchedBook,
      matchedChapter: matchedChapter,
      matchedLesson: matchedLesson,
      matchedSection: matchedSection,
    );
  }

  /// Smart structural intent matcher that handles:
  /// - Book identification: "buuga business", "chemistry", "sayniska", etc.
  /// - Ordinal lesson indexing: "casharkiisa 1aad", "lesson 2", "cutubka 1", etc.
  /// - Topic and Section matching: "measuring instruments", "length", etc.
  AiCurriculumResolution _resolveStructurally({
    required String userQuery,
    required String formLevel,
    required List<PreparedBook> formBooks,
  }) {
    final clean = userQuery.trim().toLowerCase();

    // 1. Identify which book is referenced (if any) via title or Somali aliases
    PreparedBook? targetBook;
    for (final book in formBooks) {
      final title = book.title.toLowerCase();
      if (clean.contains(title) || title.contains(clean)) {
        targetBook = book;
        break;
      }
      for (final entry in curriculumSubjectAliases.entries) {
        if (title.contains(entry.key)) {
          for (final alias in entry.value) {
            if (clean.contains(alias)) {
              targetBook = book;
              break;
            }
          }
        }
        if (targetBook != null) break;
      }
      if (targetBook != null) break;
    }

    final candidateBooks = targetBook != null ? [targetBook] : formBooks;

    // 2. Identify ordinal chapter/lesson requests: e.g. "cutubka 2aad", "casharka 1aad"
    final isChapterRequested =
        clean.contains('cutub') || clean.contains('chapter');
    final isLessonRequested =
        clean.contains('cashar') || clean.contains('lesson');

    final ordinalRegex = RegExp(
      r'(\d+)\s*(aad|aadka|aadkiisa|aadkaas)?|koobaad|koowaad|labaad|saddexaad|afraad|shanaad|lixaad',
    );
    final ordinalMatch = ordinalRegex.firstMatch(clean);
    int? requestedOrdinalIndex;
    if (ordinalMatch != null) {
      final matchStr = ordinalMatch.group(0)!;
      if (matchStr.contains('1') ||
          matchStr.contains('koobaad') ||
          matchStr.contains('koowaad')) {
        requestedOrdinalIndex = 0;
      } else if (matchStr.contains('2') || matchStr.contains('labaad')) {
        requestedOrdinalIndex = 1;
      } else if (matchStr.contains('3') || matchStr.contains('saddexaad')) {
        requestedOrdinalIndex = 2;
      } else if (matchStr.contains('4') || matchStr.contains('afraad')) {
        requestedOrdinalIndex = 3;
      } else if (matchStr.contains('5') || matchStr.contains('shanaad')) {
        requestedOrdinalIndex = 4;
      } else if (matchStr.contains('6') || matchStr.contains('lixaad')) {
        requestedOrdinalIndex = 5;
      }
    }

    // A: Chapter ordinal requested: e.g. "buuga ganacsiga cutubka 2aad"
    if (targetBook != null &&
        isChapterRequested &&
        requestedOrdinalIndex != null) {
      if (requestedOrdinalIndex < targetBook.chapters.length) {
        final chapter = targetBook.chapters[requestedOrdinalIndex];
        final lesson =
            chapter.lessons.isNotEmpty ? chapter.lessons.first : null;
        if (lesson != null) {
          return AiCurriculumResolution(
            found: true,
            bookId: targetBook.id,
            bookTitle: targetBook.title,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            lessonId: lesson.id,
            lessonTitle: lesson.title,
            startPage: lesson.startPage,
            endPage: lesson.endPage,
            startPosition: lesson.startPosition,
            endPosition: lesson.endPosition,
            concisePreview:
                'Wuxuu ka bilaabanayaa "${chapter.title}" ee buugga "${targetBook.title}".',
            reasoning:
                'Ardaygu wuxuu toos u codsaday cutubka ${requestedOrdinalIndex + 1}aad ("${chapter.title}").',
            matchedBook: targetBook,
            matchedChapter: chapter,
            matchedLesson: lesson,
          );
        }
      }
    }

    // B: Lesson ordinal requested: e.g. "buuga business casharkiisa 1aad"
    if (targetBook != null &&
        isLessonRequested &&
        requestedOrdinalIndex != null) {
      if (targetBook.chapters.isNotEmpty) {
        final chapter = targetBook.chapters.first;
        if (requestedOrdinalIndex < chapter.lessons.length) {
          final lesson = chapter.lessons[requestedOrdinalIndex];
          return AiCurriculumResolution(
            found: true,
            bookId: targetBook.id,
            bookTitle: targetBook.title,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            lessonId: lesson.id,
            lessonTitle: lesson.title,
            startPage: lesson.startPage,
            endPage: lesson.endPage,
            startPosition: lesson.startPosition,
            endPosition: lesson.endPosition,
            concisePreview:
                'Wuxuu ku saabsan yahay casharka ${requestedOrdinalIndex + 1}aad ee buugga "${targetBook.title}".',
            reasoning:
                'Ardaygu wuxuu toos u codsaday casharka ${requestedOrdinalIndex + 1}aad ee buugga "${targetBook.title}".',
            matchedBook: targetBook,
            matchedChapter: chapter,
            matchedLesson: lesson,
          );
        }
      }
    }

    // C: Section and topic matching across candidate books
    for (final book in candidateBooks) {
      for (final chapter in book.chapters) {
        for (final lesson in chapter.lessons) {
          final lessonTitleLower = lesson.title.toLowerCase();

          // Section matching
          for (final sec in lesson.sections) {
            final secTitleLower = sec.title.toLowerCase();
            if (clean.contains(secTitleLower) ||
                _hasKeyTokens(clean, secTitleLower)) {
              return AiCurriculumResolution(
                found: true,
                bookId: book.id,
                bookTitle: book.title,
                chapterId: chapter.id,
                chapterTitle: chapter.title,
                lessonId: lesson.id,
                lessonTitle: lesson.title,
                sectionTitle: sec.title,
                startPage: sec.startPage > 0 ? sec.startPage : lesson.startPage,
                endPage: sec.endPage > 0 ? sec.endPage : lesson.endPage,
                startPosition: sec.startPosition,
                endPosition: sec.endPosition,
                concisePreview:
                    'Wuxuu si gaar ah u faaqidayaa qaybta "${sec.title}" ee casharka "${lesson.title}".',
                reasoning:
                    'Waxaa la helay qaybta (Section) "${sec.title}" oo ku dhex jirta buugga "${book.title}".',
                matchedBook: book,
                matchedChapter: chapter,
                matchedLesson: lesson,
                matchedSection: sec,
              );
            }
          }

          // Direct Lesson match
          if (clean.contains(lessonTitleLower) ||
              _hasKeyTokens(clean, lessonTitleLower)) {
            return AiCurriculumResolution(
              found: true,
              bookId: book.id,
              bookTitle: book.title,
              chapterId: chapter.id,
              chapterTitle: chapter.title,
              lessonId: lesson.id,
              lessonTitle: lesson.title,
              startPage: lesson.startPage,
              endPage: lesson.endPage,
              startPosition: lesson.startPosition,
              endPosition: lesson.endPosition,
              concisePreview:
                  'Wuxuu ka hadlayaa dulucda guud ee "${lesson.title}" ee cutubka "${chapter.title}".',
              reasoning:
                  'Waxaa toos loo helay casharka "${lesson.title}" ee buugga "${book.title}".',
              matchedBook: book,
              matchedChapter: chapter,
              matchedLesson: lesson,
            );
          }
        }
      }
    }

    // If target book was specified but no specific topic or lesson was matched:
    // Do NOT guess Chapter 1 Lesson 1 blindly! Return found: false so caller provides clean Table of Contents!
    if (targetBook != null) {
      return AiCurriculumResolution(
        found: false,
        concisePreview: '',
        reasoning:
            'Waxaa la helay buugga "${targetBook.title}", laakiin ma jiro cashar gaar ah oo la xusay. Waxaa la soo saarayaa Table of Contents.',
      );
    }

    return AiCurriculumResolution(
      found: false,
      concisePreview: '',
      reasoning:
          'Baaritaanka fasalka $formLevel waxaa laga baaray ${formBooks.length} buug, balse lama helin cashar toos ula fariista "$clean".',
    );
  }

  bool _hasKeyTokens(String query, String target) {
    const stopWords = {
      'waxaan',
      'rabaa',
      'rabay',
      'doonayaa',
      'codsanayaa',
      'fadlan',
      'iiga',
      'ii',
      'ku',
      'ka',
      'ee',
      'ah',
      'waxa',
      'waa',
      'maxay',
      'sheeg',
      'sharax',
      'sharaxaad',
      'faahfaahin',
      'baro',
      'ibarto',
      'suaal',
      'cashar',
      'casharka',
      'casharkiisa',
      'cutub',
      'cutubka',
      'buug',
      'buuga',
      'buugga',
    };
    final qTokens = query
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4 && !stopWords.contains(w));

    if (qTokens.isEmpty) return false;

    int matchCount = 0;
    for (final token in qTokens) {
      if (target.contains(token) || token.contains(target)) {
        matchCount++;
      }
    }
    return matchCount >= 1;
  }

  String? _extractJson(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return response.substring(start, end + 1);
    }
    return null;
  }
}
