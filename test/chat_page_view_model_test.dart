import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatProvider fakeChatProvider;
  late FakePermissionService fakePermissionService;
  late FakeImageService fakeImageService;
  late ChatPageViewModel viewModel;

  setUpAll(() async {
    // Setup fake path provider for Hive
    PathProviderPlatform.instance = FakePathProviderPlatform();

    // Initialize Hive for testing
    final testDir = Directory.systemTemp.createTempSync('chat_page_vm_test').path;
    Hive.init(testDir);
    await Hive.openBox('settings');
  });

  setUp(() async {
    fakeChatProvider = FakeChatProvider();
    fakePermissionService = FakePermissionService();
    fakeImageService = FakeImageService();

    // Ensure server is configured for most tests
    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    viewModel = ChatPageViewModel(
      chatProvider: fakeChatProvider,
      permissionService: fakePermissionService,
      imageService: fakeImageService,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('Initial State', () {
    test('selectedModel should be null initially', () {
      expect(viewModel.selectedModel, isNull);
    });

    test('presets should not be empty', () {
      expect(viewModel.presets, isNotEmpty);
    });

    test('hasText should be false initially', () {
      expect(viewModel.hasText, isFalse);
    });

    test('imageFiles should be empty initially', () {
      expect(viewModel.imageFiles, isEmpty);
    });

    test('hasImageAttachments should be false initially', () {
      expect(viewModel.hasImageAttachments, isFalse);
    });
  });

  group('Model Selection', () {
    test('setSelectedModel should update selectedModel', () {
      final model = createTestModel('llama3.2');

      viewModel.setSelectedModel(model);

      expect(viewModel.selectedModel, model);
    });

    test('setSelectedModel should notify listeners', () {
      final model = createTestModel('llama3.2');
      var notified = false;
      viewModel.addListener(() => notified = true);

      viewModel.setSelectedModel(model);

      expect(notified, isTrue);
    });

    test('setSelectedModel with null should clear selection', () {
      final model = createTestModel('llama3.2');
      viewModel.setSelectedModel(model);

      viewModel.setSelectedModel(null);

      expect(viewModel.selectedModel, isNull);
    });
  });

  group('Text Field', () {
    test('setTextFieldValue should update text field', () {
      viewModel.setTextFieldValue('Hello');

      expect(viewModel.textFieldController.text, 'Hello');
    });

    test('hasText should return true when text field has content', () {
      viewModel.setTextFieldValue('Hello');

      expect(viewModel.hasText, isTrue);
    });

    test('hasText should return false for whitespace only', () {
      viewModel.setTextFieldValue('   ');

      expect(viewModel.hasText, isFalse);
    });

    test('textFieldController changes should notify only on empty/non-empty transitions', () {
      var notifyCount = 0;
      viewModel.addListener(() => notifyCount++);

      // Empty -> non-empty: should notify
      viewModel.textFieldController.text = 'T';
      expect(notifyCount, 1);

      // Non-empty -> non-empty: should NOT notify
      viewModel.textFieldController.text = 'Te';
      expect(notifyCount, 1);

      // Non-empty -> non-empty: should NOT notify
      viewModel.textFieldController.text = 'Test';
      expect(notifyCount, 1);

      // Non-empty -> empty: should notify
      viewModel.textFieldController.text = '';
      expect(notifyCount, 2);

      // Empty -> empty: should NOT notify
      viewModel.textFieldController.text = '';
      expect(notifyCount, 2);
    });
  });

  group('ChatProvider State (Proxied)', () {
    test('messages should proxy ChatProvider messages', () {
      final messages = [
        OllamaMessage('Hello', role: OllamaMessageRole.user),
      ];
      fakeChatProvider.setMessages(messages);

      expect(viewModel.messages, messages);
    });

    test('currentChat should proxy ChatProvider currentChat', () {
      final chat = createTestChat('test-id');
      fakeChatProvider.setCurrentChat(chat);

      expect(viewModel.currentChat, chat);
    });

    test('isStreaming should proxy ChatProvider isCurrentChatStreaming', () {
      fakeChatProvider.setIsStreaming(true);

      expect(viewModel.isStreaming, isTrue);
    });

    test('isThinking should proxy ChatProvider isCurrentChatThinking', () {
      fakeChatProvider.setIsThinking(true);

      expect(viewModel.isThinking, isTrue);
    });

    test('currentError should proxy ChatProvider currentChatError', () {
      final error = OllamaException('Test error');
      fakeChatProvider.setCurrentError(error);

      expect(viewModel.currentError, error);
    });

    test('ChatProvider changes should notify ViewModel listeners', () {
      var notified = false;
      viewModel.addListener(() => notified = true);

      // Change state so the notification proxy detects a difference
      fakeChatProvider.setMessages([
        OllamaMessage('Hello', role: OllamaMessageRole.user),
      ]);
      fakeChatProvider.triggerNotifyListeners();

      expect(notified, isTrue);
    });
  });

  group('ChatProvider Actions (Delegated)', () {
    test('cancelStreaming should delegate to ChatProvider', () {
      viewModel.cancelStreaming();

      expect(fakeChatProvider.cancelStreamingCalled, isTrue);
    });

    test('retryLastPrompt should delegate to ChatProvider', () async {
      await viewModel.retryLastPrompt();

      expect(fakeChatProvider.retryLastPromptCalled, isTrue);
    });

    test('fetchAvailableModels should delegate to ChatProvider', () async {
      final models = [createTestModel('llama3.2')];
      fakeChatProvider.setAvailableModels(models);

      final result = await viewModel.fetchAvailableModels();

      expect(result, models);
    });
  });

  group('deleteExchange', () {
    test('delegates to ChatProvider.deleteExchange', () async {
      final msg = OllamaMessage('hi', role: OllamaMessageRole.user);
      await viewModel.deleteExchange(msg);
      expect(fakeChatProvider.deletedExchangeAnchor, same(msg));
    });
  });

  group('sendMessage', () {
    test('should return false when text field is empty', () async {
      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    test('should return false when currently streaming', () async {
      viewModel.setTextFieldValue('Hello');
      fakeChatProvider.setIsStreaming(true);

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    group('while a run is paused on its clarification card', () {
      // The card is opened the way SearchAgent opens it: through the
      // onClarification callback of a run in flight, so the live segments
      // hold an unanswered ClarificationSegment when the user types.
      Future<ClarificationSegment> pauseOnCard() async {
        viewModel.acceptWebSearchConsent();
        fakeChatProvider.setCurrentChat(createTestChat('chat-1'));
        viewModel.setTextFieldValue('Tell me about Mercury');
        final paused = Completer<void>();
        fakeChatProvider.duringSendPrompt = () => paused.future;
        final send = viewModel.sendMessage(
          onModelSelectionRequired: () async {},
          onServerNotConfigured: () {},
        );
        await Future.microtask(() {});
        fakeChatProvider.capturedOnClarification!(const ResearchClarification(
          question: 'Which Mercury?',
          options: ['The planet', 'The element'],
        ));
        fakeChatProvider.setIsStreaming(true);
        fakeChatProvider.awaitingClarification = true;
        addTearDown(() async {
          paused.complete();
          await send;
        });
        return viewModel.searchSegments.whereType<ClarificationSegment>().single;
      }

      test('a message typed in the prompt bar answers the card in the user\'s own words', () async {
        final card = await pauseOnCard();
        viewModel.setTextFieldValue('  the Freddie one  ');

        final result = await viewModel.sendMessage(
          onModelSelectionRequired: () async {},
          onServerNotConfigured: () {},
        );

        expect(result, isTrue);
        expect(fakeChatProvider.answeredClarification, ['the Freddie one'],
            reason: 'the typed text is the answer, trimmed, not a new prompt');
        expect(card.selected, ['the Freddie one'],
            reason: 'the card records it like a pick');
        expect(viewModel.hasText, isFalse, reason: 'the prompt bar is cleared');
        expect(fakeChatProvider.lastSentPrompt, 'Tell me about Mercury',
            reason: 'no second prompt was sent');
      });

      test('an already-answered card is not answered again from the prompt bar', () async {
        final card = await pauseOnCard();
        viewModel.answerClarification(card, const ['The planet']);
        fakeChatProvider.answeredClarification = null;
        // The provider still says a run is paused (say, a stale flag);
        // with no open card there is nothing to answer, and the ordinary
        // streaming guard applies.
        fakeChatProvider.awaitingClarification = true;
        viewModel.setTextFieldValue('the Freddie one');

        final result = await viewModel.sendMessage(
          onModelSelectionRequired: () async {},
          onServerNotConfigured: () {},
        );

        expect(result, isFalse);
        expect(fakeChatProvider.answeredClarification, isNull);
        expect(card.selected, ['The planet']);
      });
    });

    test('should call onServerNotConfigured when server not configured', () async {
      await Hive.box('settings').delete('serverAddress');
      viewModel.setTextFieldValue('Hello');
      var serverNotConfiguredCalled = false;

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () => serverNotConfiguredCalled = true,
      );

      expect(result, isFalse);
      expect(serverNotConfiguredCalled, isTrue);
    });

    test('should call onModelSelectionRequired when no model selected and no current chat', () async {
      viewModel.setTextFieldValue('Hello');
      var modelSelectionCalled = false;

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {
          modelSelectionCalled = true;
        },
        onServerNotConfigured: () {},
      );

      expect(modelSelectionCalled, isTrue);
    });

    test('should return false if no model selected after selection callback', () async {
      viewModel.setTextFieldValue('Hello');

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    test('should create new chat and send message when model selected', () async {
      viewModel.setTextFieldValue('Hello');
      final model = createTestModel('llama3.2');
      viewModel.setSelectedModel(model);

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.createNewChatCalled, isTrue);
      expect(fakeChatProvider.sendPromptCalled, isTrue);
      expect(fakeChatProvider.generateTitleCalled, isTrue);
    });

    test('should clear text field after sending', () async {
      viewModel.setTextFieldValue('Hello');
      viewModel.setSelectedModel(createTestModel('llama3.2'));

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(viewModel.textFieldController.text, isEmpty);
    });

    test('should send message directly when current chat exists', () async {
      viewModel.setTextFieldValue('Hello');
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.createNewChatCalled, isFalse);
      expect(fakeChatProvider.sendPromptCalled, isTrue);
      expect(fakeChatProvider.generateTitleCalled, isFalse);
    });
  });

  group('web search propagation to re-run paths', () {
    setUp(() {
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));
      fakeChatProvider.setMessages([
        OllamaMessage('Hello', role: OllamaMessageRole.user),
        OllamaMessage('Hi there', role: OllamaMessageRole.assistant),
      ]);
    });

    test('regenerateMessage forwards search attempts and wires callbacks when web search enabled', () async {
      viewModel.acceptWebSearchConsent(); // enables web search

      await viewModel.regenerateMessage(fakeChatProvider.messages.last);

      expect(fakeChatProvider.regenerateMessageCalled, isTrue);
      expect(fakeChatProvider.lastRegenerateSearchAttempts, 3);
      expect(fakeChatProvider.setWebSearchCallbacksCalled, isTrue);
      expect(fakeChatProvider.clearWebSearchCallbacksCalled, isTrue);
    });

    test('regenerateMessage uses 0 attempts when web search disabled', () async {
      await viewModel.regenerateMessage(fakeChatProvider.messages.last);

      expect(fakeChatProvider.regenerateMessageCalled, isTrue);
      expect(fakeChatProvider.lastRegenerateSearchAttempts, 0);
      expect(fakeChatProvider.setWebSearchCallbacksCalled, isFalse);
    });

    test('editAndResend forwards search attempts and wires callbacks when web search enabled', () async {
      viewModel.acceptWebSearchConsent();

      await viewModel.editAndResend(fakeChatProvider.messages.first, 'edited');

      expect(fakeChatProvider.editAndResendCalled, isTrue);
      expect(fakeChatProvider.lastEditAndResendSearchAttempts, 3);
      expect(fakeChatProvider.setWebSearchCallbacksCalled, isTrue);
      expect(fakeChatProvider.clearWebSearchCallbacksCalled, isTrue);
    });

    test('editAndResend uses 0 attempts when web search disabled', () async {
      await viewModel.editAndResend(fakeChatProvider.messages.first, 'edited');

      expect(fakeChatProvider.editAndResendCalled, isTrue);
      expect(fakeChatProvider.lastEditAndResendSearchAttempts, 0);
      expect(fakeChatProvider.setWebSearchCallbacksCalled, isFalse);
    });

    test('retryLastPrompt forwards search attempts when web search enabled', () async {
      viewModel.acceptWebSearchConsent();

      await viewModel.retryLastPrompt();

      expect(fakeChatProvider.retryLastPromptCalled, isTrue);
      expect(fakeChatProvider.lastRetrySearchAttempts, 3);
    });

    test('retryLastPrompt uses 0 attempts when web search disabled', () async {
      await viewModel.retryLastPrompt();

      expect(fakeChatProvider.retryLastPromptCalled, isTrue);
      expect(fakeChatProvider.lastRetrySearchAttempts, 0);
    });
  });

  group('web search UI wiring (round, ledger, skip, termination)', () {
    setUp(() async {
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));
      viewModel.setTextFieldValue('Hello');
      viewModel.acceptWebSearchConsent(); // enables web search

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
    });

    test('captured onSearchStart stamps increasing round numbers in order', () {
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;

      onSearchStart('first query');
      onSearchStart('second query');
      onSearchStart('third query');

      final cards =
          viewModel.searchSegments.whereType<SearchCardSegment>().toList();
      expect(cards.map((c) => c.round).toList(), [1, 2, 3]);
      expect(cards.map((c) => c.query).toList(),
          ['first query', 'second query', 'third query']);
    });

    test(
        'onLedgerUpdate creates exactly one ResearchLedgerSegment and updates it in place',
        () {
      final onLedgerUpdate = fakeChatProvider.capturedOnLedgerUpdate!;
      final goal = SubGoal(query: 'q1', normalizedQuery: 'q1')
        ..status = SubGoalStatus.searched
        ..ranges.add(const SourceIdRange(1, 2))
        ..excerpt = 'evidence found';

      onLedgerUpdate('what is the objective', [goal]);

      var ledgers = viewModel.searchSegments
          .whereType<ResearchLedgerSegment>()
          .toList();
      expect(ledgers.length, 1);
      expect(ledgers.single.objective, 'what is the objective');
      expect(ledgers.single.entries.single.query, 'q1');
      expect(ledgers.single.entries.single.searched, isTrue);
      expect(ledgers.single.entries.single.ranges,
          [const SourceIdRange(1, 2)]);
      expect(ledgers.single.entries.single.excerpt, 'evidence found');

      // A second update (e.g. a later round) must overwrite the same
      // segment in place, not append a second one.
      final secondGoal = SubGoal(query: 'q2', normalizedQuery: 'q2');
      onLedgerUpdate('what is the objective', [goal, secondGoal]);

      ledgers = viewModel.searchSegments
          .whereType<ResearchLedgerSegment>()
          .toList();
      expect(ledgers.length, 1,
          reason: 'must update in place, not append a duplicate segment');
      expect(ledgers.single.entries.length, 2);
      expect(ledgers.single.entries[1].searched, isFalse);
    });

    test('a rendered ledger entry does not change when the harness searches '
        'that sub-goal again', () {
      // The harness keeps mutating its own SubGoal list for the rest of the
      // run. An entry already handed to the UI must be a snapshot, or a
      // later search silently rewrites a panel the user is looking at.
      final onLedgerUpdate = fakeChatProvider.capturedOnLedgerUpdate!;
      final goal = SubGoal(query: 'q1', normalizedQuery: 'q1')
        ..status = SubGoalStatus.searched
        ..ranges.add(const SourceIdRange(1, 8));

      onLedgerUpdate('objective', [goal]);
      final rendered = viewModel.searchSegments
          .whereType<ResearchLedgerSegment>()
          .single
          .entries
          .single;

      goal.ranges.add(const SourceIdRange(25, 32));

      expect(rendered.ranges, [const SourceIdRange(1, 8)]);
    });

    test(
        'onSearchSkipped appends a new card and never mutates a completed one',
        () {
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchComplete = fakeChatProvider.capturedOnSearchComplete!;
      final onSearchSkipped = fakeChatProvider.capturedOnSearchSkipped!;

      onSearchStart('q1');
      onSearchComplete([
        WebSearchResult(
            url: 'https://example.com',
            title: 't',
            snippet: 's',
            pageContent: 'body'),
      ]);
      onSearchSkipped(
          'q1 again', 'You already asked something very close to this.');

      final cards =
          viewModel.searchSegments.whereType<SearchCardSegment>().toList();
      expect(cards.length, 2);
      expect(cards[0].query, 'q1');
      expect(cards[0].skipReason, isNull);
      expect(cards[0].urls, isNotEmpty,
          reason: 'the completed card must be untouched by the skip');
      expect(cards[1].query, 'q1 again');
      expect(cards[1].skipReason,
          'You already asked something very close to this.');
      expect(cards[1].isComplete, isTrue);
      expect(cards[1].round, 2);
    });

    test('onResearchDone sets terminationReason on the ledger segment', () {
      fakeChatProvider.capturedOnLedgerUpdate!('objective', const []);
      fakeChatProvider.capturedOnResearchDone!(SearchTerminationReason.converged);

      final ledger = viewModel.searchSegments
          .whereType<ResearchLedgerSegment>()
          .single;
      expect(ledger.terminationReason, 'converged');
    });

    test(
        'a search abandoned mid-flight resolves its own card instead of '
        'leaving it spinning', () {
      // What a rate-limited round actually does: SearchAgent opens a card
      // via onSearchStart, the search throws WebSearchUnavailableException,
      // and the SAME query comes back through onSearchSkipped — it never
      // reaches onSearchComplete. Appending there left the opened card
      // reading "Searching: ..." with a spinner for the rest of the
      // session, next to a duplicate card for the same query.
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchSkipped = fakeChatProvider.capturedOnSearchSkipped!;

      onSearchStart('taiwan gdp 2025');
      onSearchSkipped('taiwan gdp 2025', 'This query was NOT searched.');

      final cards =
          viewModel.searchSegments.whereType<SearchCardSegment>().toList();
      expect(cards.length, 1,
          reason: 'the in-flight card is resolved, not duplicated');
      expect(cards.single.isComplete, isTrue);
      expect(cards.single.skipReason, 'This query was NOT searched.');
      expect(cards.single.round, 1);
    });

    test('a skip for a different query still appends while one is in flight',
        () {
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchSkipped = fakeChatProvider.capturedOnSearchSkipped!;

      onSearchStart('q1');
      onSearchSkipped('q2', 'Not run this round.');

      final cards =
          viewModel.searchSegments.whereType<SearchCardSegment>().toList();
      expect(cards.length, 2);
      expect(cards[0].query, 'q1');
      expect(cards[0].skipReason, isNull);
      expect(cards[1].query, 'q2');
      expect(cards[1].skipReason, 'Not run this round.');
    });

    test('an in-flight card is still resolved when skips for other queries '
        'were reported first', () {
      // A round reports the queries it declined only after the one it
      // actually started, so the open card is not necessarily the last one.
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchSkipped = fakeChatProvider.capturedOnSearchSkipped!;

      onSearchStart('q1');
      onSearchSkipped('', 'No query provided; nothing was searched.');
      onSearchSkipped('q1', 'This query was NOT searched.');

      final cards =
          viewModel.searchSegments.whereType<SearchCardSegment>().toList();
      expect(cards.length, 2);
      expect(cards[0].query, 'q1');
      expect(cards[0].isComplete, isTrue);
      expect(cards[0].skipReason, 'This query was NOT searched.');
    });

    test('segmentsProvider closes a card the run left open before the '
        'message is persisted', () {
      // ChatProvider calls this to encode the segments into the saved
      // message. Decoding forces every card complete, so a card left open
      // here would come back claiming it searched and found nothing.
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onUrlsKnown = fakeChatProvider.capturedOnUrlsKnown!;

      onSearchStart('q1');
      onUrlsKnown([
        WebSearchResult(url: 'https://example.com', title: 't', snippet: 's'),
      ]);

      fakeChatProvider.capturedSegmentsProvider!();

      final card =
          viewModel.searchSegments.whereType<SearchCardSegment>().single;
      expect(card.isComplete, isTrue);
      expect(card.error, 'Search did not finish');
      expect(card.urls.single.state, SearchURLState.failed,
          reason: 'a pending row shimmers forever otherwise');
    });

    test('a completed card is left untouched by the finalize sweep', () {
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchComplete = fakeChatProvider.capturedOnSearchComplete!;

      onSearchStart('q1');
      onSearchComplete([
        WebSearchResult(
            url: 'https://example.com',
            title: 't',
            snippet: 's',
            pageContent: 'body'),
      ]);

      fakeChatProvider.capturedSegmentsProvider!();

      final card =
          viewModel.searchSegments.whereType<SearchCardSegment>().single;
      expect(card.error, isNull);
      expect(card.urls.single.state, SearchURLState.success);
    });

    test(
        'onSearchComplete truncates persisted source content and drops the duplicate extractedContent copy',
        () {
      final onSearchStart = fakeChatProvider.capturedOnSearchStart!;
      final onSearchComplete = fakeChatProvider.capturedOnSearchComplete!;

      onSearchStart('q1');
      onSearchComplete([
        WebSearchResult(
          url: 'https://example.com/a',
          title: 't',
          snippet: 's',
          pageContent: 'x'.padRight(5000, 'x'),
        ),
      ]);

      final card =
          viewModel.searchSegments.whereType<SearchCardSegment>().single;
      // sources[].content already carries this (SearchDetailDialog prefers
      // it); persisting the same text a second time here just bloats the
      // `thinking` blob every card gets base64-JSON'd into.
      expect(card.extractedContent, isNull);
      expect(card.sources, isNotNull);
      expect(card.sources!.single.content.length, lessThan(5000));
    });
  });

  group('live thinking and the phase signal', () {
    setUp(() async {
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));
      viewModel.setTextFieldValue('Hello');
      viewModel.acceptWebSearchConsent(); // enables web search

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
    });

    test('thinking deltas accumulate into one open segment', () {
      final onThinkingDelta = fakeChatProvider.capturedOnThinkingDelta!;

      onThinkingDelta('I should ');
      onThinkingDelta('look this up.');

      final thinking =
          viewModel.searchSegments.whereType<ThinkingSegment>().toList();
      // One block that grows, not one block per token — the whole point of
      // making the segment live rather than appending completed ones.
      expect(thinking, hasLength(1));
      expect(thinking.single.text, 'I should look this up.');
      expect(thinking.single.isComplete, isFalse);
      expect(thinking.single.startedAt, isNotNull);
    });

    test('onSearchThinking completes the segment the deltas were building',
        () {
      final onThinkingDelta = fakeChatProvider.capturedOnThinkingDelta!;
      final onSearchThinking = fakeChatProvider.capturedOnSearchThinking!;

      onThinkingDelta('partial reason');
      final open =
          viewModel.searchSegments.whereType<ThinkingSegment>().single;

      onSearchThinking('the whole reason, authoritatively');

      final thinking =
          viewModel.searchSegments.whereType<ThinkingSegment>().toList();
      expect(thinking, hasLength(1),
          reason: 'the turn ending must not append a second block below the '
              'one the user has been watching');
      // Same instance, so the widget keyed on it keeps its element and its
      // collapse animation instead of being swapped out.
      expect(identical(thinking.single, open), isTrue);
      expect(thinking.single.text, 'the whole reason, authoritatively');
      expect(thinking.single.isComplete, isTrue);
      // Measured from startedAt; a test run is far under a second, so the
      // contract asserted here is that it was measured at all.
      expect(thinking.single.elapsedSeconds, isNotNull);
      expect(thinking.single.elapsedSeconds, greaterThanOrEqualTo(0));
    });

    test('onSearchThinking with nothing open appends a complete segment', () {
      // The legacy path: a caller that reports a whole turn's reasoning
      // without ever having streamed a delta.
      fakeChatProvider.capturedOnSearchThinking!('a whole turn at once');

      final thinking =
          viewModel.searchSegments.whereType<ThinkingSegment>().single;
      expect(thinking.text, 'a whole turn at once');
      expect(thinking.isComplete, isTrue);
      expect(thinking.elapsedSeconds, isNull);
    });

    test('the answer turn closes the block it was reasoning in', () {
      // The answering turn's thinking never reaches onSearchThinking — the
      // agent only reports that for turns that go on to search — so without
      // this the last block would stay live forever.
      final onThinkingDelta = fakeChatProvider.capturedOnThinkingDelta!;
      onThinkingDelta('deciding how to phrase this');

      fakeChatProvider.capturedOnAnswerStart!();

      final thinking =
          viewModel.searchSegments.whereType<ThinkingSegment>().single;
      expect(thinking.isComplete, isTrue);
      expect(thinking.elapsedSeconds, isNotNull);
    });

    test('the ledger says it is deriving only while the goal is being framed',
        () {
      final onPhase = fakeChatProvider.capturedOnPhase!;
      final onLedgerUpdate = fakeChatProvider.capturedOnLedgerUpdate!;

      onPhase(ResearchPhase.framingGoal);
      onLedgerUpdate('What is Vietnam GDP?', const []);

      final ledger =
          viewModel.searchSegments.whereType<ResearchLedgerSegment>().single;
      // The objective on screen is still the user's raw question standing
      // in for a derived goal that has not landed yet.
      expect(ledger.isDeriving, isTrue);

      onPhase(ResearchPhase.thinking);

      expect(ledger.isDeriving, isFalse);
    });

    test('a finished run leaves no phase behind', () async {
      fakeChatProvider.capturedOnPhase!(ResearchPhase.searching);

      expect(viewModel.researchPhase, ResearchPhase.searching);
      expect(viewModel.researchPhaseStartedAt, isNotNull);

      // The strip must never outlive the run it describes: the next run
      // resets on the way in, and this one clears on the way out.
      await viewModel.retryLastPrompt();

      expect(viewModel.researchPhase, isNull);
      expect(viewModel.researchPhaseStartedAt, isNull);
    });
  });

  group('search machinery teardown', () {
    test('a run that ends without closing its card does not leave the bubble '
        'searching', () async {
      // The stop button and the search card both read as "generating". A run
      // that ends between onSearchStart and its matching close — cancelled
      // mid-fetch, or a turn that threw before anything was persisted — must
      // not leave the card spinning once the machinery is torn down.
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));
      viewModel.setTextFieldValue('Hello');
      viewModel.acceptWebSearchConsent();
      fakeChatProvider.duringSendPrompt = () async {
        fakeChatProvider.capturedOnSearchStart!('q1');
      };

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(viewModel.isSearching, isFalse);
      final card =
          viewModel.searchSegments.whereType<SearchCardSegment>().single;
      expect(card.isComplete, isTrue);
      expect(card.error, 'Search did not finish');
    });
  });

  group('isServerConfigured', () {
    test('should return true when serverAddress is set', () {
      expect(viewModel.isServerConfigured, isTrue);
    });

    test('should return false when serverAddress is null', () async {
      await Hive.box('settings').delete('serverAddress');

      expect(viewModel.isServerConfigured, isFalse);
    });
  });
}

