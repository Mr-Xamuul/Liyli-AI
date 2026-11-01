import 'package:flutter/material.dart';

import '../models/prepared_book.dart';
import '../services/gemini_book_chat_service.dart';
import 'admin_dashboard_screen.dart';
import 'book_chat_screen.dart';
import 'library_screen.dart';
import 'prepared_book_editor_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  // 0 = AI Chat, 1 = Library, 2 = Admin Dashboard, 3 = Editor
  int _currentIndex = 0;

  PreparedBook? _chatBook;
  String? _chatChapter;
  String? _chatLesson;
  String? _chatSection;
  TutorMode? _chatMode;

  PreparedBook? _editorBook;
  int _editorInitialTabIndex = 0;
  int? _editorChapterIndex;
  int? _editorLessonIndex;
  int? _editorSectionIndex;
  bool _editorReturnToPreview = false;

  void _openChatWithBook(
    PreparedBook book, {
    String? chapter,
    String? lesson,
    String? section,
    TutorMode? mode,
  }) {
    setState(() {
      _chatBook = book;
      _chatChapter = chapter;
      _chatLesson = lesson;
      _chatSection = section;
      _chatMode = mode;
      _currentIndex = 0; // Open AI Chat Screen
    });
  }

  void _openEditorWithBook(PreparedBook book, {int initialTabIndex = 0}) {
    setState(() {
      _editorBook = book;
      _editorInitialTabIndex = initialTabIndex;
      _editorChapterIndex = null;
      _editorLessonIndex = null;
      _editorSectionIndex = null;
      _editorReturnToPreview = false;
      _currentIndex = 3; // Editor Screen
    });
  }

  void _goToLibrary() {
    setState(() {
      _currentIndex = 1; // Library Screen
    });
  }

  void _goToChat() {
    setState(() {
      _currentIndex = 0; // AI Chat Screen
    });
  }

  int _adminRefreshKey = 0;
  int _adminSidebarIndex = 0;
  int _adminBookStageIndex = 0;
  PreparedBook? _adminTargetBook;

  void _goToAdminDashboard({
    int sidebarIndex = 0,
    int bookStageIndex = 0,
    PreparedBook? book,
  }) {
    setState(() {
      _adminRefreshKey++;
      _adminSidebarIndex = sidebarIndex;
      _adminBookStageIndex = bookStageIndex;
      _adminTargetBook = book;
      _currentIndex = 2; // Admin Dashboard
    });
  }

  void _goToAdminPreview(PreparedBook book) {
    _goToAdminDashboard(
      sidebarIndex: 1, // Book Management
      bookStageIndex: 2, // Preview Stage
      book: book,
    );
  }

  void _goToEditor({
    PreparedBook? book,
    int initialTabIndex = 0,
    int? chapterIndex,
    int? lessonIndex,
    int? sectionIndex,
    bool returnToPreview = false,
  }) {
    setState(() {
      _editorBook = book;
      _editorInitialTabIndex = initialTabIndex;
      _editorChapterIndex = chapterIndex;
      _editorLessonIndex = lessonIndex;
      _editorSectionIndex = sectionIndex;
      _editorReturnToPreview = returnToPreview;
      _currentIndex = 3; // Editor Screen
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      // 0: AI Study Tutor (Primary screen on launch)
      BookChatScreen(
        key: ValueKey(
          '${_chatBook?.id}_${_chatChapter}_${_chatLesson}_${_chatSection}_$_chatMode',
        ),
        book: _chatBook,
        initialChapter: _chatChapter,
        initialLesson: _chatLesson,
        initialSection: _chatSection,
        initialMode: _chatMode,
        onOpenLibrary: _goToLibrary,
        onOpenEditor: _goToAdminDashboard,
        onOpenAdmin: _goToAdminDashboard,
      ),
      // 1: Maktabadda (Library)
      LibraryScreen(
        onOpenChat: _openChatWithBook,
        onOpenEditor: (book) => _openEditorWithBook(book, initialTabIndex: 0),
        onOpenAdmin: _goToAdminDashboard,
        onBackToChat: _goToChat,
      ),
      // 2: Admin Dashboard (Dedicated admin hub)
      AdminDashboardScreen(
        key: ValueKey(
          'admin_dashboard_${_adminRefreshKey}_${_adminSidebarIndex}_${_adminBookStageIndex}_${_adminTargetBook?.id}',
        ),
        initialSidebarIndex: _adminSidebarIndex,
        initialBookStageIndex: _adminBookStageIndex,
        initialBook: _adminTargetBook,
        onOpenEditor: _goToEditor,
        onBackToChat: _goToChat,
        onOpenLibrary: _goToLibrary,
        onOpenChatWithBook: _openChatWithBook,
      ),
      // 3: Book Editor & AI Manage
      PreparedBookEditorScreen(
        key: ValueKey(
          '${_editorBook?.id ?? 'default_editor'}_${_editorInitialTabIndex}_${_editorChapterIndex}_${_editorLessonIndex}_$_editorReturnToPreview',
        ),
        initialBook: _editorBook,
        initialTabIndex: _editorInitialTabIndex,
        initialChapterIndex: _editorChapterIndex,
        initialLessonIndex: _editorLessonIndex,
        initialSectionIndex: _editorSectionIndex,
        returnToPreview: _editorReturnToPreview,
        onOpenChat: _openChatWithBook,
        onOpenLibrary: _goToLibrary,
        onBackToChat: _goToChat,
        onBackToAdmin: () => _goToAdminDashboard(),
        onGoToPreview: _goToAdminPreview,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
    );
  }
}
