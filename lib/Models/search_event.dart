/// Status of a single URL fetch.
class SearchURLStatus {
  final String url;
  final String domain;
  final SearchURLState state;

  SearchURLStatus({
    required this.url,
    required this.domain,
    required this.state,
  });
}

enum SearchURLState { success, failed }

/// Segments for rendering search-augmented messages.
/// Persisted as JSON in the thinking field.
sealed class MessageSegment {}

class ThinkingSegment extends MessageSegment {
  String text;
  ThinkingSegment(this.text);
}

class SearchCardSegment extends MessageSegment {
  String query;
  List<SearchURLStatus> urls;
  int? resultCount;
  String? error;
  bool isComplete;
  String? extractedContent;

  SearchCardSegment({
    required this.query,
    this.urls = const [],
    this.resultCount,
    this.error,
    this.isComplete = false,
    this.extractedContent,
  });
}

class AnswerSegment extends MessageSegment {}
