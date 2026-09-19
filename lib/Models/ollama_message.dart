import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
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

  bool get hasVisualInput =>
      (images != null && images!.isNotEmpty) ||
      (attachments?.any((attachment) => attachment.images.isNotEmpty) ?? false);

  /// Files attached to a user message (PDFs, docs, and classified images).
  List<ChatAttachment>? attachments;

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
    this.attachments,
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
      attachments: _constructAttachments(map['attachments']),
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

  Future<Map<String, dynamic>> toChatJson({bool supportsVision = true}) async => {
        "role": role.name,
        "content": modelContent(supportsVision: supportsVision),
        if (thinking != null) "thinking": thinking,
        if (supportsVision) "images": await _base64EncodeImages(),
        if (toolCalls != null && toolCalls!.isNotEmpty)
          "tool_calls": [for (final call in toolCalls!) call.toJson()],
        if (toolName != null) "tool_name": toolName,
      };

  /// Prompt the model actually sees: typed text plus extracted document text.
  ///
  /// When [supportsVision] is false, page images are dropped and a short
  /// placeholder is added so the model still knows a visual file was attached.
  String modelContent({bool supportsVision = true}) {
    final parts = <String>[];
    if (content.trim().isNotEmpty) parts.add(content);

    final docs = attachments ?? const <ChatAttachment>[];
    for (final attachment in docs) {
      if (attachment.kind == ChatAttachmentKind.image) continue;
      if (attachment.hasExtractedText) {
        parts.add(
          '--- Attached file: ${attachment.fileName} ---\n'
          '${attachment.extractedText}\n'
          '--- End of ${attachment.fileName} ---',
        );
      } else if (!supportsVision && attachment.images.isNotEmpty) {
        parts.add(
          '[Attached file: ${attachment.fileName} — visual pages not viewable by this model]',
        );
      } else if (!attachment.hasExtractedText && attachment.images.isEmpty) {
        parts.add('[Attached file: ${attachment.fileName} — no extractable text]');
      }
    }

    final onlyImages = docs.isEmpty || docs.every((a) => a.kind == ChatAttachmentKind.image);
    if (!supportsVision && (images?.isNotEmpty ?? false) && onlyImages) {
      final count = images!.length;
      final tag =
          '[$count image${count > 1 ? 's' : ''} attached — not viewable by this model]';
      parts.insert(0, tag);
    }

    return parts.join('\n\n');
  }

  Map<String, dynamic> toDatabaseMap() => {
        'message_id': id,
        'content': content,
        'thinking': thinking,
        'images': _breakImages(images),
        'attachments': _breakAttachments(attachments),
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

  static List<ChatAttachment>? _constructAttachments(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) return null;
    return [
      for (final item in decoded)
        if (item is Map)
          ChatAttachment.fromDatabaseJson(Map<String, dynamic>.from(item)),
    ];
  }

  String? _breakAttachments(List<ChatAttachment>? attachments) {
    if (attachments == null || attachments.isEmpty) return null;
    return jsonEncode([
      for (final attachment in attachments) attachment.toDatabaseJson(),
    ]);
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
