import 'package:flutter/material.dart';

import '../../models/prepared_book.dart';
import '../../services/prepared_book_storage.dart';

/// Stage 2: Editor (Kala Jar-jarista & Xuduudaha)
/// Manages books currently being split and structured into chapters, lessons,
/// and sections. Allows opening the editor directly, and advancing the book
/// to Stage 3 (Preview / Hubinta) once splitting is complete.
class BookEditorStageView extends StatefulWidget {
  const BookEditorStageView({
    super.key,
    required this.onOpenEditor,
    required this.onAdvanceToPreview,
  });

  final void Function(PreparedBook book) onOpenEditor;
  final void Function(PreparedBook book) onAdvanceToPreview;

  @override
  State<BookEditorStageView> createState() => _BookEditorStageViewState();
}

class _BookEditorStageViewState extends State<BookEditorStageView> {
  final _bookStorage = const PreparedBookStorage();
  List<PreparedBook> _editorBooks = const [];
  bool _loading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      final all = await _bookStorage.loadAll();
      final drafts = all.where((b) => b.isDraft).toList();
      if (!mounted) return;
      setState(() {
        _editorBooks = drafts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendToPreview(PreparedBook book) async {
    if (book.chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buuggu ma lahan wax cutubyo ah. Fadlan marka hore Editor-ka ku samee cutubyo.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final updated = book.copyWith(
      status: PreparedBookStatus.review,
      updatedAt: DateTime.now(),
    );
    await _bookStorage.save(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buugga "${book.title}" waxaa loo gudbiyey Qaybta Preview (Hubinta)!'),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );
    widget.onAdvanceToPreview(updated);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'All'
        ? _editorBooks
        : _editorBooks.where((b) => b.category == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Guide Banner
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
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.content_cut_rounded, color: Color(0xFFA78BFA), size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Talaabada 2: Kala Jar-jarista & Xuduudaha (Editor)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Halkan waxaa lagu maamulaa buugaagta lagu qabanayo shaqada kala qaybinta Cutubyada, Casharrada, iyo Qaybaha (Sections). '
                      'Marka shaqada kala jar-jarista la dhameeyo, buugga waxaa toos loogu gudbiyaa Talaabada 3 (Preview) si xuduudaha loo xaqiijiyo.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Filter Bar & Stats
        Row(
          children: [
            Wrap(
              spacing: 8,
              children: ['All', 'Form 1', 'Form 2', 'Form 3', 'Form 4'].map((cat) {
                final isSelected = _filter == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _filter = cat),
                  selectedColor: const Color(0xFF0022FF),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
            Text(
              '${filtered.length} buug oo qabyo ah',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Cusbooneysii',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _loadBooks,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // List / Grid of Books in Editor stage
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (filtered.isEmpty)
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
                  Icon(Icons.edit_note_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Ma jiraan buugaag hadda ku jira marxaladda Editor-ka.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ka bilow Talaabada 1 (Upload) si aad buug cusub u soo geliso.',
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
                maxCrossAxisExtent: 420,
                mainAxisExtent: 200,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, idx) {
                final book = filtered[idx];
                final chapterCount = book.chapters.length;
                final lessonCount = book.chapters.fold<int>(
                  0,
                  (sum, ch) => sum + ch.lessons.length,
                );

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
                              book.category,
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
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                CircleAvatar(radius: 3, backgroundColor: Color(0xFFEAB308)),
                                SizedBox(width: 5),
                                Text(
                                  'Kala Jarid (Draft)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF854D0E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        book.title,
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
                        '${book.pageCount} bogag • $chapterCount cutub • $lessonCount cashar',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      const Divider(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => widget.onOpenEditor(book),
                              icon: const Icon(Icons.edit_note_rounded, size: 16),
                              label: const Text('Fur Editor-ka'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _sendToPreview(book),
                              icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                              label: const Text('U gudbi Preview'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0022FF),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
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
    );
  }
}
