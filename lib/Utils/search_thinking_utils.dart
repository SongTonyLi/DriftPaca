/// Separator between persisted search thinking and model thinking.
const String searchThinkingSeparator = '\n\n---\n\n';

/// Combines search thinking and model thinking for persistence.
/// Returns the non-empty part when either side is empty.
String mergeSearchThinking({
  required String searchThinking,
  required String modelThinking,
}) {
  if (searchThinking.isEmpty) return modelThinking;
  if (modelThinking.isEmpty) return searchThinking;
  return '$searchThinking$searchThinkingSeparator$modelThinking';
}

/// Extracts model thinking from a combined string.
/// If no separator is found, returns the original string unchanged.
String modelThinkingFromCombined(String combined) {
  final separatorIndex = combined.indexOf(searchThinkingSeparator);
  if (separatorIndex == -1) return combined;
  return combined.substring(separatorIndex + searchThinkingSeparator.length);
}
