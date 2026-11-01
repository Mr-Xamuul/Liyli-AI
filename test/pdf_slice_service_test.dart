import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/services/pdf_slice_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('PdfSliceService Tests', () {
    const service = PdfSliceService();

    test('createPdfFromKnowledge generates valid PDF bytes with page count matching map', () {
      final bytes = service.createPdfFromKnowledge(
        bookTitle: 'Sayniska Fasalka 1aad',
        scopeTitle: 'Casharka 1: Unugyada',
        grade: 'Form 1',
        pageContents: {
          1: 'Qoraalka bogga kowaad ee unugga.',
          2: 'Qoraalka bogga labaad ee unugga.',
          3: 'Qoraalka bogga saddexaad ee unugga.',
        },
      );

      expect(bytes, isNotEmpty);
      final doc = PdfDocument(inputBytes: bytes);
      expect(doc.pages.count, equals(3));
      doc.dispose();
    });

    test('slicePdf slices exact pages from source PDF', () {
      // First create a 5-page PDF
      final initialDoc = PdfDocument();
      for (var i = 1; i <= 5; i++) {
        final page = initialDoc.pages.add();
        page.graphics.drawString(
          'Bogga $i',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
      }
      final sourceBytes = Uint8List.fromList(initialDoc.saveSync());
      initialDoc.dispose();

      // Slice pages 2 to 4 (inclusive -> 3 pages)
      final slicedBytes = service.slicePdf(
        sourcePdfBytes: sourceBytes,
        startPage: 2,
        endPage: 4,
      );

      final slicedDoc = PdfDocument(inputBytes: slicedBytes);
      expect(slicedDoc.pages.count, equals(3));
      slicedDoc.dispose();
    });

    test('slicePdf clamps pages properly if requested outside bounds', () {
      final initialDoc = PdfDocument();
      for (var i = 1; i <= 3; i++) {
        initialDoc.pages.add();
      }
      final sourceBytes = Uint8List.fromList(initialDoc.saveSync());
      initialDoc.dispose();

      // Request 2 to 10 on 3-page doc -> should clamp to 2..3 (2 pages)
      final slicedBytes = service.slicePdf(
        sourcePdfBytes: sourceBytes,
        startPage: 2,
        endPage: 10,
      );

      final slicedDoc = PdfDocument(inputBytes: slicedBytes);
      expect(slicedDoc.pages.count, equals(2));
      slicedDoc.dispose();
    });

    test('slicePdf crops pages vertically when startPosition and endPosition are specified', () {
      final initialDoc = PdfDocument();
      for (var i = 1; i <= 3; i++) {
        final page = initialDoc.pages.add();
        page.graphics.drawString(
          'Bogga $i - Qoraalka Sare',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
          bounds: Rect.fromLTWH(20, 50, 200, 30),
        );
        page.graphics.drawString(
          'Bogga $i - Qoraalka Dhexe (Section)',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
          bounds: Rect.fromLTWH(20, 300, 250, 30),
        );
        page.graphics.drawString(
          'Bogga $i - Qoraalka Hoose',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
          bounds: Rect.fromLTWH(20, 600, 200, 30),
        );
      }
      final sourceBytes = Uint8List.fromList(initialDoc.saveSync());
      initialDoc.dispose();

      // Test single page cropping (e.g. page 2 from 0.25 to 0.70)
      final croppedSingle = service.slicePdf(
        sourcePdfBytes: sourceBytes,
        startPage: 2,
        endPage: 2,
        startPosition: 0.25,
        endPosition: 0.70,
      );

      final docSingle = PdfDocument(inputBytes: croppedSingle);
      expect(docSingle.pages.count, equals(1));
      expect(croppedSingle.isNotEmpty, isTrue);
      docSingle.dispose();

      // Test multi-page cropping (page 1 from 0.40 to page 2 up to 0.50)
      final croppedMulti = service.slicePdf(
        sourcePdfBytes: sourceBytes,
        startPage: 1,
        endPage: 2,
        startPosition: 0.40,
        endPosition: 0.50,
      );

      final docMulti = PdfDocument(inputBytes: croppedMulti);
      expect(docMulti.pages.count, equals(2));
      docMulti.dispose();
    });
  });
}
