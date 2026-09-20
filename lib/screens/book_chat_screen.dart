import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/book_knowledge.dart';
import '../models/chat_session.dart';
import '../models/learning_session.dart';
import '../models/prepared_book.dart';
import '../services/book_knowledge_storage.dart';
import '../services/chat_history_storage.dart';
import '../services/form_preference_storage.dart';
import '../services/gemini_book_chat_service.dart';
import '../services/pdf_visual_crop_service.dart';
import '../services/pdf_slice_service.dart';
import '../services/prepared_book_storage.dart';
import '../widgets/rich_tutor_markdown.dart';

class BookChatScreen extends StatefulWidget {
  const BookChatScreen({
    super.key,
    this.book,
    this.initialChapter,
    this.initialLesson,
    this.initialSection,
    this.initialMode,
    this.onOpenLibrary,
    this.onOpenEditor,
  });

  final PreparedBook? book;
  final String? initialChapter;
  final String? initialLesson;
  final String? initialSection;
  final TutorMode? initialMode;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenEditor;

  @override
  State<BookChatScreen> createState() => _BookChatScreenState();
}

class _BookChatScreenState extends State<BookChatScreen> {
  static final _lessonVisualMarker = RegExp(
    r'\[\[LEYLI_VISUAL\s+page\s*=\s*(\d+)\s*;\s*x\s*=\s*([0-9.]+)\s*;\s*y\s*=\s*([0-9.]+)\s*;\s*width\s*=\s*([0-9.]+)\s*;\s*height\s*=\s*([0-9.]+)\s*;\s*title\s*=\s*(.*?)\s*\]\]',
    caseSensitive: false,
  );

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  final _knowledgeStorage = const BookKnowledgeStorage();
  final _bookStorage = const PreparedBookStorage();
  final _historyStorage = const ChatHistoryStorage();
  final _chatService = GeminiBookChatService();
  final _pdfSliceService = const PdfSliceService();
  final _pdfVisualCropService = const PdfVisualCropService();
  final _messages = <_ChatEntry>[];

  List<PreparedBook> _availableBooks = const [];
  PreparedBook? _currentBook;
  BookKnowledge? _knowledge;

  String? _focusChapter;
  String? _focusLesson;
  String? _focusSection;
  LearningSession? _learningSession;

  bool _loading = true;
  final Map<String, CancellationToken> _activeGenerations = {};
  bool get _isCurrentSessionSending =>
      _activeGenerations.containsKey(_currentSessionId);
  String? _error;

  void _stopCurrentGeneration({String? targetSessionId}) {
    final sId = targetSessionId ?? _currentSessionId;
    final token = _activeGenerations[sId];
    if (token != null) {
      token.cancel();
      _activeGenerations.remove(sId);
    }
    if (mounted) {
      setState(() {});
    }
  }

  // Scope picker & mini popup state
  String? _activeChapterPopup;
  final Set<String> _expandedLessonsInPopup = <String>{};

  final _formStorage = const FormPreferenceStorage();
  String _selectedForm = FormPreferenceStorage.defaultForm;
  bool _isLibraryExpandedInDrawer = true;