// ============================================================
// Test Helpers
// ============================================================

OllamaModel createTestModel(String name) {
  return OllamaModel(
    name: name,
    model: name,
    modifiedAt: DateTime.now(),
    size: 1000,
    digest: 'test-digest-$name',
    parameterSize: '1B',
  );
}

OllamaChat createTestChat(String id) {
  return OllamaChat(
    id: id,
    model: 'llama3.2',
    title: 'Test Chat',
    options: OllamaChatOptions(),
    systemPrompt: null,
  );
}

// ============================================================
// Fake Classes
// ============================================================

class FakeChatProvider extends ChangeNotifier implements ChatProvider {
  List<OllamaMessage> _messages = [];
  OllamaChat? _currentChat;
  bool _isStreaming = false;
  bool _isThinking = false;
  OllamaException? _currentError;
  List<OllamaModel> _availableModels = [];

  bool cancelStreamingCalled = false;
  bool retryLastPromptCalled = false;
  bool regenerateMessageCalled = false;
  bool editAndResendCalled = false;
  bool createNewChatCalled = false;
  bool displayUserMessageCalled = false;
  bool sendPromptCalled = false;
  bool generateTitleCalled = false;
  bool setWebSearchCallbacksCalled = false;
  bool clearWebSearchCallbacksCalled = false;
  String? lastSentPrompt;
  List<File>? lastSentImages;
  int? lastSendPromptSearchAttempts;
  int? lastRegenerateSearchAttempts;
  int? lastEditAndResendSearchAttempts;
  int? lastRetrySearchAttempts;
  OllamaMessage? deletedExchangeAnchor;

