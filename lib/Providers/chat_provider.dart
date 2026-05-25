import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:notification_centre/notification_centre.dart';

import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/chat_configure_arguments.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/search_thinking_utils.dart';
import 'package:llamaseek/Services/web_search_service.dart';

String _webSearchInstruction() {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return '''You have web search access. ALWAYS search unless the answer is a universal truth that never changes (math, physics constants, basic definitions).

If you need to search, your ENTIRE output must be ONLY:
WEBSEARCH: <query>

Nothing else. No explanation, no preamble, no other text. Just that single line.

You MUST search for: numbers, statistics, prices, dates, current events, news, recent developments, product info, people, companies, forecasts, rankings, comparisons.

Today's date: $today.''';
}

class ChatProvider extends ChangeNotifier {
  final OllamaService _ollamaService;
  OllamaService get ollamaService => _ollamaService;
  final DatabaseService _databaseService;
  final MemoryService _memoryService;

  ValueListenable? _settingsListenable;
  VoidCallback? _settingsCallback;

  /// Callbacks for web search UI updates. Set by ViewModel before sendPrompt.
  void Function(String thinking)? _webSearchThinkingCallback;
  void Function(String query)? _webSearchCallback;
  void Function(String query)? _webSearchQueryUpdateCallback;
  void Function(List<WebSearchResult> results)? _webSearchCompleteCallback;
  List<MessageSegment> Function()? _webSearchSegmentsProvider;

  void setWebSearchCallbacks({
    required void Function(String thinking) onSearchThinking,
    required void Function(String query) onSearchStart,
    required void Function(String query) onSearchQueryUpdate,
    required void Function(List<WebSearchResult> results) onSearchComplete,
    required List<MessageSegment> Function() segmentsProvider,
  }) {
    _webSearchThinkingCallback = onSearchThinking;
    _webSearchCallback = onSearchStart;
    _webSearchQueryUpdateCallback = onSearchQueryUpdate;
    _webSearchCompleteCallback = onSearchComplete;
    _webSearchSegmentsProvider = segmentsProvider;
  }

  void clearWebSearchCallbacks() {
    _webSearchThinkingCallback = null;
    _webSearchCallback = null;
    _webSearchQueryUpdateCallback = null;
    _webSearchCompleteCallback = null;
    _webSearchSegmentsProvider = null;
  }

  /// Source URLs intercepted during WEBSEARCH stream interception.
  Map<int, String>? _interceptedSourceUrls;

  List<OllamaMessage> _messages = [];
  List<OllamaMessage> get messages => _messages;

  List<OllamaChat> _chats = [];
  List<OllamaChat> get chats => _chats;

  int _currentChatIndex = -1;
  int get selectedDestination => _currentChatIndex + 1;

  OllamaChat? get currentChat =>
      _currentChatIndex == -1 ? null : _chats[_currentChatIndex];

  final Map<String, OllamaMessage?> _activeChatStreams = {};

  bool get isCurrentChatStreaming =>
      _activeChatStreams.containsKey(currentChat?.id);

  bool get isCurrentChatThinking =>
      currentChat != null &&
      _activeChatStreams.containsKey(currentChat?.id) &&
      _activeChatStreams[currentChat?.id] == null;

  /// A map of chat errors, indexed by chat ID.
  final Map<String, OllamaException> _chatErrors = {};

  /// The current chat error. This is the error associated with the current chat.
  /// If there is no error, this will be `null`.
  ///
  /// This is used to display error messages in the chat view.
  OllamaException? get currentChatError => _chatErrors[currentChat?.id];

  /// The current chat configuration.
  ChatConfigureArguments get currentChatConfiguration {
    if (currentChat == null) {
      return _emptyChatConfiguration ?? ChatConfigureArguments.defaultArguments;
    } else {
      return ChatConfigureArguments(
        systemPrompt: currentChat!.systemPrompt,
        chatOptions: currentChat!.options,
      );
    }
  }

  /// The chat configuration for the empty chat.
  ChatConfigureArguments? _emptyChatConfiguration;

