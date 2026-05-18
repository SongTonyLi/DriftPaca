import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Utils/http_error_formatter.dart';
import 'package:llamaseek/Models/api/tags_response.dart';
import 'package:llamaseek/Models/api/show_response.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/api/create_request.dart';

class OllamaService {
  static const String defaultLocalUrl = "http://localhost:11434";
  static const String cloudBaseUrl = "https://ollama.com";

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

  /// Whether the service is in cloud mode.
  bool _isCloudMode = false;
  bool get isCloudMode => _isCloudMode;
  set isCloudMode(bool value) {
    _isCloudMode = value;
    if (value) {
      _baseUrl = cloudBaseUrl;
    }
  }

  /// The API key for Ollama Cloud authentication.
  String? _apiKey;
  String? get apiKey => _apiKey;
  set apiKey(String? value) => _apiKey = value;

  /// The headers to include in all network requests.
  Map<String, String> get headers {
    final h = {'Content-Type': 'application/json'};
    if (_isCloudMode && _apiKey != null && _apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_apiKey';
    }
    return h;
  }

  /// Creates a new instance of the Ollama service.
  OllamaService({String? baseUrl}) : _baseUrl = baseUrl ?? defaultLocalUrl;

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
    if (_isCloudMode) return null;
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
    final url = constructUrl("/api/generate");

    final response = await http.post(
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
      final jsonBody = json.decode(response.body);
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

    http.StreamedResponse response = await request.send();

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
  }) async {
    final url = constructUrl("/api/chat");

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "messages": await _prepareMessagesWithSystemPrompt(messages, chat.systemPrompt),
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
  }) async* {
    final url = constructUrl('/api/chat');

    final request = http.Request("POST", url);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "messages": await _prepareMessagesWithSystemPrompt(messages, chat.systemPrompt),
      if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
      "stream": true,
    });

    http.StreamedResponse response = await request.send();

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
  Future<List<Map<String, dynamic>>> _prepareMessagesWithSystemPrompt(
    List<OllamaMessage> messages,
    String? systemPrompt,
  ) async {
    final jsonMessages = <Map<String, dynamic>>[];

    for (final m in messages) {
      final json = await m.toChatJson();
      if (m.role == OllamaMessageRole.assistant &&
          m.model != null &&
          m.model!.isNotEmpty) {
        final displayName =
            m.model!.contains(':') ? m.model!.split(':').first : m.model!;
        json['content'] = '[$displayName]\n${json['content']}';
      }
      jsonMessages.add(json);
    }

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      final sp = OllamaMessage(systemPrompt, role: OllamaMessageRole.system);
      jsonMessages.insert(0, await sp.toChatJson());
    }

    return jsonMessages;
  }

  /// Lists the available models on the Ollama service.
  ///
  /// Fetches models from /api/tags and enriches each with capabilities
  /// from /api/show. If /api/show fails for a model, capabilities will be null.
  Future<List<OllamaModel>> listModels() async {
    final tagsResponse = await _fetchTags();

    // Fetch capabilities for each model in parallel
    final models = await Future.wait(
      tagsResponse.models.map((model) async {
        final showResponse = await _showModel(model.name);
        return OllamaModel.from(model, showResponse);
      }),
    );

    return models;
  }

  /// Fetches the list of models from /api/tags
  Future<ApiTagsResponse> _fetchTags() async {
    final url = constructUrl("/api/tags");

    final response = await http.get(url, headers: headers).timeout(
          Duration(seconds: _isCloudMode ? 10 : 2),
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

      final response = await http
          .post(
            url,
            headers: headers,
            body: json.encode({"model": name}),
          )
          .timeout(Duration(seconds: _isCloudMode ? 10 : 5));

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        return ApiShowResponse.fromJson(jsonBody);
      }
    } catch (_) {
      // Silently ignore - endpoint may not exist on cloud or older Ollama versions
    }

    return null;
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

    final response = await http.post(
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

    final response = await http.delete(
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

    final baseName = modelName.contains(':')
        ? modelName.split(':').first
        : modelName;

    try {
      final url = Uri.parse('https://ollama.com/library/$baseName');
      final response = await http.get(url).timeout(const Duration(seconds: 8));

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
