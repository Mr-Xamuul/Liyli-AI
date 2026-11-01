import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/prepared_book.dart';
import 'book_chat_screen.dart';
import '../services/prepared_book_storage.dart';

/// Admin-only editor. It stores one original PDF and non-destructive page markers.
class PreparedBookEditorScreen extends StatefulWidget {
  const PreparedBookEditorScreen({
    super.key,
    this.storage,
    this.initialBook,
    this.initialTabIndex = 0,
    this.returnToPreview = false,
    this.initialChapterIndex,
    this.initialLessonIndex,
    this.initialSectionIndex,
    this.onOpenChat,
    this.onOpenLibrary,
    this.onBackToChat,
    this.onBackToAdmin,
    this.onGoToPreview,
  });

  final PreparedBookStorage? storage;
  final PreparedBook? initialBook;
  final int initialTabIndex;
  final bool returnToPreview;
  final int? initialChapterIndex;
  final int? initialLessonIndex;
  final int? initialSectionIndex;
  final void Function(
    PreparedBook book, {
    String? chapter,
    String? lesson,
    String? section,
  })?
  onOpenChat;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onBackToChat;
  final VoidCallback? onBackToAdmin;
  final void Function(PreparedBook book)? onGoToPreview;

  @override
  State<PreparedBookEditorScreen> createState() =>
      _PreparedBookEditorScreenState();
}

class _PreparedBookEditorScreenState extends State<PreparedBookEditorScreen> {
  final _storage = const PreparedBookStorage();
  final _pdfController = PdfViewerController();
  PreparedBook? _book;
  Uint8List? _pdfBytes;
  List<PreparedBook> _savedBooks = const [];
  _PreviewRange? _previewRange;
  List<_PreviewMarkerRange> _previewMarkers = const [];
  int? _selectedChapterIndex;
  int? _selectedLessonIndex;
  String? _markerKind;
  int? _markerChapterIndex;
  int? _markerLessonIndex;
  int? _markerSectionIndex;
  bool _markerEditing = false;
  String? _markerInitialTitle;
  int _markerStartPage = 1;
  int _markerEndPage = 1;
  double _markerStartPosition = .25;
  double _markerEndPosition = .75;
  String _activeMarker = 'start';
  final Map<int, double> _pdfPageHeights = {};
  final Map<int, double> _pdfPageWidths = {};
  String? _message;
  Timer? _autoSaveTimer;
  bool _showThumbnails = true;

