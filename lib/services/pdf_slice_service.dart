import 'dart:typed_data';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfSliceService {
  const PdfSliceService();

  /// Slices [sourcePdfBytes] from [startPage] to [endPage] (inclusive, 1-indexed).
  ///
  /// If [startPosition] (0.0 to 1.0) and [endPosition] (0.0 to 1.0) are specified,
  /// the sliced PDF will be precisely cropped vertically to only include the exact
  /// content of the section, cutting away preceding and succeeding sections on the
  /// boundary pages.
  Uint8List slicePdf({
    required Uint8List sourcePdfBytes,
    required int startPage,
    required int endPage,
    double startPosition = 0.0,
    double endPosition = 1.0,
  }) {
    final sourceDoc = PdfDocument(inputBytes: sourcePdfBytes);
    final targetDoc = PdfDocument();
    try {
      final totalPages = sourceDoc.pages.count;
      if (totalPages == 0) {
        throw ArgumentError('Source PDF has no pages.');
      }
      final clampedStart = startPage.clamp(1, totalPages);
      final clampedEnd = endPage.clamp(clampedStart, totalPages);

      final cleanStartPos = startPosition.clamp(0.0, 1.0);
      final cleanEndPos = endPosition.clamp(0.0, 1.0);

      targetDoc.pageSettings.setMargins(0);

      final isSinglePage = (clampedStart == clampedEnd);

      for (var pageNum = clampedStart; pageNum <= clampedEnd; pageNum++) {
        final sourcePage = sourceDoc.pages[pageNum - 1];
        final template = sourcePage.createTemplate();
        final pageWidth = sourcePage.size.width;
        final pageHeight = sourcePage.size.height;

        double cropTopRatio = 0.0;
        double cropBottomRatio = 1.0;

        if (isSinglePage) {
          final top = cleanStartPos < cleanEndPos ? cleanStartPos : cleanEndPos;
          final bottom = cleanStartPos < cleanEndPos ? cleanEndPos : cleanStartPos;
          cropTopRatio = top;
          cropBottomRatio = (bottom > top + 0.01) ? bottom : (top + 0.05).clamp(0.0, 1.0);
        } else {
          if (pageNum == clampedStart) {
            // First page: start at cleanStartPos and go to the bottom of the page
            cropTopRatio = cleanStartPos;
            cropBottomRatio = 1.0;
          } else if (pageNum == clampedEnd) {
            // Last page: start from top of the page and end at cleanEndPos
            cropTopRatio = 0.0;
            cropBottomRatio = cleanEndPos > 0.0 ? cleanEndPos : 1.0;
          } else {
            // Intermediate pages: full page
            cropTopRatio = 0.0;
            cropBottomRatio = 1.0;
          }
        }

        // Apply slicing: if crop ratio specifies a partial vertical slice
        final shouldCrop = (cropTopRatio > 0.005) || (cropBottomRatio < 0.995);

        if (shouldCrop) {
          final topY = pageHeight * cropTopRatio;
          final bottomY = pageHeight * cropBottomRatio;
          final sliceHeight = (bottomY - topY).clamp(10.0, pageHeight);

          // Crop strictly to the designated boundary height so preceding/succeeding
          // sections and empty trailing space are not included in the sliced document.
          targetDoc.pageSettings.setMargins(0);
          targetDoc.pageSettings.orientation = (sliceHeight < pageWidth)
              ? PdfPageOrientation.landscape
              : PdfPageOrientation.portrait;
          targetDoc.pageSettings.size = Size(pageWidth, sliceHeight);

          final newPage = targetDoc.pages.add();

          // Clip to slice window and draw the template shifted up
          newPage.graphics.save();
          newPage.graphics.setClip(bounds: Rect.fromLTWH(0, 0, pageWidth, sliceHeight));
          newPage.graphics.drawPdfTemplate(
            template,
            Offset(0, -topY),
            sourcePage.size,
          );
          newPage.graphics.restore();
        } else {
          targetDoc.pageSettings.setMargins(0);
          targetDoc.pageSettings.orientation = PdfPageOrientation.portrait;
          targetDoc.pageSettings.size = sourcePage.size;

          final newPage = targetDoc.pages.add();
          newPage.graphics.drawPdfTemplate(
            template,
            const Offset(0, 0),
            sourcePage.size,
          );
        }
      }

      final bytes = targetDoc.saveSync();
      return Uint8List.fromList(bytes);
    } finally {
      targetDoc.dispose();
      sourceDoc.dispose();
    }
  }

  /// Generates a valid PDF containing the lesson content when no physical PDF file exists.
  Uint8List createPdfFromKnowledge({
    required String bookTitle,
    required String scopeTitle,
    required String grade,
    required Map<int, String> pageContents,
  }) {
    final doc = PdfDocument();
    try {
      doc.pageSettings.setMargins(30);
      final fontTitle = PdfStandardFont(
        PdfFontFamily.helvetica,
        15,
        style: PdfFontStyle.bold,
      );
      final fontSubtitle = PdfStandardFont(
        PdfFontFamily.helvetica,
        11,
        style: PdfFontStyle.bold,
      );
      final fontBody = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final fontPageNum = PdfStandardFont(
        PdfFontFamily.helvetica,
        9,
        style: PdfFontStyle.italic,
      );

      final sortedPages = pageContents.keys.toList()..sort();

      if (sortedPages.isEmpty) {
        final page = doc.pages.add();
        page.graphics.drawString(
          '$bookTitle ($grade)\n$scopeTitle\n\n(Qoraalka qaybtaan weli lama diyaarin)',
          fontBody,
          bounds: Rect.fromLTWH(
            0,
            0,
            page.getClientSize().width,
            page.getClientSize().height,
          ),
        );
      } else {
        for (final pageNum in sortedPages) {
          final page = doc.pages.add();
          final text = pageContents[pageNum] ?? '';
          final clientSize = page.getClientSize();

          // Header
          page.graphics.drawString(
            '$bookTitle • $grade',
            fontSubtitle,
            bounds: Rect.fromLTWH(0, 0, clientSize.width, 18),
          );
          page.graphics.drawString(
            'Qaybta: $scopeTitle',
            fontTitle,
            bounds: Rect.fromLTWH(0, 20, clientSize.width, 22),
          );
          page.graphics.drawLine(
            PdfPen(PdfColor(120, 120, 120), width: 0.5),
            const Offset(0, 46),
            Offset(clientSize.width, 46),
          );

          // Content
          final textElement = PdfTextElement(
            text: text.trim().isEmpty ? 'Nuxurka boggan...' : text,
            font: fontBody,
            format: PdfStringFormat(lineSpacing: 2),
          );
          textElement.draw(
            page: page,
            bounds: Rect.fromLTWH(
              0,
              54,
              clientSize.width,
              clientSize.height - 75,
            ),
          );

          // Footer
          page.graphics.drawString(
            'Bogga: $pageNum',
            fontPageNum,
            bounds: Rect.fromLTWH(
              0,
              clientSize.height - 15,
              clientSize.width,
              15,
            ),
            format: PdfStringFormat(alignment: PdfTextAlignment.right),
          );
        }
      }

      final bytes = doc.saveSync();
      return Uint8List.fromList(bytes);
    } finally {
      doc.dispose();
    }
  }
}
