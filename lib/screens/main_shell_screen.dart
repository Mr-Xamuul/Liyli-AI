import 'package:flutter/material.dart';

import '../models/prepared_book.dart';
import '../services/gemini_book_chat_service.dart';
import 'book_chat_screen.dart';
import 'library_screen.dart';
import 'prepared_book_editor_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  // Requirement 2: Default to AI Chat on app launch
  int _currentIndex = 0; // 0 = AI Chat, 1 = Library, 2 = Editor

  PreparedBook? _chatBook;
  String? _chatChapter;
  String? _chatLesson;
  String? _chatSection;
  TutorMode? _chatMode;

  PreparedBook? _editorBook;

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

  void _openEditorWithBook(PreparedBook book) {
    setState(() {
      _editorBook = book;
      _currentIndex = 2; // Editor Screen
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

  void _goToEditor() {
    setState(() {
      _currentIndex = 2; // Editor Screen
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
        onOpenEditor: _goToEditor,
      ),
      // 1: Maktabadda
      LibraryScreen(
        onOpenChat: _openChatWithBook,
        onOpenEditor: _openEditorWithBook,
        onBackToChat: _goToChat,
      ),
      // 2: Book Editor
      PreparedBookEditorScreen(
        key: ValueKey(_editorBook?.id ?? 'default_editor'),
        initialBook: _editorBook,
        onOpenChat: _openChatWithBook,
        onOpenLibrary: _goToLibrary,
        onBackToChat: _goToChat,
      ),
    ];

    // Requirement 1: Removed bottom navbar
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
    );
  }
}
