import 'dart:math';

import '../../models/prepared_book.dart';
import '../book_knowledge_storage.dart';
import '../form_preference_storage.dart';
import '../prepared_book_storage.dart';
import 'ai_curriculum_resolver.dart';

/// Somali subject aliases mapped to standardized English subject roots.
const Map<String, List<String>> curriculumSubjectAliases = {
  'business': ['ganacsi', 'ganacsiga', 'ganacsi-ga', 'business studies', 'business', 'commerce'],
  'biology': ['bayoolaji', 'bayoolajiga', 'bayoolaji-ga', 'noolaha', 'cilmil noolaha', 'biology'],
  'chemistry': ['kimistari', 'kimistariga', 'kimistari-ga', 'chemistry'],
  'physics': ['fiisikis', 'fiisikiska', 'fiisikis-ka', 'fiisigis', 'fiisigiska', 'fiisigis-ka', 'fisikis', 'fisigis', 'physics'],
  'mathematics': ['xisaab', 'xisaabta', 'xisaab-ta', 'math', 'mathematics', 'maths'],
  'history': ['taariikh', 'taariikhda', 'taariikh-da', 'history'],
  'geography': ['juqraafi', 'juqraafiga', 'juqraafi-ga', 'geography'],
  'islamic': ['tarbiya', 'tarbiyada', 'tarbiya-da', 'diin', 'diinta', 'diin-ta', 'islamic studies', 'islaamka', 'tarbiyah'],
  'somali': ['af soomaali', 'af-soomaali', 'soomaali', 'suugaan'],
  'english': ['english', 'ingiriisi', 'ingiriiska', 'ingiriisi-ka'],
  'arabic': ['carabi', 'carabiga', 'carabi-ga', 'arabic'],
};

class CurriculumSearchMatch {
  const CurriculumSearchMatch({
    required this.book,
    required this.chapter,
    required this.lesson,
    this.section,
    required this.startPage,
    required this.endPage,
    required this.score,
    required this.matchReason,
  });

  final PreparedBook book;
  final PreparedChapter chapter;
  final PreparedLesson lesson;
  final PreparedSection? section;
  final int startPage;
  final int endPage;
  final double score;
  final String matchReason;

  /// Internal full JSON for admin trace logging.
  Map<String, dynamic> toJson() => {
    'bookId': book.id,
    'bookTitle': book.title,
    'bookCategory': book.category,
    'chapterId': chapter.id,
    'chapterTitle': chapter.title,
    'lessonId': lesson.id,
    'lessonTitle': lesson.title,
    if (section != null) 'sectionId': section?.id,
    if (section != null) 'sectionTitle': section?.title,
    'startPage': startPage,
    'endPage': endPage,
    'score': double.parse(score.toStringAsFixed(2)),
    'matchReason': matchReason,
  };

  /// Clean, title-focused JSON returned to the AI model during curriculum discovery.
  /// Omits noisy technical fields like startPage, endPage, score, and positions.
  Map<String, dynamic> toCleanTitlesJson() => {
    'bookId': book.id,
    'bookTitle': book.title,
    'chapterId': chapter.id,
    'chapterTitle': chapter.title,
    'lessonId': lesson.id,
    'lessonTitle': lesson.title,
    if (section != null) 'sectionId': section?.id,
    if (section != null) 'sectionTitle': section?.title,
  };
}

class CurriculumSearchResult {
  const CurriculumSearchResult({
    required this.searchedFormLevel,
    required this.userQuery,
    this.matchedBook,
    this.tableOfContents,
    this.bestMatch,
    this.alternatives = const [],
    required this.totalBooksSearched,
    required this.internalThought,
    this.allDiscoveredMatches = const [],
  });

  final String searchedFormLevel;
  final String userQuery;
  final PreparedBook? matchedBook;
  final List<Map<String, dynamic>>? tableOfContents;
  final CurriculumSearchMatch? bestMatch;
  final List<CurriculumSearchMatch> alternatives;
  final int totalBooksSearched;
  final String internalThought;
  final List<CurriculumSearchMatch> allDiscoveredMatches;

  bool get hasMatch =>
      bestMatch != null ||
      (tableOfContents != null && tableOfContents!.isNotEmpty);

