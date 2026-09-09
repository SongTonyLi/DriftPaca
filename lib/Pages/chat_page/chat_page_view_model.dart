import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/chat_preset.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';

class ChatPageViewModel extends ChangeNotifier {
  final ChatProvider _chatProvider;
  final PermissionService _permissionService;
  final ImageService _imageService;
  ChatPageViewModel({
    required ChatProvider chatProvider,
    required PermissionService permissionService,
    required ImageService imageService,
  })  : _chatProvider = chatProvider,
        _permissionService = permissionService,
        _imageService = imageService {
    _initialize();
  }

  // ============================================================
  // Page State
  // ============================================================

  /// Whether web search is enabled for the next message
  bool _webSearchEnabled = false;
  bool get webSearchEnabled => _webSearchEnabled;

  /// Whether a search orchestrator is currently running
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// Message segments for the current search-augmented response (ephemeral)
  final List<MessageSegment> _searchSegments = [];
  List<MessageSegment> get searchSegments => List.unmodifiable(_searchSegments);

  /// Whether the user has accepted the web search disclosure
  bool get webSearchConsented => Hive.box('settings').get('webSearchConsented', defaultValue: false);

  /// Toggles web search on/off. Returns true if consent dialog should be shown.
  bool toggleWebSearch() {
    if (!_webSearchEnabled && !webSearchConsented) {
      return true; // needs consent first
    }
    _webSearchEnabled = !_webSearchEnabled;
    notifyListeners();
    return false;
  }

  /// Accept web search consent and enable it
  void acceptWebSearchConsent() {
    Hive.box('settings').put('webSearchConsented', true);
    _webSearchEnabled = true;
    notifyListeners();
  }

  // ============================================================
  // Other Page State
  // ============================================================

  /// Whether the next new chat should be incognito
  bool _incognitoRequested = false;
  bool get incognitoRequested => _incognitoRequested;

  /// Request the next new chat to be incognito
  void requestIncognito() {
    _incognitoRequested = true;
    notifyListeners();
  }

  /// Clear incognito request (return to normal mode)
  void clearIncognito() {
    _incognitoRequested = false;
    notifyListeners();
  }

  /// The selected model for new chats
  OllamaModel? _selectedModel;
  OllamaModel? get selectedModel => _selectedModel;

  /// The list of chat presets
  List<ChatPreset> _presets = ChatPresets.randomPresets;
  List<ChatPreset> get presets => _presets;

  /// The text field controller
  final TextEditingController textFieldController = TextEditingController();

  /// Whether the text field has text
  bool get hasText => textFieldController.text.trim().isNotEmpty;

  bool _lastHasText = false;

  /// The app lifecycle listener for cleanup
  late final AppLifecycleListener _appLifecycleListener;

  /// The Hive settings subscription
  late final StreamSubscription _settingsSubscription;

  // Tracked state for skipping redundant notifications from ChatProvider
  int _lastMessageCount = 0;
  String? _lastChatId;
  bool _lastIsStreaming = false;
  bool _lastIsThinking = false;
  String? _lastErrorMessage;

  bool get isServerConfigured {
    final box = Hive.box('settings');
    final serverMode = box.get('serverMode', defaultValue: 'local');
    if (serverMode == 'openwebui') {
      return box.get('openwebuiAddress') != null;
    }
    if (serverMode == 'openrouter') {
      return box.get('openrouterApiKey') != null;
    }
    final isCloudMode = box.get('isCloudMode', defaultValue: false);
    if (isCloudMode) {
      return box.get('cloudApiKey') != null;
    }
    return box.get('serverAddress') != null;
  }

  // ============================================================
  // Initialization
  // ============================================================

  void _initialize() {
    // Listen to ChatProvider changes and forward notifications
    _chatProvider.addListener(_onChatProviderChanged);

    // Listen to text field changes to update UI (e.g., send button visibility)
    textFieldController.addListener(_onTextFieldChanged);

    // If server config changes, reset the selected model
    _settingsSubscription = Hive.box('settings').watch().listen((event) {
      if (event.key == 'serverAddress' ||
          event.key == 'serverMode' ||
          event.key == 'isCloudMode' ||
          event.key == 'cloudApiKey' ||
          event.key == 'openrouterApiKey') {
        _selectedModel = null;
        notifyListeners();
      }
    });

    // Listen for app exit to delete unused attached images
    _appLifecycleListener = AppLifecycleListener(onExitRequested: () async {
      await _imageService.deleteImages(imageFiles);
      return AppExitResponse.exit;
    });
  }