  // Captured web-search callbacks — installed by ChatPageViewModel via
  // setWebSearchCallbacks. Tests invoke these directly to simulate
  // SearchAgent driving the UI, instead of running a real search.
  void Function(String thinking)? capturedOnSearchThinking;
  void Function(String query)? capturedOnSearchStart;
  void Function(String query)? capturedOnSearchQueryUpdate;
  void Function(List<WebSearchResult> results)? capturedOnSearchComplete;
  List<MessageSegment> Function()? capturedSegmentsProvider;
  void Function(List<WebSearchResult> urls)? capturedOnUrlsKnown;
  void Function(String url, bool success)? capturedOnUrlFetched;
  void Function()? capturedOnAnswerStart;
  void Function(String objective, List<SubGoal> snapshot)? capturedOnLedgerUpdate;
  void Function(String query, String reason)? capturedOnSearchSkipped;
  void Function(SearchTerminationReason reason)? capturedOnResearchDone;
  void Function(ResearchClarification clarification)? capturedOnClarification;
  void Function(ResearchPhase phase)? capturedOnPhase;
  void Function(String delta)? capturedOnThinkingDelta;

  /// Whether a run is paused on a clarification card, as the view model
  /// reads it; and what it handed back when the card was answered.
  bool awaitingClarification = false;
  List<String>? answeredClarification;

