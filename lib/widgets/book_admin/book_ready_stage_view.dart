import 'package:flutter/material.dart';

import '../../models/prepared_book.dart';
import '../../services/prepared_book_storage.dart';

/// Stage 4: Buugaagta Diyaarka ah (Ready to Publish)
/// Holds books that have completed Preview & verification and are waiting
/// for official admin release into the student library.
class BookReadyStageView extends StatefulWidget {
  const BookReadyStageView({
    super.key,
    required this.onPublishToLibrary,
    required this.onReturnToPreview,
    required this.onOpenEditor,
  });

  final void Function(PreparedBook book) onPublishToLibrary;
  final void Function(PreparedBook book) onReturnToPreview;
  final void Function(PreparedBook book) onOpenEditor;

  @override
  State<BookReadyStageView> createState() => _BookReadyStageViewState();
}

class _BookReadyStageViewState extends State<BookReadyStageView> {
  final _bookStorage = const PreparedBookStorage();
  List<PreparedBook> _readyBooks = const [];
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
      final ready = all.where((b) => b.isReady).toList();
      if (!mounted) return;
      setState(() {
        _readyBooks = ready;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publishBook(PreparedBook book) async {
    final updated = book.copyWith(
      status: PreparedBookStatus.published,
      updatedAt: DateTime.now(),
    );
    await _bookStorage.save(updated);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buugga "${book.title}" waxaa si toos ah loogu fasaxay Maktabadda!'),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );

    widget.onPublishToLibrary(updated);
  }

  Future<void> _revertToReview(PreparedBook book) async {
    final updated = book.copyWith(
      status: PreparedBookStatus.review,
      updatedAt: DateTime.now(),
    );
    await _bookStorage.save(updated);
    if (!mounted) return;
    widget.onReturnToPreview(updated);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'All'
        ? _readyBooks
        : _readyBooks.where((b) => b.category == _filter).toList();

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
                  color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified_rounded, color: Color(0xFF4ADE80), size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Talaabada 4: Buugaagta Diyaarka ah (Ready to Publish)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Qaybtan waxaa lagu hayaa buugaagta soo maray hubinta tayada xuduudaha ee diyaarka u ah '
                      'in ardayda loo fasaxo. Marka la riixo "Fasax / Maktabadda", buuggu wuxuu si toos ah uga muuqanayaa '
                      'maktabadda ardayda iyo chat-ka AI-ga.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Filter & Controls
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
                  selectedColor: const Color(0xFF16A34A),
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
              '${filtered.length} buug oo diyaar ah',
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

        // List / Grid
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
                  Icon(Icons.inventory_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Ma jiraan buugaag hadda ku jira marxaladda Diyaar ah.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hubi buug ku jira Talaabada 3 (Preview) si aad halkan ugu soo gudbiso.',
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
                mainAxisExtent: 220,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, idx) {
                final b = filtered[idx];
                final chapterCount = b.chapters.length;
                final lessonCount = b.chapters.fold<int>(
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
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                                SizedBox(width: 4),
                                Text(
                                  'Diyaar u ah Fasaxidda',
                                  style: TextStyle(
                                    fontSize: 10.5,
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
                        '${b.pageCount} bogag • $chapterCount cutub • $lessonCount cashar',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      const Divider(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _revertToReview(b),
                            icon: const Icon(Icons.undo_rounded, size: 15),
                            label: const Text('Dib u eeg'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _publishBook(b),
                              icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                              label: const Text('Fasax / Maktabadda ➔'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                padding: const EdgeInsets.symmetric(vertical: 9),
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
