enum PageFetchState {
  extracted,
  httpError,
  timedOut,
  networkError,
  unsupportedType,
  tooLarge,
  emptyText,
  cancelled,
  budgetExpired,
}

/// Retrieval provenance, independent of whether the text answers a question.
class PageFetchOutcome {
  final PageFetchState state;
  final Duration elapsed;
  final Duration downloadElapsed;
  final Duration extractionElapsed;
  final int? httpStatus;
  final String? contentType;
  final String? text;

  const PageFetchOutcome(
      {required this.state,
      required this.elapsed,
      this.httpStatus,
      this.contentType,
      this.text,
      this.downloadElapsed = Duration.zero,
      this.extractionElapsed = Duration.zero});

  bool get isSuccess => state == PageFetchState.extracted && text != null && text!.isNotEmpty;

  String get label => switch (state) {
        PageFetchState.extracted => 'Page text retrieved',
        PageFetchState.httpError =>
          httpStatus == 403 ? 'Access denied (403)' : 'HTTP error${httpStatus == null ? '' : ' ($httpStatus)'}',
        PageFetchState.timedOut => 'Timed out',
        PageFetchState.networkError => 'Connection failed',
        PageFetchState.unsupportedType => 'Unsupported format',
        PageFetchState.tooLarge => 'Page too large',
        PageFetchState.emptyText => 'Page text unavailable',
        PageFetchState.cancelled => 'Cancelled',
        PageFetchState.budgetExpired => 'Retrieval time limit reached',
      };
}