  void _onChatProviderChanged() {
    final messageCount = _chatProvider.messages.length;
    final chatId = _chatProvider.currentChat?.id;
    final isStreaming = _chatProvider.isCurrentChatStreaming;
    final isThinking = _chatProvider.isCurrentChatThinking;
    final errorMessage = _chatProvider.currentChatError?.message;

    // Clear stale search segments when switching chats
    if (chatId != _lastChatId) {
      _searchSegments.clear();
    }

    // Always forward during streaming/thinking — message content is mutated
    // in place so tracked values won't change, but the UI (typewriter reveal)
    // depends on each notification to advance.
    if (isStreaming || isThinking ||
        messageCount != _lastMessageCount ||
        chatId != _lastChatId ||
        isStreaming != _lastIsStreaming ||
        isThinking != _lastIsThinking ||
        errorMessage != _lastErrorMessage) {
      _lastMessageCount = messageCount;
      _lastChatId = chatId;
      _lastIsStreaming = isStreaming;
      _lastIsThinking = isThinking;
      _lastErrorMessage = errorMessage;
      notifyListeners();
    }
  }

  void _onTextFieldChanged() {
    final currentHasText = hasText;
    if (currentHasText != _lastHasText) {
      _lastHasText = currentHasText;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_onChatProviderChanged);
    textFieldController.removeListener(_onTextFieldChanged);
    textFieldController.dispose();
    _appLifecycleListener.dispose();
    _settingsSubscription.cancel();
    super.dispose();
  }

  // ============================================================
  // ChatProvider State (Proxied)
  // ============================================================

  /// The list of messages in the current chat
  List<OllamaMessage> get messages => _chatProvider.messages;

  /// The current chat
  OllamaChat? get currentChat => _chatProvider.currentChat;

  /// Whether the current chat is streaming a response
  bool get isStreaming => _chatProvider.isCurrentChatStreaming;

  /// Whether the current chat is thinking (waiting for response)
  bool get isThinking => _chatProvider.isCurrentChatThinking;

  /// The current chat error, if any
  OllamaException? get currentError => _chatProvider.currentChatError;

  // ============================================================
  // ChatProvider Actions (Delegated)
  // ============================================================

  /// Cancels the current streaming response and any active search
  void cancelStreaming() {
    _isSearching = false;
    _chatProvider.cancelCurrentStreaming();
  }

  /// Retries the last prompt
  Future<void> retryLastPrompt() async {
    _searchSegments.clear();
    final searchToken = _webSearchEnabled ? _beginWebSearch() : null;
    try {
      await _chatProvider.retryLastPrompt(
          searchAttemptsRemaining: _webSearchEnabled ? 3 : 0);
    } finally {
      if (searchToken != null) _endWebSearch(searchToken);
    }
  }

  /// Regenerates the response for [message]
  Future<void> regenerateMessage(OllamaMessage message) async {
    _searchSegments.clear();
    final searchToken = _webSearchEnabled ? _beginWebSearch() : null;
    try {
      await _chatProvider.regenerateMessage(message,
          searchAttemptsRemaining: _webSearchEnabled ? 3 : 0);
    } finally {
      if (searchToken != null) _endWebSearch(searchToken);
    }
  }

  /// Edits [message] and resends it as a new message
  Future<void> editAndResend(OllamaMessage message, String newContent) async {
    _searchSegments.clear();
    final searchToken = _webSearchEnabled ? _beginWebSearch() : null;
    try {
      await _chatProvider.editAndResend(message, newContent,
          searchAttemptsRemaining: _webSearchEnabled ? 3 : 0);
    } finally {
      if (searchToken != null) _endWebSearch(searchToken);
    }
  }

  /// Fetches available models from the server
  Future<List<OllamaModel>> fetchAvailableModels() async {
    return await _chatProvider.fetchAvailableModels();
  }