  Map<String, dynamic> toJson() => {
    'searchedFormLevel': searchedFormLevel,
    'userQuery': userQuery,
    'hasMatch': hasMatch,
    if (matchedBook != null) 'bookTitle': matchedBook?.title,
    if (matchedBook != null) 'bookId': matchedBook?.id,
    if (tableOfContents != null) 'tableOfContents': tableOfContents,
    if (bestMatch != null) 'bestMatch': bestMatch?.toJson(),
    'alternatives': alternatives.map((a) => a.toJson()).toList(),
    'totalBooksSearched': totalBooksSearched,
    'internalThought': internalThought,
  };

  /// Clean response sent to the AI agent without technical page/score noise.
  Map<String, dynamic> toAgentResponse() => {
    'found': hasMatch,
    'summary': internalThought,
    if (matchedBook != null) 'bookTitle': matchedBook?.title,
    if (matchedBook != null) 'bookId': matchedBook?.id,
    if (tableOfContents != null) 'tableOfContents': tableOfContents,
    if (bestMatch != null) 'bestMatch': bestMatch?.toCleanTitlesJson(),
    if (alternatives.isNotEmpty)
      'alternatives': alternatives.map((a) => a.toCleanTitlesJson()).toList(),
  };
}

class CurriculumSearchTool {
  CurriculumSearchTool({
    PreparedBookStorage? bookStorage,
    FormPreferenceStorage? formStorage,
    BookKnowledgeStorage? knowledgeStorage,
    AiCurriculumResolver? resolver,
  }) : _bookStorage = bookStorage ?? const PreparedBookStorage(),
       _formStorage = formStorage ?? const FormPreferenceStorage(),
       _knowledgeStorage = knowledgeStorage ?? const BookKnowledgeStorage(),
       _resolver = resolver ?? AiCurriculumResolver();

  final PreparedBookStorage _bookStorage;
  final FormPreferenceStorage _formStorage;
  final BookKnowledgeStorage _knowledgeStorage;
  final AiCurriculumResolver _resolver;

