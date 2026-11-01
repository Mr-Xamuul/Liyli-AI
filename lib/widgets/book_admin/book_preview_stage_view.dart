import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/prepared_book.dart';
import '../../services/pdf_slice_service.dart';
import '../../services/prepared_book_storage.dart';

/// Stage 3: Preview (Hubinta Tayada & Xuduudaha)
/// Comprehensive inspection stage where the admin verifies that chapters,
/// lessons, and sections are sliced accurately. Slices the PDF in real-time
/// exactly as sent to AI in chat.
class BookPreviewStageView extends StatefulWidget {
  const BookPreviewStageView({
    super.key,
    required this.onOpenEditor,
    required this.onAdvanceToReady,
    this.initialSelectedBook,
  });

  final void Function(
    PreparedBook book, {
    int? chapterIndex,
    int? lessonIndex,
    int? sectionIndex,
    bool returnToPreview,
  }) onOpenEditor;

  final void Function(PreparedBook book) onAdvanceToReady;
  final PreparedBook? initialSelectedBook;

  @override
  State<BookPreviewStageView> createState() => _BookPreviewStageViewState();
}

class _BookPreviewStageViewState extends State<BookPreviewStageView> {
  final _bookStorage = const PreparedBookStorage();
  final _pdfSliceService = const PdfSliceService();

  List<PreparedBook> _reviewBooks = const [];
  bool _loading = true;

  PreparedBook? _selectedBook;
  Uint8List? _fullPdfBytes;