  @override
  bool get isAwaitingClarification => awaitingClarification;

  @override
  void answerClarification(List<String> selected) {
    answeredClarification = selected;
    awaitingClarification = false;
  }

  void setMessages(List<OllamaMessage> messages) {
    _messages = messages;
  }

  void setCurrentChat(OllamaChat? chat) {
    _currentChat = chat;
  }

  void setIsStreaming(bool value) {
    _isStreaming = value;
  }

  void setIsThinking(bool value) {
    _isThinking = value;
  }

  void setCurrentError(OllamaException? error) {
    _currentError = error;
  }

  void setAvailableModels(List<OllamaModel> models) {
    _availableModels = models;
  }

  void triggerNotifyListeners() {
    notifyListeners();
  }

  @override
  List<OllamaMessage> get messages => _messages;

  @override
  OllamaChat? get currentChat => _currentChat;

  @override
  bool get isCurrentChatStreaming => _isStreaming;

  @override
  bool get isCurrentChatThinking => _isThinking;

  @override
  OllamaException? get currentChatError => _currentError;

  @override
  void cancelCurrentStreaming() {
    cancelStreamingCalled = true;
  }

  @override
  Future<void> retryLastPrompt({int searchAttemptsRemaining = 0}) async {
    retryLastPromptCalled = true;
    lastRetrySearchAttempts = searchAttemptsRemaining;
  }

