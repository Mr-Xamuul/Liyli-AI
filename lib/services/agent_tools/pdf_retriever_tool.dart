import 'dart:typed_data';

import '../../models/book_knowledge.dart';
import '../../models/prepared_book.dart';
import '../book_knowledge_storage.dart';
import '../pdf_slice_service.dart';
import '../prepared_book_storage.dart';

class PdfRetrieverResult {
  const PdfRetrieverResult({
    required this.bookId,
    required this.bookTitle,
    required this.startPage,
    required this.endPage,
    required this.pageCount,
    this.slicedPdfBytes,
    this.extractedTextSummary,
    required this.isPdfSourceAvailable,
    required this.latencyMs,
    required this.summaryReason,
  });

  final String bookId;
  final String bookTitle;
  final int startPage;
  final int endPage;
  final int pageCount;
  final Uint8List? slicedPdfBytes;
  final String? extractedTextSummary;
  final bool isPdfSourceAvailable;
  final int latencyMs;
  final String summaryReason;

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'bookTitle': bookTitle,
    'startPage': startPage,
    'endPage': endPage,
    'pageCount': pageCount,
    'hasPdfBytes': slicedPdfBytes != null && slicedPdfBytes!.isNotEmpty,
    'pdfBytesSize': slicedPdfBytes?.length ?? 0,
    if (extractedTextSummary != null)
      'hasTextSummary': extractedTextSummary!.isNotEmpty,
    'isPdfSourceAvailable': isPdfSourceAvailable,
    'latencyMs': latencyMs,
    'summaryReason': summaryReason,
  };
}

class PdfRetrieverTool {
  PdfRetrieverTool({
    PreparedBookStorage? bookStorage,
    PdfSliceService? sliceService,
    BookKnowledgeStorage? knowledgeStorage,
  }) : _bookStorage = bookStorage ?? const PreparedBookStorage(),
       _sliceService = sliceService ?? const PdfSliceService(),
       _knowledgeStorage = knowledgeStorage ?? const BookKnowledgeStorage();

  final PreparedBookStorage _bookStorage;
  final PdfSliceService _sliceService;
  final BookKnowledgeStorage _knowledgeStorage;

  Future<PdfRetrieverResult> retrieveContent({
    required PreparedBook book,
    required int startPage,
    required int endPage,
    String? lessonId,
    double startPosition = 0.0,
    double endPosition = 1.0,
  }) async {
    final stopwatch = Stopwatch()..start();
    final clampedStart = startPage > 0 ? startPage : 1;
    final clampedEnd = endPage >= clampedStart ? endPage : clampedStart;
    final pageCount = (clampedEnd - clampedStart) + 1;

    // 1. Try loading raw PDF bytes from local storage
    Uint8List? slicedBytes;
    bool pdfAvailable = false;

    try {
      final rawPdfBytes = await _bookStorage.loadPdf(book);
      if (rawPdfBytes != null && rawPdfBytes.isNotEmpty) {
        pdfAvailable = true;
        slicedBytes = _sliceService.slicePdf(
          sourcePdfBytes: rawPdfBytes,
          startPage: clampedStart,
          endPage: clampedEnd,
          startPosition: startPosition,
          endPosition: endPosition,
        );
      }
    } catch (_) {
      // PDF slice fallback
      pdfAvailable = false;
    }

    // 2. Fetch structured knowledge / textbook notes if available
    String? knowledgeSummary;
    try {
      final knowledge = await _knowledgeStorage.load(book.id);
      if (knowledge != null && knowledge.pages.isNotEmpty) {
        final parts = <String>[];
        for (var page = clampedStart; page <= clampedEnd; page++) {
          final pageContent = knowledge.pages[page];
          if (pageContent != null && pageContent.trim().isNotEmpty) {
            parts.add('Bogga $page: ${pageContent.trim()}');
          }
        }
        if (parts.isNotEmpty) {
          knowledgeSummary = parts.join('\n\n');
        }
      }
    } catch (_) {
      // Knowledge lookup fallback
    }

    stopwatch.stop();

    final reason = pdfAvailable
        ? 'Waxaa si guul leh loo gooyay bogagga $clampedStart-$clampedEnd ee PDF-ka (${slicedBytes?.length ?? 0} bytes).'
        : 'Faylka PDF-ka ee disk-ga ma oollin, waxaa la isticmaalay qoraalka keydka xogta manhajka (Knowledge summary).';

    return PdfRetrieverResult(
      bookId: book.id,
      bookTitle: book.title,
      startPage: clampedStart,
      endPage: clampedEnd,
      pageCount: pageCount,
      slicedPdfBytes: slicedBytes,
      extractedTextSummary: knowledgeSummary,
      isPdfSourceAvailable: pdfAvailable,
      latencyMs: stopwatch.elapsedMilliseconds,
      summaryReason: reason,
    );
  }
}