  // Chat history session state
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<ChatSession> _historySessions = const [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    setState(() => _loading = true);
    final savedForm = await _formStorage.getSelectedForm();
    final published = await _bookStorage.loadPublished();
    final all = published.isNotEmpty ? published : await _bookStorage.loadAll();

    PreparedBook? active = widget.book;

    _selectedForm = savedForm;
    _availableBooks = all;
    _currentBook = active;

    await _loadHistory();

    if (active != null) {
      await _loadKnowledgeForBook(active);
    } else {
      if (mounted) {
        setState(() {
          _messages.clear();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    final sessions = await _historyStorage.loadAll();
    if (mounted) {
      setState(() => _historySessions = sessions);
    }
  }

  Future<void> _saveCurrentSessionToHistory() async {
    if (_messages.isEmpty) return;

    final firstUserMsg = _messages.firstWhere(
      (m) => m.isUser,
      orElse: () => _messages.first,
    );

    String rawTitle = firstUserMsg.text.trim().replaceAll('\n', ' ');
    if (rawTitle.isEmpty) {
      rawTitle = _currentBook?.title ?? 'Sheeko Cusub';
    }
    final title = rawTitle.length > 36
        ? '${rawTitle.substring(0, 36)}...'
        : rawTitle;

    final session = ChatSession(
      id: _currentSessionId,
      title: title,
      updatedAt: DateTime.now(),
      bookId: _currentBook?.id,
      bookTitle: _currentBook?.title,
      focusChapter: _focusChapter,
      focusLesson: _focusLesson,
      focusSection: _focusSection,
      focusChapterId: _learningSession?.chapterId,
      focusLessonId: _learningSession?.lessonId,
      focusSectionId: _learningSession?.sectionId,
      learningSessionId: _learningSession?.id,
      learningScopeType: _learningSession?.scopeType.name,
      currentPartIndex: _learningSession?.currentPartIndex ?? 0,
      partCount: _learningSession?.partCount ?? 1,
      messages: _messages
          .map(
            (m) => ChatMessageModel(
              text: m.text,
              isUser: m.isUser,
              scopeLabel: m.scopeLabel,
              pagesLabel: m.pagesLabel,
              hasPdf: m.hasPdf,
              canContinue: m.canContinue,
              partIndex: m.partIndex,
              isLessonComplete: m.isLessonComplete,
              visuals: m.visuals,
            ),
          )
          .toList(),
    );

    await _historyStorage.saveSession(session);
    await _loadHistory();
  }

  void _startNewChat({bool clearBook = true}) {
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      if (clearBook) {
        _currentBook = null;
      }
      _messages.clear();
      _questionController.clear();
      _error = null;
      _resetFocus();
      _activeChapterPopup = null;
    });
  }

  Future<void> _loadSessionFromHistory(ChatSession session) async {
    PreparedBook? foundBook;
    if (session.bookId != null && _availableBooks.isNotEmpty) {
      for (final b in _availableBooks) {
        if (b.id == session.bookId) {
          foundBook = b;
          break;
        }
      }
    }

    setState(() {
      _currentSessionId = session.id;
      _currentBook = foundBook;
      _focusChapter = session.focusChapter;
      _focusLesson = session.focusLesson;
      _focusSection = session.focusSection;
      _learningSession = _learningSessionFromHistory(session, foundBook);
      _messages.clear();
      for (final m in session.messages) {
        _messages.add(
          _ChatEntry(
            text: m.text,
            isUser: m.isUser,
            scopeLabel: m.scopeLabel,
            pagesLabel: m.pagesLabel,
            hasPdf: m.hasPdf,
            canContinue: m.canContinue,
            partIndex: m.partIndex,
            isLessonComplete: m.isLessonComplete,
            visuals: m.visuals,
          ),
        );
      }
      _activeChapterPopup = null;
    });

    if (foundBook != null) {
      final knowledge = await _knowledgeStorage.load(foundBook.id);
      if (mounted) {
        setState(() {
          _knowledge =
              knowledge ??
              BookKnowledge(bookId: foundBook!.id, pages: const {});
        });
      }
      await _restoreHistoryVisuals(foundBook);
    }
  }

  Future<void> _restoreHistoryVisuals(PreparedBook book) async {
    for (var index = 0; index < _messages.length; index++) {
      final entry = _messages[index];
      if (entry.isUser || entry.visuals.isEmpty) continue;
      final missing = entry.visuals.where(
        (visual) =>
            visual.thumbnailBytes == null &&
            (visual.thumbnailPath == null ||
                !File(visual.thumbnailPath!).existsSync()),
      );
      if (missing.isEmpty) continue;

      final scope = _resolveScopeForHistoryPart(entry.partIndex);
      final pdfBytes = await _obtainScopePdf(
        book: book,
        startPage: scope.startPage,
        endPage: scope.endPage,
        startPosition: scope.startPosition,
        endPosition: scope.endPosition,
        scopeTitle: scope.label,
      );
      if (pdfBytes == null || pdfBytes.isEmpty) continue;

      final restored = <ChatVisualModel>[];
      for (final visual in entry.visuals) {
        if (visual.thumbnailBytes != null ||
            (visual.thumbnailPath != null &&
                File(visual.thumbnailPath!).existsSync())) {
          restored.add(visual);
          continue;
        }
        try {
          final bytes = await _pdfVisualCropService.cropPage(
            pdfBytes: pdfBytes,
            pageNumber: visual.page,
            left: visual.left,
            top: visual.top,
            width: visual.width,
            height: visual.height,
          );
          if (bytes != null && bytes.isNotEmpty) {
            final path = await _pdfVisualCropService.saveThumbnail(
              bytes,
              id: '$_currentSessionId-restored-$index-${restored.length}',
            );
            restored.add(visual.withThumbnail(bytes, path: path));
          }
        } catch (error) {
          debugPrint('Could not restore history visual: $error');
        }
      }
      if (mounted && restored.isNotEmpty) {
        setState(() => _messages[index] = entry.copyWithVisuals(restored));
      }
    }
    await _saveCurrentSessionToHistory();
  }

  ({
    int startPage,
    int endPage,
    double startPosition,
    double endPosition,
    String label,
    String type,
  })
  _resolveScopeForHistoryPart(int? partIndex) {
    final scope = _resolveCurrentScope();
    final index = partIndex ?? 0;
    const pagesPerPart = 2;
    if ((_learningSession?.partCount ?? 1) <= 1) return scope;
    final startPage = (scope.startPage + index * pagesPerPart)
        .clamp(scope.startPage, scope.endPage)
        .toInt();
    final endPage = (startPage + pagesPerPart - 1)
        .clamp(startPage, scope.endPage)
        .toInt();
    return (
      startPage: startPage,
      endPage: endPage,
      startPosition: startPage == scope.startPage ? scope.startPosition : 0.0,
      endPosition: endPage == scope.endPage ? scope.endPosition : 1.0,
      label: scope.label,
      type: scope.type,
    );
  }

  Future<void> _deleteSession(String id) async {
    _stopCurrentGeneration(targetSessionId: id);
    await _historyStorage.deleteSession(id);
    if (_currentSessionId == id) {
      _startNewChat();
    }
    await _loadHistory();
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: const Text(
          'Ma hubtaa inaad tirtirto dhammaan sheekooyinkii hore?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maya'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
            ),
            child: const Text('Tirtir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyStorage.clearAll();
      _startNewChat();
      await _loadHistory();
    }
  }

  Future<void> _loadKnowledgeForBook(
    PreparedBook book, {
    bool preserveMessages = false,
  }) async {
    BookKnowledge? knowledge = await _knowledgeStorage.load(book.id);

    // Extract text from PDF if not already stored
    if ((knowledge == null || knowledge.pages.isEmpty) &&
        book.originalPdfPath != null) {
      try {
        final pdfBytes = await _bookStorage.loadPdf(book);
        if (pdfBytes != null) {
          final document = PdfDocument(inputBytes: pdfBytes);
          final pageTexts = <int, String>{};
          for (var i = 0; i < document.pages.count; i++) {
            final pageText = PdfTextExtractor(
              document,
            ).extractText(startPageIndex: i, endPageIndex: i);
            if (pageText.trim().isNotEmpty) {
              pageTexts[i + 1] = pageText;
            }
          }
          document.dispose();
          if (pageTexts.isNotEmpty) {
            knowledge = BookKnowledge(bookId: book.id, pages: pageTexts);
            await _knowledgeStorage.save(knowledge);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final initialCh = widget.initialChapter;
    final initialLs = widget.initialLesson;
    final initialSec = widget.initialSection;

    setState(() {
      _currentBook = book;
      _knowledge = knowledge ?? BookKnowledge(bookId: book.id, pages: const {});
      _focusChapter = initialCh;
      _focusLesson = initialLs;
      _focusSection = initialSec;
      if (!preserveMessages) {
        _messages.clear();
      }
      _activeChapterPopup = null;
      _loading = false;
    });

    if (widget.initialMode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeTutorAction(widget.initialMode!);
      });
    }
  }

  ({
    int startPage,
    int endPage,
    double startPosition,
    double endPosition,
    String label,
    String type,
  })
  _resolveCurrentScope() {
    final book = _currentBook;
    if (book == null) {
      return (
        startPage: 1,
        endPage: 1,
        startPosition: 0.0,
        endPosition: 1.0,
        label: 'Buugga',
        type: 'Buug',
      );
    }

    final activeScope = _learningSession;
    if (activeScope?.sectionId != null) {
      for (final ch in book.chapters) {
        for (final ls in ch.lessons) {
          for (final sec in ls.sections) {
            if (sec.id == activeScope!.sectionId) {
              return (
                startPage: sec.startPage,
                endPage: sec.endPage,
                startPosition: sec.startPosition,
                endPosition: sec.endPosition,
                label: sec.title,
                type: 'Section',
              );
            }
          }
        }
      }
    }

    if (activeScope?.lessonId != null) {
      for (final ch in book.chapters) {
        for (final ls in ch.lessons) {
          if (ls.id == activeScope!.lessonId) {
            return (
              startPage: ls.startPage,
              endPage: ls.endPage,
              startPosition: ls.startPosition,
              endPosition: ls.endPosition,
              label: ls.title,
              type: 'Cashar',
            );
          }
        }
      }
    }

    if (activeScope?.chapterId != null) {
      for (final ch in book.chapters) {
        if (ch.id == activeScope!.chapterId) {
          return (
            startPage: ch.startPage,
            endPage: ch.endPage,
            startPosition: 0.0,
            endPosition: 1.0,
            label: ch.title,
            type: 'Cutub',
          );
        }
      }
    }

    if (_focusSection != null) {
      for (final ch in book.chapters) {
        for (final ls in ch.lessons) {
          for (final sec in ls.sections) {
            if (sec.title == _focusSection) {
              return (
                startPage: sec.startPage,
                endPage: sec.endPage,
                startPosition: sec.startPosition,
                endPosition: sec.endPosition,
                label: sec.title,
                type: 'Section',
              );
            }
          }
        }
      }
    }

    if (_focusLesson != null) {
      for (final ch in book.chapters) {
        for (final ls in ch.lessons) {
          if (ls.title == _focusLesson) {
            return (
              startPage: ls.startPage,
              endPage: ls.endPage,
              startPosition: ls.startPosition,
              endPosition: ls.endPosition,
              label: ls.title,
              type: 'Cashar',
            );
          }
        }
      }
    }

    if (_focusChapter != null) {
      for (final ch in book.chapters) {
        if (ch.title == _focusChapter) {
          return (
            startPage: ch.startPage,
            endPage: ch.endPage,
            startPosition: 0.0,
            endPosition: 1.0,
            label: ch.title,
            type: 'Cutub',
          );
        }
      }
    }

    return (
      startPage: 1,
      endPage: book.pageCount > 0 ? book.pageCount : 1,
      startPosition: 0.0,
      endPosition: 1.0,
      label: book.title,
      type: 'Buugga oo dhan',
    );
  }

  ({
    int startPage,
    int endPage,
    double startPosition,
    double endPosition,
    String label,
    String type,
  })
  _resolveCurrentLearningPart(
    ({
      int startPage,
      int endPage,
      double startPosition,
      double endPosition,
      String label,
      String type,
    })
    scope,
  ) {
    final session = _learningSession;
    if (session == null || session.partCount <= 1) return scope;

    const pagesPerPart = 2;
    final partStart =
        (scope.startPage + session.currentPartIndex * pagesPerPart).clamp(
          scope.startPage,
          scope.endPage,
        );
    final partEnd = (partStart + pagesPerPart - 1).clamp(
      partStart,
      scope.endPage,
    );
    return (
      startPage: partStart,
      endPage: partEnd,
      startPosition: partStart == scope.startPage ? scope.startPosition : 0.0,
      endPosition: partEnd == scope.endPage ? scope.endPosition : 1.0,
      label:
          '${scope.label} • Qaybta ${session.currentPartIndex + 1}/${session.partCount}',
      type: scope.type,
    );
  }

  Future<Uint8List?> _obtainScopePdf({
    required PreparedBook book,
    required int startPage,
    required int endPage,
    double startPosition = 0.0,
    double endPosition = 1.0,
    required String scopeTitle,
  }) async {
    if (book.originalPdfPath != null && book.originalPdfPath!.isNotEmpty) {
      try {
        final originalBytes = await _bookStorage.loadPdf(book);
        if (originalBytes != null && originalBytes.isNotEmpty) {
          return _pdfSliceService.slicePdf(
            sourcePdfBytes: originalBytes,
            startPage: startPage,
            endPage: endPage,
            startPosition: startPosition,
            endPosition: endPosition,
          );
        }
      } catch (e) {
        debugPrint('Could not slice source PDF: $e');
      }
    }

    final knowledge = _knowledge ?? await _knowledgeStorage.load(book.id);
    final pageMap = <int, String>{};
    if (knowledge != null) {
      for (var p = startPage; p <= endPage; p++) {
        final content = knowledge.pages[p];
        if (content != null && content.isNotEmpty) {
          pageMap[p] = content;
        }
      }
    }
    return _pdfSliceService.createPdfFromKnowledge(
      bookTitle: book.title,
      scopeTitle: scopeTitle,
      grade: book.category,
      pageContents: pageMap,
    );
  }

  Future<void> _executeTutorAction(
    TutorMode mode, {
    String? customPrompt,
  }) async {
    if (_isCurrentSessionSending) return;

    final book = _currentBook;
    final knowledge = _knowledge;
    final scope = _resolveCurrentLearningPart(_resolveCurrentScope());
    final isLessonScope =
        _learningSession?.scopeType == LearningScopeType.lesson ||
        _learningSession?.scopeType == LearningScopeType.section;

    String userDisplay;
    switch (mode) {
      case TutorMode.teach:
        userDisplay = customPrompt ?? '📖 I Bar qaybta: ${scope.label}';
        break;
      case TutorMode.visuals:
        userDisplay = '🖼️ Sharax sawirrada & jaantusyada: ${scope.label}';
        break;
      case TutorMode.explain:
        userDisplay = '💡 I Sharax qaybta: ${scope.label}';
        break;
      case TutorMode.quiz:
        userDisplay = '📝 I weydii su\'aalo (Quiz): ${scope.label}';
        break;
      case TutorMode.summary:
        userDisplay = '📌 Ii soo koob: ${scope.label}';
        break;
      case TutorMode.freeChat:
        userDisplay = customPrompt ?? _questionController.text.trim();
        break;
    }

    final isFinalPart =
        _isLessonExplanationRequest(mode, userDisplay) &&
        isLessonScope &&
        !(_learningSession?.hasNextPart ?? false);

    if (userDisplay.trim().isEmpty) return;
    if (mode == TutorMode.freeChat) _questionController.clear();

    final targetSessionId = _currentSessionId;
    final token = CancellationToken();
    _activeGenerations[targetSessionId] = token;

    setState(() {
      _messages.add(_ChatEntry(text: userDisplay, isUser: true));
      _error = null;
    });
    _saveCurrentSessionToHistory();
    _scrollToBottom();

    try {
      Uint8List? slicedPdfBytes;
      if (book != null) {
        slicedPdfBytes = await _obtainScopePdf(
          book: book,
          startPage: scope.startPage,
          endPage: scope.endPage,
          startPosition: scope.startPosition,
          endPosition: scope.endPosition,
          scopeTitle: scope.label,
        );
      }

      if (token.isCancelled) return;

      final answer = await _chatService.ask(
        book: book,
        knowledge: knowledge,
        question: userDisplay,
        focusChapter: _focusChapter,
        focusLesson: _focusLesson,
        focusSection: _focusSection,
        startPosition: scope.startPosition,
        endPosition: scope.endPosition,
        slicedPdfBytes: slicedPdfBytes,
        mode: mode,
        learningScopeType: _learningSession?.scopeType,
        learningPartNumber: _learningSession == null
            ? null
            : _learningSession!.currentPartIndex + 1,
        learningPartCount: _learningSession?.partCount,
        priorLearningContext: _recentLearningContext(),
        isLessonCompletion: isFinalPart,
        cancellationToken: token,
      );

      if (token.isCancelled) return;

      final visuals = await _extractLessonVisuals(answer, slicedPdfBytes);

      final hasCrop =
          (scope.startPosition > 0.02) || (scope.endPosition < 0.98);
      final cropSummary = hasCrop
          ? 'Bogagga ${scope.startPage}-${scope.endPage} (${(scope.startPosition * 100).toInt()}% - ${(scope.endPosition * 100).toInt()}%)'
          : 'Bogagga ${scope.startPage}-${scope.endPage}';

      final entry = _ChatEntry(
        text: answer,
        isUser: false,
        scopeLabel: book != null ? scope.label : null,
        pagesLabel: book != null ? cropSummary : null,
        hasPdf: slicedPdfBytes != null && slicedPdfBytes.isNotEmpty,
        canContinue: _learningSession?.hasNextPart ?? false,
        partIndex: _learningSession?.currentPartIndex,
        isLessonComplete: isFinalPart,
        visuals: visuals,
      );

      if (_currentSessionId == targetSessionId) {
        if (!mounted) return;
        setState(() {
          _messages.add(entry);
        });
        _saveCurrentSessionToHistory();
      } else {
        // User has switched to another session; save directly into target session storage
        final savedSession = await _historyStorage.getSession(targetSessionId);
        if (savedSession != null) {
          final updatedMessages =
              List<ChatMessageModel>.from(savedSession.messages)..add(
                ChatMessageModel(
                  text: entry.text,
                  isUser: false,
                  scopeLabel: entry.scopeLabel,
                  pagesLabel: entry.pagesLabel,
                  hasPdf: entry.hasPdf,
                  canContinue: entry.canContinue,
                  partIndex: entry.partIndex,
                  isLessonComplete: entry.isLessonComplete,
                  visuals: entry.visuals,
                ),
              );
          await _historyStorage.saveSession(
            savedSession.copyWith(
              messages: updatedMessages,
              updatedAt: DateTime.now(),
            ),
          );
          await _loadHistory();
        }
      }
    } on GeminiCancelledException {
      // Stopped by user
    } catch (e) {
      if (token.isCancelled) return;
      if (mounted && _currentSessionId == targetSessionId) {
        setState(() => _error = 'Su’aasha lama dirin: $e');
      }
    } finally {
      _activeGenerations.remove(targetSessionId);
      if (mounted) {
        setState(() {});
        if (_currentSessionId == targetSessionId) {
          _scrollToBottom();
        }
      }
    }
  }

  Future<List<ChatVisualModel>> _extractLessonVisuals(
    String answer,
    Uint8List? slicedPdfBytes,
  ) async {
    if (slicedPdfBytes == null || slicedPdfBytes.isEmpty) return const [];
    final markers = _readVisualMarkers(answer);
    if (markers.isEmpty) return const [];

    final visuals = <ChatVisualModel>[];
    for (final marker in markers.take(2)) {
      try {
        final thumbnail = await _pdfVisualCropService.cropPage(
          pdfBytes: slicedPdfBytes,
          pageNumber: marker.page,
          left: marker.left,
          top: marker.top,
          width: marker.width,
          height: marker.height,
        );
        if (thumbnail != null && thumbnail.isNotEmpty) {
          final path = await _pdfVisualCropService.saveThumbnail(
            thumbnail,
            id: '$_currentSessionId-${DateTime.now().microsecondsSinceEpoch}-${visuals.length}',
          );
          visuals.add(marker.withThumbnail(thumbnail, path: path));
        }
      } catch (error) {
        debugPrint('Could not crop lesson visual: $error');
      }
    }
    return visuals;
  }

  List<ChatVisualModel> _readVisualMarkers(String answer) {
    final matches = _lessonVisualMarker.allMatches(answer);
    return matches.map((match) {
      double value(int group, double fallback) =>
          double.tryParse(match.group(group) ?? '') ?? fallback;
      return ChatVisualModel(
        page: int.tryParse(match.group(1) ?? '') ?? 1,
        left: value(2, 0),
        top: value(3, 0),
        width: value(4, 1),
        height: value(5, 1),
        title: (match.group(6) ?? 'Sawirka casharka').trim(),
      );
    }).toList();
  }

  String _recentLearningContext() {
    final previousAnswers = _messages
        .where((entry) => !entry.isUser)
        .map((entry) => entry.text)
        .toList();
    if (previousAnswers.isEmpty) return '';
    final recent = previousAnswers.reversed
        .take(2)
        .toList()
        .reversed
        .join('\n\n');
    return recent.length > 1600
        ? recent.substring(recent.length - 1600)
        : recent;
  }

  bool _isLessonExplanationRequest(TutorMode mode, String userPrompt) {
    if (mode == TutorMode.teach) return true;
    if (mode != TutorMode.freeChat) return false;
    final prompt = userPrompt.toLowerCase();
    return prompt.contains('sharax') ||
        prompt.contains('cashar') ||
        prompt.contains('bar') ||
        prompt.contains('explain') ||
        prompt.contains('teach');
  }

  Future<void> _continueToNextPart() async {
    final session = _learningSession;
    if (session == null || !session.hasNextPart || _isCurrentSessionSending)
      return;

    setState(() {
      _learningSession = session.copyWith(
        currentPartIndex: session.currentPartIndex + 1,
      );
      _error = null;
    });
    await _executeTutorAction(
      TutorMode.teach,
      customPrompt: 'U gudub qaybta xigta ee ${session.scopeLabel}.',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetFocus() {
    _focusChapter = null;
    _focusLesson = null;
    _focusSection = null;
    _learningSession = null;
    _activeChapterPopup = null;
  }

  LearningSession? _learningSessionFromHistory(
    ChatSession session,
    PreparedBook? book,
  ) {
    if (book == null || session.learningSessionId == null) return null;
    final scopeType = LearningScopeType.values.where(
      (type) => type.name == session.learningScopeType,
    );
    final type = scopeType.isEmpty ? LearningScopeType.book : scopeType.first;
    return LearningSession(
      id: session.learningSessionId!,
      bookId: book.id,
      bookTitle: book.title,
      scopeType: type,
      scopeLabel:
          session.focusSection ??
          session.focusLesson ??
          session.focusChapter ??
          book.title,
      startedAt: session.updatedAt,
      chapterId: session.focusChapterId,
      chapterTitle: session.focusChapter,
      lessonId: session.focusLessonId,
      lessonTitle: session.focusLesson,
      sectionId: session.focusSectionId,
      sectionTitle: session.focusSection,
      currentPartIndex: session.currentPartIndex,
      partCount: session.partCount,
    );
  }

  Future<void> _startLearningSession({
    required LearningScopeType scopeType,
    required String scopeLabel,
    String? chapterId,
    String? chapterTitle,
    String? lessonId,
    String? lessonTitle,
    String? sectionId,
    String? sectionTitle,
    int partCount = 1,
  }) async {
    final book = _currentBook;
    if (book == null) return;

    if (_isCurrentSessionSending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sug jawaabta hadda socota ka hor intaadan casharka beddelin ama jooji adoo riixaya badhanka Jooji.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final nextSession = LearningSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      bookId: book.id,
      bookTitle: book.title,
      scopeType: scopeType,
      scopeLabel: scopeLabel,
      startedAt: DateTime.now(),
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      sectionId: sectionId,
      sectionTitle: sectionTitle,
      partCount: partCount,
    );

    if (_learningSession != null && _learningSession!.matches(nextSession)) {
      if (mounted) setState(() => _activeChapterPopup = null);
      return;
    }

    await _saveCurrentSessionToHistory();
    if (!mounted) return;

    setState(() {
      _currentSessionId = nextSession.id;
      _learningSession = nextSession;
      _focusChapter = chapterTitle;
      _focusLesson = lessonTitle;
      _focusSection = sectionTitle;
      _messages.clear();
      _questionController.clear();
      _error = null;
      _activeChapterPopup = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cashar cusub ayaa loo bilaabay: $scopeLabel'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startBookOverview() async {
    final book = _currentBook;
    if (book == null) return;
    await _startLearningSession(
      scopeType: LearningScopeType.book,
      scopeLabel: book.title,
    );
  }

  Future<void> _startChapterOverview(PreparedChapter chapter) =>
      _startLearningSession(
        scopeType: LearningScopeType.chapter,
        scopeLabel: chapter.title,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
      );

  Future<void> _startLessonSession(
    PreparedChapter chapter,
    PreparedLesson lesson,
  ) => _startLearningSession(
    scopeType: LearningScopeType.lesson,
    scopeLabel: lesson.title,
    chapterId: chapter.id,
    chapterTitle: chapter.title,
    lessonId: lesson.id,
    lessonTitle: lesson.title,
    partCount: _partCount(lesson.startPage, lesson.endPage),
  );

  Future<void> _startSectionSession(
    PreparedChapter chapter,
    PreparedLesson lesson,
    PreparedSection section,
  ) => _startLearningSession(
    scopeType: LearningScopeType.section,
    scopeLabel: section.title,
    chapterId: chapter.id,
    chapterTitle: chapter.title,
    lessonId: lesson.id,
    lessonTitle: lesson.title,
    sectionId: section.id,
    sectionTitle: section.title,
    partCount: _partCount(section.startPage, section.endPage),
  );

  int _partCount(int startPage, int endPage) {
    final pages = (endPage - startPage + 1).clamp(1, 9999);
    return (pages / 2).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _currentBook;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildChatDrawer(theme),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Image.asset(
              'assets/icon-Leyli AI.png',
              height: 28,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Text(
              'Leyli',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF000000),
              ),
            ),
            if (book != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat Cusub',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _startNewChat,
          ),
          IconButton(
            tooltip: 'Maktabadda',
            icon: const Icon(Icons.local_library_outlined),
            onPressed: widget.onOpenLibrary,
          ),
          IconButton(
            tooltip: 'Editor-ka',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: widget.onOpenEditor,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? (book == null
                            ? _buildEmptyNoBookChatState(theme)
                            : _buildBookWelcomeCard(book, theme))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount:
                              _messages.length +
                              (_isCurrentSessionSending ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _messages.length) {
                              return _buildMessageCard(_messages[index], theme);
                            }
                            return _buildLoadingBubble(theme);
                          },
                        ),
                ),
                if (_error != null) _buildErrorBanner(theme),
                _buildBottomArea(theme),
              ],
            ),
    );
  }

  /// Drawer containing Chat History and shortcuts
  Widget _buildChatDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.35,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/icon-Leyli AI.png',
                    height: 38,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leyli AI',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF000000),
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Macallinkaaga Gaarka ah ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // New Chat Action Button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _startNewChat();
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    'New Chat',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            // Expanded scrollable drawer body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                children: [
                  // Maktabadda In-Menu Toggle Section with Form Selector Icon Window
                  _buildDrawerLibrarySection(theme),
                  const SizedBox(height: 10),

                  // History Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 17,
                          color: Color(0xFF000000),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chat History (${_historySessions.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (_historySessions.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 17,
                            ),
                            tooltip: 'Tirtir dhammaan',
                            visualDensity: VisualDensity.compact,
                            onPressed: _clearAllHistory,
                          ),
                      ],
                    ),
                  ),

