import 'dart:convert';

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
                  'state': u.state.name,
                })
            .toList(),
        'resultCount': segment.resultCount,
        'error': segment.error,
        if (segment.extractedContent != null)
          'content': segment.extractedContent,
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
                      state: SearchURLState.values.firstWhere(
                        (s) => s.name == (u['state'] as String? ?? ''),
                        orElse: () => SearchURLState.failed,
                      ),
                    ))
                .toList() ??
            [];
        segments.add(SearchCardSegment(
          query: item['query'] as String? ?? '',
          urls: urls,
          resultCount: item['resultCount'] as int?,
          error: item['error'] as String?,
          isComplete: true,
          extractedContent: item['content'] as String?,
        ));
      }
    }
    return segments.isNotEmpty ? segments : null;
  } catch (e) {
    return null;
  }
}

/// Strips the search data header from thinking text for display.
String stripSearchData(String thinking) {
  if (!thinking.startsWith(_searchDataPrefix)) return thinking;
  final endIndex = thinking.indexOf(_searchDataSuffix);
  if (endIndex == -1) return thinking;
  return thinking.substring(endIndex + _searchDataSuffix.length).trimLeft();
}
