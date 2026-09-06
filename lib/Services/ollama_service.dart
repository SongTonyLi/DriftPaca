import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Utils/http_error_formatter.dart';
import 'package:llamaseek/Models/api/tags_response.dart';
import 'package:llamaseek/Models/api/show_response.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/api/create_request.dart';
import 'package:llamaseek/Services/openrouter_codec.dart';

class OllamaService {
  static const String defaultLocalUrl = "http://localhost:11434";
  static const String cloudBaseUrl = "https://ollama.com";
  static const String openRouterBaseUrl = "https://openrouter.ai/api/v1";

  /// The base URL for the Ollama service API.
  ///
  /// This URL is used as the root endpoint for all network requests
  /// made by the Ollama service. It should be set to the base address
  /// of the API server.
  ///
  /// The default value is "http://localhost:11434".
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String? value) => _baseUrl = value ?? defaultLocalUrl;

  /// Whether the service is in Ollama Cloud mode.
  bool _isCloudMode = false;
  bool get isCloudMode => _isCloudMode;
  set isCloudMode(bool value) {
    _isCloudMode = value;
    if (value) {
      _isOpenRouterMode = false;
      _baseUrl = cloudBaseUrl;
    }
  }

  /// Whether the service is talking to OpenRouter (OpenAI-compatible).
  bool _isOpenRouterMode = false;
  bool get isOpenRouterMode => _isOpenRouterMode;
  set isOpenRouterMode(bool value) {
    _isOpenRouterMode = value;
    if (value) {
      _isCloudMode = false;
      _baseUrl = openRouterBaseUrl;
    }
  }

  /// Hosted backends (Cloud / OpenRouter) omit local-only Ollama options
  /// and use longer timeouts.
  bool get isRemoteMode => _isCloudMode || _isOpenRouterMode;

  /// The API key for hosted-backend authentication.
  String? _apiKey;
  String? get apiKey => _apiKey;
  set apiKey(String? value) => _apiKey = value;

  /// The headers to include in all network requests.
  Map<String, String> get headers {
    final h = {'Content-Type': 'application/json'};
    if (isRemoteMode && _apiKey != null && _apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_apiKey';
    }
    if (_isOpenRouterMode) {
      h['HTTP-Referer'] = OpenRouterCodec.referer;
      h['X-Title'] = OpenRouterCodec.title;
    }
    return h;
  }

  /// Cached model capabilities from /api/show, keyed by model name.
  final Map<String, ModelCapabilities> _capabilitiesCache = {};

  /// Models whose /api/show probe came back with nothing usable, keyed by
  /// "<server>|<model>" so switching servers re-probes rather than
  /// inheriting the old one's answer.
  ///
  /// Without this a server that does not report capabilities is probed
  /// again before EVERY search-enabled message — see [getCapabilities],
  /// which sits on the critical path between pressing send and research
  /// starting, and pays a full round trip (or _showModel's 5-10s timeout)
  /// every time to re-learn the same nothing.
  final Set<String> _capabilitiesUnavailable = {};

  String _capabilityProbeKey(String model) => '$_baseUrl|$model';

  /// Persistent HTTP client so TCP/TLS connections are reused across requests.
  /// Top-level http.* helpers create a fresh client per call, which pays a
  /// new TLS handshake every time on Ollama Cloud. When injected (shared with
  /// MemoryService), both services reuse a single TLS connection to ollama.com
  /// instead of each paying a separate cold-start handshake.
  final http.Client _client;
  final bool _ownsClient;

  /// Creates a new instance of the Ollama service.
  OllamaService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? defaultLocalUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// Constructs a URL by resolving the provided path against the base URL.
  Uri constructUrl(String path) {
    final baseUri = Uri.parse(baseUrl);

    // Split the base URI path into segments, filtering out empty strings
    final segments = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Split the provided path into segments, filtering out empty strings
    final extraSegments = path.split('/').where((s) => s.isNotEmpty).toList();

    // Combine both sets of segments and create a new URI
    return baseUri.replace(pathSegments: [...segments, ...extraSegments]);
  }

  /// Returns options map for requests. Cloud mode omits advanced options
  /// that may cause errors with cloud-hosted models.
  Map<String, dynamic>? _buildOptions(OllamaChatOptions options) {
    if (isRemoteMode) return null;
    return options.toMap();
  }

  /// Generates an OllamaMessage.
  ///
  /// This method is responsible for generating an instance of
  /// [OllamaMessage] based on the provided prompt and options.
  ///
  /// [prompt] is the input string used to generate the message.
  /// [options] is a map of additional options that can be used to
  /// customize the generation process. It defaults to an empty map.
  ///
  /// Returns a [Future] that completes with an [OllamaMessage].
  Future<OllamaMessage> generate(
    String prompt, {
    required OllamaChat chat,
  }) async {
    if (_isOpenRouterMode) {
      return _openRouterGenerate(prompt, chat: chat);
    }
    final url = constructUrl("/api/generate");

    final response = await _client.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "prompt": prompt,
        "system": chat.systemPrompt,
        if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
        "stream": false,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(utf8.decode(response.bodyBytes));
      return OllamaMessage.fromJson(jsonBody);
    } else if (response.statusCode == 404) {
      throw OllamaException("${chat.model} not found on the server.");
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Stream<OllamaMessage> generateStream(
    String prompt, {
    required OllamaChat chat,
  }) async* {
    if (_isOpenRouterMode) {
      yield* _openRouterGenerateStream(prompt, chat: chat);
      return;
    }
    final url = constructUrl('/api/generate');

    final request = http.Request("POST", url);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "prompt": prompt,
      "system": chat.systemPrompt,
      if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
      "stream": true,
    });

    http.StreamedResponse response = await _client.send(request);

    if (response.statusCode == 200) {
      await for (final message in _processStream(response.stream)) {
        yield message;
      }
    } else if (response.statusCode == 404) {
      throw OllamaException("${chat.model} not found on the server.");
    } else {
      final body = await response.stream.bytesToString();
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: body));
    }
  }

  /// Sends a chat message to the Ollama service and returns the response.
  ///
  /// This method takes a message and sends it to the Ollama service, which
  /// processes the message and returns a response. The response is then
  /// encapsulated in an [OllamaMessage] object.
  ///
  /// Returns an [OllamaMessage] containing the response from the Ollama service.
  ///
  /// Throws an [Exception] if there is an error during the communication with
  /// the Ollama service.
  Future<OllamaMessage> chat(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaToolDefinition>? tools,
    List<OllamaMessage> extraMessages = const [],
  }) async {
    if (_isOpenRouterMode) {
      return _openRouterChat(
        messages,
        chat: chat,
        conversationMemory: conversationMemory,
        profile: profile,
        relevantContext: relevantContext,
        tools: tools,
        extraMessages: extraMessages,
      );
    }
    final url = constructUrl("/api/chat");

    final response = await _client.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "messages": await prepareMessagesWithSystemPrompt(
          messages, chat.systemPrompt,
          conversationMemory: conversationMemory,
          profile: profile,
          relevantContext: relevantContext,
          currentModel: chat.model,
          extraMessages: extraMessages,
        ),
        if (tools != null && tools.isNotEmpty)
          "tools": [for (final t in tools) t.toJson()],
        if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
        "stream": false,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return OllamaMessage.fromJson(jsonBody);
    } else if (response.statusCode == 404) {
      throw OllamaException("${chat.model} not found on the server.");
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaToolDefinition>? tools,
    List<OllamaMessage> extraMessages = const [],
  }) async* {
    if (_isOpenRouterMode) {
      yield* _openRouterChatStream(
        messages,
        chat: chat,
        conversationMemory: conversationMemory,
        profile: profile,
        relevantContext: relevantContext,
        tools: tools,
        extraMessages: extraMessages,
      );
      return;
    }
    // Determine vision support: only strip images when we are confident
    // the model lacks vision. Default to true (send images) when unknown.
    final hasImages = messages.any((m) => m.images != null && m.images!.isNotEmpty);
    bool supportsVision = true;
    if (hasImages) {
      if (!_capabilitiesCache.containsKey(chat.model)) {
        final show = await _showModel(chat.model);
        if (show != null && show.capabilities.isNotEmpty) {
          _capabilitiesCache[chat.model] = ModelCapabilities.fromList(show.capabilities);
        }
      }
      supportsVision = _capabilitiesCache[chat.model]?.vision ?? true;
    }

    final preparedMessages = await prepareMessagesWithSystemPrompt(
      messages, chat.systemPrompt,
      conversationMemory: conversationMemory,
      profile: profile,
      relevantContext: relevantContext,
      currentModel: chat.model,
      supportsVision: supportsVision,
      extraMessages: extraMessages,
    );

    final url = constructUrl('/api/chat');

    final request = http.Request("POST", url);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "messages": preparedMessages,
      if (tools != null && tools.isNotEmpty)
        "tools": [for (final t in tools) t.toJson()],
      if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
      "stream": true,
    });

    http.StreamedResponse response = await _client.send(request);

    // If the server rejects images (400), retry without them and cache
    // the model as non-vision so future requests skip images immediately.
    if (response.statusCode == 400 && supportsVision && hasImages) {
      final body = await response.stream.bytesToString();
      if (body.contains('image')) {
        _capabilitiesCache[chat.model] = const ModelCapabilities();

        final retryMessages = await prepareMessagesWithSystemPrompt(
          messages, chat.systemPrompt,
          conversationMemory: conversationMemory,
          profile: profile,
          relevantContext: relevantContext,
          currentModel: chat.model,
          supportsVision: false,
          extraMessages: extraMessages,
        );

        final retryRequest = http.Request("POST", url);
        retryRequest.headers.addAll(headers);
        retryRequest.body = json.encode({
          "model": chat.model,
          "messages": retryMessages,
          if (tools != null && tools.isNotEmpty)
            "tools": [for (final t in tools) t.toJson()],
          if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
          "stream": true,
        });

        response = await _client.send(retryRequest);
      }
    }

    if (response.statusCode == 200) {
      await for (final message in _processStream(response.stream)) {
        yield message;
      }
    } else if (response.statusCode == 404) {
      throw OllamaException("${chat.model} not found on the server.");
    } else {
      final body = await response.stream.bytesToString();
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: body));
    }
  }

  Stream<OllamaMessage> _processStream(Stream stream) async* {
    // Buffer to store the incomplete JSON object. This is necessary because
    // the Ollama service may send partial JSON objects in a single response.
    // We need to buffer the partial JSON objects and combine them to form
    // complete JSON objects.
    String buffer = '';

    await for (var chunk in stream.transform(utf8.decoder)) {
      chunk = buffer + chunk;
      buffer = '';

      // Split the chunk into lines and parse each line as JSON. This is
      // necessary because the Ollama service may send multiple JSON objects
      // in a single response.
      final lines = LineSplitter.split(chunk);

      for (var line in lines) {
        try {
          final jsonBody = json.decode(line);
          yield OllamaMessage.fromJson(jsonBody);
        } catch (_) {
          buffer = line;
        }
      }
    }
  }

  // Serializes chat messages with a system prompt.
  // Annotates assistant messages with the model that generated them
  // so the receiving model understands multi-model conversation context.
  // When memory is available and the conversation is long, only the most
  // recent messages are kept (the memory summary covers older context).
  @visibleForTesting
  Future<List<Map<String, dynamic>>> prepareMessagesWithSystemPrompt(
    List<OllamaMessage> messages,
    String? systemPrompt, {
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    String? currentModel,
    bool supportsVision = true,
    List<OllamaMessage> extraMessages = const [],
  }) async {
    // Coverage-based window: send raw everything the conversation summary does
    // NOT cover, so a lagging summary yields a larger — never lossy — context
    // instead of silently dropping the messages between the summary and the
    // recent window.
    int coveredCount = 0;
    if (conversationMemory != null && !conversationMemory.isEmpty) {
      final c = conversationMemory.summarizedMessageCount;
      if (c > 0 && c < messages.length) coveredCount = c;
    }
    final messagesToProcess =
        coveredCount > 0 ? messages.sublist(coveredCount) : messages;

    // Detect if multiple models are used in the conversation
    final modelNames = messagesToProcess
        .where((m) => m.role == OllamaMessageRole.assistant && m.model != null)
        .map((m) => m.model!)
        .toSet();
    final isMultiModel = modelNames.length > 1 ||
        (modelNames.length == 1 && currentModel != null && !modelNames.contains(currentModel));

    final jsonMessages = <Map<String, dynamic>>[];

    for (final m in messagesToProcess) {
      Map<String, dynamic> msgJson;

      // For confirmed non-vision models, replace images with a text placeholder
      // so the model knows images were attached but can still answer.
      if (!supportsVision && m.images != null && m.images!.isNotEmpty) {
        final count = m.images!.length;
        final tag = '[${count} image${count > 1 ? 's' : ''} attached — not viewable by this model]';
        msgJson = {
          "role": m.role.name,
          "content": '$tag\n${m.content}',
        };
      } else {
        msgJson = await m.toChatJson();
      }

      // Never re-send prior reasoning or the persisted <!--SEARCH_DATA:…--> blob
      // to the model — history should carry only the visible answer. The stored
      // copy (decoded by the UI think-block / search card) keeps `thinking`.
      msgJson.remove('thinking');

      // Only annotate assistant messages from a DIFFERENT model in multi-model chats
      // Use system-style annotation that models are less likely to copy
      if (isMultiModel &&
          m.role == OllamaMessageRole.assistant &&
          m.model != null &&
          m.model!.isNotEmpty &&
          m.model != currentModel) {
        final displayName =
            m.model!.contains(':') ? m.model!.split(':').first : m.model!;
        msgJson['content'] = '(Response from $displayName)\n${msgJson['content']}';
      }
      jsonMessages.add(msgJson);
    }

    // Tool-call transcript is always appended after the coverage window so a
    // fully-summarized history cannot drop the latest tool turn.
    for (final m in extraMessages) {
      final extraJson = await m.toChatJson();
      final keepThinking = m.toolCalls != null && m.toolCalls!.isNotEmpty;
      if (!keepThinking) {
        extraJson.remove('thinking');
      }
      jsonMessages.add(extraJson);
    }

    // Build the system prompt with memory injection
    final systemParts = <String>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      systemParts.add(systemPrompt);
    }

    // Inject memories if available. The conversation summary is only useful
    // when it covers messages that are NOT in the raw window above; when the
    // whole conversation is sent raw (coveredCount == 0) the summary would just
    // duplicate it, so skip it.
    final profileBlock = profile?.toPromptBlock() ?? '';
    final convBlock =
        coveredCount > 0 ? (conversationMemory?.toPromptBlock() ?? '') : '';
    if (profileBlock.isNotEmpty || relevantContext.isNotEmpty || convBlock.isNotEmpty) {
      systemParts.add(MemoryConstants.buildMemoryInjection(
        profileBlock: profileBlock,
        relevantContextBlock: relevantContext,
        conversationMemoryBlock: convBlock,
      ));
    }

    if (systemParts.isNotEmpty) {
      final combinedSystem = systemParts.join('\n\n');
      final sp = OllamaMessage(combinedSystem, role: OllamaMessageRole.system);
      jsonMessages.insert(0, await sp.toChatJson());
    }

    return jsonMessages;
  }

  /// Lists the available models on the Ollama service.
  ///
  /// Fetches models from /api/tags and enriches each with capabilities
  /// from /api/show. If /api/show fails for a model, capabilities will be null.
  Future<List<OllamaModel>> listModels() async {
    if (_isOpenRouterMode) {
      return _listOpenRouterModels();
    }
    final tagsResponse = await _fetchTags();

    // Fetch capabilities for each model in parallel
    final models = await Future.wait(
      tagsResponse.models.map((model) async {
        final showResponse = await _showModel(model.name);
        final ollamaModel = OllamaModel.from(model, showResponse);
        // Cache capabilities for vision checks during streaming
        if (ollamaModel.capabilities != null) {
          _capabilitiesCache[ollamaModel.name] = ollamaModel.capabilities!;
        }
        return ollamaModel;
      }),
    );

    return models;
  }

  /// Fetches the list of models from /api/tags
  Future<ApiTagsResponse> _fetchTags() async {
    final url = constructUrl("/api/tags");

    final response = await _client.get(url, headers: headers).timeout(
          Duration(seconds: isRemoteMode ? 10 : 2),
        );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return ApiTagsResponse.fromJson(jsonBody);
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw OllamaException("Invalid API key. Check your key in Settings.");
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  /// Fetches detailed model information from /api/show
  ///
  /// Returns null if the endpoint is unavailable or returns an error.
  /// This ensures graceful degradation for older Ollama versions.
  Future<ApiShowResponse?> _showModel(String name) async {
    try {
      final url = constructUrl("/api/show");

      final response = await _client
          .post(
            url,
            headers: headers,
            body: json.encode({"model": name}),
          )
          .timeout(Duration(seconds: isRemoteMode ? 10 : 5));

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        return ApiShowResponse.fromJson(jsonBody);
      }
    } catch (_) {
      // Silently ignore - endpoint may not exist on cloud or older Ollama versions
    }

    return null;
  }

  /// Returns cached or freshly-fetched capabilities for [model].
  /// Null means unknown (show failed or returned no capabilities).
  Future<ModelCapabilities?> getCapabilities(String model) async {
    final cached = _capabilitiesCache[model];
    if (cached != null) return cached;
    // OpenRouter capabilities come from /models. An uncached model is
    // unknown; probing Ollama's /api/show here only adds a failed network
    // round trip (or a 10-second timeout) before research can start.
    if (_isOpenRouterMode) return null;
    final probeKey = _capabilityProbeKey(model);
    if (_capabilitiesUnavailable.contains(probeKey)) return null;
    final show = await _showModel(model);
    if (show != null && show.capabilities.isNotEmpty) {
      final caps = ModelCapabilities.fromList(show.capabilities);
      _capabilitiesCache[model] = caps;
      return caps;
    }
    // Remembered as unknown, not retried. Callers treat null the same as
    // "capable" (an unknown model still gets tools), so re-asking costs a
    // stall before every research run and can never change the answer
    // within a session.
    _capabilitiesUnavailable.add(probeKey);
    return null;
  }

  Future<List<OllamaModel>> _listOpenRouterModels() async {
    final url = constructUrl('/models');
    final response = await _client.get(url, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OllamaException('Invalid API key. Check your key in Settings.');
    }
    if (response.statusCode != 200) {
      throw OllamaException(HttpErrorFormatter.formatHttpError(
        response.statusCode,
        body: response.body,
      ));
    }

    final jsonBody = json.decode(response.body);
    if (jsonBody is! Map<String, dynamic>) {
      throw OllamaException('Unexpected OpenRouter models response.');
    }
    final models = OpenRouterCodec.parseModels(jsonBody);
    for (final model in models) {
      if (model.capabilities != null) {
        _capabilitiesCache[model.name] = model.capabilities!;
      }
    }
    return models;
  }

  Future<List<Map<String, dynamic>>> _openRouterPreparedMessages(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaMessage> extraMessages = const [],
    bool supportsVision = true,
  }) async {
    final prepared = await prepareMessagesWithSystemPrompt(
      messages,
      chat.systemPrompt,
      conversationMemory: conversationMemory,
      profile: profile,
      relevantContext: relevantContext,
      currentModel: chat.model,
      supportsVision: supportsVision,
      extraMessages: extraMessages,
    );
    return OpenRouterCodec.toOpenAiMessages(prepared);
  }

  Map<String, dynamic> _openRouterBody({
    required OllamaChat chat,
    required List<Map<String, dynamic>> messages,
    required bool stream,
    List<OllamaToolDefinition>? tools,
  }) {
    return OpenRouterCodec.chatBody(
      model: chat.model,
      messages: messages,
      stream: stream,
      temperature: chat.options.temperature,
      tools: tools == null || tools.isEmpty
          ? null
          : [for (final t in tools) t.toJson()],
    );
  }

  Future<OllamaMessage> _openRouterChat(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaToolDefinition>? tools,
    List<OllamaMessage> extraMessages = const [],
  }) async {
    final prepared = await _openRouterPreparedMessages(
      messages,
      chat: chat,
      conversationMemory: conversationMemory,
      profile: profile,
      relevantContext: relevantContext,
      extraMessages: extraMessages,
    );
    final response = await _client.post(
      constructUrl('/chat/completions'),
      headers: headers,
      body: json.encode(_openRouterBody(
        chat: chat,
        messages: prepared,
        stream: false,
        tools: tools,
      )),
    );
    return _openRouterCompletionFromResponse(response, chat.model);
  }

  Stream<OllamaMessage> _openRouterChatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaToolDefinition>? tools,
    List<OllamaMessage> extraMessages = const [],
  }) async* {
    final hasImages =
        messages.any((m) => m.images != null && m.images!.isNotEmpty);
    bool supportsVision = true;
    if (hasImages) {
      if (!_capabilitiesCache.containsKey(chat.model)) {
        await listModels();
      }
      supportsVision = _capabilitiesCache[chat.model]?.vision ?? true;
    }

    final prepared = await _openRouterPreparedMessages(
      messages,
      chat: chat,
      conversationMemory: conversationMemory,
      profile: profile,
      relevantContext: relevantContext,
      extraMessages: extraMessages,
      supportsVision: supportsVision,
    );

    final request = http.Request('POST', constructUrl('/chat/completions'));
    request.headers.addAll(headers);
    request.body = json.encode(_openRouterBody(
      chat: chat,
      messages: prepared,
      stream: true,
      tools: tools,
    ));

    var response = await _client.send(request);
    if (response.statusCode == 400 && supportsVision && hasImages) {
      final body = await response.stream.bytesToString();
      if (body.toLowerCase().contains('image')) {
        _capabilitiesCache[chat.model] = const ModelCapabilities();
        final retryMessages = await _openRouterPreparedMessages(
          messages,
          chat: chat,
          conversationMemory: conversationMemory,
          profile: profile,
          relevantContext: relevantContext,
          extraMessages: extraMessages,
          supportsVision: false,
        );
        final retry = http.Request('POST', constructUrl('/chat/completions'));
        retry.headers.addAll(headers);
        retry.body = json.encode(_openRouterBody(
          chat: chat,
          messages: retryMessages,
          stream: true,
          tools: tools,
        ));
        response = await _client.send(retry);
      }
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OllamaException('Invalid API key. Check your key in Settings.');
    }
    if (response.statusCode == 404) {
      throw OllamaException('${chat.model} not found on OpenRouter.');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw OllamaException(
        HttpErrorFormatter.formatHttpError(response.statusCode, body: body),
      );
    }

    await for (final message in _processOpenRouterStream(response.stream)) {
      yield message;
    }
  }

  Future<OllamaMessage> _openRouterGenerate(
    String prompt, {
    required OllamaChat chat,
  }) async {
    final messages = <Map<String, dynamic>>[
      if (chat.systemPrompt != null && chat.systemPrompt!.isNotEmpty)
        {'role': 'system', 'content': chat.systemPrompt},
      {'role': 'user', 'content': prompt},
    ];
    final response = await _client.post(
      constructUrl('/chat/completions'),
      headers: headers,
      body: json.encode(_openRouterBody(
        chat: chat,
        messages: messages,
        stream: false,
      )),
    );
    return _openRouterCompletionFromResponse(response, chat.model);
  }

  Stream<OllamaMessage> _openRouterGenerateStream(
    String prompt, {
    required OllamaChat chat,
  }) async* {
    final messages = <Map<String, dynamic>>[
      if (chat.systemPrompt != null && chat.systemPrompt!.isNotEmpty)
        {'role': 'system', 'content': chat.systemPrompt},
      {'role': 'user', 'content': prompt},
    ];
    final request = http.Request('POST', constructUrl('/chat/completions'));
    request.headers.addAll(headers);
    request.body = json.encode(_openRouterBody(
      chat: chat,
      messages: messages,
      stream: true,
    ));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw OllamaException(
        HttpErrorFormatter.formatHttpError(response.statusCode, body: body),
      );
    }
    await for (final message in _processOpenRouterStream(response.stream)) {
      yield message;
    }
  }

  Future<OllamaMessage> _openRouterCompletionFromResponse(
    http.Response response,
    String model,
  ) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OllamaException('Invalid API key. Check your key in Settings.');
    }
    if (response.statusCode == 404) {
      throw OllamaException('$model not found on OpenRouter.');
    }
    if (response.statusCode != 200) {
      throw OllamaException(HttpErrorFormatter.formatHttpError(
        response.statusCode,
        body: response.body,
      ));
    }
    final jsonBody = json.decode(utf8.decode(response.bodyBytes));
    if (jsonBody is! Map) {
      throw OllamaException('Unexpected OpenRouter response.');
    }
    return OpenRouterCodec.parseCompletion(
      Map<String, dynamic>.from(jsonBody),
    );
  }

  Stream<OllamaMessage> _processOpenRouterStream(Stream<List<int>> stream) async* {
    String buffer = '';
    final assembler = OpenRouterToolCallAssembler();
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final message = _consumeOpenRouterSseLine(line, assembler);
        if (message != null) yield message;
      }
    }
    if (buffer.trim().isNotEmpty) {
      final message = _consumeOpenRouterSseLine(buffer, assembler);
      if (message != null) yield message;
    }
    final leftover = assembler.build();
    if (leftover.isNotEmpty) {
      yield OllamaMessage(
        '',
        role: OllamaMessageRole.assistant,
        toolCalls: leftover,
        done: true,
      );
    }
  }

  OllamaMessage? _consumeOpenRouterSseLine(
    String line,
    OpenRouterToolCallAssembler assembler,
  ) {
    final json = OpenRouterCodec.decodeSseJson(line);
    if (json == null) return OpenRouterCodec.parseSseLine(line);
    assembler.addFromCompletionJson(json);
    final message = OpenRouterCodec.parseCompletion(json);
    if (message.done == true) {
      final built = assembler.build();
      assembler.clear();
      if (built.isEmpty) return message;
      return OllamaMessage(
        message.content,
        role: message.role,
        thinking: message.thinking,
        toolCalls: built,
        model: message.model,
        done: true,
      );
    }
    if (message.toolCalls != null) {
      return OllamaMessage(
        message.content,
        role: message.role,
        thinking: message.thinking,
        model: message.model,
        done: false,
      );
    }
    return message;
  }

  Future<void> createModel(
    String model, {
    required OllamaChat chat,
    List<OllamaMessage>? messages,
  }) async {
    final url = constructUrl("/api/create");

    final request = ApiCreateRequest.fromChat(
      model,
      chat: chat,
      messages: messages,
    );

    final response = await _client.post(
      url,
      headers: headers,
      body: json.encode(await request.toJson()),
    );

    if (response.statusCode == 200) {
      return;
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Future<void> deleteModel(String model) async {
    final url = constructUrl("/api/delete");

    final response = await _client.delete(
      url,
      headers: headers,
      body: json.encode({"model": model}),
    );

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 404) {
      throw OllamaException("$model not found on the server.");
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  // ── Model readme fetching from ollama.com ──

  /// Readme parser version. Bump to invalidate cached readmes
  /// when the parsing logic changes.
  static const _readmeVersion = 2;
  static const _readmeVersionKey = '__readme_version__';

  /// Returns a cached readme for [modelName] from persistent storage,
  /// or null if not yet fetched.
  String? getCachedReadme(String modelName) {
    final box = Hive.box('model_readmes');
    if (box.get(_readmeVersionKey) != _readmeVersion) return null;
    return box.get(modelName);
  }

  /// Fetches the readme for a model from ollama.com/library/{name}.
  /// Returns the extracted text, or null on failure.
  /// Results are persisted to Hive for offline access.
  Future<String?> fetchModelReadme(String modelName) async {
    final box = Hive.box('model_readmes');
    // Invalidate old cache when parser version changes
    if (box.get(_readmeVersionKey) != _readmeVersion) {
      await box.clear();
      await box.put(_readmeVersionKey, _readmeVersion);
    }
    final cached = box.get(modelName) as String?;
    if (cached != null) return cached;

    // OpenRouter ids are `provider/model` and have no ollama.com library page.
    if (modelName.contains('/')) return null;

    final baseName = modelName.contains(':')
        ? modelName.split(':').first
        : modelName;

    try {
      final url = Uri.parse('https://ollama.com/library/$baseName');
      final response = await _client.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final readme = _parseReadmeFromHtml(response.body);
      if (readme != null && readme.isNotEmpty) {
        await box.put(modelName, readme);
      }
      return readme;
    } catch (_) {
      return null;
    }
  }

  /// Parses the readme text from the Ollama library HTML page.
  /// Extracts the core model description, stripping boilerplate.
  static String? _parseReadmeFromHtml(String html) {
    // Find the display div content inside the readme section
    final displayStart = html.indexOf('id="display"');
    if (displayStart == -1) return null;

    final contentStart = html.indexOf('>', displayStart);
    if (contentStart == -1) return null;

    // End at the next major section or end of content
    var endIndex = html.length;
    for (final marker in ['</section>', '<footer', '<div class="flex flex-1 flex-col py-8" id="']) {
      final idx = html.indexOf(marker, contentStart + 1);
      if (idx != -1 && idx < endIndex && idx > contentStart + 100) {
        endIndex = idx;
      }
    }

    var rawContent = html.substring(contentStart + 1, endIndex);

    // Remove images, tables, code blocks, and blockquotes (boilerplate)
    rawContent = rawContent
        .replaceAll(RegExp(r'<img[^>]*>'), '')
        .replaceAll(RegExp(r'<table[\s\S]*?</table>'), '')
        .replaceAll(RegExp(r'<pre[\s\S]*?</pre>'), '')
        .replaceAll(RegExp(r'<blockquote[\s\S]*?</blockquote>'), '');

    // Convert to text
    var text = rawContent
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</p>|</li>|</h[1-6]>'), '\n')
        .replaceAll(RegExp(r'<li[^>]*>'), '- ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // Collapse whitespace and split into lines
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Filter out boilerplate lines
    final boilerplatePatterns = [
      RegExp(r'^(This model )?requires? Ollama', caseSensitive: false),
      RegExp(r'^Download Ollama', caseSensitive: false),
      RegExp(r'^ollama (run|pull|serve)', caseSensitive: false),
      RegExp(r'^\d+[BKMG] parameter model', caseSensitive: false),
      RegExp(r'^\d+[BKMG] ?parameter', caseSensitive: false),
      RegExp(r'^Models$', caseSensitive: false),
      RegExp(r'^Text$', caseSensitive: false),
      RegExp(r'^\d+[kmKM] context window', caseSensitive: false),
      RegExp(r'^Note:', caseSensitive: false),
    ];

    final filtered = lines.where((line) {
      return !boilerplatePatterns.any((p) => p.hasMatch(line));
    }).toList();

    text = filtered.join('\n');

    // Limit to ~500 chars — cut at a sentence boundary
    if (text.length > 500) {
      // Try to cut at a period followed by space or newline
      final cutoff = text.indexOf(RegExp(r'\.\s'), 350);
      if (cutoff > 0 && cutoff < 500) {
        text = text.substring(0, cutoff + 1);
      } else {
        final nlCutoff = text.lastIndexOf('\n', 500);
        text = '${text.substring(0, nlCutoff > 300 ? nlCutoff : 500)}...';
      }
    }

    return text.trim().isEmpty ? null : text.trim();
  }
}