  ChatProvider({
    required OllamaService ollamaService,
    required DatabaseService databaseService,
    required MemoryService memoryService,
  })  : _ollamaService = ollamaService,
        _databaseService = databaseService,
        _memoryService = memoryService {
    _initialize();
  }

  Future<void> _initialize() async {
    _updateOllamaServiceAddress();

    await _databaseService.open("ollama_chat.db");
    _chats = await _databaseService.getAllChats();
    notifyListeners();
  }

  void destinationChatSelected(int destination) {
    _currentChatIndex = destination - 1;

    if (destination == 0) {
      _resetChat();
    } else {
      _loadCurrentChat();
    }

    notifyListeners();
  }

  void _resetChat() {
    _currentChatIndex = -1;

    _messages.clear();

    notifyListeners();
  }

  Future<void> _loadCurrentChat() async {
    _messages = await _databaseService.getMessages(currentChat!.id);

    // Add the streaming message to the chat if it exists
    final streamingMessage = _activeChatStreams[currentChat!.id];
    if (streamingMessage != null) {
      _messages.add(streamingMessage);
    }

    // Unfocus the text field to dismiss the keyboard
    FocusManager.instance.primaryFocus?.unfocus();

    notifyListeners();
  }

  Future<void> createNewChat(OllamaModel model, {bool isIncognito = false}) async {
    final chat = await _databaseService.createChat(model.name, isIncognito: isIncognito);

    _chats.insert(0, chat);
    _currentChatIndex = 0;

    if (_emptyChatConfiguration != null) {
      await updateCurrentChat(
        newSystemPrompt: _emptyChatConfiguration!.systemPrompt,
        newOptions: _emptyChatConfiguration!.chatOptions,
      );

      _emptyChatConfiguration = null;
    }

    notifyListeners();
  }

  Future<void> updateCurrentChat({
    String? newModel,
    String? newTitle,
    String? newSystemPrompt,
    OllamaChatOptions? newOptions,
  }) async {
    await updateChat(
      currentChat,
      newModel: newModel,
      newTitle: newTitle,
      newSystemPrompt: newSystemPrompt,
      newOptions: newOptions,
    );
  }

  /// Updates the chat with the given parameters.
  ///
  /// If the chat is `null`, it updates the empty chat configuration.
  Future<void> updateChat(
    OllamaChat? chat, {
    String? newModel,
    String? newTitle,
    String? newSystemPrompt,
    OllamaChatOptions? newOptions,
  }) async {
    if (chat == null) {
      final chatOptions = newOptions ?? _emptyChatConfiguration?.chatOptions;
      _emptyChatConfiguration = ChatConfigureArguments(
        systemPrompt: newSystemPrompt ?? _emptyChatConfiguration?.systemPrompt,
        chatOptions: chatOptions ?? OllamaChatOptions(),
      );
    } else {
      await _databaseService.updateChat(
        chat,
        newModel: newModel,
        newTitle: newTitle,
        newSystemPrompt: newSystemPrompt,
        newOptions: newOptions,
      );

      final chatIndex = _chats.indexWhere((c) => c.id == chat.id);

      if (chatIndex != -1) {
        _chats[chatIndex] = (await _databaseService.getChat(chat.id))!;
        notifyListeners();
      } else {
        throw OllamaException("Chat not found.");
      }
    }
  }

  Future<void> deleteCurrentChat() async {
    final chat = currentChat;
    if (chat == null) return;

    _resetChat();

    _chats.remove(chat);
    _activeChatStreams.remove(chat.id);

    _memoryService.invalidateConversationMemoryCache(chat.id);
    await _databaseService.deleteChat(chat.id);
  }

  Future<void> deleteChat(OllamaChat chat) async {
    final chatIndex = _chats.indexWhere((c) => c.id == chat.id);
    if (chatIndex == -1) return;

    if (currentChat?.id == chat.id) {
      _resetChat();
    } else if (chatIndex < _currentChatIndex) {
      _currentChatIndex--;
    }

    _chats.removeAt(chatIndex);
    _activeChatStreams.remove(chat.id);

    _memoryService.invalidateConversationMemoryCache(chat.id);
    await _databaseService.deleteChat(chat.id);
    notifyListeners();
  }

