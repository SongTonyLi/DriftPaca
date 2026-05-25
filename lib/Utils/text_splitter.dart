/// Recursively splits text into chunks using separator hierarchy.
/// Tries separators in order: "\n\n", "\n", ". ", " "
/// Each chunk is at most [chunkSize] characters.
/// Adjacent chunks overlap by [overlap] characters.
List<String> splitText(
  String text, {
  int chunkSize = 1500,
  int overlap = 200,
}) {
  text = text.trim();
  if (text.isEmpty) return [];
  if (text.length <= chunkSize) return [text];

  const separators = ['\n\n', '\n', '. ', ' '];
  return _splitRecursive(text, separators, chunkSize, overlap);
}

List<String> _splitRecursive(
  String text,
  List<String> separators,
  int chunkSize,
  int overlap,
) {
  if (text.length <= chunkSize) return [text];
  if (separators.isEmpty) {
    return _hardSplit(text, chunkSize, overlap);
  }

  final separator = separators.first;
  final parts = text.split(separator);

  // If splitting didn't help (only 1 part), try next separator
  if (parts.length <= 1) {
    return _splitRecursive(text, separators.sublist(1), chunkSize, overlap);
  }

  // Merge parts into chunks that fit within chunkSize
  final chunks = <String>[];
  var current = '';

  for (final part in parts) {
    final candidate = current.isEmpty ? part : '$current$separator$part';

    if (candidate.length <= chunkSize) {
      current = candidate;
    } else {
      if (current.isNotEmpty) {
        chunks.add(current.trim());
      }
      // If single part exceeds chunkSize, recurse with finer separator
      if (part.length > chunkSize) {
        chunks.addAll(
          _splitRecursive(part, separators.sublist(1), chunkSize, overlap),
        );
        current = '';
      } else {
        current = part;
      }
    }
  }

  if (current.trim().isNotEmpty) {
    chunks.add(current.trim());
  }

  // Apply overlap
  if (overlap > 0 && chunks.length > 1) {
    return _applyOverlap(chunks, overlap);
  }

  return chunks;
}

List<String> _hardSplit(String text, int chunkSize, int overlap) {
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    final end = (start + chunkSize).clamp(0, text.length);
    chunks.add(text.substring(start, end).trim());
    start += chunkSize - overlap;
    if (start >= text.length) break;
  }
  return chunks.where((c) => c.isNotEmpty).toList();
}

List<String> _applyOverlap(List<String> chunks, int overlap) {
  if (chunks.length <= 1) return chunks;
  final result = <String>[chunks.first];
  for (var i = 1; i < chunks.length; i++) {
    final prev = chunks[i - 1];
    final overlapText =
        prev.substring((prev.length - overlap).clamp(0, prev.length));
    result.add('$overlapText ${chunks[i]}'.trim());
  }
  return result;
}