  /// Deletes the exchange (turn-pair) that [message] belongs to.
  Future<void> deleteExchange(OllamaMessage message) async {
    await _chatProvider.deleteExchange(message);
  }

  // ============================================================
  // Model Selection
  // ============================================================

  /// Sets the selected model
  void setSelectedModel(OllamaModel? model) {
    _selectedModel = model;
    notifyListeners();
  }

  // ============================================================
  // Text Field
  // ============================================================

  /// Sets the text field value (e.g., for presets)
  void setTextFieldValue(String value) {
    textFieldController.text = value;
  }

  /// Gets and clears the text field value (for sending)
  String _takeTextFieldValue() {
    final value = textFieldController.text;
    textFieldController.clear();
    return value;
  }

  // ============================================================
  // Image Attachments
  // ============================================================

  final List<File> _imageFiles = [];

  /// The list of attached image files
  List<File> get imageFiles => List.unmodifiable(_imageFiles);

  /// Whether there are any image attachments
  bool get hasImageAttachments => _imageFiles.isNotEmpty;

  /// Handles image picking and compression
  Future<void> pickImages({
    VoidCallback? onPermissionDenied,
    VoidCallback? onCompressionFailed,
    int quality = 10,
  }) async {
    // Check permissions
    final hasPermission = await _permissionService.requestPhotoPermission(
      onDenied: onPermissionDenied,
    );
    if (!hasPermission) return;

    // Pick images
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(
      source: ImageSource.gallery,
    );
    // await _picker.pickMultiImage(limit: maxImages);

    if (pickedImage == null) return;

    // Compress and save
    final compressedFile = await _imageService.compressAndSave(
      pickedImage.path,
      quality: quality,
    );

    // Report the failure to the caller instead of attaching the image
    if (compressedFile == null) {
      onCompressionFailed?.call();
      return;
    }

    _imageFiles.add(compressedFile);

    notifyListeners();
  }

  /// Deletes a single image and removes it from the list
  Future<void> removeImage(File imageFile) async {
    await _imageService.deleteImage(imageFile);
    _imageFiles.remove(imageFile);
    notifyListeners();
  }

  /// Gets and clears the current images (for sending)
  List<File> _takeImages() {
    final images = _imageFiles.toList();
    _imageFiles.clear();
    return images;
  }

  // ============================================================
  // Operations
  // ============================================================

  /// Handles sending a message
  /// Returns true if the message was sent successfully
  Future<bool> sendMessage({
    required Future<void> Function() onModelSelectionRequired,
    required void Function() onServerNotConfigured,
  }) async {
    // A run paused on its clarification card is streaming as far as the
    // guard below is concerned, so what the user types here used to go
    // nowhere — under a prompt bar whose hint said to answer the question
    // above. Typed while the card is open, the message IS the answer: it
    // goes to the card as the user's own words, exactly as the card's own
    // field would send it, and the run resumes.
    if (hasText && isAwaitingClarification) {
      final card = _openClarification();
      if (card != null) {
        answerClarification(card, [_takeTextFieldValue().trim()]);
        return true;
      }
    }

    // Early return if nothing to send or currently streaming/searching
    if (!hasText || isStreaming || _isSearching) {
      return false;
    }

    // Clear stale search segments from previous messages
    _searchSegments.clear();

    // Check if server is configured
    if (!isServerConfigured) {
      onServerNotConfigured();
      return false;
    }

    // If no current chat, need to create one
    bool isNewChat = false;
    if (_chatProvider.currentChat == null) {
      // If no model selected, request selection
      if (_selectedModel == null) {
        await onModelSelectionRequired();
      }

      // If still no model after selection, abort
      if (_selectedModel == null) {
        return false;
      }

      // Create a new chat with the selected model
      await _chatProvider.createNewChat(_selectedModel!, isIncognito: _incognitoRequested);
      _incognitoRequested = false;
      _presets = ChatPresets.randomPresets;
      isNewChat = true;
    }

    // Take the prompt and images, then display the bubble immediately
    final prompt = _takeTextFieldValue();
    final images = _takeImages();
    final message = _chatProvider.displayUserMessage(prompt, images: images);
    notifyListeners();

    // Set up web search machinery (UI callbacks + segment persistence)
    final searchToken = _webSearchEnabled ? _beginWebSearch() : null;

    // Persist message and start the AI response stream
    try {
      await _chatProvider.sendPrompt(message,
          searchAttemptsRemaining: _webSearchEnabled ? 3 : 0);
    } finally {
      // Always clean up search state, even on error
      if (searchToken != null) {
        _endWebSearch(searchToken);
      }

      // Generate title for new chats — in finally so it runs even if
      // sendPrompt throws (e.g. post-stream processing errors in web search)
      if (isNewChat) {
        await _chatProvider.generateTitleForCurrentChat();
      }
    }

    return true;
  }

