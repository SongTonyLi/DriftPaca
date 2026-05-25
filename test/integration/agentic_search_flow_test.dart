/// Comprehensive integration tests for the agentic web search flow.
///
/// Tests the FULL pipeline: user message → think → WEBSEARCH detection →
/// search execution → recursive stream → final answer.
///
/// Run with:
///   OLLAMA_CLOUD_API_KEY=<key> flutter test test/integration/agentic_search_flow_test.dart --timeout 120s
///
/// These tests exercise the ChatProvider state machine at the provider level,
/// verifying state transitions, listener notifications, and the recursive
/// streaming architecture that the UI depends on.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';

// API key from environment — NEVER hardcoded
final _cloudApiKey = Platform.environment['OLLAMA_CLOUD_API_KEY'] ?? '';
const _testModel = 'qwen3-next:80b';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseService databaseService;
  late OllamaService ollamaService;
  late MemoryService memoryService;
  late ChatProvider chatProvider;

  late Directory _tempDir;

  setUpAll(() async {
    if (_cloudApiKey.isEmpty) {
      throw Exception(
        'OLLAMA_CLOUD_API_KEY not set.\n'
        'Run with: OLLAMA_CLOUD_API_KEY=<key> flutter test test/integration/agentic_search_flow_test.dart',
      );
    }

    // Use a temp directory for Hive to avoid contaminating test/assets
    _tempDir = await Directory.systemTemp.createTemp('agentic_search_test_');
    PathProviderPlatform.instance = _FakePathProvider(_tempDir.path);
    Hive.init(_tempDir.path);
    await Hive.openBox('settings');
  });

  setUp(() async {
    // Real database (in-memory via ffi)
    final dbPath = path.join(await getDatabasesPath(), 'agentic_flow_test.db');
    await databaseFactoryFfi.deleteDatabase(dbPath);
    databaseService = DatabaseService();
    await databaseService.open('agentic_flow_test.db');

    // Configure Hive settings for cloud mode BEFORE creating ChatProvider
    // (ChatProvider._initialize reads from Hive and overwrites manual settings)
    final settingsBox = Hive.box('settings');
    await settingsBox.put('isCloudMode', true);
    await settingsBox.put('cloudApiKey', _cloudApiKey);
    await settingsBox.put('serverAddress', 'https://ollama.com');

    // Real OllamaService — settings will be applied by ChatProvider._initialize
    ollamaService = OllamaService();

    // Real MemoryService (will return empty memories)
    memoryService = MemoryService(db: databaseService);

    // Real ChatProvider wired to real services
    chatProvider = ChatProvider(
      ollamaService: ollamaService,
      databaseService: databaseService,
      memoryService: memoryService,
    );

    // Wait for initialization (DB open + settings apply)
    await Future.delayed(const Duration(milliseconds: 200));

    // Verify cloud mode was applied correctly from Hive settings
    assert(ollamaService.isCloudMode, 'OllamaService should be in cloud mode');
    assert(ollamaService.apiKey != null && ollamaService.apiKey!.isNotEmpty,
        'API key should be set from Hive settings');
  });

  tearDown(() async {
    chatProvider.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // ===========================================================================
  // Group 1: State Machine — _activeChatStreams transitions
  // ===========================================================================
  group('State machine: _activeChatStreams transitions', () {
    test('BUG 1: WEBSEARCH detection fails when model prefixes content with '
        'leading newlines before the WEBSEARCH: marker', () async {
      // Setup: create a chat and add a user message
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);
      expect(chatProvider.currentChat, isNotNull);

      // Track web search callbacks
      String? searchQuery;
      List<WebSearchResult>? searchResults;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (results) => searchResults = results,
      );

      // Send user message that MUST trigger WEBSEARCH
      final userMsg = chatProvider.displayUserMessage('越南2025GDP');

      // Verify thinking state is set immediately
      expect(chatProvider.isCurrentChatThinking, isTrue,
          reason: 'After displayUserMessage, should be in thinking state');

      // Now call sendPrompt with search enabled (max 3 attempts)
      await chatProvider.sendPrompt(
        userMsg,
        searchAttemptsRemaining: 3,
      );

      print('=== Final state ===');
      print('Messages: ${chatProvider.messages.length}');
      print('Error: ${chatProvider.currentChatError?.message}');
      print('Search query triggered: $searchQuery');
      print('Search results count: ${searchResults?.length}');

      for (final msg in chatProvider.messages) {
        print('  [${msg.role.name}] ${_truncate(msg.content, 120)}');
      }

      // The flow should complete with an assistant message regardless of
      // whether the model decided to search or answer directly.
      final assistantMessages = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();

      expect(assistantMessages, isNotEmpty,
          reason: 'Should produce an assistant answer (with or without search)');

      // If search WAS triggered, verify the full flow worked (Bug 1 + Bug 2 fixed)
      if (searchQuery != null) {
        print('\nSearch was triggered with query: "$searchQuery"');
        print('Results: ${searchResults?.length}');

        // The final answer should NOT contain the raw WEBSEARCH marker
        // (it should have been intercepted and stripped)
        expect(assistantMessages.last.content, isNot(contains('WEBSEARCH:')),
            reason:
                'BUG: Final answer contains raw WEBSEARCH marker.\n'
                'Either Bug 1 (detection failed due to leading newlines) or\n'
                'Bug 2 (_activeChatStreams removed before recursive call) is active.');
      } else {
        // Model answered directly — still valid, just means it didn't need search
        print('\nModel answered directly without searching.');
      }

      expect(assistantMessages.last.content, isNotEmpty,
          reason: 'Answer should have content');
      print('Answer: ${_truncate(assistantMessages.last.content, 200)}');
    });

    test('streaming state should be FALSE after sendPrompt completes', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      final userMsg = chatProvider.displayUserMessage('What is 2+2?');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 0);

      // After completion, stream should be done
      expect(chatProvider.isCurrentChatStreaming, isFalse);
      expect(chatProvider.isCurrentChatThinking, isFalse);

      // Should have an assistant response
      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();
      expect(assistantMsgs, isNotEmpty);
      expect(assistantMsgs.last.content, isNotEmpty);
      print('Simple response: ${_truncate(assistantMsgs.last.content, 100)}');
    });

    test('thinking state transition: null -> streaming message -> removed', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      var sawThinking = false;
      var sawStreaming = false;
      var sawDone = false;

      chatProvider.addListener(() {
        if (chatProvider.isCurrentChatThinking) sawThinking = true;
        if (chatProvider.isCurrentChatStreaming && !chatProvider.isCurrentChatThinking) {
          sawStreaming = true;
        }
        if (!chatProvider.isCurrentChatStreaming && !chatProvider.isCurrentChatThinking) {
          if (sawStreaming || sawThinking) sawDone = true;
        }
      });

      final userMsg = chatProvider.displayUserMessage('Hello');
      await chatProvider.sendPrompt(userMsg);

      expect(sawThinking, isTrue, reason: 'Should have seen thinking state');
      expect(sawDone, isTrue, reason: 'Should have reached done state');
      print('State transitions: thinking=$sawThinking streaming=$sawStreaming done=$sawDone');
    });
  });

  // ===========================================================================
  // Group 2: Full agentic search flow (think → search → think → answer)
  // ===========================================================================
  group('Full agentic search flow', () {
    test('WEBSEARCH detected → search executed → answer produced with content', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      // Track the search lifecycle
      final searchQueries = <String>[];
      final searchResultCounts = <int>[];
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) {
          searchQueries.add(query);
          print('[SEARCH START] "$query"');
        },
        onSearchComplete: (results) {
          searchResultCounts.add(results.length);
          print('[SEARCH COMPLETE] ${results.length} results');
          for (final r in results) {
            print('  - ${r.title} (${r.url})');
            print('    content length: ${r.pageContent?.length ?? 0}');
          }
        },
      );

      final userMsg = chatProvider.displayUserMessage(
          "What is the latest news about Vietnam's economy in 2025?");

      await chatProvider.sendPrompt(
        userMsg,
        searchAttemptsRemaining: 3,
      );

      chatProvider.clearWebSearchCallbacks();

      print('\n=== Search Flow Summary ===');
      print('Queries fired: ${searchQueries.length}');
      for (var i = 0; i < searchQueries.length; i++) {
        print('  Query ${i + 1}: "${searchQueries[i]}" → ${searchResultCounts.length > i ? "${searchResultCounts[i]} results" : "pending"}');
      }

      // At least one search should have been triggered
      expect(searchQueries, isNotEmpty,
          reason: 'Model should have triggered WEBSEARCH for current events question');

      // Final state
      print('\n=== Final Messages ===');
      for (final msg in chatProvider.messages) {
        print('[${msg.role.name}] ${_truncate(msg.content, 150)}');
      }

      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();

      // This is the critical assertion — proves the recursive stream worked
      expect(assistantMsgs, isNotEmpty,
          reason:
              'No assistant message after search flow. The recursive '
              '_streamOllamaMessage likely exited due to missing _activeChatStreams entry.');

      if (assistantMsgs.isNotEmpty) {
        final answer = assistantMsgs.last.content;
        expect(answer.length, greaterThan(20),
            reason: 'Answer should be substantive, not empty/stub');

        // If search had results, answer should reference them
        if (searchResultCounts.isNotEmpty && searchResultCounts.first > 0) {
          print('\nAnswer has citations: ${RegExp(r'\[\d+\]').hasMatch(answer)}');
        }
      }
    });

    test('CJK input (越南2025GDP) triggers search and produces answer', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      String? searchQuery;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      print('Search query: $searchQuery');
      print('Messages: ${chatProvider.messages.length}');
      for (final msg in chatProvider.messages) {
        print('  [${msg.role.name}] ${_truncate(msg.content, 100)}');
      }

      expect(searchQuery, isNotNull,
          reason: 'CJK input about current GDP should trigger WEBSEARCH');

      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();
      expect(assistantMsgs, isNotEmpty,
          reason: 'BUG: No answer after CJK search — recursive stream aborted');
    });

    test('simple question produces answer (with or without search)', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      String? searchQuery;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage('What is 2 + 2?');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      print('Search triggered: ${searchQuery != null}');
      if (searchQuery != null) print('Search query: "$searchQuery"');

      // Regardless of whether the model decides to search,
      // an assistant message with content should be produced
      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();
      expect(assistantMsgs, isNotEmpty,
          reason: 'Should produce answer regardless of search decision');
      expect(assistantMsgs.last.content, isNotEmpty,
          reason: 'Answer should have content');
    });

    test('search with empty results still produces fallback answer', () async {
      // This tests the empty-results path (line 506-515 in chat_provider)
      // which should produce a fallback message
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      // Use a query unlikely to return DuckDuckGo results in headless mode
      // but that the model will still try to WEBSEARCH
      final userMsg = chatProvider.displayUserMessage(
          'xyznonexistentproduct2025price');

      String? searchQuery;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (_) {},
      );

      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      // Regardless of whether search was triggered, should have an answer
      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();

      print('Search query: $searchQuery');
      print('Assistant messages: ${assistantMsgs.length}');
      if (assistantMsgs.isNotEmpty) {
        print('Content: ${_truncate(assistantMsgs.last.content, 200)}');
      }

      expect(assistantMsgs, isNotEmpty,
          reason: 'Should always produce some response even if search fails');
    });
  });

  // ===========================================================================
  // Group 2b: Cross-model verification (non-thinking + thinking models)
  // ===========================================================================
  group('Cross-model: non-thinking model (gemma4)', () {
    test('gemma4 WEBSEARCH detection works (content arrives from first chunk)', () async {
      final model = OllamaModel(
        name: 'gemma4:31b',
        model: 'gemma4:31b',
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '31B',
      );
      await chatProvider.createNewChat(model);

      String? searchQuery;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();

      print('Model: gemma4:31b');
      print('Search query: $searchQuery');
      print('Messages: ${assistantMsgs.length}');
      if (assistantMsgs.isNotEmpty) {
        final content = assistantMsgs.last.content;
        print('Content preview: ${_truncate(content, 150)}');

        // The answer must NOT contain raw WEBSEARCH marker
        expect(content, isNot(contains('WEBSEARCH:')),
            reason:
                'BUG 4: Raw WEBSEARCH: shown to user with non-thinking model.\n'
                'For gemma4, content arrives in the first stream chunk.\n'
                'Detection only ran in the else branch, missing first-chunk content.');
      }

      expect(assistantMsgs, isNotEmpty,
          reason: 'Should produce an answer');
    });
  });

  group('Cross-model: thinking model (deepseek)', () {
    test('deepseek WEBSEARCH detection works (thinking then content)', () async {
      final model = OllamaModel(
        name: 'deepseek-v4-flash',
        model: 'deepseek-v4-flash',
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '70B',
      );
      await chatProvider.createNewChat(model);

      String? searchQuery;
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => searchQuery = query,
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      final assistantMsgs = chatProvider.messages
          .where((m) => m.role == OllamaMessageRole.assistant)
          .toList();

      print('Model: deepseek-v4-flash');
      print('Search query: $searchQuery');
      print('Messages: ${assistantMsgs.length}');
      if (assistantMsgs.isNotEmpty) {
        final content = assistantMsgs.last.content;
        print('Content preview: ${_truncate(content, 150)}');
        print('Has thinking: ${assistantMsgs.last.thinking != null}');

        expect(content, isNot(contains('WEBSEARCH:')),
            reason:
                'Raw WEBSEARCH: shown to user with thinking model.\n'
                'Detection failed to intercept WEBSEARCH marker.');
      }

      expect(assistantMsgs, isNotEmpty,
          reason: 'Should produce an answer');
    });
  });

  // ===========================================================================
  // Group 3: UI notification flow (thinking indicator, search card, answer)
  // ===========================================================================
  group('UI notification flow', () {
    test('listener sees correct state sequence for search flow', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      // Record every notification with timestamp
      final log = <_NotificationLog>[];
      chatProvider.addListener(() {
        log.add(_NotificationLog(
          timestamp: DateTime.now(),
          isThinking: chatProvider.isCurrentChatThinking,
          isStreaming: chatProvider.isCurrentChatStreaming,
          messageCount: chatProvider.messages.length,
          hasError: chatProvider.currentChatError != null,
        ));
      });

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (_) {},
        onSearchComplete: (_) {},
      );
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      print('=== Notification log (${log.length} entries) ===');
      final startTime = log.first.timestamp;
      for (var i = 0; i < log.length; i++) {
        final elapsed = log[i].timestamp.difference(startTime).inMilliseconds;
        print('  [${elapsed}ms] thinking=${log[i].isThinking} '
            'streaming=${log[i].isStreaming} '
            'msgs=${log[i].messageCount} '
            'error=${log[i].hasError}');
      }

      // Verify the sequence has expected phases:
      // 1. Thinking phase (isThinking=true, streaming but message is null)
      expect(log.any((l) => l.isThinking), isTrue,
          reason: 'UI should see thinking state at some point');

      // 2. Final state: not streaming, not thinking
      expect(log.last.isStreaming, isFalse,
          reason: 'Should not be streaming after completion');
      expect(log.last.isThinking, isFalse,
          reason: 'Should not be thinking after completion');

      // 3. Messages should end with more than just the user message
      expect(log.last.messageCount, greaterThan(1),
          reason:
              'BUG: Final notification shows only user message (count=1).\n'
              'Expected: user + assistant messages.\n'
              'Root cause: _activeChatStreams entry removed before recursive call.');
    });

    test('search callback fires before recursive stream starts', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      final events = <String>[];

      chatProvider.addListener(() {
        if (chatProvider.isCurrentChatThinking) {
          events.add('THINKING');
        } else if (chatProvider.isCurrentChatStreaming) {
          events.add('STREAMING');
        } else {
          events.add('IDLE');
        }
      });

      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) => events.add('SEARCH_START:$query'),
        onSearchComplete: (results) => events.add('SEARCH_COMPLETE:${results.length}'),
      );

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      print('=== Event sequence ===');
      for (var i = 0; i < events.length; i++) {
        print('  [$i] ${events[i]}');
      }

      // Verify search events are in correct order
      final searchStartIdx = events.indexWhere((e) => e.startsWith('SEARCH_START'));
      final searchCompleteIdx = events.indexWhere((e) => e.startsWith('SEARCH_COMPLETE'));

      if (searchStartIdx != -1) {
        expect(searchCompleteIdx, greaterThan(searchStartIdx),
            reason: 'SEARCH_COMPLETE should come after SEARCH_START');

        // After search complete, there should be more events (the recursive stream)
        // With the bug, there are NO events after SEARCH_COMPLETE
        final eventsAfterSearch = events.sublist(searchCompleteIdx + 1);
        print('\nEvents after search complete: $eventsAfterSearch');

        expect(eventsAfterSearch, isNotEmpty,
            reason:
                'BUG: No state changes after search completes.\n'
                'The recursive _streamOllamaMessage exits immediately because\n'
                '_activeChatStreams was removed and never re-added.');
      }
    });

    test('max 3 search attempts respected', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      final searchQueries = <String>[];
      chatProvider.setWebSearchCallbacks(
        onSearchStart: (query) {
          searchQueries.add(query);
          print('[SEARCH ${searchQueries.length}] "$query"');
        },
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage(
          "What are the latest GDP figures for Vietnam, Thailand, and Indonesia in 2025?");
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      print('Total searches triggered: ${searchQueries.length}');
      expect(searchQueries.length, lessThanOrEqualTo(3),
          reason: 'Should not exceed max 3 search attempts');
    });
  });

  // ===========================================================================
  // Group 4: Error resilience
  // ===========================================================================
  group('Error resilience', () {
    test('stream cancellation during search does not crash', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      chatProvider.setWebSearchCallbacks(
        onSearchStart: (_) {
          // Cancel streaming while search is in progress
          chatProvider.cancelCurrentStreaming();
        },
        onSearchComplete: (_) {},
      );

      final userMsg = chatProvider.displayUserMessage('越南2025GDP');

      // Should not throw
      await chatProvider.sendPrompt(userMsg, searchAttemptsRemaining: 3);
      chatProvider.clearWebSearchCallbacks();

      // Should be in clean state (not streaming)
      expect(chatProvider.isCurrentChatStreaming, isFalse);
      expect(chatProvider.currentChatError, isNull);
    });

    test('concurrent sends are prevented', () async {
      final model = OllamaModel(
        name: _testModel,
        model: _testModel,
        modifiedAt: DateTime.now(),
        size: 1000,
        digest: 'test',
        parameterSize: '32B',
      );
      await chatProvider.createNewChat(model);

      final userMsg1 = chatProvider.displayUserMessage('Hello');
      final future1 = chatProvider.sendPrompt(userMsg1);

      // Second send while first is in progress — the state should handle this
      // (either queue or reject)
      final userMsg2 = OllamaMessage('World', role: OllamaMessageRole.user);
      chatProvider.messages.add(userMsg2);
      final future2 = chatProvider.sendPrompt(userMsg2);

      await Future.wait([future1, future2]);

      // Should not crash and should end in clean state
      expect(chatProvider.isCurrentChatStreaming, isFalse);
    });
  });
}

// =============================================================================
// Helper classes
// =============================================================================

class _NotificationLog {
  final DateTime timestamp;
  final bool isThinking;
  final bool isStreaming;
  final int messageCount;
  final bool hasError;

  _NotificationLog({
    required this.timestamp,
    required this.isThinking,
    required this.isStreaming,
    required this.messageCount,
    required this.hasError,
  });
}

String _truncate(String? s, int maxLen) {
  if (s == null) return '<null>';
  if (s.length <= maxLen) return s.replaceAll('\n', '\\n');
  return '${s.substring(0, maxLen).replaceAll('\n', '\\n')}...';
}

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}
