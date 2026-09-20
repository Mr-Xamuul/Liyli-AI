import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/prepared_book.dart';
import '../models/book_knowledge.dart';
import 'book_chat_screen.dart';
import '../services/book_knowledge_storage.dart';
import '../services/prepared_book_storage.dart';

/// Admin-only editor. It stores one original PDF and non-destructive page markers.
class PreparedBookEditorScreen extends StatefulWidget {
  const PreparedBookEditorScreen({
    super.key,
    this.storage,
    this.initialBook,
    this.onOpenChat,
    this.onOpenLibrary,
    this.onBackToChat,
  });

  final PreparedBookStorage? storage;
  final PreparedBook? initialBook;
  final void Function(
    PreparedBook book, {
    String? chapter,
    String? lesson,
    String? section,
  })?
  onOpenChat;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onBackToChat;

  @override
  State<PreparedBookEditorScreen> createState() =>
      _PreparedBookEditorScreenState();
}

class _PreparedBookEditorScreenState extends State<PreparedBookEditorScreen> {
  final _storage = const PreparedBookStorage();
  final _knowledgeStorage = const BookKnowledgeStorage();
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
  String? _message;
  String? _selectedPdfText;
  Timer? _autoSaveTimer;

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
    if (!mounted) return;
    setState(() {
      _book = book;
      _pdfBytes = bytes;
      _message =
          'Book-ga waa la furay. Wax ka beddel ama sii wad diyaarintiisa.';
    });
  }

  Future<void> _deleteSavedBook(PreparedBook book) async {
    await _bookStorage.delete(book);
    if (!mounted) return;
    setState(() {
      _savedBooks = _savedBooks.where((item) => item.id != book.id).toList();
      if (_book?.id == book.id) {
        _book = null;
        _pdfBytes = null;
      }
      _message = 'Book-ga local-ka waa la tirtiray.';
    });
  }

  Future<void> _choosePdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _message = 'PDF-ga lama akhrin karin.');
      return;
    }

    int pageCount;
    final pageTexts = <int, String>{};
    try {
      final document = PdfDocument(inputBytes: bytes);
      pageCount = document.pages.count;
      _pdfPageHeights
        ..clear()
        ..addEntries(
          List.generate(
            pageCount,
            (index) => MapEntry(
              index + 1,
              document.pages[index].getClientSize().height,
            ),
          ),
        );
      for (var index = 0; index < pageCount; index++) {
        pageTexts[index + 1] = PdfTextExtractor(
          document,
        ).extractText(startPageIndex: index, endPageIndex: index);
      }
      document.dispose();
    } catch (_) {
      setState(() => _message = 'PDF-ga lama fahmi karin ama wuu dhaawacmay.');
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    setState(() {
      _pdfBytes = Uint8List.fromList(bytes);
      _book = PreparedBook(
        id: id,
        title: file.name.replaceFirst(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        ),
        originalFileName: file.name,
        pageCount: pageCount,
        chapters: const [],
        createdAt: now,
        updatedAt: now,
      );
      _message = 'PDF-ga waa diyaar. Calaamadee qaybaha bogagga.';
    });
    await _knowledgeStorage.save(BookKnowledge(bookId: id, pages: pageTexts));
    _scheduleAutoSave();
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
      initialTitle: initialTitle ?? _selectedPdfText ?? '',
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
    final defaultTitle = initialTitle.isNotEmpty
        ? initialTitle
        : (_selectedPdfText?.trim() ?? '');
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
    if (kind == 'Lesson') {
      final existing = _markerEditing
          ? chapter.lessons[_markerLessonIndex!]
          : null;
      final lesson = PreparedLesson(
        id: existing?.id ?? _id('lesson'),
        title: name,
        startPage: _markerStartPage,
        endPage: _markerEndPage,
        startPosition: _markerStartPosition,
        endPosition: _markerEndPosition,
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
        startPage: _markerStartPage,
        endPage: _markerEndPage,
        startPosition: _markerStartPosition,
        endPosition: _markerEndPosition,
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
    if (_book != null) {
      setState(() {
        _book = null;
        _pdfBytes = null;
        _previewRange = null;
        _previewMarkers = const [];
        _markerKind = null;
        _selectedChapterIndex = null;
        _selectedLessonIndex = null;
      });
      return;
    }
    if (widget.onBackToChat != null) {
      widget.onBackToChat!();
      return;
    }
    Navigator.maybePop(context);
  }

  Widget _markerOverlay() => LayoutBuilder(
    builder: (context, constraints) => IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          if (_currentPage == _markerStartPage)
            _draggableMarkerLine(true, constraints.maxHeight),
          if (_currentPage == _markerEndPage)
            _draggableMarkerLine(false, constraints.maxHeight),
        ],
      ),
    ),
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

        final height = constraints.maxHeight;
        final usableHeight = height - 48;

        return IgnorePointer(
          child: Stack(
            children: [
              for (final marker in _previewMarkers)
                if (page >= marker.startPage && page <= marker.endPage)
                  _previewMarkerRangeOverlay(marker, usableHeight, height),
            ],
          ),
        );
      },
    );
  }

  Widget _previewMarkerRangeOverlay(
    _PreviewMarkerRange marker,
    double usableHeight,
    double height,
  ) {
    final page = _currentPage;
    final isStartPage = page == marker.startPage;
    final isEndPage = page == marker.endPage;
    final top = isStartPage ? usableHeight * marker.startPosition : 0.0;
    final bottom = isEndPage ? usableHeight * marker.endPosition + 3 : height;
    final shadeHeight = bottom > top ? bottom - top : 0.0;
    return Stack(
      children: [
        if (shadeHeight > 0)
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: shadeHeight,
            child: ColoredBox(color: marker.color.withValues(alpha: .05)),
          ),
        if (isStartPage)
          _previewMarkerLine(
            label: '${marker.title} • BILOW',
            position: marker.startPosition,
            color: marker.color,
            height: height,
          ),
        if (isEndPage)
          _previewMarkerLine(
            label: '${marker.title} • DHAMMAAD',
            position: marker.endPosition,
            color: marker.color,
            height: height,
          ),
      ],
    );
  }

  Widget _previewMarkerLine({
    required String label,
    required double position,
    required Color color,
    required double height,
  }) {
    return Positioned(
      top: (height - 48) * position,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 48,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 3,
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
                    vertical: 4,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _draggableMarkerLine(bool isStart, double height) {
    final position = isStart ? _markerStartPosition : _markerEndPosition;
    return Positioned(
      top: (height - 48) * position,
      left: 0,
      right: 0,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          final current = isStart ? _markerStartPosition : _markerEndPosition;
          final minimum = isStart ? .02 : _markerStartPosition + .04;
          final maximum = isStart ? _markerEndPosition - .04 : .98;
          final next = (current + details.delta.dy / height).clamp(
            minimum,
            maximum,
          );
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
          height: 48,
          alignment: Alignment.topCenter,
          child: Container(
            height: 3,
            color: isStart ? const Color(0xFF0022FF) : const Color(0xFF000000),
            child: Align(
              alignment: Alignment.topLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isStart
                      ? const Color(0xFF0022FF)
                      : const Color(0xFF000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    isStart ? 'BILOW' : 'DHAMMAAD',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
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
      } else {
        _markerEndPage = details.pageNumber;
        _markerEndPosition = ratio;
      }
      _message =
          '${_activeMarker == 'start' ? 'Bilowga' : 'Dhammaadka'} waxaa lagu dhigay bogga ${details.pageNumber}.';
    });
    _scheduleAutoSave();
  }

  Future<void> _showChapterCards() async {
    final book = _book;
    if (book == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.auto_stories_outlined),
                title: Text('Chapter Cards'),
                subtitle: Text('Dooro chapter si aad u aragto pages-kiisa.'),
              ),
              Expanded(
                child: book.chapters.isEmpty
                    ? const Center(child: Text('Weli chapter lama abuurin.'))
                    : ListView.builder(
                        itemCount: book.chapters.length,
                        itemBuilder: (context, index) {
                          final chapter = book.chapters[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(chapter.title),
                              subtitle: Text(
                                'Bogagga ${chapter.startPage}–${chapter.endPage} • ${chapter.lessons.length} lessons',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Wax ka beddel Chapter',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _editChapter(index);
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Tirtir Chapter',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _deleteChapter(index);
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              onExpansionChanged: (expanded) {
                                if (expanded) {
                                  setState(() {
                                    _selectedChapterIndex = index;
                                    _selectedLessonIndex = null;
                                  });
                                  _selectChapterPreview(chapter);
                                }
                              },
                              children: [
                                for (
                                  var lessonIndex = 0;
                                  lessonIndex < chapter.lessons.length;
                                  lessonIndex++
                                )
                                  ExpansionTile(
                                    tilePadding: const EdgeInsets.only(
                                      left: 48,
                                      right: 16,
                                    ),
                                    leading: const Icon(
                                      Icons.menu_book_outlined,
                                      size: 18,
                                    ),
                                    title: Text(
                                      chapter.lessons[lessonIndex].title,
                                    ),
                                    subtitle: Text(
                                      'Bogagga ${chapter.lessons[lessonIndex].startPage}–${chapter.lessons[lessonIndex].endPage} • ${chapter.lessons[lessonIndex].sections.length} sections',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Wax ka beddel Lesson',
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _beginEditMarker(
                                              kind: 'Lesson',
                                              chapterIndex: index,
                                              lessonIndex: lessonIndex,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 20,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Tirtir Lesson',
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _deleteLesson(index, lessonIndex);
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onExpansionChanged: (expanded) {
                                      if (!expanded) return;
                                      final lesson =
                                          chapter.lessons[lessonIndex];
                                      setState(() {
                                        _selectedChapterIndex = index;
                                        _selectedLessonIndex = lessonIndex;
                                      });
                                      _selectLessonPreview(lesson);
                                    },
                                    children: [
                                      for (
                                        var sectionIndex = 0;
                                        sectionIndex <
                                            chapter
                                                .lessons[lessonIndex]
                                                .sections
                                                .length;
                                        sectionIndex++
                                      )
                                        ListTile(
                                          contentPadding: const EdgeInsets.only(
                                            left: 96,
                                            right: 16,
                                          ),
                                          leading: const Icon(
                                            Icons.segment,
                                            size: 18,
                                          ),
                                          title: Text(
                                            chapter
                                                .lessons[lessonIndex]
                                                .sections[sectionIndex]
                                                .title,
                                          ),
                                          subtitle: Text(
                                            'Bogagga ${chapter.lessons[lessonIndex].sections[sectionIndex].startPage}–${chapter.lessons[lessonIndex].sections[sectionIndex].endPage}',
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip:
                                                    'Ku Baro AI Tutor (PDF Slice)',
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  final section = chapter
                                                      .lessons[lessonIndex]
                                                      .sections[sectionIndex];
                                                  final lesson = chapter
                                                      .lessons[lessonIndex];
                                                  if (widget.onOpenChat !=
                                                      null) {
                                                    widget.onOpenChat!(
                                                      book,
                                                      chapter: chapter.title,
                                                      lesson: lesson.title,
                                                      section: section.title,
                                                    );
                                                  } else {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            BookChatScreen(
                                                              book: book,
                                                              initialChapter:
                                                                  chapter.title,
                                                              initialLesson:
                                                                  lesson.title,
                                                              initialSection:
                                                                  section.title,
                                                            ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                icon: Icon(
                                                  Icons.auto_awesome,
                                                  size: 18,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Wax ka beddel Section',
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _beginEditMarker(
                                                    kind: 'Section',
                                                    chapterIndex: index,
                                                    lessonIndex: lessonIndex,
                                                    sectionIndex: sectionIndex,
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 19,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Tirtir Section',
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _deleteSection(
                                                    index,
                                                    lessonIndex,
                                                    sectionIndex,
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 19,
                                                ),
                                              ),
                                            ],
                                          ),
                                          onTap: () {
                                            final section = chapter
                                                .lessons[lessonIndex]
                                                .sections[sectionIndex];
                                            setState(() {
                                              _selectedChapterIndex = index;
                                              _selectedLessonIndex =
                                                  lessonIndex;
                                            });
                                            Navigator.pop(context);
                                            _selectPreview(
                                              section.title,
                                              section.startPage,
                                              section.endPage,
                                              startPosition:
                                                  section.startPosition,
                                              endPosition: section.endPosition,
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Ka bax book-ga',
          onPressed: _leaveBook,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                book?.title ?? 'Book Preparation Tool',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (book != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.tonalIcon(
                onPressed: _publishToLibrary,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text(''),
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
                if (value == 'save') _saveDraft();
                if (value == 'publish') _publishToLibrary();
                if (value == 'library') widget.onOpenLibrary?.call();
              },
              itemBuilder: (_) => [
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
          ? _buildSavedBooksHome()
          : Column(
              children: [
                if (_markerKind != null || _previewRange != null)
                  _buildPreviewBar(book),
                Expanded(
                  child: Stack(
                    children: [
                      SfPdfViewer.memory(
                        _pdfBytes!,
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

  Widget _buildSavedBooksHome() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _choosePdf,
            icon: const Icon(Icons.upload_file),
            label: const Text('Soo geli PDF cusub'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Buugaagta Local-ka',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _savedBooks.isEmpty
              ? const Center(child: Text('Weli ma jiro book la diyaariyay.'))
              : ListView.separated(
                  itemCount: _savedBooks.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final saved = _savedBooks[index];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(saved.title),
                      subtitle: Text(
                        '${saved.pageCount} pages • ${saved.chapters.length} chapters • ${saved.status.name}',
                      ),
                      onTap: () => _openSavedBook(saved),
                      trailing: IconButton(
                        tooltip: 'Tirtir',
                        onPressed: () => _deleteSavedBook(saved),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

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
            TextButton(
              onPressed: () => setState(() {
                _activeMarker = 'start';
                _markerStartPage = _currentPage;
              }),
              child: const Text('Bilow'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _activeMarker = 'end';
                _markerEndPage = _currentPage;
              }),
              child: const Text('Dhamad'),
            ),
            FilledButton(onPressed: _finishMarker, child: const Text('Done')),
            IconButton(onPressed: _cancelMarker, icon: const Icon(Icons.close)),
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