  /// Executes curriculum search strictly limited to the current Form of the student.
  /// Supports bookTitle and query, Somali aliases, and returns clean Table of Contents
  /// when a book outline is needed.
  Future<CurriculumSearchResult> search({
    String? action,
    String? bookTitle,
    String? chapter,
    String? topic,
    String? query,
    String? explicitFormLevel,
    String conversationContext = '',
  }) async {
    final rawAction = (action ?? '').trim().toLowerCase();
    final rawQuery = (query ?? '').trim();
    final rawBookTitle = (bookTitle ?? '').trim();
    final rawChapter = (chapter ?? '').trim();
    final rawTopic = (topic ?? '').trim();

    final effectiveTopic = rawTopic.isNotEmpty ? rawTopic : rawQuery;
    final cleanTopic = effectiveTopic.toLowerCase();
    final cleanQuery = cleanTopic;

    // 1. Determine the student's current Form level
    final currentForm =
        explicitFormLevel ?? await _formStorage.getSelectedForm();

    // 2. Load books (seeding sample books if empty)
    await _bookStorage.seedSampleBooksIfEmpty(_knowledgeStorage);
    final allBooks = await _bookStorage.loadPublished();

    // 3. STRICT FILTER: Only search books of the current Form
    final formBooks = allBooks.where((b) {
      final cat = b.category.toLowerCase().trim();
      final target = currentForm.toLowerCase().trim();
      return cat == target || cat.contains(target) || target.contains(cat);
    }).toList();

    if (formBooks.isEmpty) {
      return CurriculumSearchResult(
        searchedFormLevel: currentForm,
        userQuery: rawTopic.isNotEmpty ? rawTopic : rawQuery,
        totalBooksSearched: 0,
        internalThought:
            'Baaraha wuxuu ku ekaa $currentForm, laakiin ma helin wax buug ah oo u diiwaangashan fasalkaan.',
      );
    }

    // 4. Match target book from bookTitle or search term
    PreparedBook? targetBook;
    if (rawBookTitle.isNotEmpty) {
      targetBook = _findBookByTitleOrAlias(rawBookTitle, formBooks);
    }
    if (targetBook == null && cleanTopic.isNotEmpty) {
      targetBook = _findBookByTitleOrAlias(cleanTopic, formBooks);
    }

    // 5. ACTION-BASED CURRICULUM EXECUTION
    if (targetBook != null) {
      // A: ACTION "get_chapter" (Specific Chapter Requested)
      if (rawAction == 'get_chapter' ||
          (rawChapter.isNotEmpty && rawAction != 'get_table_of_contents')) {
        PreparedChapter? matchedChapter;
        final cleanChap = rawChapter.toLowerCase();
        for (int i = 0; i < targetBook.chapters.length; i++) {
          final ch = targetBook.chapters[i];
          final tLower = ch.title.toLowerCase();
          if (tLower.contains(cleanChap) ||
              cleanChap.contains(tLower) ||
              cleanChap == '${i + 1}' ||
              cleanChap.contains('cutubka ${i + 1}') ||
              cleanChap.contains('chapter ${i + 1}')) {
            matchedChapter = ch;
            break;
          }
        }
        matchedChapter ??= targetBook.chapters.first;

        final chapterToc = [
          {
            'chapterId': matchedChapter.id,
            'chapterTitle': matchedChapter.title,
            'lessons': matchedChapter.lessons.map((les) => {
              'lessonId': les.id,
              'lessonTitle': les.title,
              if (les.sections.isNotEmpty)
                'sections': les.sections.map((sec) => {
                  'sectionId': sec.id,
                  'sectionTitle': sec.title,
                }).toList(),
            }).toList(),
          }
        ];

        final chapterMatches = <CurriculumSearchMatch>[];
        for (final les in matchedChapter.lessons) {
          chapterMatches.add(CurriculumSearchMatch(
            book: targetBook,
            chapter: matchedChapter,
            lesson: les,
            startPage: les.startPage,
            endPage: les.endPage,
            score: 1.0,
            matchReason: 'Chapter ${matchedChapter.title} lesson',
          ));
          for (final sec in les.sections) {
            chapterMatches.add(CurriculumSearchMatch(
              book: targetBook,
              chapter: matchedChapter,
              lesson: les,
              section: sec,
              startPage: sec.startPage > 0 ? sec.startPage : les.startPage,
              endPage: sec.endPage > 0 ? sec.endPage : les.endPage,
              score: 1.0,
              matchReason: 'Chapter ${matchedChapter.title} section',
            ));
          }
        }

        return CurriculumSearchResult(
          searchedFormLevel: currentForm,
          userQuery: rawChapter,
          matchedBook: targetBook,
          tableOfContents: chapterToc,
          totalBooksSearched: formBooks.length,
          internalThought:
              'Waxaa la soo saaray casharrada iyo qaybaha (sections) ee cutubka "${matchedChapter.title}" ee buugga "${targetBook.title}".',
          allDiscoveredMatches: chapterMatches,
        );
      }

      // Build full Table of Contents with Chapters -> Lessons -> Sections
      final fullToc = targetBook.chapters.map((chap) => {
        'chapterId': chap.id,
        'chapterTitle': chap.title,
        'lessons': chap.lessons.map((les) => {
          'lessonId': les.id,
          'lessonTitle': les.title,
          if (les.sections.isNotEmpty)
            'sections': les.sections.map((sec) => {
              'sectionId': sec.id,
              'sectionTitle': sec.title,
            }).toList(),
        }).toList(),
      }).toList();

      final allMatches = <CurriculumSearchMatch>[];
      for (final chap in targetBook.chapters) {
        for (final les in chap.lessons) {
          allMatches.add(CurriculumSearchMatch(
            book: targetBook,
            chapter: chap,
            lesson: les,
            startPage: les.startPage,
            endPage: les.endPage,
            score: 1.0,
            matchReason: 'Table of contents lesson entry',
          ));
          for (final sec in les.sections) {
            allMatches.add(CurriculumSearchMatch(
              book: targetBook,
              chapter: chap,
              lesson: les,
              section: sec,
              startPage: sec.startPage > 0 ? sec.startPage : les.startPage,
              endPage: sec.endPage > 0 ? sec.endPage : les.endPage,
              score: 1.0,
              matchReason: 'Table of contents section entry',
            ));
          }
        }
      }

      // B: ACTION "search_topic" or topic provided:
      CurriculumSearchMatch? directMatch;
      if (rawAction == 'search_topic' ||
          (cleanTopic.isNotEmpty && !_isPureSubjectQuery(cleanTopic, targetBook))) {
        // Priority 1: Check section titles
        for (final chap in targetBook.chapters) {
          for (final les in chap.lessons) {
            for (final sec in les.sections) {
              final secTitleLower = sec.title.toLowerCase();
              if (cleanTopic.contains(secTitleLower) ||
                  secTitleLower.contains(cleanTopic) ||
                  _tokenMatchesText(secTitleLower, cleanTopic)) {
                directMatch = CurriculumSearchMatch(
                  book: targetBook,
                  chapter: chap,
                  lesson: les,
                  section: sec,
                  startPage: sec.startPage > 0 ? sec.startPage : les.startPage,
                  endPage: sec.endPage > 0 ? sec.endPage : les.endPage,
                  score: 0.99,
                  matchReason: 'Qaybta tooska ah: "${sec.title}"',
                );
                break;
              }
            }
            if (directMatch != null) break;

            // Priority 2: Check lesson titles
            final lesTitleLower = les.title.toLowerCase();
            if (cleanTopic.contains(lesTitleLower) ||
                lesTitleLower.contains(cleanTopic) ||
                _tokenMatchesText(lesTitleLower, cleanTopic)) {
              directMatch = CurriculumSearchMatch(
                book: targetBook,
                chapter: chap,
                lesson: les,
                startPage: les.startPage,
                endPage: les.endPage,
                score: 0.95,
                matchReason: 'Casharka tooska ah: "${les.title}"',
              );
              break;
            }
          }
          if (directMatch != null) break;
        }
      }

      // C: ACTION "get_table_of_contents" or default full outline:
      return CurriculumSearchResult(
        searchedFormLevel: currentForm,
        userQuery: rawTopic.isNotEmpty ? rawTopic : rawQuery,
        matchedBook: targetBook,
        tableOfContents: fullToc,
        bestMatch: directMatch,
        totalBooksSearched: formBooks.length,
        internalThought: directMatch != null
            ? 'Waxaa buugga "${targetBook.title}" laga helay qaybta "${directMatch.section?.title ?? directMatch.lesson.title}".'
            : 'Waxaa si shuruud la\'aan ah loo soo saaray Liiska Cutubyada, Casharrada & Qaybaha (Sections) ee buugga "${targetBook.title}".',
        allDiscoveredMatches: allMatches,
      );
    }

    // 6. Autonomous Hierarchical Resolver
    final candidateBooks = targetBook != null ? [targetBook] : formBooks;
    final resolution = await _resolver.resolve(
      userQuery: rawQuery.isNotEmpty ? rawQuery : (targetBook?.title ?? ''),
      formLevel: currentForm,
      formBooks: candidateBooks,
      conversationContext: conversationContext,
    );

    if (resolution.found &&
        resolution.matchedBook != null &&
        resolution.matchedChapter != null &&
        resolution.matchedLesson != null) {
      final bestMatch = CurriculumSearchMatch(
        book: resolution.matchedBook!,
        chapter: resolution.matchedChapter!,
        lesson: resolution.matchedLesson!,
        section: resolution.matchedSection,
        startPage: resolution.startPage ?? resolution.matchedLesson!.startPage,
        endPage: resolution.endPage ?? resolution.matchedLesson!.endPage,
        score: 0.98,
        matchReason: resolution.reasoning,
      );

      return CurriculumSearchResult(
        searchedFormLevel: currentForm,
        userQuery: rawQuery,
        matchedBook: resolution.matchedBook,
        bestMatch: bestMatch,
        totalBooksSearched: formBooks.length,
        internalThought: resolution.reasoning,
        allDiscoveredMatches: [bestMatch],
      );
    }

    // 7. Token and Keyword Search across candidate books
    final rawTokens = _tokenize(cleanQuery);
    const stopWords = {
      'waxaan', 'rabaa', 'rabay', 'doonayaa', 'codsanayaa', 'fadlan', 'iiga',
      'ii', 'ku', 'ka', 'ee', 'ah', 'waxa', 'waa', 'maxay', 'sheeg', 'sharax',
      'sharaxaad', 'faahfaahin', 'baro', 'suaal', 'su\'aal', 'cashar', 'casharka',
      'cutub', 'cutubka', 'buug', 'buugga',
    };
    final queryTokens = rawTokens
        .where((t) => t.length >= 3 && !stopWords.contains(t))
        .toList();
    final effectiveTokens = queryTokens.isNotEmpty
        ? queryTokens
        : rawTokens.where((t) => t.length >= 3).toList();

    final matches = <CurriculumSearchMatch>[];

    for (final book in candidateBooks) {
      final bookTitleLower = book.title.toLowerCase();

      for (final chapter in book.chapters) {
        final chapterTitleLower = chapter.title.toLowerCase();

        for (final lesson in chapter.lessons) {
          final lessonTitleLower = lesson.title.toLowerCase();
          double score = 0.0;
          final matchReasons = <String>[];

          if (cleanQuery.isNotEmpty && lessonTitleLower.contains(cleanQuery)) {
            score += 0.80;
            matchReasons.add('Cinwaanka casharka ayaa toos u dhex yaal');
          }

          PreparedSection? matchedSection;
          for (final sec in lesson.sections) {
            final secLower = sec.title.toLowerCase();
            if (secLower.contains(cleanQuery)) {
              score += 0.70;
              matchedSection = sec;
              matchReasons.add('Qaybta (section): "${sec.title}"');
              break;
            }
          }

          int matchedTokensCount = 0;
          for (final token in effectiveTokens) {
            if (_tokenMatchesText(lessonTitleLower, token)) {
              matchedTokensCount += 2;
            } else if (_tokenMatchesText(chapterTitleLower, token)) {
              matchedTokensCount += 1;
            } else if (_tokenMatchesText(bookTitleLower, token)) {
              matchedTokensCount += 1;
            }
          }

          if (effectiveTokens.isNotEmpty && matchedTokensCount > 0) {
            final tokenRatio =
                (matchedTokensCount / (effectiveTokens.length * 2)).clamp(
                  0.0,
                  1.0,
                );
            score += tokenRatio * 0.50;
            if (matchReasons.isEmpty) {
              matchReasons.add(
                'Erayo ($matchedTokensCount) ayaa ku dhex jira casharka/cutubka',
              );
            }
          }

          if (cleanQuery.isNotEmpty && chapterTitleLower.contains(cleanQuery)) {
            score += 0.40;
            matchReasons.add('Cutubka: "${chapter.title}"');
          }

          final finalScore = min(1.0, score);

          if (finalScore >= 0.20) {
            final start = matchedSection != null && matchedSection.startPage > 0
                ? matchedSection.startPage
                : lesson.startPage;
            final end = matchedSection != null && matchedSection.endPage > 0
                ? matchedSection.endPage
                : lesson.endPage;

            matches.add(
              CurriculumSearchMatch(
                book: book,
                chapter: chapter,
                lesson: lesson,
                section: matchedSection,
                startPage: start > 0 ? start : 1,
                endPage: end >= start ? end : start,
                score: finalScore,
                matchReason: matchReasons.join(', '),
              ),
            );
          }
        }
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));

    if (matches.isEmpty) {
      return CurriculumSearchResult(
        searchedFormLevel: currentForm,
        userQuery: rawQuery,
        matchedBook: targetBook,
        totalBooksSearched: formBooks.length,
        internalThought:
            'Baaritaanka fasalka $currentForm waxaa laga baaray ${formBooks.length} buug, balse lama helin cashar toos ula fariista "$cleanQuery".',
      );
    }

    final bestMatch = matches.first;
    final alternatives = matches.skip(1).take(3).toList();

    return CurriculumSearchResult(
      searchedFormLevel: currentForm,
      userQuery: rawQuery,
      matchedBook: bestMatch.book,
      bestMatch: bestMatch,
      alternatives: alternatives,
      totalBooksSearched: formBooks.length,
      internalThought:
          'Waxaa fasalka $currentForm laga helay casharka "${bestMatch.lesson.title}" ee buugga "${bestMatch.book.title}".',
      allDiscoveredMatches: matches,
    );
  }

