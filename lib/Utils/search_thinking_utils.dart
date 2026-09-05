import 'dart:convert';

import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/search_event.dart';

/// Separator between persisted search thinking and model thinking.
const String searchThinkingSeparator = '\n\n---\n\n';

/// Marker prefix for serialized search segments in thinking field.
const String _searchDataPrefix = '<!--SEARCH_DATA:';
const String _searchDataSuffix = '-->';

/// Combines search thinking and model thinking for persistence.
String mergeSearchThinking({
  required String searchThinking,
  required String modelThinking,
}) {
  if (searchThinking.isEmpty) return modelThinking;
  if (modelThinking.isEmpty) return searchThinking;
  return '$searchThinking$searchThinkingSeparator$modelThinking';
}

/// Extracts the model thinking portion from a combined string.
String modelThinkingFromCombined(String combined) {
  final clean = stripSearchData(combined);
  final separatorIndex = clean.indexOf(searchThinkingSeparator);
  if (separatorIndex == -1) return clean;
  return clean.substring(separatorIndex + searchThinkingSeparator.length);
}

/// Encodes search segments as a base64 JSON string with marker prefix.
String encodeSearchSegments(List<MessageSegment> segments) {
  final data = <Map<String, dynamic>>[];
  for (final segment in segments) {
    if (segment is ThinkingSegment && segment.text.isNotEmpty) {
      data.add({'type': 'thinking', 'text': segment.text});
    } else if (segment is SearchCardSegment && segment.query.isNotEmpty) {
      data.add({
        'type': 'search',
        'query': segment.query,
        'urls': segment.urls
            .map((u) => {
                  'url': u.url,
                  'domain': u.domain,
                  'title': u.title,
                  'state': u.state.name,
                })
            .toList(),
        'resultCount': segment.resultCount,
        'error': segment.error,
        if (segment.extractedContent != null)
          'content': segment.extractedContent,
        if (segment.sources != null)
          'sources': segment.sources!
              .map((s) => {
                    'url': s.url,
                    'domain': s.domain,
                    'title': s.title,
                    'content': s.content,
                  })
              .toList(),
        if (segment.round != null) 'round': segment.round,
        if (segment.skipReason != null) 'skipReason': segment.skipReason,
      });
    } else if (segment is ResearchLedgerSegment && segment.objective.isNotEmpty) {
      data.add({
        'type': 'ledger',
        'objective': segment.objective,
        'entries': segment.entries
            .map((e) => {
                  'query': e.query,
                  'searched': e.searched,
                  if (e.ranges.isNotEmpty)
                    'ranges': [
                      for (final r in e.ranges) [r.start, r.end]
                    ],
                  if (e.excerpt != null) 'excerpt': e.excerpt,
                })
            .toList(),
        if (segment.terminationReason != null)
          'terminationReason': segment.terminationReason,
      });
    }
  }
  if (data.isEmpty) return '';
  final json = jsonEncode(data);
  final encoded = base64Encode(utf8.encode(json));
  return '$_searchDataPrefix$encoded$_searchDataSuffix\n';
}

/// Decodes search segments from a thinking field string.
/// Returns null if no search data found.
List<MessageSegment>? decodeSearchSegments(String thinking) {
  if (!thinking.startsWith(_searchDataPrefix)) return null;

  final endIndex = thinking.indexOf(_searchDataSuffix);
  if (endIndex == -1) return null;

  try {
    final encoded = thinking.substring(_searchDataPrefix.length, endIndex);
    final json = utf8.decode(base64Decode(encoded));
    final data = jsonDecode(json) as List;

    final segments = <MessageSegment>[];
    for (final item in data) {
      final type = item['type'] as String?;
      if (type == 'thinking') {
        segments.add(ThinkingSegment(item['text'] as String? ?? ''));
      } else if (type == 'search') {
        final urls = (item['urls'] as List?)
                ?.map((u) => SearchURLStatus(
                      url: u['url'] as String? ?? '',
                      domain: u['domain'] as String? ?? '',
                      title: u['title'] as String? ?? '',
                      state: SearchURLState.values.firstWhere(
                        (s) => s.name == (u['state'] as String? ?? ''),
                        orElse: () => SearchURLState.failed,
                      ),
                    ))
                .toList() ??
            [];
        final sources = (item['sources'] as List?)
            ?.map((s) => SearchSource(
                  url: s['url'] as String? ?? '',
                  domain: s['domain'] as String? ?? '',
                  title: s['title'] as String? ?? '',
                  content: s['content'] as String? ?? '',
                ))
            .toList();
        segments.add(SearchCardSegment(
          query: item['query'] as String? ?? '',
          urls: urls,
          resultCount: item['resultCount'] as int?,
          error: item['error'] as String?,
          isComplete: true,
          extractedContent: item['content'] as String?,
          sources: sources,
          round: item['round'] as int?,
          skipReason: item['skipReason'] as String?,
        ));
      } else if (type == 'ledger') {
        final entries = (item['entries'] as List?)
                ?.map((e) => LedgerEntryView(
                      query: e['query'] as String? ?? '',
                      searched: e['searched'] as bool? ?? false,
                      ranges: _decodeRanges(e),
                      excerpt: e['excerpt'] as String?,
                    ))
                .toList() ??
            [];
        segments.add(ResearchLedgerSegment(
          objective: item['objective'] as String? ?? '',
          entries: entries,
          terminationReason: item['terminationReason'] as String?,
        ));
      }
    }
    return segments.isNotEmpty ? segments : null;
  } catch (e) {
    return null;
  }
}

/// Reads a ledger entry's source ids, accepting both shapes: the current
/// `ranges` list, and the single `sourceIdStart`/`sourceIdEnd` pair written
/// before a sub-goal could carry evidence from more than one search. Chats
/// persisted under the old shape keep rendering their citation chip.
List<SourceIdRange> _decodeRanges(dynamic entry) {
  final raw = entry['ranges'] as List?;
  if (raw != null) {
    return [
      for (final r in raw)
        if (r is List && r.length == 2 && r[0] is int && r[1] is int)
          SourceIdRange(r[0] as int, r[1] as int),
    ];
  }
  final start = entry['sourceIdStart'] as int?;
  if (start == null) return const [];
  return [SourceIdRange(start, entry['sourceIdEnd'] as int? ?? start)];
}

/// Strips the search data header from thinking text for display.
String stripSearchData(String thinking) {
  if (!thinking.startsWith(_searchDataPrefix)) return thinking;
  final endIndex = thinking.indexOf(_searchDataSuffix);
  if (endIndex == -1) return thinking;
  return thinking.substring(endIndex + _searchDataSuffix.length).trimLeft();
}
