import 'package:flutter_test/flutter_test.dart';
import 'package:leyli/models/prepared_book.dart';

void main() {
  group('PreparedBook validation', () {
    test('allows sections to share the same boundary page', () {
      const book = PreparedBook(
        id: 'test_book',
        title: 'Physics Test Book',
        originalFileName: 'physics.pdf',
        pageCount: 30,
        chapters: [
          PreparedChapter(
            id: 'c1',
            title: 'Periodic & Oscillatory Motion',
            startPage: 1,
            endPage: 20,
            lessons: [
              PreparedLesson(
                id: 'l1',
                title: 'Periodic and Oscillatory Motion',
                startPage: 1,
                endPage: 20,
                sections: [
                  PreparedSection(
                    id: 's1',
                    title: 'Introduction',
                    startPage: 1,
                    endPage: 5,
                  ),
                  PreparedSection(
                    id: 's2',
                    title: 'simple',
                    startPage: 5,
                    endPage: 10,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final errors = book.validate();
      expect(errors, isEmpty);
    });

    test('allows multiple sections on the exact same page', () {
      const book = PreparedBook(
        id: 'test_book',
        title: 'Physics Test Book',
        originalFileName: 'physics.pdf',
        pageCount: 30,
        chapters: [
          PreparedChapter(
            id: 'c1',
            title: 'Periodic & Oscillatory Motion',
            startPage: 1,
            endPage: 20,
            lessons: [
              PreparedLesson(
                id: 'l1',
                title: 'Lesson 1',
                startPage: 1,
                endPage: 20,
                sections: [
                  PreparedSection(
                    id: 's1',
                    title: 'Section A',
                    startPage: 5,
                    endPage: 5,
                  ),
                  PreparedSection(
                    id: 's2',
                    title: 'Section B',
                    startPage: 5,
                    endPage: 5,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final errors = book.validate();
      expect(errors, isEmpty);
    });

    test('detects actual page overlap', () {
      const book = PreparedBook(
        id: 'test_book',
        title: 'Physics Test Book',
        originalFileName: 'physics.pdf',
        pageCount: 30,
        chapters: [
          PreparedChapter(
            id: 'c1',
            title: 'Chapter 1',
            startPage: 1,
            endPage: 20,
            lessons: [
              PreparedLesson(
                id: 'l1',
                title: 'Lesson 1',
                startPage: 1,
                endPage: 20,
                sections: [
                  PreparedSection(
                    id: 's1',
                    title: 'Section A',
                    startPage: 1,
                    endPage: 8,
                  ),
                  PreparedSection(
                    id: 's2',
                    title: 'Section B',
                    startPage: 5,
                    endPage: 12,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final errors = book.validate();
      expect(errors.length, 1);
      expect(errors.first, contains('ranges overlap or are out of order'));
    });

    test('detects section outside parent lesson range', () {
      const book = PreparedBook(
        id: 'test_book',
        title: 'Physics Test Book',
        originalFileName: 'physics.pdf',
        pageCount: 30,
        chapters: [
          PreparedChapter(
            id: 'c1',
            title: 'Chapter 1',
            startPage: 1,
            endPage: 20,
            lessons: [
              PreparedLesson(
                id: 'l1',
                title: 'Lesson 1',
                startPage: 1,
                endPage: 10,
                sections: [
                  PreparedSection(
                    id: 's1',
                    title: 'Section A',
                    startPage: 1,
                    endPage: 12, // outside lesson endPage 10
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final errors = book.validate();
      expect(errors.length, 1);
      expect(errors.first, contains('is outside its parent page range'));
    });
  });
}
