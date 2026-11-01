import 'package:flutter/material.dart';

import '../../models/prepared_book.dart';
import '../../services/prepared_book_storage.dart';
import 'book_editor_stage_view.dart';
import 'book_library_stage_view.dart';
import 'book_preview_stage_view.dart';
import 'book_ready_stage_view.dart';
import 'book_upload_stage_view.dart';

/// BookManagementWorkspace
/// Implements the 5-stage pipeline for books:
/// 1. Upload: Pick & upload PDF, view pages & metadata, button "U gudbi Editor-ka"
/// 2. Editor: Boundary splitting into chapters, lessons & sections, button "U gudbi Preview"
/// 3. Preview: Real-time PDF slice verification, verified checks, deep link to editor & "U gudbi Diyaar ah"
/// 4. Ready: Books waiting to be released, button "Fasax / Maktabadda"
/// 5. Library: Live student library connected directly to the AI chat
class BookManagementWorkspace extends StatefulWidget {
  const BookManagementWorkspace({
    super.key,
    required this.onOpenEditor,
    required this.onOpenChat,
    this.initialStageIndex = 0,
    this.initialBook,
  });

  final void Function(
    PreparedBook? book, {
    int? chapterIndex,
    int? lessonIndex,
    int? sectionIndex,
    bool returnToPreview,
  }) onOpenEditor;

  final void Function(PreparedBook book) onOpenChat;
  final int initialStageIndex;
  final PreparedBook? initialBook;

  @override
  State<BookManagementWorkspace> createState() => _BookManagementWorkspaceState();
}

class _BookManagementWorkspaceState extends State<BookManagementWorkspace> {
  final _bookStorage = const PreparedBookStorage();

  // 0: Upload, 1: Editor, 2: Preview, 3: Diyaar ah, 4: Maktabadda
  int _currentStage = 0;
  PreparedBook? _targetedBookForPreview;
  int _previewRefreshCounter = 0;

  int _draftCount = 0;
  int _reviewCount = 0;
  int _readyCount = 0;
  int _publishedCount = 0;

  @override
  void initState() {
    super.initState();
    _currentStage = widget.initialStageIndex.clamp(0, 4);
    _targetedBookForPreview = widget.initialBook;
    _refreshCounts();
  }

  @override
  void didUpdateWidget(covariant BookManagementWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStageIndex != oldWidget.initialStageIndex) {
      _currentStage = widget.initialStageIndex.clamp(0, 4);
      _previewRefreshCounter++;
    }
    if (widget.initialBook != null) {
      _targetedBookForPreview = widget.initialBook;
      _previewRefreshCounter++;
    }
    _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    try {
      final all = await _bookStorage.loadAll();
      if (!mounted) return;
      setState(() {
        _draftCount = all.where((b) => b.isDraft).length;
        _reviewCount = all.where((b) => b.status == PreparedBookStatus.review).length;
        _readyCount = all.where((b) => b.isReady).length;
        _publishedCount = all.where((b) => b.isPublished).length;
      });
    } catch (_) {}
  }

  Future<void> _navigateToStage(int stage, {PreparedBook? book}) async {
    PreparedBook? freshBook = book;
    if (freshBook != null) {
      final loaded = await _bookStorage.getBookById(freshBook.id);
      if (loaded != null) freshBook = loaded;
    } else if (_targetedBookForPreview != null) {
      final loaded = await _bookStorage.getBookById(_targetedBookForPreview!.id);
      if (loaded != null) freshBook = loaded;
    }
    if (!mounted) return;
    setState(() {
      _currentStage = stage;
      _previewRefreshCounter++;
      if (freshBook != null) {
        _targetedBookForPreview = freshBook;
      }
    });
    _refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 5-Stage Top Navigation Stepper
        _buildStageNavigationBar(),
        const SizedBox(height: 16),

        // Stage Active Body
        Expanded(
          child: _buildActiveStageView(),
        ),
      ],
    );
  }

  Widget _buildStageNavigationBar() {
    final stages = [
      _StageTabItem(
        index: 0,
        title: '1. Upload',
        icon: Icons.upload_file_rounded,
        badgeCount: null,
      ),
      _StageTabItem(
        index: 1,
        title: '2. Editor',
        icon: Icons.content_cut_rounded,
        badgeCount: _draftCount,
      ),
      _StageTabItem(
        index: 2,
        title: '3. Preview (Hubinta)',
        icon: Icons.fact_check_rounded,
        badgeCount: _reviewCount,
      ),
      _StageTabItem(
        index: 3,
        title: '4. Diyaar ah (Ready)',
        icon: Icons.verified_rounded,
        badgeCount: _readyCount,
      ),
      _StageTabItem(
        index: 4,
        title: '5. Maktabadda (Library)',
        icon: Icons.local_library_rounded,
        badgeCount: _publishedCount,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: stages.map((item) {
            final isSelected = _currentStage == item.index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => setState(() => _currentStage = item.index),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0022FF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                      if (item.badgeCount != null && item.badgeCount! > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.badgeCount}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActiveStageView() {
    switch (_currentStage) {
      case 0:
        return BookUploadStageView(
          onOpenEditor: (book) => widget.onOpenEditor(book),
          onBookCreated: _refreshCounts,
        );
      case 1:
        return BookEditorStageView(
          onOpenEditor: (book) => widget.onOpenEditor(book),
          onAdvanceToPreview: (book) => _navigateToStage(2, book: book),
        );
      case 2:
        return BookPreviewStageView(
          key: ValueKey('preview_${_targetedBookForPreview?.id ?? 'all'}_$_previewRefreshCounter'),
          initialSelectedBook: _targetedBookForPreview,
          onOpenEditor: (book, {chapterIndex, lessonIndex, sectionIndex, returnToPreview = true}) {
            widget.onOpenEditor(
              book,
              chapterIndex: chapterIndex,
              lessonIndex: lessonIndex,
              sectionIndex: sectionIndex,
              returnToPreview: returnToPreview,
            );
          },
          onAdvanceToReady: (book) => _navigateToStage(3, book: book),
        );
      case 3:
        return BookReadyStageView(
          onPublishToLibrary: (book) => _navigateToStage(4, book: book),
          onReturnToPreview: (book) => _navigateToStage(2, book: book),
          onOpenEditor: (book) => widget.onOpenEditor(book),
        );
      case 4:
        return BookLibraryStageView(
          onOpenChat: widget.onOpenChat,
          onUnpublish: (book) => _refreshCounts(),
          onOpenEditor: (book) => widget.onOpenEditor(book),
        );
      default:
        return BookUploadStageView(
          onOpenEditor: (book) => widget.onOpenEditor(book),
          onBookCreated: _refreshCounts,
        );
    }
  }
}

class _StageTabItem {
  const _StageTabItem({
    required this.index,
    required this.title,
    required this.icon,
    this.badgeCount,
  });

  final int index;
  final String title;
  final IconData icon;
  final int? badgeCount;
}