  /// Wires web-search UI callbacks and segment persistence onto the
  /// ChatProvider, then flags the searching state. Every path that can
  /// trigger a search-augmented response funnels through this:
  /// [sendMessage], [regenerateMessage], [editAndResend], [retryLastPrompt].
  /// Returns a token identifying this request; pass it to [_endWebSearch]
  /// in a finally block so a stale request never tears down the callbacks
  /// installed by a newer one.
  Object _beginWebSearch() {
    _isSearching = true;
    _searchSegments.clear();
    notifyListeners();

    final token = Object();
    _webSearchToken = token;
    _chatProvider.setWebSearchCallbacks(
      onSearchThinking: (thinking) {
        _searchSegments.add(ThinkingSegment(thinking));
        notifyListeners();
      },
      // Called once, by ChatProvider, just before the assistant message is
      // encoded into its `thinking` blob — the last moment at which a card
      // left mid-flight can be closed before the stuck spinner is baked
      // into the saved message.
      segmentsProvider: () {
        _finalizeSearchCards();
        return _searchSegments;
      },
      onSearchStart: (query) {
        _searchSegments.add(SearchCardSegment(
          query: query,
          round: _searchCardOrdinal(),
        ));
        notifyListeners();
      },
      onSearchQueryUpdate: (query) {
        final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
        if (card != null) {
          card.query = query;
          notifyListeners();
        }
      },
      // Populate URLs in `pending` state as soon as DDG returns. The
      // SearchCard renders the list with a shimmer + spinner per row;
      // onUrlFetched flips entries to success/failed one by one.
      onUrlsKnown: (urls) {
        final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
        if (card == null) return;
        card.urls = [
          for (final r in urls)
            SearchURLStatus(
              url: r.url,
              domain: Uri.tryParse(r.url)?.host ?? r.url,
              title: r.title,
              state: SearchURLState.pending,
            ),
        ];
        // Warm favicon cache for these domains so the source-card
        // dialog and any future inline citation render instantly.
        FaviconCache.instance.preload(card.urls.map((u) => u.domain));
        notifyListeners();
      },
      onUrlFetched: (url, success) {
        final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
        if (card == null) return;
        for (final u in card.urls) {
          if (u.url == url) {
            u.state =
                success ? SearchURLState.success : SearchURLState.failed;
            break;
          }
        }
        notifyListeners();
      },
      onSearchComplete: (results) {
        final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
        if (card != null) {
          if (results.isEmpty) {
            card.error = 'No results found';
          } else {
            card.urls = results
                .map((r) => SearchURLStatus(
                      url: r.url,
                      domain: Uri.tryParse(r.url)?.host ?? r.url,
                      title: r.title,
                      state: r.pageContent != null
                          ? SearchURLState.success
                          : SearchURLState.failed,
                    ))
                .toList();
            card.resultCount = results.length;
            final sources = <SearchSource>[];
            for (final r in results) {
              final content = r.chunks != null && r.chunks!.isNotEmpty
                  ? r.chunks!.take(2).join('\n')
                  : (r.pageContent ?? r.snippet);
              if (content.isEmpty) continue;
              final domain = Uri.tryParse(r.url)?.host ?? r.url;
              sources.add(SearchSource(
                url: r.url,
                domain: domain,
                title: r.title,
                content: _truncateForPersistence(content),
              ));
            }
            // extractedContent is deliberately left unset: sources[].content
            // above already carries this text, and SearchDetailDialog
            // prefers sources — persisting it a second time (verbatim,
            // untruncated) just doubles the size of the `thinking` blob
            // every card gets base64-JSON'd into (see search_thinking_utils
            // .dart). Still decoded for messages persisted before this
            // field existed.
            card.sources = sources;
            // Preload favicons so inline citations and source cards
            // render instantly from cache instead of triggering a
            // network fetch when the assistant message paints.
            FaviconCache.instance.preload(sources.map((s) => s.domain));
          }
          card.isComplete = true;
          notifyListeners();
        }
      },
      onAnswerStart: () {
        if (_searchSegments.whereType<AnswerSegment>().isNotEmpty) return;
        if (_searchSegments.whereType<SearchCardSegment>().isEmpty) return;
        _searchSegments.add(AnswerSegment());
        notifyListeners();
      },
      // A search the harness declined to run (duplicate, empty query, over
      // budget, rate-limited, ...).
      //
      // Resolves the card for the search currently in flight when the skip
      // is about THAT query, and otherwise appends a fresh one. Both halves
      // matter:
      //
      //  - A rate-limited round abandons the search it had already started
      //    (SearchAgent._executeToolCalls breaks out of its loop on
      //    WebSearchUnavailableException) and reports it back through here
      //    rather than through onSearchComplete. Appending there left the
      //    started card spinning "Searching: ..." for the rest of the
      //    session — the answer finishes generating, the run ends, and the
      //    bubble still looks like it is searching — while a second card
      //    for the same query was added right below it.
      //  - Every other skip must NOT touch the most recent card: it may
      //    belong to an already-completed search, and mutating it would
      //    silently discard its URL list (see onSearchComplete above) the
      //    moment skipReason took over its render.
      onSearchSkipped: (query, reason) {
        final pending = _inFlightSearchCard();
        if (pending != null && pending.query == query) {
          // A skipped card renders its reason in place of the URL list, so
          // whatever partial list this search collected is dead weight.
          pending.urls = const [];
          pending.skipReason = reason;
          pending.isComplete = true;
        } else {
          _searchSegments.add(SearchCardSegment(
            query: query,
            skipReason: reason,
            isComplete: true,
            round: _searchCardOrdinal(),
          ));
        }
        notifyListeners();
      },
      // Fired once per round with the ledger's full current state — always
      // overwrites the single ResearchLedgerSegment in place (mirrors how
      // onSearchComplete replaces card.urls wholesale) so the bubble shows
      // one growing panel, not a stack of stale snapshots.
      onLedgerUpdate: (objective, snapshot) {
        final entries = [
          for (final goal in snapshot)
            LedgerEntryView(
              query: goal.query,
              searched: goal.status == SubGoalStatus.searched,
              // Copied, not aliased: the harness keeps mutating its own
              // list as later searches land on this sub-goal, and an
              // already-rendered entry must not change underneath the UI.
              ranges: List<SourceIdRange>.unmodifiable(goal.ranges),
              excerpt: goal.excerpt,
            ),
        ];
        final ledger =
            _searchSegments.whereType<ResearchLedgerSegment>().lastOrNull;
        if (ledger != null) {
          ledger.objective = objective;
          ledger.entries = entries;
        } else {
          _searchSegments
              .add(ResearchLedgerSegment(objective: objective, entries: entries));
        }
        notifyListeners();
      },
      onResearchDone: (reason) {
        final ledger =
            _searchSegments.whereType<ResearchLedgerSegment>().lastOrNull;
        if (ledger == null) return;
        ledger.terminationReason = reason.name;
        notifyListeners();
      },
      // The run is now paused on the user. The card renders from this
      // segment and hands the picks back through [answerClarification].
      onClarification: (clarification) {
        _searchSegments.add(ClarificationSegment(
          question: clarification.question,
          options: List<String>.unmodifiable(clarification.options),
        ));
        notifyListeners();
      },
    );

    return token;
  }

