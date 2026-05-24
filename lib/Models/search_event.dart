/// Events emitted by SearchOrchestrator for UI updates.
sealed class SearchEvent {}

/// A new thinking block has started streaming.
class ThinkingStartEvent extends SearchEvent {}

/// Incremental update to the current thinking block (accumulated text so far).
class ThinkingUpdateEvent extends SearchEvent {
  final String accumulated;
  ThinkingUpdateEvent(this.accumulated);
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

/// Extracted content from search results, for persistence.
class SearchContentEvent extends SearchEvent {
  final String content;
  SearchContentEvent(this.content);
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
  String text; // mutable — updated in-place during streaming
  ThinkingSegment(this.text);
}

class SearchCardSegment extends MessageSegment {
  String query;
  List<SearchURLStatus> urls;
  int? resultCount;
  String? error;
  bool isComplete;
  String? extractedContent; // top chunks fed to model, for persistence

  SearchCardSegment({
    required this.query,
    this.urls = const [],
    this.resultCount,
    this.error,
    this.isComplete = false,
    this.extractedContent,
  });
}

class AnswerSegment extends MessageSegment {
  // Marker — the actual answer text is in the OllamaMessage.content field
}
