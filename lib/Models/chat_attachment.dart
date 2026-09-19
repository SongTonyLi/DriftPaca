import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:llamaseek/Constants/constants.dart';

/// Kind of file the user attached to a chat message.
enum ChatAttachmentKind {
  image,
  pdf,
  document;

  static ChatAttachmentKind fromName(String name) {
    return ChatAttachmentKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => ChatAttachmentKind.document,
    );
  }
}

/// A user-selected file that will be turned into model input.
///
/// Images stay images. PDFs become extracted text plus page/embedded images.
/// Other documents become extracted text only.
class ChatAttachment {
  final String id;
  final String fileName;
  final ChatAttachmentKind kind;
  final String? extractedText;
  final List<File> images;
  final int? pageCount;

  ChatAttachment({
    String? id,
    required this.fileName,
    required this.kind,
    this.extractedText,
    List<File>? images,
    this.pageCount,
  })  : id = id ?? const Uuid().v4(),
        images = List<File>.unmodifiable(images ?? const []);

  bool get hasExtractedText =>
      extractedText != null && extractedText!.trim().isNotEmpty;

  Map<String, dynamic> toDatabaseJson() {
    final docs = PathManager.instance.documentsDirectory.path;
    return {
      'id': id,
      'fileName': fileName,
      'kind': kind.name,
      'extractedText': extractedText,
      'imageRelativePaths': [
        for (final file in images)
          path.relative(file.path, from: docs),
      ],
      'pageCount': pageCount,
    };
  }

  factory ChatAttachment.fromDatabaseJson(Map<String, dynamic> json) {
    final docs = PathManager.instance.documentsDirectory.path;
    final rels = json['imageRelativePaths'];
    return ChatAttachment(
      id: json['id'] as String?,
      fileName: (json['fileName'] as String?)?.trim().isNotEmpty == true
          ? json['fileName'] as String
          : 'file',
      kind: ChatAttachmentKind.fromName(json['kind'] as String? ?? 'document'),
      extractedText: json['extractedText'] as String?,
      images: rels is List
          ? [
              for (final rel in rels)
                File(path.join(docs, rel.toString())),
            ]
          : const [],
      pageCount: json['pageCount'] as int?,
    );
  }
}