  // Selected scope for boundary inspection
  _PreviewScopeItem? _activeScope;
  Uint8List? _slicedPdfBytes;
  int _slicePageCount = 1;
  bool _isSlicing = false;
  String? _sliceError;
  final PdfViewerController _inspectionPdfController = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _loadBooks().then((_) {
      if (widget.initialSelectedBook != null) {
        _selectBookForInspection(widget.initialSelectedBook!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookPreviewStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedBook != null) {
      _bookStorage.getBookById(widget.initialSelectedBook!.id).then((fresh) {
        if (!mounted) return;
        if (fresh != null) {
          _selectBookForInspection(fresh);
        } else {
          _selectBookForInspection(widget.initialSelectedBook!);
        }
      });
    }
  }

  @override
  void dispose() {
    _inspectionPdfController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      final all = await _bookStorage.loadAll();
      final reviews = all
          .where((b) => b.status == PreparedBookStatus.review || b.status == PreparedBookStatus.draft)
          .toList();
      if (!mounted) return;
      setState(() {
        _reviewBooks = reviews;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectBookForInspection(PreparedBook book) async {
    setState(() {
      _selectedBook = book;
      _fullPdfBytes = null;
      _activeScope = null;
      _slicedPdfBytes = null;
      _sliceError = null;
    });

    final bytes = await _bookStorage.loadPdf(book);
    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _sliceError = 'PDF-ga buuggan lama helin local storage.';
      });
      return;
    }

    setState(() => _fullPdfBytes = bytes);

    // Pick first chapter or lesson as initial scope
    if (book.chapters.isNotEmpty) {
      final ch = book.chapters.first;
      if (ch.lessons.isNotEmpty) {
        final ls = ch.lessons.first;
        _setInspectionScope(_PreviewScopeItem(
          id: ls.id,
          title: ls.title,
          type: 'Cashar',
          startPage: ls.startPage,
          endPage: ls.endPage,
          startPosition: ls.startPosition,
          endPosition: ls.endPosition,
          chapterIndex: 0,
          lessonIndex: 0,
        ));
      } else {
        _setInspectionScope(_PreviewScopeItem(
          id: ch.id,
          title: ch.title,
          type: 'Cutub',
          startPage: ch.startPage,
          endPage: ch.endPage,
          startPosition: 0.0,
          endPosition: 1.0,
          chapterIndex: 0,
        ));
      }
    }
  }

  Future<void> _setInspectionScope(_PreviewScopeItem scope) async {
    setState(() {
      _activeScope = scope;
      _isSlicing = true;
      _sliceError = null;
    });

    final sourceBytes = _fullPdfBytes;
    if (sourceBytes == null || sourceBytes.isEmpty) {
      setState(() {
        _isSlicing = false;
        _sliceError = 'Faylka PDF-ka lama helin.';
      });
      return;
    }

    try {
      final sliced = _pdfSliceService.slicePdf(
        sourcePdfBytes: sourceBytes,
        startPage: scope.startPage,
        endPage: scope.endPage,
        startPosition: scope.startPosition,
        endPosition: scope.endPosition,
      );

      if (!mounted) return;
      int pageCount = 1;
      try {
        final doc = PdfDocument(inputBytes: sliced);
        pageCount = doc.pages.count;
        doc.dispose();
      } catch (_) {}

      setState(() {
        _slicedPdfBytes = sliced;
        _slicePageCount = pageCount;
        _isSlicing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSlicing = false;
        _sliceError = 'Khalad ayaa dhacay xilligii xuduudka la jarayay: $e';
      });
    }
  }

  Future<void> _toggleVerified(_PreviewScopeItem scope) async {
    await _toggleVerifiedById(scope.id, title: scope.title);
  }

  Future<void> _toggleVerifiedById(String itemId, {String? title}) async {
    final book = _selectedBook;
    if (book == null) return;

    final currentVerified = List<String>.from(book.verifiedItemIds);
    final isAlreadyVerified = currentVerified.contains(itemId);

    if (isAlreadyVerified) {
      currentVerified.remove(itemId);
    } else {
      currentVerified.add(itemId);
    }

    final updated = book.copyWith(
      verifiedItemIds: currentVerified,
      updatedAt: DateTime.now(),
    );

    await _bookStorage.save(updated);
    if (!mounted) return;
    setState(() => _selectedBook = updated);

    final itemName = title != null ? ' "$title"' : '';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !isAlreadyVerified
              ? 'Qaybta$itemName waa la hubiyay (Sax ✓)'
              : 'Calaamaddii saxda ahayd ee$itemName waa laga saaray.',
        ),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _advanceBookToReady() async {
    final book = _selectedBook;
    if (book == null) return;

    final updated = book.copyWith(
      status: PreparedBookStatus.ready,
      updatedAt: DateTime.now(),
    );

    await _bookStorage.save(updated);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buugga "${book.title}" waxaa loo gudbiyey Buugaagta Diyaarka ah!'),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );

    widget.onAdvanceToReady(updated);
  }

  int _countTotalScopes(PreparedBook book) {
    int total = 0;
    for (final ch in book.chapters) {
      total++; // chapter
      for (final ls in ch.lessons) {
        total++; // lesson
        total += ls.sections.length; // sections
      }
    }
    return total;
  }

  int _countVerifiedScopes(PreparedBook book) {
    final verified = book.verifiedItemIds.toSet();
    int count = 0;
    for (final ch in book.chapters) {
      if (verified.contains(ch.id)) count++;
      for (final ls in ch.lessons) {
        if (verified.contains(ls.id)) count++;
        for (final sec in ls.sections) {
          if (verified.contains(sec.id)) count++;
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBook == null) {
      return _buildBookSelectionList();
    }
    return _buildInspectionWorkspace();
  }

  // ==================== 1. BOOK SELECTION LIST ====================
  Widget _buildBookSelectionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Guide Header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check_rounded, color: Color(0xFF38BDF8), size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Talaabada 3: Hubinta Tayada & Xuduudaha (Preview Stage)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Dooro buug si aad u hubiso in Cutubyada, Casharrada, iyo Qaybaha (Sections) loo jaray si sax ah. '
                      'Nidaamku wuxuu toos u soo jarayaa PDF-ka saxda ah ee AI-ga loo diri doono marka ardaygu doorto qaybtaas.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_reviewBooks.isEmpty)
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Ma jiraan buugaag hadda u baahan hubin.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Marka buug lagu kala jaro Editor-ka, riix "U gudbi Preview" si uu halkan uga soo muuqdo.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 440,
                mainAxisExtent: 230,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _reviewBooks.length,
              itemBuilder: (context, idx) {
                final b = _reviewBooks[idx];
                final totalScopes = _countTotalScopes(b);
                final verifiedScopes = _countVerifiedScopes(b);
                final progress = totalScopes > 0 ? (verifiedScopes / totalScopes) : 0.0;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              b.category,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, size: 12, color: Color(0xFF16A34A)),
                                const SizedBox(width: 4),
                                Text(
                                  '$verifiedScopes/$totalScopes la hubiyay',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        b.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${b.pageCount} bogag • ${b.chapters.length} cutubyo',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade100,
                        color: const Color(0xFF16A34A),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _selectBookForInspection(b),
                          icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                          label: const Text('Gal Hubinta & Preview-ka'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0022FF),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ==================== 2. REAL-TIME INSPECTION WORKSPACE ====================
  Widget _buildInspectionWorkspace() {
    final book = _selectedBook!;
    final totalScopes = _countTotalScopes(book);
    final verifiedScopes = _countVerifiedScopes(book);
    final allVerified = totalScopes > 0 && verifiedScopes == totalScopes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Workspace Top Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Ku noqo Liiska Buugaagta',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selectedBook = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            book.category,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tirada la hubiyay: $verifiedScopes/$totalScopes qaybood • Xuduudaha tooska ah ee AI-ga loo diri doono',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Dib u cusboonaysii (Refresh)',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () async {
                  await _loadBooks();
                  if (_selectedBook != null) {
                    final fresh = await _bookStorage.getBookById(_selectedBook!.id);
                    if (mounted && fresh != null) {
                      setState(() => _selectedBook = fresh);
                      if (_activeScope != null) {
                        _setInspectionScope(_activeScope!);
                      }
                    }
                  }
                },
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _advanceBookToReady,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: Text(allVerified ? 'U gudbi Diyaar ah (Dhameystiran)' : 'U gudbi Diyaar ah'),
                style: FilledButton.styleFrom(
                  backgroundColor: allVerified ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Two Pane Workspace: Left Structure Tree | Right Real-Time PDF Slicer
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Structure Tree Pane
              SizedBox(
                width: 320,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.account_tree_outlined, size: 18, color: Color(0xFF0F172A)),
                            SizedBox(width: 8),
                            Text(
                              'Qaab-dhismeedka Buugga',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: book.chapters.length,
                          itemBuilder: (context, chIdx) {
                            final chapter = book.chapters[chIdx];
                            return _buildChapterTreeItem(book, chapter, chIdx);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Right Slicer & Real-time PDF Preview Pane
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _buildRightInspectionContent(book),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChapterTreeItem(PreparedBook book, PreparedChapter chapter, int chIdx) {
    final isChapterVerified = book.verifiedItemIds.contains(chapter.id);
    final isChapterActive = _activeScope?.id == chapter.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            _setInspectionScope(_PreviewScopeItem(
              id: chapter.id,
              title: chapter.title,
              type: 'Cutub',
              startPage: chapter.startPage,
              endPage: chapter.endPage,
              startPosition: 0.0,
              endPosition: 1.0,
              chapterIndex: chIdx,
            ));
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isChapterActive
                  ? const Color(0xFF0022FF).withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isChapterActive
                  ? Border.all(color: const Color(0xFF0022FF).withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _toggleVerifiedById(chapter.id, title: chapter.title),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Tooltip(
                      message: isChapterVerified ? 'Waa la hubiyay (Taabo si aad uga saarto)' : 'Taabo si aad u calaamadiso Sax',
                      child: Icon(
                        isChapterVerified ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isChapterVerified ? const Color(0xFF16A34A) : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isChapterActive ? const Color(0xFF0022FF) : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Text(
                  'p.${chapter.startPage}-${chapter.endPage}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),

        // Lessons
        for (int lsIdx = 0; lsIdx < chapter.lessons.length; lsIdx++) ...[
          _buildLessonTreeItem(book, chapter, chapter.lessons[lsIdx], chIdx, lsIdx),
        ],
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildLessonTreeItem(
    PreparedBook book,
    PreparedChapter chapter,
    PreparedLesson lesson,
    int chIdx,
    int lsIdx,
  ) {
    final isLessonVerified = book.verifiedItemIds.contains(lesson.id);
    final isLessonActive = _activeScope?.id == lesson.id;

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              _setInspectionScope(_PreviewScopeItem(
                id: lesson.id,
                title: lesson.title,
                type: 'Cashar',
                startPage: lesson.startPage,
                endPage: lesson.endPage,
                startPosition: lesson.startPosition,
                endPosition: lesson.endPosition,
                chapterIndex: chIdx,
                lessonIndex: lsIdx,
              ));
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isLessonActive
                    ? const Color(0xFF0022FF).withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isLessonActive
                    ? Border.all(color: const Color(0xFF0022FF).withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _toggleVerifiedById(lesson.id, title: lesson.title),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Tooltip(
                        message: isLessonVerified ? 'Waa la hubiyay (Taabo si aad uga saarto)' : 'Taabo si aad u calaamadiso Sax',
                        child: Icon(
                          isLessonVerified ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: isLessonVerified ? const Color(0xFF16A34A) : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lesson.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLessonActive ? const Color(0xFF0022FF) : Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Text(
                    'p.${lesson.startPage}-${lesson.endPage}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),

          // Sections
          for (int secIdx = 0; secIdx < lesson.sections.length; secIdx++) ...[
            _buildSectionTreeItem(book, chapter, lesson, lesson.sections[secIdx], chIdx, lsIdx, secIdx),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTreeItem(
    PreparedBook book,
    PreparedChapter chapter,
    PreparedLesson lesson,
    PreparedSection section,
    int chIdx,
    int lsIdx,
    int secIdx,
  ) {
    final isSectionVerified = book.verifiedItemIds.contains(section.id);
    final isSectionActive = _activeScope?.id == section.id;

    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: InkWell(
        onTap: () {
          _setInspectionScope(_PreviewScopeItem(
            id: section.id,
            title: section.title,
            type: 'Section',
            startPage: section.startPage,
            endPage: section.endPage,
            startPosition: section.startPosition,
            endPosition: section.endPosition,
            chapterIndex: chIdx,
            lessonIndex: lsIdx,
            sectionIndex: secIdx,
          ));
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSectionActive
                ? const Color(0xFF0022FF).withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => _toggleVerifiedById(section.id, title: section.title),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Tooltip(
                    message: isSectionVerified ? 'Waa la hubiyay (Taabo si aad uga saarto)' : 'Taabo si aad u calaamadiso Sax',
                    child: Icon(
                      isSectionVerified ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 14,
                      color: isSectionVerified ? const Color(0xFF16A34A) : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isSectionActive ? const Color(0xFF0022FF) : Colors.grey.shade700,
                  ),
                ),
              ),
              Text(
                '${(section.startPosition * 100).toInt()}%-${(section.endPosition * 100).toInt()}%',
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightInspectionContent(PreparedBook book) {
    final scope = _activeScope;
    if (scope == null) {
      return const Center(
        child: Text('Dooro cutub ama cashar dhanka bidix si aad xuduudkiisa u aragto.'),
      );
    }

    final isVerified = book.verifiedItemIds.contains(scope.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scope Action & Metadata Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            scope.type,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            scope.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bogagga ${scope.startPage} ilaa ${scope.endPage} '
                      '• Xuduudka dhererka: ${(scope.startPosition * 100).toInt()}% ilaa ${(scope.endPosition * 100).toInt()}%',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Action: Edit in Editor (Wax ka beddel Editor-ka)
              OutlinedButton.icon(
                onPressed: () {
                  widget.onOpenEditor(
                    book,
                    chapterIndex: scope.chapterIndex,
                    lessonIndex: scope.lessonIndex,
                    sectionIndex: scope.sectionIndex,
                    returnToPreview: true,
                  );
                },
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Wax ka beddel Editor-ka'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
              ),
              const SizedBox(width: 8),

              // Action: Mark as Verified (Calaamadee Sax)
              FilledButton.icon(
                onPressed: () => _toggleVerified(scope),
                icon: Icon(
                  isVerified ? Icons.check_circle_rounded : Icons.check_rounded,
                  size: 16,
                ),
                label: Text(isVerified ? 'Waa Saxan Yahay ✓' : 'Calaamadee Sax'),
                style: FilledButton.styleFrom(
                  backgroundColor: isVerified ? const Color(0xFF16A34A) : const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ],
          ),
        ),

        // AI Info Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFEFF6FF),
          child: const Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 16, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sidan saxda ah ayuu AI-gu u helayaa PDF-ka marka ardaygu doorto casharkan chat-ka dhexdiisa.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF1E40AF)),
                ),
              ),
            ],
          ),
        ),

        // Boundary Navigation Bar (Start & End jump buttons)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  _inspectionPdfController.jumpToPage(1);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('📍 Xuduudka Bilowga: Bogga ${scope.startPage} (${(scope.startPosition * 100).toInt()}%)'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.vertical_align_top_rounded, size: 16, color: Color(0xFF0022FF)),
                label: Text('📍 Bilowga (Bogga ${scope.startPage})'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  _inspectionPdfController.jumpToPage(_slicePageCount);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🏁 Xuduudka Dhammaadka: Bogga ${scope.endPage} (${(scope.endPosition * 100).toInt()}%)'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.vertical_align_bottom_rounded, size: 16, color: Color(0xFFD97706)),
                label: Text('🏁 Dhammaadka (Bogga ${scope.endPage})'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFBEB),
                  foregroundColor: const Color(0xFFB45309),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Bogagga la jaray: $_slicePageCount bog',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Real-Time Sliced PDF View
        Expanded(
          child: _isSlicing
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('PDF-ka ayaa loo jarayaa sidii loogu diri lahaa AI-ga...'),
                    ],
                  ),
                )
              : _sliceError != null
                  ? Center(
                      child: Text(
                        _sliceError!,
                        style: const TextStyle(color: Color(0xFFDC2626)),
                      ),
                    )
                  : _slicedPdfBytes != null
                      ? Container(
                          color: const Color(0xFFF8FAFC),
                          alignment: Alignment.topCenter,
                          child: SfPdfViewer.memory(
                            _slicedPdfBytes!,
                            controller: _inspectionPdfController,
                            canShowScrollHead: false,
                            canShowScrollStatus: true,
                            pageLayoutMode: PdfPageLayoutMode.single,
                          ),
                        )
                      : const Center(
                          child: Text('PDF-ka la jaray ma jiro.'),
                        ),
        ),
      ],
    );
  }
}

class _PreviewScopeItem {
  const _PreviewScopeItem({
    required this.id,
    required this.title,
    required this.type,
    required this.startPage,
    required this.endPage,
    required this.startPosition,
    required this.endPosition,
    required this.chapterIndex,
    this.lessonIndex,
    this.sectionIndex,
  });

  final String id;
  final String title;
  final String type;
  final int startPage;
  final int endPage;
  final double startPosition;
  final double endPosition;
  final int chapterIndex;
  final int? lessonIndex;
  final int? sectionIndex;
}
