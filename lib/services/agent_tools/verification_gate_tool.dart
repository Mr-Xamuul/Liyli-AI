import 'curriculum_search_tool.dart';
import 'pdf_retriever_tool.dart';

class VerificationGateResult {
  const VerificationGateResult({
    required this.bookTitle,
    required this.chapterTitle,
    required this.lessonTitle,
    this.sectionTitle,
    required this.startPage,
    required this.endPage,
    required this.concisePreview,
    required this.verificationQuestion,
    required this.fullVerificationMessage,
    required this.suggestedReplies,
  });

  final String bookTitle;
  final String chapterTitle;
  final String lessonTitle;
  final String? sectionTitle;
  final int startPage;
  final int endPage;
  final String concisePreview;
  final String verificationQuestion;
  final String fullVerificationMessage;
  final List<String> suggestedReplies;

  Map<String, dynamic> toJson() => {
    'bookTitle': bookTitle,
    'chapterTitle': chapterTitle,
    'lessonTitle': lessonTitle,
    if (sectionTitle != null) 'sectionTitle': sectionTitle,
    'startPage': startPage,
    'endPage': endPage,
    'concisePreview': concisePreview,
    'verificationQuestion': verificationQuestion,
    'fullVerificationMessage': fullVerificationMessage,
    'suggestedReplies': suggestedReplies,
  };
}

class VerificationGateTool {
  const VerificationGateTool();

  VerificationGateResult formulateVerification({
    required CurriculumSearchMatch match,
    PdfRetrieverResult? retrieverResult,
    required String userQuery,
  }) {
    // 1. Build concise preview
    String preview = '';
    if (retrieverResult?.extractedTextSummary != null &&
        retrieverResult!.extractedTextSummary!.isNotEmpty) {
      final lines = retrieverResult.extractedTextSummary!
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(2)
          .join(' ');
      preview = lines;
    }

    if (preview.isEmpty) {
      preview =
          'Waxay ka hadlaysaa dulucda guud ee "${match.lesson.title}" ee cutubka "${match.chapter.title}".';
    }

    // 2. Somali verification question
    const question =
        'Ma casharkan ayaad u jeeddaa si aan si faahfaahsan kuugu sharaxo?';

    // 3. Assemble complete message
    final pageStr = match.startPage == match.endPage
        ? 'Bogga ${match.startPage}'
        : 'Bogagga ${match.startPage}–${match.endPage}';

    final buffer = StringBuffer();
    buffer.writeln('📖 **Waxaan helay casharka aad codsatay:**');
    buffer.writeln('• **Buugga:** ${match.book.title} (${match.book.category})');
    buffer.writeln('• **Cutubka:** ${match.chapter.title}');
    buffer.writeln('• **Casharka:** ${match.lesson.title} ($pageStr)');
    if (match.section != null) {
      buffer.writeln('• **Qaybta:** ${match.section!.title}');
    }
    buffer.writeln();
    buffer.writeln('💡 **Dulucda Kooban:**');
    buffer.writeln(preview);
    buffer.writeln();
    buffer.writeln('❓ _${question}_');

    return VerificationGateResult(
      bookTitle: match.book.title,
      chapterTitle: match.chapter.title,
      lessonTitle: match.lesson.title,
      sectionTitle: match.section?.title,
      startPage: match.startPage,
      endPage: match.endPage,
      concisePreview: preview,
      verificationQuestion: question,
      fullVerificationMessage: buffer.toString(),
      suggestedReplies: const [
        'Haa, si buuxda ii sharax',
        'Maya, ma aha kan',
      ],
    );
  }
}