  /// Adds a user message to the chat immediately and notifies listeners.
  /// Call this as early as possible so the chat bubble appears instantly.
  OllamaMessage displayUserMessage(String text, {List<File>? images}) {
    final prompt = OllamaMessage(
      text.trim(),
      images: images,
      role: OllamaMessageRole.user,
    );
    _messages.add(prompt);

    // Set thinking state immediately so UI shows user message + thinking together
    _activeChatStreams[currentChat!.id] = null;

    notifyListeners();
    return prompt;
  }

  /// Persists the user message and starts the AI response stream.
  /// Call [displayUserMessage] first to show the bubble immediately.
  Future<void> sendPrompt(OllamaMessage prompt, {
    int searchAttemptsRemaining = 0,
  }) async {
    final associatedChat = currentChat!;

    // Save the user prompt to the database
    await _databaseService.addMessage(prompt, chat: associatedChat);

    // Initialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat, searchAttemptsRemaining: searchAttemptsRemaining);
  }

  Future<void> _initializeChatStream(OllamaChat associatedChat, {int searchAttemptsRemaining = 0}) async {
    // Send a notification to inform generation begin
    NotificationCenter().postNotification(NotificationNames.generationBegin);

    // Clear the active chat streams to cancel the previous stream
    _activeChatStreams.remove(associatedChat.id);

    // Clear the error message associated with the chat
    if (_chatErrors.remove(associatedChat.id) != null) {
      notifyListeners();
      // Wait for a short time to show the user that the error message is cleared
      await Future.delayed(Duration(milliseconds: 250));
    }

    // Update the chat list to show the latest chat at the top
    _moveCurrentChatToTop();

    // Add the chat to the active chat streams to show the thinking indicator
    _activeChatStreams[associatedChat.id] = null;
    // Notify the listeners to show the thinking indicator
    notifyListeners();

    // Stream the Ollama message
    OllamaMessage? ollamaMessage;
    _interceptedSourceUrls = null;

    try {
      ollamaMessage = await _streamOllamaMessage(associatedChat, searchAttemptsRemaining: searchAttemptsRemaining);
      // Replace [N] citations with clickable markdown links using intercepted source URLs
      if (ollamaMessage != null && _interceptedSourceUrls != null && _interceptedSourceUrls!.isNotEmpty) {
        ollamaMessage.content = replaceCitationsWithLinks(ollamaMessage.content, _interceptedSourceUrls!);
        _interceptedSourceUrls = null;
      }
    } on OllamaException catch (error) {
      _chatErrors[associatedChat.id] = error;
    } on SocketException catch (_) {
      _chatErrors[associatedChat.id] = OllamaException(
        'Network connection lost. Check your server address or internet connection.',
      );
    } catch (error, stackTrace) {
      debugPrint('⚠️ [ChatProvider] Unexpected error in stream: $error');
      debugPrint('⚠️ [ChatProvider] Stack trace:\n$stackTrace');
      _chatErrors[associatedChat.id] = OllamaException("Something went wrong.");
    } finally {
      // Remove the chat from the active chat streams
      _activeChatStreams.remove(associatedChat.id);
      notifyListeners();
    }

    // Save the Ollama message to the database
    if (ollamaMessage != null) {
      // Persist search segments into the thinking field so they survive reload
      if (_webSearchSegmentsProvider != null) {
        final segments = _webSearchSegmentsProvider!();
        if (segments.isNotEmpty) {
          final encoded = encodeSearchSegments(segments);
          if (encoded.isNotEmpty) {
            ollamaMessage.thinking = '$encoded${ollamaMessage.thinking ?? ''}';
          }
        }
      }
      await _databaseService.addMessage(ollamaMessage, chat: associatedChat);

      // Trigger async memory update (fire-and-forget)
      // Incognito chats: update conversation memory only, skip agent memory
      _memoryService.triggerMemoryUpdate(
        chatId: associatedChat.id,
        messages: _messages,
        skipAgentMemory: associatedChat.isIncognito,
      );

      // Refresh chat to update lastUpdate for sidebar date grouping
      final refreshedChat = await _databaseService.getChatWithLastUpdate(associatedChat.id);
      if (refreshedChat != null) {
        final chatIdx = _chats.indexWhere((c) => c.id == associatedChat.id);
        if (chatIdx != -1) {
          _chats[chatIdx] = refreshedChat;
        }
      }
    }
  }