  @override
  Future<void> regenerateMessage(OllamaMessage message, {int searchAttemptsRemaining = 0}) async {
    regenerateMessageCalled = true;
    lastRegenerateSearchAttempts = searchAttemptsRemaining;
  }

  @override
  Future<void> deleteExchange(OllamaMessage anchor) async {
    deletedExchangeAnchor = anchor;
  }

  @override
  Future<void> editAndResend(OllamaMessage originalMessage, String newContent, {int searchAttemptsRemaining = 0}) async {
    editAndResendCalled = true;
    lastEditAndResendSearchAttempts = searchAttemptsRemaining;
  }

  @override
  void setWebSearchCallbacks({
    required void Function(String thinking) onSearchThinking,
    required void Function(String query) onSearchStart,
    required void Function(String query) onSearchQueryUpdate,
    required void Function(List<WebSearchResult> results) onSearchComplete,
    required List<MessageSegment> Function() segmentsProvider,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
    void Function()? onAnswerStart,
    void Function(String objective, List<SubGoal> snapshot)? onLedgerUpdate,
    void Function(String query, String reason)? onSearchSkipped,
    void Function(SearchTerminationReason reason)? onResearchDone,
    void Function(ResearchClarification clarification)? onClarification,
    void Function(ResearchPhase phase)? onPhase,
    void Function(String delta)? onThinkingDelta,
    bool Function()? hasLiveThinking,
  }) {
    setWebSearchCallbacksCalled = true;
    capturedOnSearchThinking = onSearchThinking;
    capturedOnSearchStart = onSearchStart;
    capturedOnSearchQueryUpdate = onSearchQueryUpdate;
    capturedOnSearchComplete = onSearchComplete;
    capturedSegmentsProvider = segmentsProvider;
    capturedOnUrlsKnown = onUrlsKnown;
    capturedOnUrlFetched = onUrlFetched;
    capturedOnAnswerStart = onAnswerStart;
    capturedOnLedgerUpdate = onLedgerUpdate;
    capturedOnSearchSkipped = onSearchSkipped;
    capturedOnResearchDone = onResearchDone;
    capturedOnClarification = onClarification;
    capturedOnPhase = onPhase;
    capturedOnThinkingDelta = onThinkingDelta;
  }

