import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prepared_book.dart';
import 'book_knowledge_storage.dart';
import 'sample_books_data.dart';
import 'supabase_config.dart';

class PreparedBookStorage {
  const PreparedBookStorage({SharedPreferences? preferences})
    : _preferences = preferences;

  static const _booksKey = 'prepared_books_manifest';
  static const _remotePdfPrefix = 'supabase://book-pdfs/';
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
    if (SupabaseConfig.isInitialized && _isRemotePdfPath(path)) {
      return SupabaseConfig.client.storage
          .from('book-pdfs')
          .download(_remoteObjectPath(path));
    }
    final file = File(path);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  Future<List<PreparedBook>> loadAll() async {
    if (SupabaseConfig.isInitialized) {
      if (SupabaseConfig.client.auth.currentSession == null) return const [];
      final rows = await SupabaseConfig.client
          .from('books')
          .select(
            'id,title,form,page_count,is_published,pdf_path,metadata,created_at,updated_at',
          )
          .order('created_at', ascending: false);
      return rows.map(_bookFromRemote).toList();
    }
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

  Future<PreparedBook?> getBookById(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((book) => book.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<PreparedBook>> loadPublished() async {
    final all = await loadAll();
    return all.where((book) => book.isPublished).toList();
  }

  Future<List<PreparedBook>> loadDrafts() async {
    final all = await loadAll();
    return all.where((book) => !book.isPublished).toList();
  }

  Future<void> seedSampleBooksIfEmpty(
    BookKnowledgeStorage knowledgeStorage,
  ) async {
    if (SupabaseConfig.isInitialized) return;
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
    if (SupabaseConfig.isInitialized) return;
    for (final book in SampleBooksData.sampleBooks) {
      await save(book);
    }
    for (final entry in SampleBooksData.sampleKnowledge.entries) {
      await knowledgeStorage.save(entry.value);
    }
  }

  Future<void> save(PreparedBook book) async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      if (client.auth.currentSession == null) {
        throw StateError(
          'Waa inaad gashaa akoon maamulka si buug loo kaydiyo.',
        );
      }
      final localPath = book.originalPdfPath;
      var remotePath = localPath == null || localPath.isEmpty
          ? '${book.id}/original.pdf'
          : _remoteObjectPath(localPath);
      if (localPath != null && !_isRemotePdfPath(localPath)) {
        final file = File(localPath);
        if (file.existsSync()) {
          remotePath = '${book.id}/original.pdf';
          await client.storage
              .from('book-pdfs')
              .upload(
                remotePath,
                file,
                fileOptions: const FileOptions(
                  contentType: 'application/pdf',
                  upsert: true,
                ),
              );
        }
      }
      await client.from('books').upsert({
        'id': book.id,
        'title': book.title,
        'subject': '',
        'form': book.category,
        'description': '',
        'pdf_path': remotePath,
        'page_count': book.pageCount,
        'is_published': book.isPublished,
        'created_by': client.auth.currentUser!.id,
        'metadata': book.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return;
    }
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
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      if (client.auth.currentSession == null) {
        throw StateError(
          'Waa inaad gashaa akoon maamulka si buug loo tirtiro.',
        );
      }
      final path = book.originalPdfPath;
      if (path != null && _isRemotePdfPath(path)) {
        await client.storage.from('book-pdfs').remove([
          _remoteObjectPath(path),
        ]);
      }
      await client.from('books').delete().eq('id', book.id);
      return;
    }
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

  PreparedBook _bookFromRemote(Map<String, dynamic> row) {
    final rawMetadata = row['metadata'];
    final metadata = rawMetadata is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawMetadata)
        : <String, dynamic>{};
    metadata['id'] = row['id'];
    metadata['title'] = row['title'];
    metadata['category'] = row['form'];
    metadata['pageCount'] = row['page_count'];
    if (row['is_published'] == true) metadata['status'] = 'published';
    metadata['originalPdfPath'] = '$_remotePdfPrefix${row['pdf_path']}';
    metadata['createdAt'] ??= row['created_at'];
    metadata['updatedAt'] ??= row['updated_at'];
    return PreparedBook.fromJson(metadata);
  }

  bool _isRemotePdfPath(String path) {
    if (path.startsWith(_remotePdfPrefix)) return true;
    if (!SupabaseConfig.isInitialized) return false;
    final isAbsolutePath =
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.startsWith(r'\\');
    // Legacy Supabase object keys are relative paths using forward slashes.
    return !isAbsolutePath && !path.contains(r'\');
  }

  String _remoteObjectPath(String path) => path.startsWith(_remotePdfPrefix)
      ? path.substring(_remotePdfPrefix.length)
      : path;
}