  Future<OllamaMessage?> _streamOllamaMessage(OllamaChat associatedChat, {String? searchContext, String? preThinking, int searchAttemptsRemaining = 0, OllamaMessage? reuseMessage}) async {
    if (_messages.isEmpty) return null;

    final searchThinking = preThinking?.trim();
    var modelThinkingBuffer = '';

    // For Call 2+ (reuseMessage), exclude the empty assistant message from
    // Call 1. Sending an empty assistant response confuses models into
    // thinking they already answered, producing garbage or truncated output.
    List<OllamaMessage> messagesToSend = reuseMessage != null
        ? _messages.where((m) => m != reuseMessage).toList()
        : _messages;

    // Fetch memories for injection — incognito chats use conv memory but skip agent memory
    final conversationMemory = await _memoryService.getConversationMemory(associatedChat.id);
    final profile = associatedChat.isIncognito
        ? null
        : await _memoryService.getAgentMemory();

    // Select relevant topics/ephemeral for this conversation.
    // Skip relevantContext only for Call 2+ (answering with search results)
    // where injecting old memory alongside fresh search context is confusing.
    // Call 1 (WEBSEARCH decision) still needs memory so the model can answer
    // from existing knowledge or make an informed search decision.
    String relevantContext = '';
    if (!associatedChat.isIncognito && searchContext == null) {
      relevantContext = await _memoryService.selectRelevantContext(
        messagesToSend,
        conversationSummary: conversationMemory?.summary,
      );
    }

    // Build the system prompt for this call:
    // - Call 1 (no search context): inject WEBSEARCH instruction
    // - Call 2 (has search context): inject search results into system prompt
    //   so they become part of the single system message (not a separate one
    //   that models may ignore)
    OllamaChat streamChat = associatedChat;
    final origPrompt = associatedChat.systemPrompt ?? '';
    if (searchAttemptsRemaining > 0 && searchContext == null) {
      // Call 1: WEBSEARCH instruction
      streamChat = OllamaChat(
        id: associatedChat.id,
        model: associatedChat.model,
        title: associatedChat.title,
        systemPrompt: origPrompt.isEmpty
            ? _webSearchInstruction()
            : '$origPrompt\n\n${_webSearchInstruction()}',
        options: associatedChat.options,
        isIncognito: associatedChat.isIncognito,
      );
    } else if (searchContext != null && searchContext.isNotEmpty) {
      // Call 2+: inject search results into the system prompt so they're
      // part of the single system message (avoids dual-system-message issue
      // where models ignore the second system message).
      streamChat = OllamaChat(
        id: associatedChat.id,
        model: associatedChat.model,
        title: associatedChat.title,
        systemPrompt: origPrompt.isEmpty
            ? searchContext
            : '$origPrompt\n\n$searchContext',
        options: associatedChat.options,
        isIncognito: associatedChat.isIncognito,
      );
    }

    final stream = _ollamaService.chatStream(
      messagesToSend,
      chat: streamChat,
      conversationMemory: conversationMemory,
      profile: profile,
      relevantContext: relevantContext,
    );

    OllamaMessage? streamingMessage;
    OllamaMessage? receivedMessage;
    final notifyThrottle = Stopwatch()..start();

    // Mid-stream WEBSEARCH detection: treat WEBSEARCH as a tool call.
    // When detected, content tokens become the search query (shown in the
    // search card UI) instead of the message body.
    final bool canSearch = searchAttemptsRemaining > 0 && searchContext == null;
    bool websearchDetected = false;
    String websearchBuffer = '';

    await for (receivedMessage in stream) {
      // If the chat id is not in the active chat streams, it means the stream
      // is cancelled by the user. So, we need to break the loop.
      if (_activeChatStreams.containsKey(associatedChat.id) == false) {
        streamingMessage?.createdAt = DateTime.now();
        return streamingMessage;
      }

      // Ignore completely empty initial messages (no content AND no thinking)
      final hasContent = receivedMessage.content.isNotEmpty;
      final hasThinking = receivedMessage.thinking != null && receivedMessage.thinking!.isNotEmpty;
      if (!hasContent && !hasThinking && streamingMessage == null) {
        continue;
      }

      if (streamingMessage == null) {
        if (reuseMessage != null) {
          streamingMessage = reuseMessage;
          streamingMessage.content = '';

          if (searchThinking != null && searchThinking.isNotEmpty) {
            final initialThinking = receivedMessage.thinking ?? '';
            if (initialThinking.isNotEmpty) {
              modelThinkingBuffer = initialThinking;
              streamingMessage.thinking = mergeSearchThinking(
                searchThinking: searchThinking,
                modelThinking: modelThinkingBuffer,
              );
            } else {
              streamingMessage.thinking = searchThinking;
            }
          }

          _activeChatStreams[associatedChat.id] = streamingMessage;
          notifyListeners();
        } else {
          streamingMessage = receivedMessage;

          if (searchThinking != null && searchThinking.isNotEmpty) {
            final initialThinking = receivedMessage.thinking ?? '';
            if (initialThinking.isNotEmpty) {
              modelThinkingBuffer = initialThinking;
              streamingMessage.thinking = mergeSearchThinking(
                searchThinking: searchThinking,
                modelThinking: modelThinkingBuffer,
              );
            } else {
              streamingMessage.thinking = searchThinking;
            }
          }

          _activeChatStreams[associatedChat.id] = streamingMessage;

          if (associatedChat.id == currentChat?.id) {
            _messages.add(streamingMessage);
          }

          notifyListeners();
        }
      } else {
        // Accumulate thinking tokens
        if (receivedMessage.thinking != null && receivedMessage.thinking!.isNotEmpty) {
          if (searchThinking != null && searchThinking.isNotEmpty) {
            modelThinkingBuffer += receivedMessage.thinking!;
            streamingMessage.thinking = mergeSearchThinking(
              searchThinking: searchThinking,
              modelThinking: modelThinkingBuffer,
            );
          } else {
            streamingMessage.thinking = (streamingMessage.thinking ?? '') + receivedMessage.thinking!;
          }
        }

        // Accumulate content — with mid-stream WEBSEARCH detection
        if (websearchDetected) {
          // Already detected: accumulate query tokens, don't show as content
          websearchBuffer += receivedMessage.content;
          final query = websearchBuffer.substring(websearchBuffer.toUpperCase().indexOf('WEBSEARCH:') + 'WEBSEARCH:'.length).trim();
          _webSearchQueryUpdateCallback?.call(query);
        } else {
          streamingMessage.content += receivedMessage.content;

          // Check if accumulated content starts with WEBSEARCH:
          if (canSearch && receivedMessage.content.isNotEmpty) {
            final trimmed = streamingMessage.content.trimLeft();
            if (trimmed.toUpperCase().startsWith('WEBSEARCH:')) {
              websearchDetected = true;
              websearchBuffer = streamingMessage.content;
              streamingMessage.content = '';
              final queryPart = websearchBuffer.substring(websearchBuffer.toUpperCase().indexOf('WEBSEARCH:') + 'WEBSEARCH:'.length).trim();
              // Emit Call 1 thinking as a segment before the search card
              final call1Think = streamingMessage.thinking ?? '';
              if (call1Think.isNotEmpty) _webSearchThinkingCallback?.call(call1Think);
              _webSearchCallback?.call(queryPart);
            }
          }
        }

        // Throttle UI updates during streaming (~30fps)
        if (notifyThrottle.elapsedMilliseconds >= 32) {
          notifyThrottle.reset();
          notifyListeners();
        }
      }
    }

    // --- POST-STREAM: execute search or handle thinking fallback ---
    debugPrint('🔍 [SEARCH] Stream ended. websearchDetected=$websearchDetected, content=${streamingMessage?.content.length ?? 0} chars');

    // Thinking fallback: model put search intent in thinking but zero content
    if (!websearchDetected && canSearch && streamingMessage != null) {
      String? fallbackQuery;
      final thinking = streamingMessage.thinking?.trim() ?? '';
      debugPrint('🔍 [SEARCH] Thinking fallback check: thinking=${thinking.length} chars, first 200: "${thinking.substring(0, thinking.length.clamp(0, 200))}"');
      // Check thinking for WEBSEARCH: pattern
      for (final line in thinking.split('\n')) {
        if (line.trim().toUpperCase().startsWith('WEBSEARCH:')) {
          fallbackQuery = line.trim().substring('WEBSEARCH:'.length).trim();
          break;
        }
      }
      // Extract quoted query from thinking (e.g. 'query "Taiwan GDP 2025"')
      if (fallbackQuery == null && streamingMessage.content.trim().isEmpty && thinking.isNotEmpty) {
        final queryMatch = RegExp(r'''(?:query|search)[^"']*["']([^"']+)["']''', caseSensitive: false).firstMatch(thinking);
        if (queryMatch != null) {
          fallbackQuery = queryMatch.group(1)!.trim();
        }
      }
      if (fallbackQuery != null && fallbackQuery.isNotEmpty) {
        websearchDetected = true;
        websearchBuffer = 'WEBSEARCH: $fallbackQuery';
        streamingMessage.content = '';
        final call1Think = streamingMessage.thinking ?? '';
        if (call1Think.isNotEmpty) _webSearchThinkingCallback?.call(call1Think);
        _webSearchCallback?.call(fallbackQuery);
        notifyListeners();
      }
    }

    // Execute web search if WEBSEARCH was detected (mid-stream or thinking fallback)
    if (websearchDetected && streamingMessage != null) {
      var searchQuery = websearchBuffer.substring(websearchBuffer.toUpperCase().indexOf('WEBSEARCH:') + 'WEBSEARCH:'.length).trim();
      // Clean query
      searchQuery = searchQuery.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      final words = searchQuery.split(RegExp(r'\s+'));
      if (words.length > 10) searchQuery = words.take(10).join(' ');
      final call1Thinking = streamingMessage.thinking ?? '';
      debugPrint('🔍 [SEARCH] Executing web search for: "$searchQuery"');

      // Update search card with final query
      _webSearchQueryUpdateCallback?.call(searchQuery);
      notifyListeners();

      final searchService = WebSearchService();
      final searchResults = await searchService.searchAndExtract(searchQuery);
      _webSearchCompleteCallback?.call(searchResults);

      if (searchResults.isEmpty) {
        streamingMessage.content = 'I searched the web for "$searchQuery" but found no results. Let me answer based on what I know.';
        _activeChatStreams[associatedChat.id] = streamingMessage;
        notifyListeners();
        return streamingMessage;
      }

      // Build search context and extract source URLs
      final newSearchContext = WebSearchService.formatResultsAsContext(searchResults);
      _interceptedSourceUrls = {};
      final urlPattern = RegExp(r'<source id="(\d+)" name="([^"]*)"');
      for (final match in urlPattern.allMatches(newSearchContext)) {
        final id = int.tryParse(match.group(1)!);
        final url = match.group(2);
        if (id != null && url != null) _interceptedSourceUrls![id] = url;
      }

      // Recursive call: re-stream with search context, reusing same message
      debugPrint('🔍 [SEARCH] Starting Call 2 with ${newSearchContext.length} chars of context');
      _activeChatStreams[associatedChat.id] = null;
      notifyListeners();

      return await _streamOllamaMessage(
        associatedChat,
        searchContext: newSearchContext,
        preThinking: call1Thinking.isNotEmpty ? call1Thinking : preThinking,
        searchAttemptsRemaining: searchAttemptsRemaining - 1,
        reuseMessage: streamingMessage,
      );
    }

    // Flush any throttled content to UI
    notifyListeners();

    if (receivedMessage != null) {
      // Update the metadata of the streaming message with the last received message
      streamingMessage?.updateMetadataFrom(receivedMessage);
    }

    // Update created at time to the current time when the stream is finished
    streamingMessage?.createdAt = DateTime.now();

    // Release base64 image data from all messages to free memory
    for (final m in _messages) {
      m.clearBase64Cache();
    }

    // Strip model annotation prefix that may have been echoed by the model
    if (streamingMessage != null) {
      streamingMessage.content = streamingMessage.content.replaceFirst(
        RegExp(r'^\(Response from [^)]+\)\n?'),
        '',
      );
    }

    return streamingMessage;
  }