  /// Directly finds a lesson by ID or Title across the curriculum.
  Future<CurriculumSearchMatch?> findDirectMatch({
    String? bookId,
    String? chapterId,
    String? lessonId,
    String? sectionId,
    String? bookTitle,
    String? lessonTitle,
    String? sectionTitle,
  }) async {
    final allBooks = await _bookStorage.loadPublished();
    final candidateBooks =
        allBooks.isNotEmpty ? allBooks : await _bookStorage.loadAll();

    final bTitleClean = bookTitle?.trim().toLowerCase();
    final lTitleClean = lessonTitle?.trim().toLowerCase();
    final sTitleClean = sectionTitle?.trim().toLowerCase();

    for (final book in candidateBooks) {
      final bMatch = (bookId != null && bookId.isNotEmpty && book.id == bookId) ||
          (bTitleClean != null &&
              bTitleClean.isNotEmpty &&
              (book.title.toLowerCase().contains(bTitleClean) ||
                  _bookMatchesAlias(book.title.toLowerCase(), bTitleClean)));
      if (!bMatch && bookId != null && bookId.isNotEmpty) continue;

      for (final chapter in book.chapters) {
        final cMatch =
            chapterId == null || chapterId.isEmpty || chapter.id == chapterId;
        if (!cMatch) continue;

        for (final lesson in chapter.lessons) {
          final lMatch = (lessonId != null &&
                  lessonId.isNotEmpty &&
                  lesson.id == lessonId) ||
              (lTitleClean != null &&
                  lTitleClean.isNotEmpty &&
                  lesson.title.toLowerCase().contains(lTitleClean));
          if (!lMatch) continue;

          PreparedSection? matchedSec;
          if ((sectionId != null && sectionId.isNotEmpty) ||
              (sTitleClean != null && sTitleClean.isNotEmpty)) {
            for (final sec in lesson.sections) {
              final idMatch = sectionId != null &&
                  sectionId.isNotEmpty &&
                  sec.id == sectionId;
              final titleMatch = sTitleClean != null &&
                  sTitleClean.isNotEmpty &&
                  sec.title.toLowerCase().contains(sTitleClean);
              if (idMatch || titleMatch) {
                matchedSec = sec;
                break;
              }
            }
          }

          final start = matchedSec != null && matchedSec.startPage > 0
              ? matchedSec.startPage
              : lesson.startPage;
          final end = matchedSec != null && matchedSec.endPage > 0
              ? matchedSec.endPage
              : lesson.endPage;

          return CurriculumSearchMatch(
            book: book,
            chapter: chapter,
            lesson: lesson,
            section: matchedSec,
            startPage: start > 0 ? start : 1,
            endPage: end >= start ? end : start,
            score: 1.0,
            matchReason: 'Direct catalog resolution',
          );
        }
      }
    }
    return null;
  }