  /// Whether the current run is paused waiting for the user to answer a
  /// clarification card.
  bool get isAwaitingClarification => _chatProvider.isAwaitingClarification;

  /// The card the current run is paused on, if the live segments hold one.
  ClarificationSegment? _openClarification() => _searchSegments
      .whereType<ClarificationSegment>()
      .where((card) => !card.isAnswered)
      .lastOrNull;

  /// Resolves a clarification card with the user's answer — ticked options
  /// and/or their own typed words, empty to continue without answering —
  /// and resumes the paused run.
  void answerClarification(ClarificationSegment segment, List<String> selected) {
    if (segment.isAnswered) return;
    segment.selected = List<String>.unmodifiable(selected);
    notifyListeners();
    _chatProvider.answerClarification(selected);
  }

  /// Cap on how much of one source's extracted text gets persisted per
  /// search card. SearchAgent's search budget went from 3 to well past it
  /// (see SearchAgent.defaultMaxSearches), so an uncapped run can now
  /// accumulate many more cards than before; this keeps each one bounded so
  /// the base64-JSON `thinking` blob doesn't grow unbounded with it.
  static const _maxPersistedSourceChars = 2000;

  static String _truncateForPersistence(String content) =>
      content.length > _maxPersistedSourceChars
          ? content.substring(0, _maxPersistedSourceChars)
          : content;

