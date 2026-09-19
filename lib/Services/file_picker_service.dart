import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:llamaseek/Services/document_types.dart';

/// A file chosen from the system document picker, before conversion.
class PickedAttachmentFile {
  final String name;
  final String? path;
  final Uint8List? bytes;

  const PickedAttachmentFile({
    required this.name,
    this.path,
    this.bytes,
  });
}

/// Thin wrapper around [FilePicker] so tests can inject a fake.
class FilePickerService {
  Future<PickedAttachmentFile?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: DocumentTypes.pickerExtensions.toList(),
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final name = file.name.trim().isEmpty ? 'file' : file.name;
    if (file.path == null && file.bytes == null) return null;
    return PickedAttachmentFile(
      name: name,
      path: file.path,
      bytes: file.bytes,
    );
  }
}