  @override
  void clearWebSearchCallbacks() {
    clearWebSearchCallbacksCalled = true;
  }

  @override
  Future<List<OllamaModel>> fetchAvailableModels() async {
    return _availableModels;
  }

  @override
  Future<void> createNewChat(OllamaModel model, {bool isIncognito = false}) async {
    createNewChatCalled = true;
    _currentChat = createTestChat('new-chat-id');
  }

  @override
  OllamaMessage displayUserMessage(String text, {List<File>? images}) {
    displayUserMessageCalled = true;
    lastSentPrompt = text;
    lastSentImages = images;
    final message = OllamaMessage(text.trim(), images: images, role: OllamaMessageRole.user);
    _messages.add(message);
    return message;
  }

  /// Runs while sendPrompt is in flight, so a test can drive the captured
  /// web-search callbacks the way SearchAgent would during a real run —
  /// i.e. before the view model tears the machinery down.
  Future<void> Function()? duringSendPrompt;

  @override
  Future<void> sendPrompt(OllamaMessage prompt, {int searchAttemptsRemaining = 0}) async {
    sendPromptCalled = true;
    lastSendPromptSearchAttempts = searchAttemptsRemaining;
    await duringSendPrompt?.call();
  }

  @override
  Future<void> generateTitleForCurrentChat() async {
    generateTitleCalled = true;
  }

  // Unused ChatProvider methods - stub implementations
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePermissionService implements PermissionService {
  bool shouldGrantPermission = true;
  bool permissionRequested = false;

  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async {
    permissionRequested = true;
    if (!shouldGrantPermission) {
      onDenied?.call();
    }
    return shouldGrantPermission;
  }
}

class FakeImageService implements ImageService {
  List<File> deletedImages = [];
  File? compressedFile;

  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async {
    return compressedFile;
  }

  @override
  Future<void> deleteImage(File imageFile) async {
    deletedImages.add(imageFile);
  }

  @override
  Future<void> deleteImages(List<File> imageFiles) async {
    deletedImages.addAll(imageFiles);
  }

  @override
  Future<Directory> getImagesDirectory() async {
    return Directory.systemTemp;
  }
}

class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.createTempSync('chat_page_vm_docs').path;
  }
}
