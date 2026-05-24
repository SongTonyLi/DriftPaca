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
import 'package:llamaseek/Utils/search_thinking_utils.dart';
import 'package:llamaseek/Services/web_search_service.dart';

const _webSearchInstruction = '''
If you need current or real-time information from the web to answer the user's question, start your response with WEBSEARCH: followed by a concise search query (max 10 words) on the first line.

If you can answer without web search, respond normally.''';

class ChatProvider extends ChangeNotifier {
  final OllamaService _ollamaService;
  OllamaService get ollamaService => _ollamaService;
  final DatabaseService _databaseService;
  final MemoryService _memoryService;

  ValueListenable? _settingsListenable;
  VoidCallback? _settingsCallback;

  /// Callbacks for web search UI updates. Set by ViewModel before sendPrompt.
  void Function(String query)? _webSearchCallback;
  void Function(List<WebSearchResult> results)? _webSearchCompleteCallback;

  void setWebSearchCallbacks({
    required void Function(String query) onSearchStart,
    required void Function(List<WebSearchResult> results) onSearchComplete,
  }) {
    _webSearchCallback = onSearchStart;
    _webSearchCompleteCallback = onSearchComplete;
  }

  void clearWebSearchCallbacks() {
    _webSearchCallback = null;
    _webSearchCompleteCallback = null;
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
    String? searchContext,
    Map<int, String>? sourceUrls,
    String? preThinking,
    bool webSearchEnabled = false,
  }) async {
    final associatedChat = currentChat!;

    // Save the user prompt to the database
    await _databaseService.addMessage(prompt, chat: associatedChat);

    // Initialize the chat stream with the messages in the chat
    await _initializeChatStream(associatedChat, searchContext: searchContext, sourceUrls: sourceUrls, preThinking: preThinking, webSearchEnabled: webSearchEnabled);
  }

  Future<void> _initializeChatStream(OllamaChat associatedChat, {String? searchContext, Map<int, String>? sourceUrls, String? preThinking, bool webSearchEnabled = false}) async {
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

    try {
      ollamaMessage = await _streamOllamaMessage(associatedChat, searchContext: searchContext, preThinking: preThinking, webSearchEnabled: webSearchEnabled);
      // Use intercepted source URLs if search happened via stream interception
      if (sourceUrls == null && _interceptedSourceUrls != null) {
        sourceUrls = _interceptedSourceUrls;
        _interceptedSourceUrls = null;
      }
      // Replace [N] citations with clickable markdown links
      if (ollamaMessage != null && sourceUrls != null && sourceUrls.isNotEmpty) {
        ollamaMessage.content = replaceCitationsWithLinks(ollamaMessage.content, sourceUrls);
      }
    } on OllamaException catch (error) {
      _chatErrors[associatedChat.id] = error;
    } on SocketException catch (_) {
      _chatErrors[associatedChat.id] = OllamaException(
        'Network connection lost. Check your server address or internet connection.',
      );
    } catch (error) {
      _chatErrors[associatedChat.id] = OllamaException("Something went wrong.");
    } finally {
      // Remove the chat from the active chat streams
      _activeChatStreams.remove(associatedChat.id);
      notifyListeners();
    }

    // Save the Ollama message to the database
    if (ollamaMessage != null) {
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

  Future<OllamaMessage?> _streamOllamaMessage(OllamaChat associatedChat, {String? searchContext, String? preThinking, bool webSearchEnabled = false}) async {
    if (_messages.isEmpty) return null;

    final searchThinking = preThinking?.trim();
    var modelThinkingBuffer = '';

    // If search context is provided, inject it as a system message before the conversation
    List<OllamaMessage> messagesToSend = _messages;
    if (searchContext != null && searchContext.isNotEmpty) {
      messagesToSend = [
        OllamaMessage(searchContext, role: OllamaMessageRole.system),
        ..._messages,
      ];
    }

    // Fetch memories for injection — incognito chats use conv memory but skip agent memory
    final conversationMemory = await _memoryService.getConversationMemory(associatedChat.id);
    final profile = associatedChat.isIncognito
        ? null
        : await _memoryService.getAgentMemory();

    // Select relevant topics/ephemeral for this conversation
    String relevantContext = '';
    if (!associatedChat.isIncognito) {
      relevantContext = await _memoryService.selectRelevantContext(
        messagesToSend,
        conversationSummary: conversationMemory?.summary,
      );
    }

    // When web search is enabled but no context yet (Call 1), inject the
    // WEBSEARCH instruction so the model can request a search on the first line.
    OllamaChat streamChat = associatedChat;
    if (webSearchEnabled && searchContext == null) {
      final origPrompt = associatedChat.systemPrompt ?? '';
      streamChat = OllamaChat(
        id: associatedChat.id,
        model: associatedChat.model,
        title: associatedChat.title,
        systemPrompt: origPrompt.isEmpty
            ? _webSearchInstruction
            : '$origPrompt\n\n$_webSearchInstruction',
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
    var contentBuffer = '';
    bool webSearchChecked = false;

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
        // Keep the first received message to add the content of the following messages
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

        // Update the active chat streams key with the ollama message
        // to be able to show the stream in the chat.
        // We also use this when the user switches between chats while streaming.
        _activeChatStreams[associatedChat.id] = streamingMessage;

        // Be sure the user is in the same chat while the initial message is received
        if (associatedChat.id == currentChat?.id) {
          _messages.add(streamingMessage);
        }

        notifyListeners();
      } else {
        // --- WEBSEARCH stream interception (Call 1) ---
        // Buffer the first content line to check for WEBSEARCH: <query>.
        if (webSearchEnabled && searchContext == null && !webSearchChecked && receivedMessage.content.isNotEmpty) {
          contentBuffer += receivedMessage.content;
          if (!contentBuffer.contains('\n')) {
            if (notifyThrottle.elapsedMilliseconds >= 32) {
              notifyThrottle.reset();
              notifyListeners();
            }
            continue;
          }
          webSearchChecked = true;
          final firstLine = contentBuffer.split('\n').first.trim();
          if (firstLine.toUpperCase().startsWith('WEBSEARCH:')) {
            final searchQuery = firstLine.substring('WEBSEARCH:'.length).trim();
            final call1Thinking = streamingMessage.thinking ?? '';

            // Remove the partial message from the UI
            _messages.remove(streamingMessage);
            _activeChatStreams.remove(associatedChat.id);
            notifyListeners();
            await Future.delayed(Duration.zero);

            // Notify the UI that a web search is starting
            _webSearchCallback?.call(searchQuery);
            await Future.delayed(Duration.zero);

            // Execute the web search
            final searchService = WebSearchService();
            final searchResults = await searchService.searchAndExtract(searchQuery);
            _webSearchCompleteCallback?.call(searchResults);
            await Future.delayed(Duration.zero);

            if (searchResults.isEmpty) {
              final failMsg = OllamaMessage(
                'I searched the web for "$searchQuery" but found no results. Let me answer based on what I know.',
                role: OllamaMessageRole.assistant,
                thinking: call1Thinking.isNotEmpty ? call1Thinking : null,
              );
              _activeChatStreams[associatedChat.id] = failMsg;
              if (associatedChat.id == currentChat?.id) _messages.add(failMsg);
              notifyListeners();
              return failMsg;
            }

            // Build search context and extract source URLs for citation linking
            final newSearchContext = WebSearchService.formatResultsAsContext(searchResults);
            _interceptedSourceUrls = {};
            final urlPattern = RegExp(r'<source id="(\d+)" name="([^"]*)"');
            for (final match in urlPattern.allMatches(newSearchContext)) {
              final id = int.tryParse(match.group(1)!);
              final url = match.group(2);
              if (id != null && url != null) _interceptedSourceUrls![id] = url;
            }

            // Recursive Call 2: re-stream with search context injected
            return await _streamOllamaMessage(
              associatedChat,
              searchContext: newSearchContext,
              preThinking: call1Thinking.isNotEmpty ? call1Thinking : preThinking,
              webSearchEnabled: false,
            );
          }

          // Not a WEBSEARCH line — flush the buffer and continue normally
          streamingMessage.content += contentBuffer;
          contentBuffer = '';
          if (notifyThrottle.elapsedMilliseconds >= 32) {
            notifyThrottle.reset();
            notifyListeners();
          }
          continue;
        }

        streamingMessage.content += receivedMessage.content;
        // Accumulate thinking tokens alongside content
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

        // Throttle UI updates during streaming (~30fps)
        if (notifyThrottle.elapsedMilliseconds >= 32) {
          notifyThrottle.reset();
          notifyListeners();
        }
      }
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

    final stayedMessages = _messages.sublist(0, messageIndex + includeMessage);
    final removeMessages = _messages.sublist(messageIndex + includeMessage);

    _messages = stayedMessages;
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
  static String replaceCitationsWithLinks(String content, Map<int, String> sourceUrls) {
    // Match both [N] and 【N】 citation formats
    return content.replaceAllMapped(
      RegExp(r'(?:\[(\d+)\]|\u3010(\d+)\u3011)(?!\()'),
      (match) {
        final id = int.tryParse(match.group(1) ?? match.group(2) ?? '');
        if (id != null && sourceUrls.containsKey(id)) {
          final url = sourceUrls[id]!;
          return '[[$id]]($url)';
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