  /// Sends the edited text as a new message at the bottom, preserving all history.
  Future<void> editAndResend(OllamaMessage originalMessage, String newContent) async {
    final associatedChat = currentChat!;

    // Create a new user message with the edited content
    final newMessage = OllamaMessage(
      newContent.trim(),
      role: OllamaMessageRole.user,
      images: originalMessage.images,
    );
    _messages.add(newMessage);

    _activeChatStreams[associatedChat.id] = null;
    notifyListeners();

    // Save the new message to the database
    await _databaseService.addMessage(newMessage, chat: associatedChat);

    // Start a new response
    await _initializeChatStream(associatedChat);
  }

  Future<void> regenerateMessage(OllamaMessage message) async {
    final associatedChat = currentChat!;

    final messageIndex = _messages.indexOf(message);
    if (messageIndex == -1) return;

    final includeMessage = (message.role == OllamaMessageRole.user ? 1 : 0);
    final removeStart = messageIndex + includeMessage;

    final removeMessages = _messages.sublist(removeStart);
    // Mutate in place to preserve list identity — ChatListView uses
    // identical() to decide whether to clear its bubble cache.
    _messages.removeRange(removeStart, _messages.length);
    notifyListeners();

    await _databaseService.deleteMessages(removeMessages);

    // Reinitialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat);
  }

