const String searchThinkingSeparator = '\n\n---\n\n';

String mergeSearchThinking({
  required String searchThinking,
  required String modelThinking,
}) {
  if (searchThinking.isEmpty) return modelThinking;
  if (modelThinking.isEmpty) return searchThinking;
  return '$searchThinking$searchThinkingSeparator$modelThinking';
}

String modelThinkingFromCombined(String combined) {
  final separatorIndex = combined.indexOf(searchThinkingSeparator);
  if (separatorIndex == -1) return combined;
  return combined.substring(separatorIndex + searchThinkingSeparator.length);
}
