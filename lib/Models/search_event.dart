/// Status of a single URL fetch. `state` is mutable so the view model
/// can flip an entry from `pending` → `success`/`failed` in place as
/// fetches resolve, without rebuilding the whole list. `title` is the
/// page title returned by the search engine — shown in the search card
/// instead of the bare domain. Empty for legacy persisted data.
class SearchURLStatus {
  final String url;
  final String domain;
  final String title;
  SearchURLState state;

  SearchURLStatus({
    required this.url,
    required this.domain,
    this.title = '',
    required this.state,
  });
}

enum SearchURLState { pending, success, failed }

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
  // Structured per-source data (url, domain, title, content) for the
  // detail dialog. Older persisted messages won't have this and the UI
  // falls back to parsing [extractedContent].
  List<SearchSource>? sources;

  SearchCardSegment({
    required this.query,
    this.urls = const [],
    this.resultCount,
    this.error,
    this.isComplete = false,
    this.extractedContent,
    this.sources,
  });
}

/// One source's full data for the detail dialog: URL, domain (for favicon),
/// page title (from the search result), and extracted text.
class SearchSource {
  final String url;
  final String domain;
  final String title;
  final String content;

  SearchSource({
    required this.url,
    required this.domain,
    required this.title,
    required this.content,
  });
}

class AnswerSegment extends MessageSegment {}
