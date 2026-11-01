import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prepared_book.dart';
import '../services/book_knowledge_storage.dart';
import '../services/form_preference_storage.dart';
import '../services/gemini_book_chat_service.dart';
import '../services/prepared_book_storage.dart';
import '../services/admin_auth_service.dart';
import '../models/user_profile.dart';
import '../services/supabase_config.dart';
import '../services/user_auth_service.dart';
import '../widgets/student_profile_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.onOpenEditor,
    required this.onOpenChat,
    this.onBackToChat,
    this.onOpenAdmin,
  });

  final void Function(PreparedBook book) onOpenEditor;
  final void Function(
    PreparedBook book, {
    String? chapter,
    String? lesson,
    String? section,
    TutorMode? mode,
  })
  onOpenChat;
  final VoidCallback? onBackToChat;
  final VoidCallback? onOpenAdmin;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _storage = const PreparedBookStorage();
  final _knowledgeStorage = const BookKnowledgeStorage();
  final _formStorage = const FormPreferenceStorage();

  late TabController _tabController;
  List<PreparedBook> _books = const [];
  bool _loading = true;
  RealtimeChannel? _bookChangesChannel;

  static const _shelves = ['Form 1', 'Form 2', 'Form 3', 'Form 4'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: _shelves.length, vsync: this);
    _tabController.addListener(_handleTabChange);
    _subscribeToBookChanges();
    _loadBooks();
  }

  void _subscribeToBookChanges() {
    if (!SupabaseConfig.isInitialized ||
        SupabaseConfig.client.auth.currentSession == null) {
      return;
    }

    final client = SupabaseConfig.client;
    _bookChangesChannel = client
        .channel('student-library-books-${client.auth.currentUser!.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'books',
          callback: (_) {
            // Re-read through PostgREST so the existing RLS policies decide
            // which published books this signed-in user may see.
            _loadBooks(showLoading: false);
          },
        )
        .subscribe();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging &&
        _tabController.index >= 0 &&
        _tabController.index < _shelves.length) {
      unawaited(_persistSelectedForm(_shelves[_tabController.index]));
    }
  }

  Future<void> _persistSelectedForm(String form) async {
    try {
      await UserAuthService.instance.updateCurrentProfile(selectedForm: form);
    } catch (error) {
      debugPrint('Could not save selected student form: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fasalka lama kaydin karin. Isku day mar kale.'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBooks(showLoading: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    final channel = _bookChangesChannel;
    if (channel != null && SupabaseConfig.isInitialized) {
      unawaited(_removeBookChangesChannel(channel));
    }
    super.dispose();
  }

  Future<void> _removeBookChangesChannel(RealtimeChannel channel) async {
    await SupabaseConfig.client.removeChannel(channel);
  }

  Future<void> _loadBooks({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      await _storage.seedSampleBooksIfEmpty(_knowledgeStorage);
      final all = await _storage.loadAll();
      final savedForm = await _formStorage.getSelectedForm();
      final index = _shelves.indexOf(savedForm);
      if (!mounted) return;
      setState(() {
        _books = all;
        _loading = false;
        if (index >= 0 && index < _shelves.length) {
          _tabController.index = index;
        }
      });
    } catch (error) {
      debugPrint('Could not refresh the student library: $error');
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  List<PreparedBook> _booksInShelf(String shelf) {
    return _books.where((b) => b.category == shelf && b.isPublished).toList();
  }

  Future<void> _deleteBook(PreparedBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ma hubtaa inaad tirtirto?'),
        content: Text('Buugga "${book.title}" waxaa laga saarayaa maktabadda.'),
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
      await _storage.delete(book);
      await _loadBooks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Buugga "${book.title}" waa la tirtiray.')),
        );
      }
    }
  }

  Future<void> _changeShelf(PreparedBook book) async {
    final newShelf = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Dooro Qaanadda Cusub'),
        children: _shelves.map((shelf) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, shelf),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    book.category == shelf
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: const Color(0xFF000000),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(shelf, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );

    if (newShelf != null && newShelf != book.category) {
      final updated = book.copyWith(
        category: newShelf,
        updatedAt: DateTime.now(),
      );
      await _storage.save(updated);
      await _loadBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackToChat != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Ku noqo Chat-ka',
                onPressed: widget.onBackToChat,
              )
            : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_library_rounded,
                color: Color(0xFF000000),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Library',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  'Form 1 - Form 4',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AdminAuthService.instance.isAdminNotifier,
            builder: (context, isAdmin, _) {
              if (!isAdmin) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0022FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF0022FF).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (widget.onOpenAdmin != null) {
                      widget.onOpenAdmin!();
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Color(0xFF0022FF),
                          size: 19,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Admin',
                          style: TextStyle(
                            color: Color(0xFF0022FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<UserProfile?>(
            valueListenable: UserAuthService.instance.currentUserNotifier,
            builder: (context, user, _) {
              if (user == null) return const SizedBox.shrink();
              return Tooltip(
                message: 'Profile-ka (${user.displayName})',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    StudentProfileDialog.show(
                      context,
                      onAccountChanged: () {
                        _loadBooks();
                      },
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(user.avatarColorValue),
                      child: Text(
                        user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Dib u cusbooneysii',
            icon: const Icon(Icons.refresh),
            onPressed: _loadBooks,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 3,
              labelColor: const Color(0xFF000000),
              unselectedLabelColor: const Color(0xFF000000),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: _shelves.map((shelf) {
                final count = _booksInShelf(shelf).length;
                return Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(shelf),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: count > 0
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: count > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _shelves.map((shelf) {
                final books = _booksInShelf(shelf);
                if (books.isEmpty) {
                  return _buildEmptyShelf(shelf);
                }
                return _buildBooksGrid(books);
              }).toList(),
            ),
    );
  }

  Widget _buildEmptyShelf(String shelf) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Qaanadda $shelf buug kuma jiro',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Ka soo diyaari buug qeybta Editor-ka kadibna u soo gudbi qaanadda $shelf.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: AdminAuthService.instance.isAdminNotifier,
              builder: (context, isAdmin, _) {
                if (!isAdmin) return const SizedBox.shrink();
                return FilledButton.icon(
                  onPressed: () {
                    // Creates a new book draft in editor
                    final newBook = PreparedBook(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      title: 'Buug Cusub ($shelf)',
                      originalFileName: 'cusub.pdf',
                      pageCount: 1,
                      category: shelf,
                      chapters: const [],
                    );
                    widget.onOpenEditor(newBook);
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Diyaari Buug Cusub ($shelf)'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBooksGrid(List<PreparedBook> books) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : constraints.maxWidth > 600
            ? 2
            : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: constraints.maxWidth > 900
                ? 1.28
                : constraints.maxWidth > 600
                ? 1.0
                : 0.88,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) => _buildBookCard(books[index]),
        );
      },
    );
  }

  Widget _buildBookCard(PreparedBook book) {
    final theme = Theme.of(context);
    final totalLessons = book.chapters.fold<int>(
      0,
      (sum, chapter) => sum + chapter.lessons.length,
    );
    final totalSections = book.chapters.fold<int>(
      0,
      (sum, chapter) =>
          sum +
          chapter.lessons.fold<int>(
            0,
            (lSum, lesson) => lSum + lesson.sections.length,
          ),
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenChat(book),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.book_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                book.category,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF000000),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${book.pageCount} bog',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AdminAuthService.instance.isAdminNotifier,
                    builder: (context, isAdmin, _) {
                      if (!isAdmin) return const SizedBox.shrink();
                      return PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (action) {
                          if (action == 'editor') widget.onOpenEditor(book);
                          if (action == 'shelf') _changeShelf(book);
                          if (action == 'delete') _deleteBook(book);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'editor',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Tafatir Qaybta Editor-ka'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'shelf',
                            child: Row(
                              children: [
                                Icon(Icons.folder_shared_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('U wareeji Qaanad kale'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFF000000),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tirtir',
                                  style: TextStyle(color: Color(0xFF000000)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Badges for Chapters, Lessons, Sections
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _infoBadge(
                    Icons.layers_outlined,
                    '${book.chapters.length} Cutub',
                    theme,
                  ),
                  _infoBadge(
                    Icons.menu_book_outlined,
                    '$totalLessons Cashar',
                    theme,
                  ),
                  _infoBadge(
                    Icons.segment_outlined,
                    '$totalSections Qayb',
                    theme,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => widget.onOpenChat(book),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Baro (AI Chat)'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _showBookChaptersModal(book),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: const Text('Casharada'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AdminAuthService.instance.isAdminNotifier,
                    builder: (context, isAdmin, _) {
                      if (!isAdmin) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: OutlinedButton(
                          onPressed: () => widget.onOpenEditor(book),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: const Icon(Icons.edit_note, size: 20),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookChaptersModal(PreparedBook book) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          final theme = Theme.of(context);
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Dooro cashar ama section si AI-gu PDF-kiisa u dhuuxo',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: book.chapters.length,
                    itemBuilder: (context, cIdx) {
                      final chapter = book.chapters[cIdx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: cIdx == 0,
                          leading: const Icon(
                            Icons.folder_special_rounded,
                            color: Color(0xFF000000),
                          ),
                          title: Text(
                            chapter.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'Bogagga ${chapter.startPage}-${chapter.endPage} • ${chapter.lessons.length} Cashar',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          children: chapter.lessons.map((lesson) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 8,
                                bottom: 6,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ExpansionTile(
                                  leading: const Icon(
                                    Icons.menu_book_rounded,
                                    size: 18,
                                    color: Color(0xFF000000),
                                  ),
                                  title: Text(
                                    lesson.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Bogagga ${lesson.startPage}-${lesson.endPage}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      widget.onOpenChat(
                                        book,
                                        chapter: chapter.title,
                                        lesson: lesson.title,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'Baro AI',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  children: lesson.sections.map((sec) {
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(
                                        left: 24,
                                        right: 8,
                                      ),
                                      leading: const Icon(
                                        Icons.segment,
                                        size: 16,
                                      ),
                                      title: Text(
                                        sec.title,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                      subtitle: Text(
                                        'Bogagga ${sec.startPage}-${sec.endPage}',
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                      trailing: TextButton.icon(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          widget.onOpenChat(
                                            book,
                                            chapter: chapter.title,
                                            lesson: lesson.title,
                                            section: sec.title,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'Baro',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          }).toList(),
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

  Widget _infoBadge(IconData icon, String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
