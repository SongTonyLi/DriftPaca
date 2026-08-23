import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:uuid/uuid.dart';

class OllamaMessage {
  /// The unique identifier of the message.
  String id;

  /// The text content of the message.
  String content;

  /// The thinking/reasoning content of the message (from models with thinking capability).
  String? thinking;

  /// The image content of the message.
  List<File>? images;

  /// The date and time the message was created.
  DateTime createdAt;

  /// The role of the message.
  OllamaMessageRole role;

  /// Tool calls emitted by an assistant turn (ephemeral — not persisted).
  List<OllamaToolCall>? toolCalls;

  /// Tool name for `role: tool` result messages (ephemeral — not persisted).
  String? toolName;

  /// The model used to generate the message.
  String? model;

  // Metadata fields
  bool? done;
  String? doneReason;
  List<int>? context;
  int? totalDuration;
  int? loadDuration;
  int? promptEvalCount;
  int? promptEvalDuration;
  int? evalCount;
  int? evalDuration;

  OllamaMessage(
    this.content, {
    String? id,
    required this.role,
    this.thinking,
    this.toolCalls,
    this.toolName,
    this.images,
    DateTime? createdAt,
    this.model,
    this.done,
    this.doneReason,
    this.context,
    this.totalDuration,
    this.loadDuration,
    this.promptEvalCount,
    this.promptEvalDuration,
    this.evalCount,
    this.evalDuration,
  })  : id = id ?? Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory OllamaMessage.fromJson(Map<String, dynamic> json) {
    final message = json["message"];
    final rawContent = message != null ? message["content"] : json["response"];
    return OllamaMessage(
      rawContent?.toString() ?? '',
      role: message != null
          ? OllamaMessageRole.fromString(message["role"] ?? 'assistant')
          : OllamaMessageRole.assistant,
      thinking: message?["thinking"],
      toolCalls: _parseToolCalls(message?["tool_calls"]),
      toolName: message?["tool_name"] as String?,
      images: null,
      createdAt: DateTime.parse(json["created_at"]),
      model: json["model"],
      done: json["done"],
      doneReason: json["done_reason"],
      totalDuration: json["total_duration"],
      loadDuration: json["load_duration"],
      promptEvalCount: json["prompt_eval_count"],
      promptEvalDuration: json["prompt_eval_duration"],
      evalCount: json["eval_count"],
      evalDuration: json["eval_duration"],
    );
  }

  static List<OllamaToolCall>? _parseToolCalls(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    return [
      for (final item in raw)
        if (item is Map)
          OllamaToolCall.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  factory OllamaMessage.fromDatabase(Map<String, dynamic> map) {
    return OllamaMessage(
      map['content'],
      id: map['message_id'],
      role: OllamaMessageRole.fromString(map['role']),
      thinking: map['thinking'],
      images: _constructImages(map['images']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      model: map['model'],
    );
  }

  Future<Map<String, dynamic>> toJson() async => {
        "model": model,
        "created_at": createdAt.toIso8601String(),
        "message": {
          "role": role.name,
          "content": content,
          "images": await _base64EncodeImages(),
        },
        "done": done,
        "done_reason": doneReason,
        "context":
            context == null ? null : List<dynamic>.from(context!.map((x) => x)),
        "total_duration": totalDuration,
        "load_duration": loadDuration,
        "prompt_eval_count": promptEvalCount,
        "prompt_eval_duration": promptEvalDuration,
        "eval_count": evalCount,
        "eval_duration": evalDuration,
      };

  Future<Map<String, dynamic>> toChatJson() async => {
        "role": role.name,
        "content": content,
        if (thinking != null) "thinking": thinking,
        "images": await _base64EncodeImages(),
        if (toolCalls != null && toolCalls!.isNotEmpty)
          "tool_calls": [for (final call in toolCalls!) call.toJson()],
        if (toolName != null) "tool_name": toolName,
      };

  Map<String, dynamic> toDatabaseMap() => {
        'message_id': id,
        'content': content,
        'thinking': thinking,
        'images': _breakImages(images),
        'role': role.name,
        'model': model,
        'timestamp': createdAt.millisecondsSinceEpoch,
      };

  void updateMetadataFrom(OllamaMessage message) {
    if (message.thinking != null) thinking = message.thinking;
    if (message.model != null) model = message.model;
    done = message.done;
    doneReason = message.doneReason;
    context = message.context;
    totalDuration = message.totalDuration;
    loadDuration = message.loadDuration;
    promptEvalCount = message.promptEvalCount;
    promptEvalDuration = message.promptEvalDuration;
    evalCount = message.evalCount;
    evalDuration = message.evalDuration;
  }

  List<String>? _cachedBase64Images;

  Future<List<String>?> _base64EncodeImages() async {
    if (images == null) return null;
    if (_cachedBase64Images != null) return _cachedBase64Images;

    _cachedBase64Images = await Future.wait(images!.map(
      (file) async => base64Encode(await file.readAsBytes()),
    ));
    return _cachedBase64Images;
  }

  /// Releases the cached base64-encoded image data to free memory.
  /// The cache will be rebuilt on the next API call if needed.
  void clearBase64Cache() {
    _cachedBase64Images = null;
  }

  static List<File>? _constructImages(String? raw) {
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((imageRelativePath) {
        return File(path.join(
          PathManager.instance.documentsDirectory.path,
          imageRelativePath,
        ));
      }).toList();
    }

    return null;
  }

  String? _breakImages(List<File>? images) {
    if (images != null) {
      final relativePathImages = images.map((file) {
        return path.relative(
          file.path,
          from: PathManager.instance.documentsDirectory.path,
        );
      }).toList();

      return jsonEncode(relativePathImages);
    }

    return null;
  }
}

enum OllamaMessageRole {
  user,
  assistant,
  system,
  tool;

  factory OllamaMessageRole.fromString(String role) {
    switch (role) {
      case 'user':
        return OllamaMessageRole.user;
      case 'assistant':
        return OllamaMessageRole.assistant;
      case 'system':
        return OllamaMessageRole.system;
      case 'tool':
        return OllamaMessageRole.tool;
      default:
        throw ArgumentError('Unknown role: $role');
    }
  }
}