  /// The card for the search the harness currently has in flight: opened by
  /// onSearchStart and not yet closed by onSearchComplete or onSearchSkipped.
  /// Null when nothing is running. Searches execute one at a time
  /// (SearchAgent._executeToolCalls awaits each in turn), so at most one card
  /// is ever open — but it need not be the LAST one, since a round reports
  /// the queries it declined only after the one it actually started.
  SearchCardSegment? _inFlightSearchCard() => _searchSegments
      .whereType<SearchCardSegment>()
      .where((card) => !card.isComplete && card.skipReason == null)
      .lastOrNull;

  /// Closes any search card still rendering as in flight.
  ///
  /// Every card the harness opens is normally closed by onSearchComplete or
  /// onSearchSkipped, but a run can end in between: stopped mid-fetch, or a
  /// turn that threw. An open card renders a spinner and a "Searching: ..."
  /// label for as long as these live segments back the bubble, so the answer
  /// finishes generating and the message still looks like it is searching.
  ///
  /// Called at persistence time (see segmentsProvider) and again when the
  /// search machinery is torn down, which together cover every path out of
  /// a run, including the ones that never save a message. The persistence
  /// call also matters after a reload: decoding forces every card complete
  /// (see search_thinking_utils.dart), so without an error recorded here a
  /// card that never finished comes back claiming it searched and found
  /// nothing.
  void _finalizeSearchCards() {
    // A clarification the run stopped waiting on is closed the same way,
    // so a reloaded message never shows a card that is still asking.
    for (final card in _searchSegments.whereType<ClarificationSegment>()) {
      card.selected ??= const [];
    }
    for (final card in _searchSegments.whereType<SearchCardSegment>()) {
      if (card.isComplete) continue;
      card.isComplete = true;
      card.error ??= 'Search did not finish';
      for (final url in card.urls) {
        if (url.state == SearchURLState.pending) {
          url.state = SearchURLState.failed;
        }
      }
    }
  }

  /// Ordinal position (1-indexed) the NEXT SearchCardSegment would occupy —
  /// real and skipped searches both counted, so "Search N" reads as one
  /// sequential narrative rather than claiming to be SearchAgent's internal
  /// batching round (several searches can share one of those).
  int _searchCardOrdinal() =>
      _searchSegments.whereType<SearchCardSegment>().length + 1;

  /// Identifies the request that currently owns the web-search machinery.
  Object? _webSearchToken;

  /// Tears down web-search callbacks and clears the searching flag, but only
  /// when [token] still owns the machinery. A request that was cancelled and
  /// superseded by a newer one must not tear the newer one's callbacks down.
  /// Pair with [_beginWebSearch].
  void _endWebSearch(Object token) {
    if (!identical(token, _webSearchToken)) {
      return;
    }
    _webSearchToken = null;
    _chatProvider.clearWebSearchCallbacks();
    // Nothing can close a card after this point — the callbacks are gone —
    // so a run that ended without closing one (an error before any message
    // was persisted, say) gets its spinner resolved here.
    _finalizeSearchCards();
    _isSearching = false;
    notifyListeners();
  }
}