  Future<void> retryLastPrompt() async {
    if (_messages.isEmpty) return;

    final associatedChat = currentChat!;

    if (_messages.last.role == OllamaMessageRole.assistant) {
      final message = _messages.removeLast();
      await _databaseService.deleteMessage(message.id);
    }

    // Reinitialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat);

    notifyListeners();
  }

  Future<void> updateMessage(
    OllamaMessage message, {
    String? newContent,
  }) async {
    message.content = newContent ?? message.content;
    notifyListeners();

    await _databaseService.updateMessage(message, newContent: newContent);
  }

  Future<void> deleteMessage(OllamaMessage message) async {
    await _databaseService.deleteMessage(message.id);

    // If the message is in the chat, remove it from the chat
    if (_messages.remove(message)) {
      notifyListeners();
    }
  }

  /// Replaces [N] and 【N】 citations in content with clickable markdown links.
  ///
  /// Handles both standard brackets [1] and fullwidth brackets 【1】
  /// (some models like qwen/deepseek output fullwidth brackets for citations).
  ///
  /// Uses negative lookahead `(?!\()` so existing markdown links aren't double-wrapped.
  @visibleForTesting
  static const _superscriptDigits = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

  static String _toSuperscript(int n) {
    return n.toString().split('').map((c) => _superscriptDigits[int.parse(c)]).join('');
  }

