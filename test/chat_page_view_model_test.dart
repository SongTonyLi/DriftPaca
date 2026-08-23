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
        ..sourceIdStart = 1
        ..sourceIdEnd = 2
        ..excerpt = 'evidence found';

      onLedgerUpdate('what is the objective', [goal]);

      var ledgers = viewModel.searchSegments
          .whereType<ResearchLedgerSegment>()
          .toList();
      expect(ledgers.length, 1);
      expect(ledgers.single.objective, 'what is the objective');
      expect(ledgers.single.entries.single.query, 'q1');
      expect(ledgers.single.entries.single.searched, isTrue);
      expect(ledgers.single.entries.single.sourceIdStart, 1);
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

    test(
        'onSearchSkipped always appends a new card and never mutates an existing one',
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

  @override
  Future<void> sendPrompt(OllamaMessage prompt, {int searchAttemptsRemaining = 0}) async {
    sendPromptCalled = true;
    lastSendPromptSearchAttempts = searchAttemptsRemaining;
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
