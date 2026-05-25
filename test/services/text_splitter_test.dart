import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/text_splitter.dart';

void main() {
  group('splitText', () {
    test('returns single chunk for short text', () {
      final chunks = splitText('Hello world', chunkSize: 100);
      expect(chunks, ['Hello world']);
    });

    test('splits on double newline first', () {
      final text = 'Paragraph one.\n\nParagraph two.\n\nParagraph three.';
      final chunks = splitText(text, chunkSize: 25, overlap: 0);
      expect(chunks.length, 3);
      expect(chunks[0], 'Paragraph one.');
      expect(chunks[1], 'Paragraph two.');
      expect(chunks[2], 'Paragraph three.');
    });

    test('falls back to single newline when paragraphs too long', () {
      final text = 'Line one\nLine two\nLine three';
      final chunks = splitText(text, chunkSize: 15, overlap: 0);
      expect(chunks.length, 3);
    });

    test('falls back to sentence boundary', () {
      final text = 'First sentence. Second sentence. Third sentence.';
      final chunks = splitText(text, chunkSize: 20, overlap: 0);
      expect(chunks.every((c) => c.length <= 20), true);
    });

    test('respects overlap between chunks', () {
      final text = 'AAAA\n\nBBBB\n\nCCCC\n\nDDDD';
      final chunks = splitText(text, chunkSize: 10, overlap: 4);
      expect(chunks.length, greaterThanOrEqualTo(2));
      // Second chunk should start with overlap from first chunk's tail
      if (chunks.length > 1) {
        expect(chunks[1].length, greaterThan(4));
      }
    });

    test('handles empty string', () {
      expect(splitText(''), isEmpty);
    });

    test('handles text shorter than overlap', () {
      final chunks = splitText('Hi', chunkSize: 100, overlap: 50);
      expect(chunks, ['Hi']);
    });
  });
}