  /// Matches a book using exact keywords or Somali subject aliases.
  PreparedBook? _findBookByTitleOrAlias(String input, List<PreparedBook> books) {
    final clean = input.trim().toLowerCase();
    for (final book in books) {
      final title = book.title.toLowerCase();
      if (title.contains(clean) || clean.contains(title)) {
        return book;
      }
      if (_bookMatchesAlias(title, clean)) {
        return book;
      }
    }
    return null;
  }

  bool _bookMatchesAlias(String bookTitleLower, String inputLower) {
    for (final entry in curriculumSubjectAliases.entries) {
      final subjectKey = entry.key;
      final aliases = entry.value;

      final bookHasSubject = bookTitleLower.contains(subjectKey);
      if (!bookHasSubject) continue;

      for (final alias in aliases) {
        if (inputLower.contains(alias) || alias.contains(inputLower)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isPureSubjectQuery(String queryLower, PreparedBook book) {
    final clean = queryLower.trim();
    if (clean.isEmpty) return true;
    final title = book.title.toLowerCase();
    if (clean == title || title.contains(clean)) return true;

    for (final entry in curriculumSubjectAliases.entries) {
      if (title.contains(entry.key)) {
        for (final alias in entry.value) {
          if (clean == alias || clean == 'buugga $alias' || clean == 'buuga $alias') {
            return true;
          }
        }
      }
    }
    return false;
  }

  List<String> _tokenize(String text) {
    final clean = text.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ').trim();
    return clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  bool _tokenMatchesText(String targetText, String token) {
    if (token.length < 3) return false;
    if (targetText.contains(token)) return true;

    final root = token.length > 4
        ? token.substring(0, token.length - 2)
        : token;
    if (root.length >= 3 && targetText.contains(root)) return true;

    final targetWords = _tokenize(targetText);
    for (final tw in targetWords) {
      if (tw.length < 3) continue;
      if (token.contains(tw) || tw.contains(token)) return true;
      if (tw.startsWith(root) || token.startsWith(tw)) return true;
    }
    return false;
  }
}
