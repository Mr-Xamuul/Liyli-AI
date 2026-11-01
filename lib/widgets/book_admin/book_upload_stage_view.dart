import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../models/prepared_book.dart';
import '../../models/book_knowledge.dart';
import '../../services/prepared_book_storage.dart';
import '../../services/book_knowledge_storage.dart';

/// Stage 1: Upload (Soo Gelinta Buugga)
/// Allows admin to select a PDF file, specify the book title and grade/category,
/// parses total page count, and displays a card with book details and a clear
/// call to action: "U gudbi Editor-ka".
class BookUploadStageView extends StatefulWidget {
  const BookUploadStageView({
    super.key,
    required this.onOpenEditor,
    required this.onBookCreated,
  });

  final void Function(PreparedBook book) onOpenEditor;
  final VoidCallback onBookCreated;

  @override
  State<BookUploadStageView> createState() => _BookUploadStageViewState();
}

class _BookUploadStageViewState extends State<BookUploadStageView> {
  final _bookStorage = const PreparedBookStorage();
  final _titleController = TextEditingController();

  String _selectedCategory = 'Form 1';
  Uint8List? _pickedPdfBytes;
  String? _pickedFileName;
  int _pickedPageCount = 0;
  bool _isProcessing = false;
  String? _statusMessage;
  PreparedBook? _newlyUploadedBook;

  List<PreparedBook> _recentDrafts = const [];
  bool _loadingDrafts = true;

