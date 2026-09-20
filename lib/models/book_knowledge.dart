import 'dart:convert';

class BookKnowledge {
  const BookKnowledge({required this.bookId, required this.pages});

  final String bookId;
  final Map<int, String> pages;

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'pages': pages.map((key, value) => MapEntry('$key', value)),
  };

  String encode() => jsonEncode(toJson());

  factory BookKnowledge.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final rawPages = json['pages'] as Map<String, dynamic>? ?? const {};
    return BookKnowledge(
      bookId: json['bookId'] as String? ?? '',
      pages: rawPages.map(
        (key, value) =>
            MapEntry(int.tryParse(key) ?? 0, value as String? ?? ''),
      ),
    );
  }
}