  static String replaceCitationsWithLinks(String content, Map<int, String> sourceUrls) {
    // Match both [N] and 【N】 citation formats (not already part of a markdown link)
    return content.replaceAllMapped(
      RegExp(r'(?:\[(\d+)\]|\u3010(\d+)\u3011)(?!\()'),
      (match) {
        final id = int.tryParse(match.group(1) ?? match.group(2) ?? '');
        if (id != null && sourceUrls.containsKey(id)) {
          final url = sourceUrls[id]!;
          // Use superscript numbers to avoid nested bracket issues and
          // dollar-sign math mode conflicts in the markdown renderer.
          return '[${_toSuperscript(id)}]($url)';
        }
        return match.group(0)!;
      },
    );
  }

  void cancelCurrentStreaming() {
    _activeChatStreams.remove(currentChat?.id);
    notifyListeners();
  }

  void _moveCurrentChatToTop() {
    if (_currentChatIndex == 0) return;

    final chat = _chats.removeAt(_currentChatIndex);
    _chats.insert(0, chat);
    _currentChatIndex = 0;
  }

  Future<List<OllamaModel>> fetchAvailableModels() async {
    return await _ollamaService.listModels();
  }

  @override
  void dispose() {
    if (_settingsListenable != null && _settingsCallback != null) {
      _settingsListenable!.removeListener(_settingsCallback!);
    }
    super.dispose();
  }