                  // History Sessions List
                  if (_historySessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 30,
                              color: Color(0xFF000000),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Ma jiraan sheekooyin hore weli.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._historySessions.map((session) {
                      final isCurrent = session.id == _currentSessionId;
                      final isGenerating = _activeGenerations.containsKey(
                        session.id,
                      );
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          leading: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 17,
                            color: Color(0xFF000000),
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: session.bookTitle != null
                              ? Text(
                                  session.bookTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF000000),
                                  ),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isGenerating)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                ),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Tirtir',
                                onPressed: () => _deleteSession(session.id),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _loadSessionFromHistory(session);
                          },
                        ),
                      );
                    }),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bottom quick link to Book Editor
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_note_rounded, size: 19),
              title: const Text(
                'Editor-ka Buugaagta',
                style: TextStyle(fontSize: 12.5),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onOpenEditor?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Clean empty chat state when no book is open (No border, no background)
  Widget _buildEmptyNoBookChatState(ThemeData theme) {
    final formBooks = _availableBooks
        .where((b) => b.category == _selectedForm && b.isPublished)
        .toList();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. App Icon
            Image.asset(
              'assets/icon-Leyli AI.png',
              height: 60,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),

            // 2. App Name
            const Text(
              'Leyli AI',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF000000),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            // 3. Sanad-ka la doortay (Selected Form)
            InkWell(
              onTap: () => _showFormSelectionDialog(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size: 16,
                      color: Color(0xFF000000),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedForm,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 20,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Books-ka ku jira magacyadooda oo hal-saf ah oo soconaya dhinaca midig ilaa bidix
            if (formBooks.isNotEmpty) ...[
              _HorizontalBooksTicker(
                books: formBooks,
                onBookSelected: _switchToBook,
              ),
              const SizedBox(height: 18),
            ],

            // 5. Ardayga oo loosheegayo in lagacaawin doono barashada form-ka
            Text(
              'Waxaan kaa caawin doonaa barashada dhammaan maadooyinka iyo buugaagta $_selectedForm.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Weydii su\'aal kasta ama dooro buug si aad casharka u bilowdo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clean welcome screen when a book is selected (mirrors empty state layout)
  Widget _buildBookWelcomeCard(PreparedBook book, ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. App Icon
            Image.asset(
              'assets/icon-Leyli AI.png',
              height: 60,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),

            // 2. App Name
            const Text(
              'Leyli AI',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF000000),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            // 3. Meesha Forms-ka: Books-ka la doortay (Book Selector Pill)
            InkWell(
              onTap: () => _showBookSelectionDialog(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      size: 16,
                      color: Color(0xFF000000),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      book.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 20,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Meesha Books-ka: Chapters-ka book-ga la doortay iyagoo socda haddii ay badan yihiin
            if (book.chapters.isNotEmpty) ...[
              _HorizontalChaptersTicker(
                chapters: book.chapters,
                onChapterSelected: (chapter) {
                  _startChapterOverview(chapter);
                },
              ),
              const SizedBox(height: 18),
            ],

            // 5. Ardayga oo loogu sheegayo in laga caawinayo barashada buugga
            Text(
              'Waxaan kaa caawin doonaa barashada buugga ${book.title} (${book.category}).',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Weydii su\'aal kasta oo ku saabsan cutubyada iyo casharrada buuggan ama dooro chapter si aad u bilowdo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chat message card
  /// User: ONLY user text, no avatar or "aniga"
  /// AI: Clean markdown, NO border, NO background box
  Widget _buildMessageCard(_ChatEntry entry, ThemeData theme) {
    final isUser = entry.isUser;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          margin: const EdgeInsets.only(bottom: 14, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: SelectableText(
            entry.text,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // AI message: border and background removed as requested
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        margin: const EdgeInsets.only(bottom: 18, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon-Leyli AI.png',
                  height: 18,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Leyli AI',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
                if (entry.scopeLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.scopeLabel!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            RichTutorMarkdown(
              text: _removeVisualMarkers(entry.text),
              isUser: false,
            ),
            if (entry.visuals.isNotEmpty)
              ...entry.visuals
                  .where(
                    (visual) =>
                        visual.thumbnailBytes != null ||
                        (visual.thumbnailPath != null &&
                            File(visual.thumbnailPath!).existsSync()),
                  )
                  .map(_buildInlineLessonVisual),
            const SizedBox(height: 6),
            if (entry.isLessonComplete)
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8ECFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF0022FF),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Casharka waa dhammaystiran yahay',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0022FF),
                      ),
                    ),
                  ],
                ),
              ),
            if (entry.canContinue &&
                entry.partIndex == _learningSession?.currentPartIndex) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: TextButton.icon(
                    onPressed: _isCurrentSessionSending
                        ? null
                        : _continueToNextPart,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('U gudub qaybta xigta'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0022FF),
                      backgroundColor: const Color(0xFFE8ECFF),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Koobiyeey',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Qoraalka waa la koobiyeeyay.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A compact typing indicator shown only while Leyli is preparing a reply.
  Widget _buildLoadingBubble(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(4),
              child: Image.asset('assets/icon-Leyli AI.png'),
            ),
            const SizedBox(width: 9),
            Text(
              'Leyli AI',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            const _PulsingDots(),
          ],
        ),
      ),
    );
  }

  String _removeVisualMarkers(String text) => text
      .replaceAll(_lessonVisualMarker, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Widget _buildInlineLessonVisual(ChatVisualModel visual) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FF),
        border: Border.all(color: const Color(0xFFD8DFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVisualImage(visual),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
            child: Text(
              visual.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildVisualImage(ChatVisualModel visual) {
    final bytes = visual.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: double.infinity,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }
    final path = visual.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: double.infinity,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }
    return const SizedBox.shrink();
  }

  /// Helper to truncate long names to a specified maximum length with ellipsis
  String _truncateScopeName(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Bottom area: Mini Scope Popup (upward) + Chapter Buttons Bar + Input Bar
  Widget _buildBottomArea(ThemeData theme) {
    final book = _currentBook;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (book != null) ...[
          if (_activeChapterPopup != null) _buildMiniScopePopup(book, theme),
          _buildChaptersBar(book, theme),
        ],
        _buildInputBar(theme),
      ],
    );
  }

  /// Horizontal scrolling row of small buttons directly above the input:
  /// "Buugga oo dhan" button + Chapter buttons (truncated to <= 13 chars with '...')
  Widget _buildChaptersBar(PreparedBook book, ThemeData theme) {
    final isAllBookSelected =
        _focusChapter == null && _focusLesson == null && _focusSection == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "Buugga oo dhan" button
            InkWell(
              onTap: _startBookOverview,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isAllBookSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isAllBookSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 13,
                      color: isAllBookSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'All',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isAllBookSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isAllBookSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Chapter buttons (truncated to 13 characters with '...')
            for (final chapter in book.chapters) ...[
              _buildChapterButton(chapter, theme),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// Small Chapter Button with 13-character truncation & toggle list icon
  Widget _buildChapterButton(PreparedChapter chapter, ThemeData theme) {
    final isChapterActive = _focusChapter == chapter.title;
    final isPopupOpen = _activeChapterPopup == chapter.title;
    final truncatedTitle = _truncateScopeName(chapter.title, 13);

    return Container(
      decoration: BoxDecoration(
        color: isChapterActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
            : isPopupOpen
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isChapterActive
              ? theme.colorScheme.primary.withValues(alpha: 0.7)
              : isPopupOpen
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chapter name button
          InkWell(
            onTap: () {
              _startChapterOverview(chapter);
            },
            borderRadius: BorderRadius.horizontal(
              left: const Radius.circular(16),
              right: Radius.circular(chapter.lessons.isNotEmpty ? 0 : 16),
            ),
            child: Tooltip(
              message: chapter.title,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 10,
                  right: chapter.lessons.isNotEmpty ? 4 : 10,
                  top: 5,
                  bottom: 5,
                ),
                child: Text(
                  truncatedTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ),

          // Toggle list icon button for chapter lessons
          if (chapter.lessons.isNotEmpty) ...[
            InkWell(
              onTap: () {
                setState(() {
                  if (_activeChapterPopup == chapter.title) {
                    _activeChapterPopup = null;
                  } else {
                    _activeChapterPopup = chapter.title;
                  }
                });
              },
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(16),
              ),
              child: Tooltip(
                message: isPopupOpen
                    ? 'Xir liiska casharrada'
                    : 'Muuji casharrada ${chapter.title}',
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 2,
                    right: 6,
                    top: 5,
                    bottom: 5,
                  ),
                  child: Icon(
                    isPopupOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: const Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Qayb yar oo ku aaddan korka button-ka chapter-ka (Mini popup positioned directly above the button)
  /// Waxay leedahay KALIYA magacyada oo lagu soo koobay 15 xaraf iyo icon-nada
  Widget _buildMiniScopePopup(PreparedBook book, ThemeData theme) {
    final chapterIdx = book.chapters.indexWhere(
      (c) => c.title == _activeChapterPopup,
    );
    final chapter = chapterIdx >= 0
        ? book.chapters[chapterIdx]
        : book.chapters.first;

    final screenWidth = MediaQuery.sizeOf(context).width;
    const popupWidth = 205.0;
    final maxLeft = (screenWidth - popupWidth - 12.0).clamp(
      12.0,
      double.infinity,
    );
    final calculatedLeft =
        12.0 + 115.0 + (chapterIdx >= 0 ? chapterIdx : 0) * 105.0;
    final leftOffset = calculatedLeft.clamp(12.0, maxLeft);

    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(left: leftOffset, bottom: 4, top: 2),
      child: Container(
        constraints: const BoxConstraints(maxWidth: popupWidth, maxHeight: 195),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mini Header
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 13,
                    color: Color(0xFF000000),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Tooltip(
                      message: chapter.title,
                      child: Text(
                        _truncateScopeName(chapter.title, 15),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF000000),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _activeChapterPopup = null),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Only list of lesson names (truncated to <= 15 chars with icon)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 155),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 3),
                itemCount: chapter.lessons.length,
                separatorBuilder: (context, _) =>
                    const Divider(height: 1, indent: 22, endIndent: 8),
                itemBuilder: (context, idx) {
                  final lesson = chapter.lessons[idx];
                  final isLessonExpanded = _expandedLessonsInPopup.contains(
                    lesson.title,
                  );
                  final isLessonSelected =
                      _focusChapter == chapter.title &&
                      _focusLesson == lesson.title &&
                      _focusSection == null;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 12,
                              color: Color(0xFF000000),
                            ),
                            const SizedBox(width: 5),
                            // Tap lesson name to select it (max 15 characters)
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  _startLessonSession(chapter, lesson);
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Tooltip(
                                  message: lesson.title,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                      horizontal: 2,
                                    ),
                                    child: Text(
                                      _truncateScopeName(lesson.title, 15),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isLessonSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: const Color(0xFF000000),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Toggle list icon for sections
                            if (lesson.sections.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isLessonExpanded) {
                                      _expandedLessonsInPopup.remove(
                                        lesson.title,
                                      );
                                    } else {
                                      _expandedLessonsInPopup.add(lesson.title);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    isLessonExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 15,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // If sections toggled open: list of section names (max 15 characters + icon)
                      if (isLessonExpanded)
                        for (final section in lesson.sections)
                          InkWell(
                            onTap: () {
                              _startSectionSession(chapter, lesson, section);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 22,
                                right: 8,
                                top: 3,
                                bottom: 3,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.subdirectory_arrow_right_rounded,
                                    size: 11,
                                    color: Color(0xFF000000),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Tooltip(
                                      message: section.title,
                                      child: Text(
                                        _truncateScopeName(section.title, 15),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              _focusSection == section.title
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: const Color(0xFF000000),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final focusScopeTitle = _focusSection ?? _focusLesson ?? _focusChapter;
    final hasFocusScope =
        focusScopeTitle != null && focusScopeTitle.trim().isNotEmpty;
    final shortScopeTitle = hasFocusScope
        ? (focusScopeTitle.trim().length > 10
              ? '${focusScopeTitle.trim().substring(0, 10)}...'
              : focusScopeTitle.trim())
        : '';

    const hint = 'Weydii Leyli AI su\'aal kasta...';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, hasFocusScope ? 10 : 4, 12, 10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  if (!_isCurrentSessionSending) {
                    _executeTutorAction(TutorMode.freeChat);
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _questionController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!_isCurrentSessionSending) {
                    _executeTutorAction(TutorMode.freeChat);
                  }
                },
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: PopupMenuButton<PreparedBook>(
                    tooltip: 'Buugaagta',
                    icon: const Icon(
                      Icons.auto_stories_rounded,
                      size: 20,
                      color: Color(0xFF000000),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    position: PopupMenuPosition.over,
                    offset: const Offset(0, -10),
                    onSelected: (book) {
                      _switchToBook(book);
                    },
                    itemBuilder: (context) {
                      final formBooks = _availableBooks
                          .where(
                            (b) => b.category == _selectedForm && b.isPublished,
                          )
                          .toList();
                      final effectiveBooks = formBooks.isNotEmpty
                          ? formBooks
                          : _availableBooks
                                .where((b) => b.category == _selectedForm)
                                .toList();

                      return [
                        PopupMenuItem<PreparedBook>(
                          enabled: false,
                          height: 36,
                          child: Text(
                            _selectedForm,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        if (effectiveBooks.isEmpty)
                          PopupMenuItem<PreparedBook>(
                            enabled: false,
                            height: 36,
                            child: Text(
                              'Buug lagama helin $_selectedForm',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          ...effectiveBooks.map(
                            (book) => PopupMenuItem<PreparedBook>(
                              value: book,
                              height: 38,
                              child: Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _currentBook?.id == book.id
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _currentBook?.id == book.id
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                      ];
                    },
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: IconButton(
                      onPressed: _isCurrentSessionSending
                          ? _stopCurrentGeneration
                          : () => _executeTutorAction(TutorMode.freeChat),
                      tooltip: _isCurrentSessionSending
                          ? 'Jooji fariinta'
                          : 'Dir fariinta',
                      style: IconButton.styleFrom(
                        backgroundColor: _isCurrentSessionSending
                            ? const Color(0xFFD32F2F)
                            : theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                      icon: _isCurrentSessionSending
                          ? const Icon(
                              Icons.stop_rounded,
                              color: Colors.white,
                              size: 20,
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                    ),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                    fontSize: 13.5,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (hasFocusScope)
              Positioned(
                top: -10,
                left: 20,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Diiradda: $focusScopeTitle'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_rounded,
                            size: 11,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            shortScopeTitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 3),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _resetFocus();
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(1),
                              child: Icon(
                                Icons.close_rounded,
                                size: 10,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeSelectedForm(String newForm) async {
    await _formStorage.setSelectedForm(newForm);
    if (mounted) {
      setState(() {
        _selectedForm = newForm;
      });
    }
  }

  Future<void> _showFormSelectionDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.window_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dooro Fasalka (Form)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Xulo fasalka aad dhigato hal mar',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: FormPreferenceStorage.availableForms.map((form) {
            final isSelected = form == _selectedForm;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                  ),
                ),
                title: Text(
                  form,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 14,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        color: Colors.grey,
                        size: 20,
                      ),
                onTap: () => Navigator.pop(ctx, form),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Xir'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (chosen != null && chosen != _selectedForm) {
      final messenger = ScaffoldMessenger.of(context);
      await _changeSelectedForm(chosen);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Fasalka waxbarashada waxaa loo beddelay $chosen'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showBookSelectionDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final currentCat = _currentBook?.category ?? _selectedForm;
    final relevantBooks = _availableBooks
        .where(
          (b) =>
              b.isPublished &&
              (b.category == currentCat || b.category == _selectedForm),
        )
        .toList();
    final allOtherBooks = _availableBooks
        .where((b) => b.isPublished && !relevantBooks.contains(b))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dooro Buug',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Xulo buugga aad rabto inaad barato',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...relevantBooks.map((b) {
                  final isSelected = b.id == _currentBook?.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.35,
                            )
                          : theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.book_rounded,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : const Color(0xFF000000),
                      ),
                      title: Text(
                        b.title,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 14,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : const Color(0xFF000000),
                        ),
                      ),
                      subtitle: Text(
                        '${b.category} • ${b.chapters.length} cutub',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: theme.colorScheme.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchToBook(b);
                      },
                    ),
                  );
                }),
                if (allOtherBooks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),
                  ...allOtherBooks.map((b) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.book_outlined,
                          color: Colors.black54,
                        ),
                        title: Text(
                          b.title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000000),
                          ),
                        ),
                        subtitle: Text(
                          '${b.category} • ${b.chapters.length} cutub',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _switchToBook(b);
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchToBook(PreparedBook book) async {
    if (_currentBook?.id == book.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Buugga "${book.title}" mar hore ayaa la doortay.'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_isCurrentSessionSending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sug jawaabta hadda socota ka hor intaadan buugga beddelin.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _saveCurrentSessionToHistory();
    if (!mounted) return;

    setState(() {
      _loading = true;
      _resetFocus();
      _learningSession = LearningSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: book.id,
        bookTitle: book.title,
        scopeType: LearningScopeType.book,
        scopeLabel: book.title,
        startedAt: DateTime.now(),
      );
      _activeChapterPopup = null;
      _messages.clear();
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    });
    _loadKnowledgeForBook(book);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buugga "${book.title}" waa la furay.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDrawerLibrarySection(ThemeData theme) {
    final formBooks = _availableBooks
        .where((b) => b.category == _selectedForm && b.isPublished)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header / Toggle button (No border, no background)
        InkWell(
          onTap: () {
            setState(() {
              _isLibraryExpandedInDrawer = !_isLibraryExpandedInDrawer;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // 1. Icon-ka book
                const Icon(
                  Icons.auto_stories_rounded,
                  size: 20,
                  color: Color(0xFF000000),
                ),
                const SizedBox(width: 12),

                // 2. Magaca: Library
                const Expanded(
                  child: Text(
                    'Library',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),

                // 3. Button-ka sheegayo Form-ka (opens Form Selection window)
                InkWell(
                  onTap: () => _showFormSelectionDialog(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedForm,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 4. Icon-ka toggle list-ga
                Icon(
                  _isLibraryExpandedInDrawer
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF000000),
                ),
              ],
            ),
          ),
        ),

        // When opened: ONLY list books in that form (No border, no background, no bottom button)
        if (_isLibraryExpandedInDrawer) ...[
          if (formBooks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Buugaag lagama helin $_selectedForm.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
              itemCount: formBooks.length,
              itemBuilder: (context, idx) {
                final book = formBooks[idx];
                final isCurrent = _currentBook?.id == book.id;

                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: Icon(
                    Icons.book_outlined,
                    size: 16,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : const Color(0xFF000000),
                  ),
                  title: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : const Color(0xFF000000),
                    ),
                  ),
                  trailing: isCurrent
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Dooran',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _switchToBook(book);
                  },
                );
              },
            ),
        ],
      ],
    );
  }
}

class _ChatEntry {
  const _ChatEntry({
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

  _ChatEntry copyWithVisuals(List<ChatVisualModel> nextVisuals) => _ChatEntry(
    text: text,
    isUser: isUser,
    scopeLabel: scopeLabel,
    pagesLabel: pagesLabel,
    hasPdf: hasPdf,
    canContinue: canContinue,
    partIndex: partIndex,
    isLessonComplete: isLessonComplete,
    visuals: nextVisuals,
  );
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.25;
            final val = (_controller.value - delay) % 1.0;
            final opacity = (val < 0.5 ? val * 2 : (1.0 - val) * 2).clamp(
              0.2,
              1.0,
            );
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.5,
              height: 3.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0022FF).withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

class _HorizontalBooksTicker extends StatefulWidget {
  const _HorizontalBooksTicker({
    required this.books,
    required this.onBookSelected,
  });

  final List<PreparedBook> books;
  final void Function(PreparedBook book) onBookSelected;

  @override
  State<_HorizontalBooksTicker> createState() => _HorizontalBooksTickerState();
}

class _HorizontalBooksTickerState extends State<_HorizontalBooksTicker> {
  final ScrollController _scrollController = ScrollController();
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoScroll();
    });
  }

  void _startAutoScroll() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= maxExtent) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(current + 1.1);
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.books.isEmpty) return const SizedBox.shrink();

    // Multiply the list to ensure smooth continuous scrolling from right to left
    final displayList = [
      ...widget.books,
      ...widget.books,
      ...widget.books,
      ...widget.books,
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: displayList.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final book = displayList[index];
          return InkWell(
            onTap: () => widget.onBookSelected(book),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    size: 14,
                    color: Color(0xFF000000),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Chapters ticker for the book welcome screen (mirrors _HorizontalBooksTicker)
class _HorizontalChaptersTicker extends StatefulWidget {
  const _HorizontalChaptersTicker({
    required this.chapters,
    required this.onChapterSelected,
  });

  final List<PreparedChapter> chapters;
  final void Function(PreparedChapter chapter) onChapterSelected;

  @override
  State<_HorizontalChaptersTicker> createState() =>
      _HorizontalChaptersTickerState();
}

class _HorizontalChaptersTickerState extends State<_HorizontalChaptersTicker> {
  final ScrollController _scrollController = ScrollController();
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoScroll();
    });
  }

  void _startAutoScroll() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= maxExtent) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(current + 1.1);
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapters.isEmpty) return const SizedBox.shrink();

    // Duplicate list for seamless looping
    final displayList = [
      ...widget.chapters,
      ...widget.chapters,
      ...widget.chapters,
      ...widget.chapters,
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: displayList.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chapter = displayList[index];
          return InkWell(
            onTap: () => widget.onChapterSelected(chapter),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bookmark_rounded,
                    size: 13,
                    color: Color(0xFF000000),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    chapter.title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
