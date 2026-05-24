/// Events emitted by SearchOrchestrator for UI updates.
sealed class SearchEvent {}

/// Model reasoning text to display in thinking block.
class ThinkingEvent extends SearchEvent {
  final String text;
  ThinkingEvent(this.text);
}

/// Search has started for a query.
class SearchStartEvent extends SearchEvent {
  final String query;
  SearchStartEvent(this.query);
}

/// Per-URL fetch status update.
class SearchProgressEvent extends SearchEvent {
  final List<SearchURLStatus> urls;
  SearchProgressEvent(this.urls);
}

/// Search iteration complete.
class SearchCompleteEvent extends SearchEvent {
  final int resultCount;
  SearchCompleteEvent(this.resultCount);
}

/// Search error (network, timeout, etc).
class SearchErrorEvent extends SearchEvent {
  final String message;
  SearchErrorEvent(this.message);
}

/// Search phase done, answer streaming begins.
class AnswerStartEvent extends SearchEvent {}

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

enum SearchURLState { loading, success, failed, timedOut }

/// Segments for rendering search-augmented messages during streaming.
/// These are ephemeral — not persisted to the database.
sealed class MessageSegment {}

class ThinkingSegment extends MessageSegment {
  final String text;
  ThinkingSegment(this.text);
}

class SearchCardSegment extends MessageSegment {
  String query;
  List<SearchURLStatus> urls;
  int? resultCount;
  String? error;
  bool isComplete;

  SearchCardSegment({
    required this.query,
    this.urls = const [],
    this.resultCount,
    this.error,
    this.isComplete = false,
  });
}

class AnswerSegment extends MessageSegment {
  // Marker — the actual answer text is in the OllamaMessage.content field
}
