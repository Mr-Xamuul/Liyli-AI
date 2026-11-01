import 'package:flutter/material.dart';

import '../../models/prepared_book.dart';
import '../../services/prepared_book_storage.dart';

/// Stage 5: Maktabadda (Library)
/// The live student library. Books here are fully published and immediately
/// accessible to students in the AI Chat.
class BookLibraryStageView extends StatefulWidget {
  const BookLibraryStageView({
    super.key,
    required this.onOpenChat,
    required this.onUnpublish,
    required this.onOpenEditor,
  });

  final void Function(PreparedBook book) onOpenChat;
  final void Function(PreparedBook book) onUnpublish;
  final void Function(PreparedBook book) onOpenEditor;

  @override
  State<BookLibraryStageView> createState() => _BookLibraryStageViewState();
}

class _BookLibraryStageViewState extends State<BookLibraryStageView> {
  final _bookStorage = const PreparedBookStorage();
  List<PreparedBook> _publishedBooks = const [];
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
      final published = all.where((b) => b.isPublished).toList();
      if (!mounted) return;
      setState(() {
        _publishedBooks = published;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unpublishBook(PreparedBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ka saar Maktabadda?'),
        content: Text(
          'Ma hubtaa inaad buugga "${book.title}" ka saarto maktabadda oo aad dib ugu celiso qabyo (draft)? '
          'Ardaydu ma arki doonaan inta dib loo fasaxayo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Maya')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Ka saar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updated = book.copyWith(
      status: PreparedBookStatus.draft,
      updatedAt: DateTime.now(),
    );
    await _bookStorage.save(updated);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Buugga "${book.title}" dib ayaa loogu celiyey Qabyo (Draft).'),
      ),
    );

    _loadBooks();
    widget.onUnpublish(updated);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'All'
        ? _publishedBooks
        : _publishedBooks.where((b) => b.category == _filter).toList();

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
                  color: const Color(0xFF0022FF).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_library_rounded, color: Color(0xFF60A5FA), size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Talaabada 5: Maktabadda Ardayda (Live Student Library)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tani waa maktabadda tooska ah ee ay ardaydu ka dhex isticmaalayaan abka. Buug kasta oo halkan ku jira '
                      'wuxuu toos ugu xiran yahay Chat-ka ardayda iyo barashada AI-ga.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Filter and stats
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
              '${filtered.length} buug oo firfircoon',
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
                  Icon(Icons.local_library_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Ma jiraan buugaag hadda ku jira qaanaddan.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ka fasax buugaag Talaabada 4 (Diyaar ah) si ay halkan uga soo muuqdaan.',
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
                              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                CircleAvatar(radius: 3, backgroundColor: Color(0xFF16A34A)),
                                SizedBox(width: 5),
                                Text(
                                  'Kujira Chat-ka',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF15803D),
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
                          IconButton(
                            tooltip: 'Ka saar Maktabadda (Draft ka dhig)',
                            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.grey),
                            onPressed: () => _unpublishBook(b),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => widget.onOpenChat(b),
                            icon: const Icon(Icons.forum_outlined, size: 16),
                            label: const Text('Tijaabi Chat-ka'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0022FF),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
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