  void _updateOllamaServiceAddress() {
    final settingsBox = Hive.box('settings');

    _applyServerSettings(settingsBox);

    _settingsListenable = settingsBox.listenable(keys: ["serverAddress", "isCloudMode", "cloudApiKey"]);
    _settingsCallback = () {
      _applyServerSettings(settingsBox);

      // This will update empty chat state to dismiss "Tap to configure server address" message
      notifyListeners();
    };
    _settingsListenable!.addListener(_settingsCallback!);
  }

  void _applyServerSettings(Box settingsBox) {
    final isCloudMode = settingsBox.get('isCloudMode', defaultValue: false);
    _ollamaService.isCloudMode = isCloudMode;

    if (isCloudMode) {
      _ollamaService.apiKey = settingsBox.get('cloudApiKey');
    } else {
      _ollamaService.apiKey = null;
      _ollamaService.baseUrl = settingsBox.get('serverAddress');
    }
  }

  Future<void> saveAsNewModel(String modelName) async {
    final associatedChat = currentChat;
    if (associatedChat == null) {
      // TODO: Empty chat should be saved as a new model.
      throw OllamaException("No chat is selected.");
    }

    await _ollamaService.createModel(
      modelName,
      chat: associatedChat,
      messages: _messages.toList(),
    );
  }

  Future<void> generateTitleForCurrentChat() async {
    final associatedChat = currentChat;
    final message = _messages.firstOrNull;
    if (associatedChat == null || message == null) return;

    // Create a temp chat with necessary system prompt
    final chat = OllamaChat(
      model: associatedChat.model,
      systemPrompt: GenerateTitleConstants.systemPrompt,
    );

    try {
      // Generate a title for the message
      final stream = _ollamaService.generateStream(
        GenerateTitleConstants.prompt + message.content,
        chat: chat,
      );

      var title = "";
      final titleThrottle = Stopwatch()..start();
      await for (final titleMessage in stream) {
        // Ignore empty initial messages, preventing empty title
        if (title.isEmpty && titleMessage.content.isEmpty) {
          continue;
        }

        title += titleMessage.content;

        // Throttle title updates to at most every 100ms
        if (titleThrottle.elapsedMilliseconds >= 100) {
          titleThrottle.reset();
          if (title.startsWith("<think>")) {
            await updateChat(associatedChat, newTitle: "Thinking for a title...");
          } else {
            await updateChat(associatedChat, newTitle: title);
          }
        }
      }

      // Remove <think> tag and its content
      if (title.startsWith("<think>")) {
        title = title.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
      }

      // Final update with complete title
      await updateChat(associatedChat, newTitle: title.trim());
    } catch (_) {
      // Silently ignore title generation failures (e.g., cloud model errors)
    }
  }
}
