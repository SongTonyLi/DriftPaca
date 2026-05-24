import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/chat_preset.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

class ChatPageViewModel extends ChangeNotifier {
  final ChatProvider _chatProvider;
  final PermissionService _permissionService;
  final ImageService _imageService;
  final OllamaService _ollamaService;

  ChatPageViewModel({
    required ChatProvider chatProvider,
    required PermissionService permissionService,
    required ImageService imageService,
    required OllamaService ollamaService,
  })  : _chatProvider = chatProvider,
        _permissionService = permissionService,
        _imageService = imageService,
        _ollamaService = ollamaService {
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

  /// Active orchestrator reference for cancellation
  SearchOrchestrator? _activeOrchestrator;

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
  // Search Segment Management
  // ============================================================

  void _startThinkingSegment() {
    _searchSegments.add(ThinkingSegment(''));
  }

  void _updateThinkingSegment(String accumulated) {
    final thinking = _searchSegments.whereType<ThinkingSegment>().lastOrNull;
    if (thinking != null) {
      thinking.text = accumulated;
    }
  }

  void _addSearchCard(String query) {
    _searchSegments.add(SearchCardSegment(query: query));
  }

  void _updateSearchCard(List<SearchURLStatus> urls) {
    final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
    if (card != null) {
      card.urls = urls;
    }
  }

  void _collapseSearchCard(int resultCount) {
    final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
    if (card != null) {
      card.resultCount = resultCount;
      card.isComplete = true;
    }
  }

  void _showSearchError(String message) {
    final card = _searchSegments.whereType<SearchCardSegment>().lastOrNull;
    if (card != null && !card.isComplete) {
      card.error = message;
      card.isComplete = true;
    } else {
      _searchSegments.add(SearchCardSegment(
        query: '',
        error: message,
        isComplete: true,
      ));
    }
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
          event.key == 'isCloudMode' ||
          event.key == 'cloudApiKey') {
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
    _activeOrchestrator?.cancel();
    _activeOrchestrator = null;
    _isSearching = false;
    _chatProvider.cancelCurrentStreaming();
  }

  /// Retries the last prompt
  Future<void> retryLastPrompt() async {
    await _chatProvider.retryLastPrompt();
  }

  /// Fetches available models from the server
  Future<List<OllamaModel>> fetchAvailableModels() async {
    return await _chatProvider.fetchAvailableModels();
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

    // Add an empty path if the image could not be compressed to show error
    if (compressedFile != null) {
      _imageFiles.add(compressedFile);
    } else {
      _imageFiles.add(File(''));
    }

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
    // Early return if nothing to send or currently streaming/searching
    if (!hasText || isStreaming || _isSearching) {
      return false;
    }

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

    // Perform web search if enabled (user already sees their message)
    String? searchContext;
    Map<int, String>? sourceUrls;
    String? searchThinking;

    if (_webSearchEnabled) {
      _isSearching = true;
      _searchSegments.clear();
      notifyListeners();

      SearchOrchestrator? orchestrator;
      try {
        orchestrator = SearchOrchestrator(
          ollamaService: _ollamaService,
          chat: _chatProvider.currentChat!,
        );
        _activeOrchestrator = orchestrator;

        // Listen to events for UI updates
        final subscription = orchestrator.events.listen((event) {
          switch (event) {
            case ThinkingStartEvent():
              _startThinkingSegment();
            case ThinkingUpdateEvent():
              _updateThinkingSegment(event.accumulated);
            case SearchStartEvent():
              _addSearchCard(event.query);
            case SearchProgressEvent():
              _updateSearchCard(event.urls);
            case SearchCompleteEvent():
              _collapseSearchCard(event.resultCount);
            case SearchErrorEvent():
              _showSearchError(event.message);
            case AnswerStartEvent():
              _searchSegments.add(AnswerSegment());
          }
          notifyListeners();
        });

        // Run the agentic loop
        searchContext = await orchestrator.run(prompt);

        await subscription.cancel();

        // Build source URL map from context source tags
        if (searchContext != null) {
          final urlPattern = RegExp(r'<source id="(\d+)" name="([^"]*)"');
          for (final match in urlPattern.allMatches(searchContext)) {
            final id = int.tryParse(match.group(1)!);
            final url = match.group(2);
            if (id != null && url != null) {
              sourceUrls ??= {};
              sourceUrls[id] = url;
            }
          }
        }

        // Collect thinking text + searched URLs for persistence
        final thinkingParts = <String>[];
        for (final segment in _searchSegments) {
          if (segment is ThinkingSegment && segment.text.isNotEmpty) {
            thinkingParts.add(segment.text);
          } else if (segment is SearchCardSegment && segment.query.isNotEmpty) {
            final urls = segment.urls
                .where((u) => u.state == SearchURLState.success)
                .map((u) => u.domain)
                .toList();
            if (urls.isNotEmpty) {
              thinkingParts.add('Searched: "${segment.query}" → ${urls.join(', ')}');
            }
          }
        }
        if (thinkingParts.isNotEmpty) {
          searchThinking = thinkingParts.join('\n\n');
        }
      } catch (_) {
        // Orchestrator failed — continue without search
      } finally {
        orchestrator?.dispose();
        _activeOrchestrator = null;
        _isSearching = false;
        notifyListeners();
      }
    }

    // Persist message and start the AI response stream
    await _chatProvider.sendPrompt(message,
        searchContext: searchContext,
        sourceUrls: sourceUrls,
        preThinking: searchThinking);

    // Generate title for new chats
    if (isNewChat) {
      await _chatProvider.generateTitleForCurrentChat();
    }

    return true;
  }
}
