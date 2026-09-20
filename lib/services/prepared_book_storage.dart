import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prepared_book.dart';
import 'book_knowledge_storage.dart';
import 'sample_books_data.dart';

class PreparedBookStorage {
  const PreparedBookStorage({SharedPreferences? preferences})
    : _preferences = preferences;

  static const _booksKey = 'prepared_books_manifest';
  final SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  Future<Directory> _pdfDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}prepared_books',
    );
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> savePdf(String bookId, Uint8List bytes) async {
    final directory = await _pdfDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$bookId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> loadPdf(PreparedBook book) async {
    final path = book.originalPdfPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  Future<List<PreparedBook>> loadAll() async {
    final prefs = await _prefs();
    final values = prefs.getStringList(_booksKey) ?? const [];
    return values
        .map((value) {
          try {
            return PreparedBook.decode(value);
          } catch (_) {
            return null;
          }
        })
        .whereType<PreparedBook>()
        .toList();
  }

  Future<List<PreparedBook>> loadPublished() async {
    final all = await loadAll();
    return all.where((book) => book.isPublished).toList();
  }

  Future<List<PreparedBook>> loadDrafts() async {
    final all = await loadAll();
    return all.where((book) => !book.isPublished).toList();
  }

  Future<void> seedSampleBooksIfEmpty(BookKnowledgeStorage knowledgeStorage) async {
    final current = await loadAll();
    if (current.isNotEmpty) return;
    for (final book in SampleBooksData.sampleBooks) {
      await save(book);
    }
    for (final entry in SampleBooksData.sampleKnowledge.entries) {
      await knowledgeStorage.save(entry.value);
    }
  }

  Future<void> resetToSamples(BookKnowledgeStorage knowledgeStorage) async {
    for (final book in SampleBooksData.sampleBooks) {
      await save(book);
    }
    for (final entry in SampleBooksData.sampleKnowledge.entries) {
      await knowledgeStorage.save(entry.value);
    }
  }

  Future<void> save(PreparedBook book) async {
    final prefs = await _prefs();
    final books = await loadAll();
    final index = books.indexWhere((item) => item.id == book.id);
    if (index >= 0) {
      books[index] = book;
    } else {
      books.insert(0, book);
    }
    await prefs.setStringList(
      _booksKey,
      books.map((item) => item.encode()).toList(),
    );
  }

  Future<void> delete(PreparedBook book) async {
    final prefs = await _prefs();
    final books = (await loadAll())
        .where((item) => item.id != book.id)
        .toList();
    await prefs.setStringList(
      _booksKey,
      books.map((item) => item.encode()).toList(),
    );
    final path = book.originalPdfPath;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }
}
