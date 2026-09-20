import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_knowledge.dart';

class BookKnowledgeStorage {
  const BookKnowledgeStorage({SharedPreferences? preferences})
    : _preferences = preferences;

  final SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  Future<void> save(BookKnowledge knowledge) async {
    final prefs = await _prefs();
    await prefs.setString(
      'book_knowledge_${knowledge.bookId}',
      knowledge.encode(),
    );
  }

  Future<BookKnowledge?> load(String bookId) async {
    final value = (await _prefs()).getString('book_knowledge_$bookId');
    if (value == null || value.isEmpty) return null;
    try {
      return BookKnowledge.decode(value);
    } catch (_) {
      return null;
    }
  }
}