  PreparedBookStorage get _bookStorage => widget.storage ?? _storage;

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _pdfController.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 700), () {
      _autoSaveWorkingBook();
    });
  }

  Future<void> _autoSaveWorkingBook() async {
    final book = _book;
    final bytes = _pdfBytes;
    if (book == null || bytes == null || bytes.isEmpty) return;
    try {
      final path = await _bookStorage.savePdf(book.id, bytes);
      final saved = book.copyWith(
        originalPdfPath: path,
        status: PreparedBookStatus.draft,
        updatedAt: DateTime.now(),
      );
      await _bookStorage.save(saved);
      if (!mounted || _book?.id != book.id) return;
      setState(() {
        _book = saved;
        _savedBooks = [
          saved,
          ..._savedBooks.where((item) => item.id != saved.id),
        ];
      });
    } catch (_) {
      // The explicit Save Draft action remains available if local auto-save fails.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedBooks().then((_) {
      if (widget.initialBook != null) {
        _openSavedBook(widget.initialBook!);
      }
    });
  }

  Future<void> _loadSavedBooks() async {
    final books = await _bookStorage.loadAll();
    if (mounted) setState(() => _savedBooks = books);
  }

  Future<void> _openSavedBook(PreparedBook book) async {
    final bytes = await _bookStorage.loadPdf(book);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _message = 'PDF-ga buuggan lama helin local storage.');
      }
      return;
    }
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final count = doc.pages.count;
      _pdfPageHeights
        ..clear()
        ..addEntries(
          List.generate(
            count,
            (i) => MapEntry(i + 1, doc.pages[i].size.height),
          ),
        );
      _pdfPageWidths
        ..clear()
        ..addEntries(
          List.generate(
            count,
            (i) => MapEntry(i + 1, doc.pages[i].size.width),
          ),
        );
      doc.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _book = book;
      _pdfBytes = bytes;
      _message =
          'Book-ga waa la furay. Wax ka beddel ama sii wad diyaarintiisa.';
    });
  }

  Future<void> _saveDraft() async {
    final book = _book;
    final bytes = _pdfBytes;
    if (book == null || bytes == null) return;

    try {
      final path = await _bookStorage.savePdf(book.id, bytes);
      final saved = book.copyWith(
        originalPdfPath: path,
        status: PreparedBookStatus.draft,
        updatedAt: DateTime.now(),
      );
      await _bookStorage.save(saved);
      if (!mounted) return;
      setState(() {
        _book = saved;
        _savedBooks = [
          saved,
          ..._savedBooks.where((item) => item.id != saved.id),
        ];
        _message = 'Draft-ka waa la kaydiyay.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buugga waa la kaydiyay (Draft).')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Kaydintu way fashilantay: $error');
      }
    }
  }

  Future<void> _publishToLibrary() async {
    final book = _book;
    final bytes = _pdfBytes;
    if (book == null || bytes == null) return;

    final errors = book.validate();
    if (errors.isNotEmpty) {
      await _showErrors(errors);
      return;
    }

    String chosenShelf = book.category;
    final confirmedShelf = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.publish_rounded, color: Color(0xFF000000)),
              SizedBox(width: 8),
              Text('U Gudbi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dooro qaanadda aad rabto in buugga "${book.title}" lagu daro:',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PreparedBook.categories.map((shelf) {
                  final isSelected = chosenShelf == shelf;
                  return ChoiceChip(
                    selected: isSelected,
                    label: Text(
                      shelf,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    avatar: isSelected
                        ? const Icon(Icons.check, size: 16)
                        : null,
                    onSelected: (_) => setModalState(() => chosenShelf = shelf),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ka noqo'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, chosenShelf),
              icon: const Icon(Icons.check),
              label: const Text('Gudbi Hadda'),
            ),
          ],
        ),
      ),
    );

    if (confirmedShelf == null) return;

    try {
      final path = await _bookStorage.savePdf(book.id, bytes);
      final saved = book.copyWith(
        originalPdfPath: path,
        category: confirmedShelf,
        status: PreparedBookStatus.published,
        updatedAt: DateTime.now(),
      );
      await _bookStorage.save(saved);
      if (!mounted) return;
      setState(() {
        _book = saved;
        _savedBooks = [
          saved,
          ..._savedBooks.where((item) => item.id != saved.id),
        ];
        _message = 'Buugga waxaa loo gudbiyey Maktabadda ($confirmedShelf)!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Buugga "${book.title}" waxaa lagu daray qaanadda $confirmedShelf!',
          ),
          action: SnackBarAction(
            label: 'Baro (AI Chat)',
            onPressed: () {
              if (widget.onOpenChat != null) {
                widget.onOpenChat!(saved);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookChatScreen(book: saved),
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'Gudbinta Maktabaddu way fashilantay: $error',
        );
      }
    }
  }

  Future<void> _sendToPreview() async {
    final book = _book;
    final bytes = _pdfBytes;
    if (book == null || bytes == null || bytes.isEmpty) return;

    if (book.chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fadlan marka hore ku dar ugu yaraan hal cutub ka hor inta aan Preview loo gudbin.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    try {
      final path = await _bookStorage.savePdf(book.id, bytes);
      final saved = book.copyWith(
        originalPdfPath: path,
        status: PreparedBookStatus.review,
        updatedAt: DateTime.now(),
      );
      await _bookStorage.save(saved);
      if (!mounted) return;
      setState(() => _book = saved);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Buugga "${book.title}" waxaa loo gudbiyey Qaybta Preview (Hubinta)!'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );

      if (widget.onGoToPreview != null) {
        widget.onGoToPreview!(saved);
      } else if (widget.onBackToAdmin != null) {
        widget.onBackToAdmin!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Khalad ayaa dhacay: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _doneAndReturnToPreview() async {
    final book = _book;
    final bytes = _pdfBytes;
    PreparedBook? finalSaved = book;
    if (book != null && bytes != null && bytes.isNotEmpty) {
      final path = await _bookStorage.savePdf(book.id, bytes);
      final saved = book.copyWith(
        originalPdfPath: path,
        status: PreparedBookStatus.review,
        updatedAt: DateTime.now(),
      );
      await _bookStorage.save(saved);
      finalSaved = saved;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wax ka beddelka waa la keydiyey! Dib ugu soo noqoshada Hubinta (Preview)...'),
        backgroundColor: Color(0xFF16A34A),
      ),
    );
    if (widget.onGoToPreview != null && finalSaved != null) {
      widget.onGoToPreview!(finalSaved);
    } else if (widget.onBackToAdmin != null) {
      widget.onBackToAdmin!();
    }
  }

  Future<void> _showErrors(List<String> errors) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Book-ga wuxuu u baahan yahay sixid'),
        content: SingleChildScrollView(child: Text(errors.join('\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Xir'),
          ),
        ],
      ),
    );
  }

  Future<void> _addChapter({String? initialTitle}) async {
    final book = _book;
    if (book == null || book.pageCount == 0) return;
    final value = await _rangeDialog(
      'Chapter cusub',
      book.pageCount,
      initialTitle: initialTitle ?? '',
    );
    if (value == null) return;
    final chapter = PreparedChapter(
      id: _id('chapter'),
      title: value.title,
      startPage: value.startPage,
      endPage: value.endPage,
    );
    setState(
      () => _book = book.copyWith(chapters: [...book.chapters, chapter]),
    );
    _scheduleAutoSave();
  }

  Future<void> _editChapter(int index) async {
    final book = _book!;
    final current = book.chapters[index];
    final value = await _rangeDialog(
      'Wax ka beddel Chapter',
      book.pageCount,
      initialTitle: current.title,
      initialStart: current.startPage,
      initialEnd: current.endPage,
      actionLabel: 'Cusboonaysii',
    );
    if (value == null) return;
    final chapters = [...book.chapters];
    chapters[index] = PreparedChapter(
      id: current.id,
      title: value.title,
      startPage: value.startPage,
      endPage: value.endPage,
      lessons: current.lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _deleteChapter(int index) {
    final book = _book!;
    final chapters = [...book.chapters]..removeAt(index);
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _deleteLesson(int chapterIndex, int lessonIndex) {
    final book = _book!;
    final chapter = book.chapters[chapterIndex];
    final lessons = [...chapter.lessons]..removeAt(lessonIndex);
    final chapters = [...book.chapters];
    chapters[chapterIndex] = PreparedChapter(
      id: chapter.id,
      title: chapter.title,
      startPage: chapter.startPage,
      endPage: chapter.endPage,
      lessons: lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _deleteSection(int chapterIndex, int lessonIndex, int sectionIndex) {
    final book = _book!;
    final chapter = book.chapters[chapterIndex];
    final lesson = chapter.lessons[lessonIndex];
    final sections = [...lesson.sections]..removeAt(sectionIndex);
    final lessons = [...chapter.lessons];
    lessons[lessonIndex] = PreparedLesson(
      id: lesson.id,
      title: lesson.title,
      startPage: lesson.startPage,
      endPage: lesson.endPage,
      sections: sections,
    );
    final chapters = [...book.chapters];
    chapters[chapterIndex] = PreparedChapter(
      id: chapter.id,
      title: chapter.title,
      startPage: chapter.startPage,
      endPage: chapter.endPage,
      lessons: lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  Future<_RangeValue?> _rangeDialog(
    String label,
    int maximum, {
    int minimum = 1,
    String initialTitle = '',
    int? initialStart,
    int? initialEnd,
    String actionLabel = 'Ku dar',
  }) async {
    final defaultTitle = initialTitle;
    final title = TextEditingController(text: defaultTitle);
    final start = TextEditingController(
      text: '${initialStart ?? _currentPage}',
    );
    final end = TextEditingController(text: '${initialEnd ?? _currentPage}');
    return showDialog<_RangeValue>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Magaca'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: start,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bogga bilowga',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: end,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bogga dhammaadka',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Bogagga: $minimum ilaa $maximum',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ka noqo'),
          ),
          FilledButton(
            onPressed: () {
              final first = int.tryParse(start.text);
              final last = int.tryParse(end.text);
              if (title.text.trim().isEmpty ||
                  first == null ||
                  last == null ||
                  first < minimum ||
                  last > maximum ||
                  first > last) {
                return;
              }
              Navigator.pop(
                context,
                _RangeValue(title.text.trim(), first, last),
              );
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  int get _currentPage =>
      _pdfController.pageNumber == 0 ? 1 : _pdfController.pageNumber;
  static String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  void _selectPreview(
    String title,
    int startPage,
    int endPage, {
    double? startPosition,
    double? endPosition,
  }) {
    setState(() {
      _previewRange = _PreviewRange(title, startPage, endPage);
      _previewMarkers = [
        _PreviewMarkerRange(
          title: title,
          startPage: startPage,
          endPage: endPage,
          startPosition: startPosition ?? .02,
          endPosition: endPosition ?? .98,
          color: const Color(0xFF0022FF),
        ),
      ];
      _message = 'Preview: $title (bogagga $startPage–$endPage)';
    });
    _pdfController.jumpToPage(startPage);
  }

  void _selectChapterPreview(PreparedChapter chapter) {
    final markers = <_PreviewMarkerRange>[
      _PreviewMarkerRange(
        title: chapter.title,
        startPage: chapter.startPage,
        endPage: chapter.endPage,
        startPosition: .02,
        endPosition: .98,
        color: const Color(0xFF0022FF),
      ),
      for (final lesson in chapter.lessons) _lessonPreviewMarker(lesson),
      for (final lesson in chapter.lessons)
        for (final section in lesson.sections) _sectionPreviewMarker(section),
    ];
    _selectPreviewGroup(
      chapter.title,
      chapter.startPage,
      chapter.endPage,
      markers,
    );
  }

  void _selectLessonPreview(PreparedLesson lesson) {
    _selectPreviewGroup(lesson.title, lesson.startPage, lesson.endPage, [
      _lessonPreviewMarker(lesson),
      for (final section in lesson.sections) _sectionPreviewMarker(section),
    ]);
  }

  _PreviewMarkerRange _lessonPreviewMarker(PreparedLesson lesson) =>
      _PreviewMarkerRange(
        title: lesson.title,
        startPage: lesson.startPage,
        endPage: lesson.endPage,
        startPosition: lesson.startPosition,
        endPosition: lesson.endPosition,
        color: const Color(0xFF000000),
      );

  _PreviewMarkerRange _sectionPreviewMarker(PreparedSection section) =>
      _PreviewMarkerRange(
        title: section.title,
        startPage: section.startPage,
        endPage: section.endPage,
        startPosition: section.startPosition,
        endPosition: section.endPosition,
        color: const Color(0xFFBDBDBD),
      );

  void _selectPreviewGroup(
    String title,
    int startPage,
    int endPage,
    List<_PreviewMarkerRange> markers,
  ) {
    setState(() {
      _previewRange = _PreviewRange(title, startPage, endPage);
      _previewMarkers = markers;
      _message = 'Preview: $title (bogagga $startPage–$endPage)';
    });
    _pdfController.jumpToPage(startPage);
  }

  void _beginMarker({
    required String kind,
    required int chapterIndex,
    int? lessonIndex,
  }) {
    setState(() {
      _previewRange = null;
      _previewMarkers = const [];
      _markerKind = kind;
      _markerChapterIndex = chapterIndex;
      _markerLessonIndex = lessonIndex;
      _markerSectionIndex = null;
      _markerEditing = false;
      _markerInitialTitle = null;
      _markerStartPage = _currentPage;
      _markerEndPage = _currentPage;
      _markerStartPosition = .25;
      _markerEndPosition = .75;
      _message =
          'Jiido labada line si aad u calaamadeyso bilowga iyo dhammaadka.';
    });
  }

  void _beginEditMarker({
    required String kind,
    required int chapterIndex,
    required int lessonIndex,
    int? sectionIndex,
  }) {
    final book = _book!;
    final chapter = book.chapters[chapterIndex];
    final lesson = chapter.lessons[lessonIndex];
    final isSection = kind == 'Section';
    final section = isSection ? lesson.sections[sectionIndex!] : null;
    final title = isSection ? section!.title : lesson.title;
    final startPage = isSection ? section!.startPage : lesson.startPage;
    final endPage = isSection ? section!.endPage : lesson.endPage;
    final startPosition = isSection
        ? section!.startPosition
        : lesson.startPosition;
    final endPosition = isSection ? section!.endPosition : lesson.endPosition;

    setState(() {
      _previewRange = null;
      _previewMarkers = const [];
      _markerKind = kind;
      _markerChapterIndex = chapterIndex;
      _markerLessonIndex = lessonIndex;
      _markerSectionIndex = sectionIndex;
      _markerEditing = true;
      _markerInitialTitle = title;
      _markerStartPage = startPage;
      _markerEndPage = endPage;
      _markerStartPosition = startPosition;
      _markerEndPosition = endPosition;
      _activeMarker = 'start';
      _message = 'Jiido labada line si aad u saxdo $kind-ka.';
    });
    _pdfController.jumpToPage(startPage);
  }

  Future<void> _finishMarker() async {
    final kind = _markerKind;
    final chapterIndex = _markerChapterIndex;
    if (kind == null || chapterIndex == null) return;
    final title = TextEditingController(text: _markerInitialTitle ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Magaca $kind'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Magaca qaybta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ka noqo'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isNotEmpty) {
                Navigator.pop(context, title.text.trim());
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final book = _book!;
    final chapter = book.chapters[chapterIndex];
    final chapters = [...book.chapters];

    int sPage = _markerStartPage;
    int ePage = _markerEndPage;
    double sPos = _markerStartPosition;
    double ePos = _markerEndPosition;

    if (sPage > ePage) {
      final tmpP = sPage;
      sPage = ePage;
      ePage = tmpP;
      final tmpPos = sPos;
      sPos = ePos;
      ePos = tmpPos;
    } else if (sPage == ePage && sPos > ePos) {
      final tmpPos = sPos;
      sPos = ePos;
      ePos = tmpPos;
    }

    if (kind == 'Lesson') {
      final existing = _markerEditing
          ? chapter.lessons[_markerLessonIndex!]
          : null;
      final lesson = PreparedLesson(
        id: existing?.id ?? _id('lesson'),
        title: name,
        startPage: sPage,
        endPage: ePage,
        startPosition: sPos,
        endPosition: ePos,
        sections: existing?.sections ?? const [],
      );
      final lessons = [...chapter.lessons];
      if (_markerEditing) {
        lessons[_markerLessonIndex!] = lesson;
      } else {
        lessons.add(lesson);
      }
      chapters[chapterIndex] = PreparedChapter(
        id: chapter.id,
        title: chapter.title,
        startPage: chapter.startPage,
        endPage: chapter.endPage,
        lessons: lessons,
      );
    } else {
      final lessonIndex = _markerLessonIndex;
      if (lessonIndex == null) return;
      final lesson = chapter.lessons[lessonIndex];
      final sectionIndex = _markerSectionIndex;
      final existing = _markerEditing && sectionIndex != null
          ? lesson.sections[sectionIndex]
          : null;
      final section = PreparedSection(
        id: existing?.id ?? _id('section'),
        title: name,
        startPage: sPage,
        endPage: ePage,
        startPosition: sPos,
        endPosition: ePos,
      );
      final lessons = [...chapter.lessons];
      lessons[lessonIndex] = PreparedLesson(
        id: lesson.id,
        title: lesson.title,
        startPage: lesson.startPage,
        endPage: lesson.endPage,
        startPosition: lesson.startPosition,
        endPosition: lesson.endPosition,
        sections: [
          for (var index = 0; index < lesson.sections.length; index++)
            if (_markerEditing && index == sectionIndex)
              section
            else
              lesson.sections[index],
          if (!_markerEditing) section,
        ],
      );
      chapters[chapterIndex] = PreparedChapter(
        id: chapter.id,
        title: chapter.title,
        startPage: chapter.startPage,
        endPage: chapter.endPage,
        lessons: lessons,
      );
    }
    setState(() {
      _book = book.copyWith(chapters: chapters);
      _markerKind = null;
      _markerSectionIndex = null;
      _markerEditing = false;
      _markerInitialTitle = null;
      _message = '$kind waa la sameeyay.';
    });
    _scheduleAutoSave();
  }

  void _cancelMarker() => setState(() => _markerKind = null);

  void _leaveBook() {
    if (widget.onBackToAdmin != null) {
      widget.onBackToAdmin!();
      return;
    }
    if (widget.onBackToChat != null) {
      widget.onBackToChat!();
      return;
    }
    Navigator.maybePop(context);
  }

  Widget _markerOverlay() => LayoutBuilder(
    builder: (context, constraints) {
      final pageHeight = _pdfPageHeights[_currentPage] ?? 792.0;
      final pageWidth = _pdfPageWidths[_currentPage] ?? 612.0;
      final double scale = math.min(
        constraints.maxWidth / pageWidth,
        constraints.maxHeight / pageHeight,
      );
      final double renderedWidth = pageWidth * scale;
      final double renderedHeight = pageHeight * scale;
      final double pageLeft = (constraints.maxWidth - renderedWidth) / 2;
      final double pageTop = (constraints.maxHeight - renderedHeight) / 2;

      return IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            if (_currentPage == _markerStartPage)
              _draggableMarkerLine(
                isStart: true,
                pageLeft: pageLeft,
                pageTop: pageTop,
                pageWidth: renderedWidth,
                pageHeight: renderedHeight,
              ),
            if (_currentPage == _markerEndPage)
              _draggableMarkerLine(
                isStart: false,
                pageLeft: pageLeft,
                pageTop: pageTop,
                pageWidth: renderedWidth,
                pageHeight: renderedHeight,
              ),
          ],
        ),
      );
    },
  );

  Widget _previewOverlay() {
    final range = _previewRange;
    if (range == null || _previewMarkers.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final page = _currentPage;
        if (page < range.startPage || page > range.endPage) {
          return const SizedBox.shrink();
        }

        final pageHeight = _pdfPageHeights[page] ?? 792.0;
        final pageWidth = _pdfPageWidths[page] ?? 612.0;
        final double scale = math.min(
          constraints.maxWidth / pageWidth,
          constraints.maxHeight / pageHeight,
        );
        final double renderedWidth = pageWidth * scale;
        final double renderedHeight = pageHeight * scale;
        final double pageLeft = (constraints.maxWidth - renderedWidth) / 2;
        final double pageTop = (constraints.maxHeight - renderedHeight) / 2;

        return IgnorePointer(
          child: Stack(
            children: [
              for (final marker in _previewMarkers)
                if (page >= marker.startPage && page <= marker.endPage)
                  _previewMarkerRangeOverlay(
                    marker,
                    pageLeft,
                    pageTop,
                    renderedWidth,
                    renderedHeight,
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _previewMarkerRangeOverlay(
    _PreviewMarkerRange marker,
    double pageLeft,
    double pageTop,
    double pageWidth,
    double pageHeight,
  ) {
    final page = _currentPage;
    final isStartPage = page == marker.startPage;
    final isEndPage = page == marker.endPage;
    final top = isStartPage ? pageTop + pageHeight * marker.startPosition : pageTop;
    final bottom = isEndPage ? pageTop + pageHeight * marker.endPosition : pageTop + pageHeight;
    final shadeHeight = bottom > top ? bottom - top : 0.0;
    return Stack(
      children: [
        if (shadeHeight > 0)
          Positioned(
            left: pageLeft,
            width: pageWidth,
            top: top,
            height: shadeHeight,
            child: ColoredBox(color: marker.color.withValues(alpha: .08)),
          ),
        if (isStartPage)
          _previewMarkerLine(
            label: '${marker.title} • BILOW',
            position: marker.startPosition,
            color: marker.color,
            pageLeft: pageLeft,
            pageTop: pageTop,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
          ),
        if (isEndPage)
          _previewMarkerLine(
            label: '${marker.title} • DHAMMAAD',
            position: marker.endPosition,
            color: marker.color,
            pageLeft: pageLeft,
            pageTop: pageTop,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
          ),
      ],
    );
  }

  Widget _previewMarkerLine({
    required String label,
    required double position,
    required Color color,
    required double pageLeft,
    required double pageTop,
    required double pageWidth,
    required double pageHeight,
  }) {
    final lineY = pageTop + (pageHeight * position).clamp(0.0, pageHeight);
    return Positioned(
      top: lineY - 14,
      left: pageLeft,
      width: pageWidth,
      height: 28,
      child: Align(
        alignment: Alignment.center,
        child: Container(
          height: 2.5,
          color: color,
          child: Align(
            alignment: Alignment.topLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _draggableMarkerLine({
    required bool isStart,
    required double pageLeft,
    required double pageTop,
    required double pageWidth,
    required double pageHeight,
  }) {
    final position = isStart ? _markerStartPosition : _markerEndPosition;
    final isActive = isStart ? (_activeMarker == 'start') : (_activeMarker == 'end');
    final color = isStart ? const Color(0xFF0022FF) : const Color(0xFFD97706);
    final label = isStart ? 'BILOW' : 'DHAMMAAD';
    final lineY = pageTop + (pageHeight * position).clamp(0.0, pageHeight);

    return Positioned(
      top: lineY - 18,
      left: pageLeft,
      width: pageWidth,
      height: 38,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _activeMarker = isStart ? 'start' : 'end';
            _message = isStart
                ? 'Line-ka Bilowga (Kore) ayaa la doortay. Taabo bogga ama jiid si aad u beddesho.'
                : 'Line-ka Dhammaadka (Hoose) ayaa la doortay. Taabo bogga ama jiid si aad u beddesho.';
          });
        },
        onVerticalDragStart: (_) {
          setState(() {
            _activeMarker = isStart ? 'start' : 'end';
          });
        },
        onVerticalDragUpdate: (details) {
          final current = isStart ? _markerStartPosition : _markerEndPosition;
          final next = (current + details.delta.dy / pageHeight).clamp(0.01, 0.99);
          setState(() {
            if (isStart) {
              _markerStartPosition = next;
            } else {
              _markerEndPosition = next;
            }
          });
          _scheduleAutoSave();
        },
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Visible Horizontal Dividing Line
              Container(
                height: isActive ? 3.5 : 2.0,
                decoration: BoxDecoration(
                  color: color,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              // Draggable / Interactive Badge Handle
              Positioned(
                left: isStart ? 12 : null,
                right: isStart ? null : 12,
                top: 3,
                child: Material(
                  elevation: isActive ? 6 : 2,
                  borderRadius: BorderRadius.circular(6),
                  color: color,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        _activeMarker = isStart ? 'start' : 'end';
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isStart
                                ? Icons.vertical_align_top_rounded
                                : Icons.vertical_align_bottom_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$label ${(position * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.check_circle, size: 11, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePageChanged(PdfPageChangedDetails details) {
    final range = _previewRange;
    if (range != null && details.newPageNumber < range.startPage) {
      _pdfController.jumpToPage(range.startPage);
    } else if (range != null && details.newPageNumber > range.endPage) {
      _pdfController.jumpToPage(range.endPage);
    }
    if ((_markerKind != null || _previewRange != null) && mounted) {
      setState(() {});
    }
  }

  void _handlePdfTap(PdfGestureDetails details) {
    if (_markerKind == null || details.pageNumber < 1) return;
    final pageHeight = _pdfPageHeights[details.pageNumber] ?? 792;
    final ratio = (details.pagePosition.dy / pageHeight).clamp(.02, .98);
    setState(() {
      if (_activeMarker == 'start') {
        _markerStartPage = details.pageNumber;
        _markerStartPosition = ratio;
        // Automatically switch active marker to 'end' so the next tap sets the bottom line!
        _activeMarker = 'end';
        _message =
            'Bilowga (Kore) waxaa lagu dhigay bogga ${details.pageNumber} (${(ratio * 100).toInt()}%). Hadda taabo meesha uu ku dhammaado line-ka hoose.';
      } else {
        _markerEndPage = details.pageNumber;
        _markerEndPosition = ratio;
        _message =
            'Dhammaadka (Hoose) waxaa lagu dhigay bogga ${details.pageNumber} (${(ratio * 100).toInt()}%).';
      }
    });
    _scheduleAutoSave();
  }

  void _moveChapter(int from, int to) {
    final book = _book;
    if (book == null || from == to || from < 0 || to < 0 || from >= book.chapters.length || to >= book.chapters.length) return;
    final chapters = List<PreparedChapter>.from(book.chapters);
    final item = chapters.removeAt(from);
    chapters.insert(to, item);
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _moveLesson(int chIdx, int from, int to) {
    final book = _book;
    if (book == null) return;
    final ch = book.chapters[chIdx];
    if (from == to || from < 0 || to < 0 || from >= ch.lessons.length || to >= ch.lessons.length) return;
    final lessons = List<PreparedLesson>.from(ch.lessons);
    final item = lessons.removeAt(from);
    lessons.insert(to, item);
    final chapters = List<PreparedChapter>.from(book.chapters);
    chapters[chIdx] = PreparedChapter(
      id: ch.id,
      title: ch.title,
      startPage: ch.startPage,
      endPage: ch.endPage,
      lessons: lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _moveSection(int chIdx, int lsIdx, int from, int to) {
    final book = _book;
    if (book == null) return;
    final ch = book.chapters[chIdx];
    final ls = ch.lessons[lsIdx];
    if (from == to || from < 0 || to < 0 || from >= ls.sections.length || to >= ls.sections.length) return;
    final sections = List<PreparedSection>.from(ls.sections);
    final item = sections.removeAt(from);
    sections.insert(to, item);
    final lessons = List<PreparedLesson>.from(ch.lessons);
    lessons[lsIdx] = PreparedLesson(
      id: ls.id,
      title: ls.title,
      startPage: ls.startPage,
      endPage: ls.endPage,
      startPosition: ls.startPosition,
      endPosition: ls.endPosition,
      sections: sections,
    );
    final chapters = List<PreparedChapter>.from(book.chapters);
    chapters[chIdx] = PreparedChapter(
      id: ch.id,
      title: ch.title,
      startPage: ch.startPage,
      endPage: ch.endPage,
      lessons: lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _relocateLesson(int fromChIdx, int lsIdx, int toChIdx) {
    if (fromChIdx == toChIdx) return;
    final book = _book;
    if (book == null) return;
    final chapters = List<PreparedChapter>.from(book.chapters);
    final fromCh = chapters[fromChIdx];
    final toCh = chapters[toChIdx];
    final fromLessons = List<PreparedLesson>.from(fromCh.lessons);
    final moving = fromLessons.removeAt(lsIdx);
    final toLessons = List<PreparedLesson>.from(toCh.lessons)..add(moving);
    chapters[fromChIdx] = PreparedChapter(
      id: fromCh.id,
      title: fromCh.title,
      startPage: fromCh.startPage,
      endPage: fromCh.endPage,
      lessons: fromLessons,
    );
    chapters[toChIdx] = PreparedChapter(
      id: toCh.id,
      title: toCh.title,
      startPage: toCh.startPage,
      endPage: toCh.endPage,
      lessons: toLessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  void _relocateSection(int chIdx, int fromLsIdx, int secIdx, int toLsIdx) {
    if (fromLsIdx == toLsIdx) return;
    final book = _book;
    if (book == null) return;
    final chapters = List<PreparedChapter>.from(book.chapters);
    final ch = chapters[chIdx];
    final lessons = List<PreparedLesson>.from(ch.lessons);
    final fromLs = lessons[fromLsIdx];
    final toLs = lessons[toLsIdx];
    final fromSecs = List<PreparedSection>.from(fromLs.sections);
    final moving = fromSecs.removeAt(secIdx);
    final toSecs = List<PreparedSection>.from(toLs.sections)..add(moving);
    lessons[fromLsIdx] = PreparedLesson(
      id: fromLs.id,
      title: fromLs.title,
      startPage: fromLs.startPage,
      endPage: fromLs.endPage,
      startPosition: fromLs.startPosition,
      endPosition: fromLs.endPosition,
      sections: fromSecs,
    );
    lessons[toLsIdx] = PreparedLesson(
      id: toLs.id,
      title: toLs.title,
      startPage: toLs.startPage,
      endPage: toLs.endPage,
      startPosition: toLs.startPosition,
      endPosition: toLs.endPosition,
      sections: toSecs,
    );
    chapters[chIdx] = PreparedChapter(
      id: ch.id,
      title: ch.title,
      startPage: ch.startPage,
      endPage: ch.endPage,
      lessons: lessons,
    );
    setState(() => _book = book.copyWith(chapters: chapters));
    _scheduleAutoSave();
  }

  Future<void> _showChapterCards() async {
    final book = _book;
    if (book == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentBook = _book ?? book;
          return Container(
            height: MediaQuery.sizeOf(context).height * .84,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Drag Handle & Header
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_tree_rounded, color: Color(0xFF0022FF), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Qaab-dhismeedka Buugga & Dib-u-habeynta',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Qayb kasta booskeeda saxda ah u wareeji (⬆️ / ⬇️) ama u wareeji cutub kale.',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await _addChapter();
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.add_box_outlined, size: 16),
                        label: const Text('+ Chapter'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Main Tree & Reordering List
                Expanded(
                  child: currentBook.chapters.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.menu_book_rounded, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text('Weli wax cutubyo ah lama abuurin.'),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  await _addChapter();
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Abuur Cutubkii Koowaad'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: currentBook.chapters.length,
                          itemBuilder: (context, chIdx) {
                            final chapter = currentBook.chapters[chIdx];
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF0022FF),
                                  foregroundColor: Colors.white,
                                  child: Text('${chIdx + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(chapter.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                subtitle: Text(
                                  'Bogagga ${chapter.startPage}–${chapter.endPage} • ${chapter.lessons.length} cashar',
                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Move Chapter Up
                                    IconButton(
                                      tooltip: 'Kor u qaad Cutubka',
                                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                      onPressed: chIdx > 0
                                          ? () {
                                              _moveChapter(chIdx, chIdx - 1);
                                              setModalState(() {});
                                            }
                                          : null,
                                    ),
                                    // Move Chapter Down
                                    IconButton(
                                      tooltip: 'Hoos u dhig Cutubka',
                                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                      onPressed: chIdx < currentBook.chapters.length - 1
                                          ? () {
                                              _moveChapter(chIdx, chIdx + 1);
                                              setModalState(() {});
                                            }
                                          : null,
                                    ),
                                    IconButton(
                                      tooltip: 'Wax ka beddel',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () async {
                                        await _editChapter(chIdx);
                                        setModalState(() {});
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Tirtir',
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      onPressed: () {
                                        _deleteChapter(chIdx);
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                children: [
                                  // Add Lesson Button
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          Navigator.pop(modalContext);
                                          _beginMarker(kind: 'Lesson', chapterIndex: chIdx);
                                        },
                                        icon: const Icon(Icons.add, size: 15),
                                        label: const Text('+ Ku dar Cashar cutubkan'),
                                      ),
                                    ),
                                  ),
                                  // Lesson items
                                  for (int lsIdx = 0; lsIdx < chapter.lessons.length; lsIdx++) ...[
                                    Builder(
                                      builder: (context) {
                                        final lesson = chapter.lessons[lsIdx];
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 20, right: 12, bottom: 6),
                                          child: Card(
                                            color: const Color(0xFFF8FAFC),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              side: BorderSide(color: Colors.grey.shade200),
                                            ),
                                            child: ExpansionTile(
                                              leading: const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF16A34A)),
                                              title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                              subtitle: Text(
                                                'p.${lesson.startPage}-${lesson.endPage} • ${lesson.sections.length} qaybood',
                                                style: const TextStyle(fontSize: 10.5),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Move Lesson Up
                                                  IconButton(
                                                    tooltip: 'Kor u qaad Casharka',
                                                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                                                    onPressed: lsIdx > 0
                                                        ? () {
                                                            _moveLesson(chIdx, lsIdx, lsIdx - 1);
                                                            setModalState(() {});
                                                          }
                                                        : null,
                                                  ),
                                                  // Move Lesson Down
                                                  IconButton(
                                                    tooltip: 'Hoos u dhig Casharka',
                                                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                                                    onPressed: lsIdx < chapter.lessons.length - 1
                                                        ? () {
                                                            _moveLesson(chIdx, lsIdx, lsIdx + 1);
                                                            setModalState(() {});
                                                          }
                                                        : null,
                                                  ),
                                                  // Relocate Lesson to another chapter
                                                  if (currentBook.chapters.length > 1)
                                                    PopupMenuButton<int>(
                                                      tooltip: 'U wareeji Cutub kale',
                                                      icon: const Icon(Icons.drive_file_move_outlined, size: 17),
                                                      onSelected: (targetChIdx) {
                                                        _relocateLesson(chIdx, lsIdx, targetChIdx);
                                                        setModalState(() {});
                                                      },
                                                      itemBuilder: (context) => [
                                                        for (int c = 0; c < currentBook.chapters.length; c++)
                                                          if (c != chIdx)
                                                            PopupMenuItem(
                                                              value: c,
                                                              child: Text('U wareeji: ${currentBook.chapters[c].title}'),
                                                            ),
                                                      ],
                                                    ),
                                                  IconButton(
                                                    tooltip: 'Wax ka beddel',
                                                    icon: const Icon(Icons.edit_outlined, size: 17),
                                                    onPressed: () {
                                                      Navigator.pop(modalContext);
                                                      _beginEditMarker(
                                                        kind: 'Lesson',
                                                        chapterIndex: chIdx,
                                                        lessonIndex: lsIdx,
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Tirtir',
                                                    icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                                                    onPressed: () {
                                                      _deleteLesson(chIdx, lsIdx);
                                                      setModalState(() {});
                                                    },
                                                  ),
                                                ],
                                              ),
                                              children: [
                                                // Add Section button
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                                  child: Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: TextButton.icon(
                                                      onPressed: () {
                                                        Navigator.pop(modalContext);
                                                        _beginMarker(
                                                          kind: 'Section',
                                                          chapterIndex: chIdx,
                                                          lessonIndex: lsIdx,
                                                        );
                                                      },
                                                      icon: const Icon(Icons.add, size: 14),
                                                      label: const Text('+ Ku dar Section casharkan'),
                                                    ),
                                                  ),
                                                ),
                                                // Section Items
                                                for (int secIdx = 0; secIdx < lesson.sections.length; secIdx++) ...[
                                                  Builder(
                                                    builder: (context) {
                                                      final section = lesson.sections[secIdx];
                                                      return Container(
                                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: Colors.grey.shade200),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.segment_rounded, size: 16, color: Color(0xFFD97706)),
                                                            const SizedBox(width: 8),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(section.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                                  Text(
                                                                    'p.${section.startPage}-${section.endPage} • ${(section.startPosition * 100).toInt()}%-${(section.endPosition * 100).toInt()}%',
                                                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            // Move Section Up
                                                            IconButton(
                                                              tooltip: 'Kor u qaad Section-ka',
                                                              icon: const Icon(Icons.arrow_upward_rounded, size: 15),
                                                              onPressed: secIdx > 0
                                                                  ? () {
                                                                      _moveSection(chIdx, lsIdx, secIdx, secIdx - 1);
                                                                      setModalState(() {});
                                                                    }
                                                                  : null,
                                                            ),
                                                            // Move Section Down
                                                            IconButton(
                                                              tooltip: 'Hoos u dhig Section-ka',
                                                              icon: const Icon(Icons.arrow_downward_rounded, size: 15),
                                                              onPressed: secIdx < lesson.sections.length - 1
                                                                  ? () {
                                                                      _moveSection(chIdx, lsIdx, secIdx, secIdx + 1);
                                                                      setModalState(() {});
                                                                    }
                                                                  : null,
                                                            ),
                                                            // Relocate Section to another lesson
                                                            if (chapter.lessons.length > 1)
                                                              PopupMenuButton<int>(
                                                                tooltip: 'U wareeji Cashar kale',
                                                                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                                                onSelected: (targetLsIdx) {
                                                                  _relocateSection(chIdx, lsIdx, secIdx, targetLsIdx);
                                                                  setModalState(() {});
                                                                },
                                                                itemBuilder: (context) => [
                                                                  for (int l = 0; l < chapter.lessons.length; l++)
                                                                    if (l != lsIdx)
                                                                      PopupMenuItem(
                                                                        value: l,
                                                                        child: Text('U wareeji: ${chapter.lessons[l].title}'),
                                                                      ),
                                                                ],
                                                              ),
                                                            IconButton(
                                                              tooltip: 'Wax ka beddel Section',
                                                              icon: const Icon(Icons.edit_outlined, size: 16),
                                                              onPressed: () {
                                                                Navigator.pop(modalContext);
                                                                _beginEditMarker(
                                                                  kind: 'Section',
                                                                  chapterIndex: chIdx,
                                                                  lessonIndex: lsIdx,
                                                                  sectionIndex: secIdx,
                                                                );
                                                              },
                                                            ),
                                                            IconButton(
                                                              tooltip: 'Tirtir Section',
                                                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                                              onPressed: () {
                                                                _deleteSection(chIdx, lsIdx, secIdx);
                                                                setModalState(() {});
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: book != null
              ? 'Ka bax buugga'
              : (widget.onBackToAdmin != null
                  ? 'Ku noqo Admin Dashboard'
                  : 'Ku noqo Chat-ka'),
          onPressed: _leaveBook,
          icon: const Icon(Icons.arrow_back),
        ),
        title: book != null
            ? Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const Text(
                'Book Editor',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
        actions: [
          if (book != null)
            IconButton(
              tooltip: _showThumbnails ? 'Qari Thumbnails-ka' : 'Muuji Thumbnails-ka bogagga',
              icon: Icon(
                _showThumbnails
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
              ),
              onPressed: () => setState(() => _showThumbnails = !_showThumbnails),
            ),
          if (book != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: widget.returnToPreview
                  ? FilledButton.icon(
                      onPressed: _doneAndReturnToPreview,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Done ➔ Ku noqo Hubinta'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _sendToPreview,
                      icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                      label: const Text('U gudbi Preview'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0022FF),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
            ),
          if (book != null)
            IconButton(
              tooltip: 'Chapter Cards (Qaab-dhismeedka buugga)',
              onPressed: _showChapterCards,
              icon: const Icon(Icons.auto_stories_outlined),
            ),
          if (book != null)
            PopupMenuButton<String>(
              tooltip: 'Fursado dheeraad ah',
              onSelected: (value) {
                if (value == 'preview') _sendToPreview();
                if (value == 'save') _saveDraft();
                if (value == 'publish') _publishToLibrary();
                if (value == 'library') widget.onOpenLibrary?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'preview',
                  child: Row(
                    children: [
                      Icon(Icons.remove_red_eye_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('U Gudbi Preview (Hubinta)'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'save',
                  child: Row(
                    children: [
                      Icon(Icons.save_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Keydi Draft ahaan'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'publish',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('U Gudbi Maktabadda'),
                    ],
                  ),
                ),
                if (widget.onOpenLibrary != null)
                  const PopupMenuItem(
                    value: 'library',
                    child: Row(
                      children: [
                        Icon(Icons.local_library_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Fur Maktabadda'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: book == null || _pdfBytes == null
          ? _buildNoBookSelectedView()
          : Column(
              children: [
                if (_markerKind != null || _previewRange != null)
                  _buildPreviewBar(book),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_showThumbnails)
                        _buildThumbnailsSidebar(book),
                      Expanded(
                        child: Stack(
                          children: [
                            SfPdfViewer.memory(
                              _pdfBytes!,
                              key: ValueKey('pdf_editor_${book.id}_${_pdfBytes!.length}'),
                              controller: _pdfController,
                              enableTextSelection: true,
                              canShowTextSelectionMenu: true,
                              pageLayoutMode: PdfPageLayoutMode.single,
                              onPageChanged: _handlePageChanged,
                              onTap: _handlePdfTap,
                            ),
                            if (_markerKind != null)
                              _markerOverlay()
                            else if (_previewRange != null)
                              _previewOverlay(),
                            Positioned(
                              right: 14,
                              top: 20,
                              bottom: 20,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: _buildFloatingNotionNav(book),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildToolbar(book),
              ],
            ),
      bottomNavigationBar: _message == null || _markerKind != null
          ? null
          : Material(
              color: Theme.of(context).colorScheme.inverseSurface,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildToolbar(PreparedBook book) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _addChapter,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Chapter'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _selectedChapterIndex == null
                    ? null
                    : () => _beginMarker(
                        kind: 'Lesson',
                        chapterIndex: _selectedChapterIndex!,
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Lesson'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed:
                    _selectedChapterIndex == null ||
                        _selectedLessonIndex == null
                    ? null
                    : () => _beginMarker(
                        kind: 'Section',
                        chapterIndex: _selectedChapterIndex!,
                        lessonIndex: _selectedLessonIndex!,
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Section'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildFloatingNotionNav(PreparedBook book) {
    final items = <_NotionMinimapItem>[];
    for (int c = 0; c < book.chapters.length; c++) {
      final ch = book.chapters[c];
      items.add(
        _NotionMinimapItem(
          title: ch.title,
          page: ch.startPage,
          endPage: ch.endPage,
          type: _NotionItemType.chapter,
          chapterIndex: c,
        ),
      );
      for (int l = 0; l < ch.lessons.length; l++) {
        final les = ch.lessons[l];
        items.add(
          _NotionMinimapItem(
            title: les.title,
            page: les.startPage,
            endPage: les.endPage,
            type: _NotionItemType.lesson,
            chapterIndex: c,
            lessonIndex: l,
          ),
        );
        for (int s = 0; s < les.sections.length; s++) {
          final sec = les.sections[s];
          items.add(
            _NotionMinimapItem(
              title: sec.title,
              page: sec.startPage,
              endPage: sec.endPage,
              type: _NotionItemType.section,
              chapterIndex: c,
              lessonIndex: l,
              sectionIndex: s,
            ),
          );
        }
      }
    }

    return Container(
      width: 44,
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: const Color(0xF018181B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Chapter Cards\n(Fur qaab-dhismeedka buuxa)',
            preferBelow: false,
            child: IconButton(
              iconSize: 20,
              padding: const EdgeInsets.symmetric(vertical: 8),
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.auto_stories_outlined,
                color: Colors.white,
              ),
              onPressed: _showChapterCards,
            ),
          ),
          const Divider(
            color: Colors.white12,
            height: 1,
            indent: 8,
            endIndent: 8,
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Tooltip(
                message: 'Kudar cutubkii kowaad',
                child: IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _addChapter,
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _buildNotionMinimapLine(book, items[i]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotionMinimapLine(PreparedBook book, _NotionMinimapItem item) {
    final double lineWidth;
    final double lineHeight;
    final double radius;
    final String typeName;

    switch (item.type) {
      case _NotionItemType.chapter:
        lineWidth = 24.0;
        lineHeight = 3.5;
        radius = 2.0;
        typeName = 'Cutub';
        break;
      case _NotionItemType.lesson:
        lineWidth = 16.0;
        lineHeight = 3.0;
        radius = 1.5;
        typeName = 'Cashar';
        break;
      case _NotionItemType.section:
        lineWidth = 10.0;
        lineHeight = 2.5;
        radius = 1.2;
        typeName = 'Qayb';
        break;
    }

    final bool isSelected =
        _selectedChapterIndex == item.chapterIndex &&
        (item.lessonIndex == null || _selectedLessonIndex == item.lessonIndex);
    final bool isOnCurrentPage =
        _currentPage >= item.page && _currentPage <= item.endPage;
    final bool isActive = isSelected || isOnCurrentPage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message:
            '[$typeName] ${item.title}\nBogagga ${item.page}–${item.endPage}',
        preferBelow: false,
        verticalOffset: 12,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            if (item.type == _NotionItemType.chapter) {
              setState(() {
                _selectedChapterIndex = item.chapterIndex;
                _selectedLessonIndex = null;
              });
              _selectChapterPreview(book.chapters[item.chapterIndex]);
            } else if (item.type == _NotionItemType.lesson) {
              setState(() {
                _selectedChapterIndex = item.chapterIndex;
                _selectedLessonIndex = item.lessonIndex;
              });
              _selectLessonPreview(
                book.chapters[item.chapterIndex].lessons[item.lessonIndex!],
              );
            } else {
              final sec = book
                  .chapters[item.chapterIndex]
                  .lessons[item.lessonIndex!]
                  .sections[item.sectionIndex!];
              setState(() {
                _selectedChapterIndex = item.chapterIndex;
                _selectedLessonIndex = item.lessonIndex;
              });
              _selectPreview(
                sec.title,
                sec.startPage,
                sec.endPage,
                startPosition: sec.startPosition,
                endPosition: sec.endPosition,
              );
            }
          },
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: lineWidth,
              height: lineHeight,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(radius),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.8),
                          blurRadius: 5,
                          spreadRadius: 0.8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoBookSelectedView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Ma jiro buug hadda furan.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Fadlan ka dooro buug qaybta Maamulka Buugaagta (Book Management).',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _leaveBook,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Ku noqo Maamulka Buugaagta'),
          ),
        ],
      ),
    ),
  );


  Widget _buildThumbnailsSidebar(PreparedBook book) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 16, color: Color(0xFF0F172A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bogagga (${book.pageCount})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showThumbnails = false),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.chevron_left_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: book.pageCount,
              itemBuilder: (context, idx) {
                final pageNumber = idx + 1;
                final isCurrentPage = _currentPage == pageNumber;

                // Check markers on this page
                bool hasChapter = book.chapters.any((c) => c.startPage == pageNumber);
                bool hasLesson = book.chapters.any((c) => c.lessons.any((l) => l.startPage == pageNumber));
                bool hasSection = book.chapters.any((c) => c.lessons.any((l) => l.sections.any((s) => s.startPage == pageNumber)));

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      _pdfController.jumpToPage(pageNumber);
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isCurrentPage ? Colors.white : Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrentPage ? const Color(0xFF0022FF) : Colors.grey.shade300,
                          width: isCurrentPage ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isCurrentPage
                                ? const Color(0xFF0022FF).withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.03),
                            blurRadius: isCurrentPage ? 6 : 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isCurrentPage ? const Color(0xFF0022FF) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Bogga $pageNumber',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrentPage ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              if (isCurrentPage)
                                const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF0022FF)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.article_outlined,
                                    size: 20,
                                    color: isCurrentPage ? const Color(0xFF0022FF) : Colors.grey.shade400,
                                  ),
                                  if (hasChapter || hasLesson || hasSection) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (hasChapter)
                                          Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(color: Color(0xFF0022FF), shape: BoxShape.circle),
                                          ),
                                        if (hasLesson)
                                          Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                                          ),
                                        if (hasSection)
                                          Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBar(PreparedBook book) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _markerKind == null
                ? Text(
                    _previewRange == null
                        ? 'Dooro Chapter, Lesson ama Section si aad u Preview-gareyso.'
                        : 'Preview: ${_previewRange!.title} • Bogagga ${_previewRange!.startPage}–${_previewRange!.endPage}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  )
                : Text(
                    '$_markerKind: Start $_markerStartPage, End $_markerEndPage',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
          ),
          if (_markerKind != null) ...[
            // Bilow (Kore) Interactive Chip
            InkWell(
              onTap: () => setState(() {
                _activeMarker = 'start';
                _markerStartPage = _currentPage;
                _message = 'Line-ka Bilowga (Kore) ayaa la doortay. Taabo meesha aad rabto.';
              }),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _activeMarker == 'start'
                      ? const Color(0xFF0022FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _activeMarker == 'start'
                        ? const Color(0xFF0022FF)
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                  boxShadow: _activeMarker == 'start'
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0022FF).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.vertical_align_top_rounded,
                      size: 15,
                      color: _activeMarker == 'start'
                          ? Colors.white
                          : const Color(0xFF0022FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bilow (Kore): ${(_markerStartPosition * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _activeMarker == 'start'
                            ? Colors.white
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Dhammaad (Hoose) Interactive Chip
            InkWell(
              onTap: () => setState(() {
                _activeMarker = 'end';
                _markerEndPage = _currentPage;
                _message = 'Line-ka Dhammaadka (Hoose) ayaa la doortay. Taabo meesha aad rabto.';
              }),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _activeMarker == 'end'
                      ? const Color(0xFFD97706)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _activeMarker == 'end'
                        ? const Color(0xFFD97706)
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                  boxShadow: _activeMarker == 'end'
                      ? [
                          BoxShadow(
                            color: const Color(0xFFD97706).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.vertical_align_bottom_rounded,
                      size: 15,
                      color: _activeMarker == 'end'
                          ? Colors.white
                          : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Dhammaad (Hoose): ${(_markerEndPosition * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _activeMarker == 'end'
                            ? Colors.white
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _finishMarker,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Done'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Ka noqo',
              onPressed: _cancelMarker,
              icon: const Icon(Icons.close),
            ),
          ],
          if (_previewRange != null)
            if (_markerKind == null)
              TextButton(
                onPressed: () => setState(() {
                  _previewRange = null;
                  _previewMarkers = const [];
                }),
                child: const Text('Nadiifi'),
              ),
        ],
      ),
    ),
  );
}

class _RangeValue {
  const _RangeValue(this.title, this.startPage, this.endPage);
  final String title;
  final int startPage;
  final int endPage;
}

class _PreviewRange {
  const _PreviewRange(this.title, this.startPage, this.endPage);

  final String title;
  final int startPage;
  final int endPage;
}

class _PreviewMarkerRange {
  const _PreviewMarkerRange({
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.startPosition,
    required this.endPosition,
    required this.color,
  });

  final String title;
  final int startPage;
  final int endPage;
  final double startPosition;
  final double endPosition;
  final Color color;
}

enum _NotionItemType { chapter, lesson, section }

class _NotionMinimapItem {
  const _NotionMinimapItem({
    required this.title,
    required this.page,
    required this.endPage,
    required this.type,
    required this.chapterIndex,
    this.lessonIndex,
    this.sectionIndex,
  });

  final String title;
  final int page;
  final int endPage;
  final _NotionItemType type;
  final int chapterIndex;
  final int? lessonIndex;
  final int? sectionIndex;
}
