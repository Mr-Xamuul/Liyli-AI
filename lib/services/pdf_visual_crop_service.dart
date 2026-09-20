import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Renders only the requested rectangle of a PDF page as a compact PNG.
class PdfVisualCropService {
  const PdfVisualCropService();

  Future<String?> saveThumbnail(Uint8List bytes, {required String id}) async {
    if (bytes.isEmpty) return null;
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}chat_visuals',
    );
    if (!directory.existsSync()) await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$id.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> cropPage({
    required Uint8List pdfBytes,
    required int pageNumber,
    required double left,
    required double top,
    required double width,
    required double height,
  }) async {
    if (pdfBytes.isEmpty || pageNumber < 1) return null;

    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(
      pdfBytes,
      sourceName: 'leyli-visual-$pageNumber',
    );
    PdfImage? rendered;
    try {
      if (pageNumber > document.pages.length) return null;
      final page = await document.pages[pageNumber - 1].ensureLoaded();
      const fullWidth = 1200.0;
      final fullHeight = (fullWidth * page.height / page.width).roundToDouble();
      final safeLeft = left.clamp(0.0, 0.95);
      final safeTop = top.clamp(0.0, 0.95);
      final safeWidth = width.clamp(0.05, 1.0 - safeLeft);
      final safeHeight = height.clamp(0.05, 1.0 - safeTop);

      rendered = await page.render(
        x: (safeLeft * fullWidth).round(),
        y: (safeTop * fullHeight).round(),
        width: (safeWidth * fullWidth).round(),
        height: (safeHeight * fullHeight).round(),
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );
      if (rendered == null) return null;

      final buffer = await ui.ImmutableBuffer.fromUint8List(rendered.pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: rendered.width,
        height: rendered.height,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return png?.buffer.asUint8List();
    } finally {
      rendered?.dispose();
      await document.dispose();
    }
  }
}