  @override
  void initState() {
    super.initState();
    _loadRecentDrafts();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentDrafts() async {
    setState(() => _loadingDrafts = true);
    try {
      final all = await _bookStorage.loadAll();
      final drafts = all.where((b) => b.isDraft).toList();
      if (!mounted) return;
      setState(() {
        _recentDrafts = drafts;
        _loadingDrafts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _pickPdfFile() async {
    setState(() => _statusMessage = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        setState(() => _statusMessage = 'PDF-ga la doortay xog ma lahan.');
        return;
      }

      setState(() => _isProcessing = true);

      // Parse page count using Syncfusion
      final doc = PdfDocument(inputBytes: bytes);
      final pageCount = doc.pages.count;
      doc.dispose();

      final cleanName = file.name.replaceAll('.pdf', '').replaceAll('_', ' ');
      final title = cleanName[0].toUpperCase() + cleanName.substring(1);

      setState(() {
        _pickedPdfBytes = bytes;
        _pickedFileName = file.name;
        _pickedPageCount = pageCount;
        _titleController.text = title;
        _isProcessing = false;
        _newlyUploadedBook = null;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Khalad ayaa dhacay xilligii PDF-ka la furayay: $e';
      });
    }
  }

  Future<void> _saveAndPrepareBook() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _statusMessage = 'Fadlan geli magaca buugga.');
      return;
    }
    if (_pickedPdfBytes == null || _pickedPageCount <= 0) {
      setState(() => _statusMessage = 'Fadlan marka hore dooro fayl PDF ah.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final bookId = 'book-${DateTime.now().millisecondsSinceEpoch}';
      final pdfPath = await _bookStorage.savePdf(bookId, _pickedPdfBytes!);

      final newBook = PreparedBook(
        id: bookId,
        title: title,
        originalFileName: _pickedFileName ?? '$title.pdf',
        pageCount: _pickedPageCount,
        category: _selectedCategory,
        originalPdfPath: pdfPath,
        chapters: const [],
        status: PreparedBookStatus.draft,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Extract digital text from already OCR'd PDF for AI Chat knowledge base
      try {
        final doc = PdfDocument(inputBytes: _pickedPdfBytes!);
        final pageTexts = <int, String>{};
        for (var i = 0; i < _pickedPageCount; i++) {
          final t = PdfTextExtractor(
            doc,
          ).extractText(startPageIndex: i, endPageIndex: i);
          pageTexts[i + 1] = t;
        }
        doc.dispose();
        await const BookKnowledgeStorage().save(
          BookKnowledge(bookId: bookId, pages: pageTexts),
        );
      } catch (_) {}

      await _bookStorage.save(newBook);
      widget.onBookCreated();

      if (!mounted) return;
      setState(() {
        _newlyUploadedBook = newBook;
        _isProcessing = false;
        _statusMessage = null;
      });

      _loadRecentDrafts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Lama keydin karin buugga: $e';
      });
    }
  }

  void _resetForm() {
    setState(() {
      _pickedPdfBytes = null;
      _pickedFileName = null;
      _pickedPageCount = 0;
      _titleController.clear();
      _newlyUploadedBook = null;
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Guide
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0022FF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: Color(0xFF60A5FA),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Talaabada 1: Soo Gelinta Buugga Cusub (PDF Upload)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Dooro buug PDF ah. Nidaamku wuxuu si toos ah u soo saarayaa tirada bogagga iyo magaca. '
                        'Kadib riix "U gudbi Editor-ka" si aad u bilowdo kala jar-jarista cutubyada iyo xuduudaha.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Upload Form & Card Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Upload Dropzone & Fields
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Xogta Buugga Cusub',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // PDF Picker Area
                      InkWell(
                        onTap: _isProcessing ? null : _pickPdfFile,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 32,
                            horizontal: 20,
                          ),
                          decoration: BoxDecoration(
                            color: _pickedPdfBytes != null
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _pickedPdfBytes != null
                                  ? const Color(0xFF3B82F6)
                                  : Colors.grey.shade300,
                              width: 1.5,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _pickedPdfBytes != null
                                    ? Icons.picture_as_pdf_rounded
                                    : Icons.cloud_upload_outlined,
                                size: 44,
                                color: _pickedPdfBytes != null
                                    ? const Color(0xFF0022FF)
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _pickedPdfBytes != null
                                    ? 'Faylka la doortay: $_pickedFileName'
                                    : 'Riix halkan si aad u doorato PDF-ka buugga',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _pickedPdfBytes != null
                                      ? const Color(0xFF1E3A8A)
                                      : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _pickedPdfBytes != null
                                    ? 'Tirada bogagga: $_pickedPageCount bogag • Diyaar u ah diiwaangelin'
                                    : 'Kaliya faylasha .pdf ayaa la aqbalayaa',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _pickedPdfBytes != null
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title Field
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Magaca Buugga',
                          hintText: 'Tusaale: Physics Form 1',
                          prefixIcon: const Icon(
                            Icons.menu_book_rounded,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Grade / Category Selector
                      Row(
                        children: [
                          const Text(
                            'Heerka (Form):',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Wrap(
                            spacing: 8,
                            children: PreparedBook.categories.map((cat) {
                              final isSelected = _selectedCategory == cat;
                              return ChoiceChip(
                                label: Text(cat),
                                selected: isSelected,
                                onSelected: (_) =>
                                    setState(() => _selectedCategory = cat),
                                selectedColor: const Color(0xFF0022FF),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (_statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Actions
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                (_isProcessing || _pickedPdfBytes == null)
                                ? null
                                : _saveAndPrepareBook,
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                  ),
                            label: const Text('Diiwaangeli Buugga (Keydi)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0022FF),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          if (_pickedPdfBytes != null)
                            OutlinedButton(
                              onPressed: _resetForm,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Nadiifi'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Right Column: Newly Uploaded Book Card & Quick Transition to Editor
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_newlyUploadedBook != null) ...[
                      _buildBookReadyForEditorCard(_newlyUploadedBook!),
                      const SizedBox(height: 16),
                    ],

                    // Recent Draft Books awaiting editor work
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: Color(0xFF0F172A),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Buugaagta Cusub ee Sugaya Editor-ka',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_recentDrafts.length} buug',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_loadingDrafts)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (_recentDrafts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  'Ma jiraan buugaag qabyo ah oo sugaya Editor-ka.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recentDrafts.take(4).length,
                              separatorBuilder: (_, _) => Divider(
                                height: 16,
                                color: Colors.grey.shade100,
                              ),
                              itemBuilder: (context, idx) {
                                final b = _recentDrafts[idx];
                                return Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.picture_as_pdf,
                                        color: Color(0xFF2563EB),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            b.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '${b.category} • ${b.pageCount} bogag',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.tonal(
                                      onPressed: () => widget.onOpenEditor(b),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Editor-ka ➔',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookReadyForEditorCard(PreparedBook book) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Buugga si guul leh ayaa loo soo geliyey!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            book.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  book.category,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${book.pageCount} bogag guud ahaan',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onOpenEditor(book),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('U gudbi Editor-ka (Talaabada 2)'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
