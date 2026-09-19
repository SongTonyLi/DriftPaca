/// Extensions the composer can import, grouped by how they become model input.
class DocumentTypes {
  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };

  static const Set<String> pdfExtensions = {'pdf'};

  static const Set<String> wordExtensions = {'docx'};

  static const Set<String> sheetExtensions = {'xlsx'};

  static const Set<String> slideExtensions = {'pptx'};

  static const Set<String> textExtensions = {
    'txt',
    'md',
    'markdown',
    'csv',
    'tsv',
    'json',
    'xml',
    'html',
    'htm',
    'log',
    'yaml',
    'yml',
    'rtf',
  };

  /// Older Office binaries we can detect so the user gets a convert-to-docx hint.
  static const Set<String> unsupportedLegacyExtensions = {
    'doc',
    'xls',
    'ppt',
  };

  static Set<String> get pickerExtensions => {
        ...imageExtensions,
        ...pdfExtensions,
        ...wordExtensions,
        ...sheetExtensions,
        ...slideExtensions,
        ...textExtensions,
        ...unsupportedLegacyExtensions,
      };

  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static bool isImage(String fileName) =>
      imageExtensions.contains(extensionOf(fileName));

  static bool isPdf(String fileName) =>
      pdfExtensions.contains(extensionOf(fileName));

  static bool isWord(String fileName) =>
      wordExtensions.contains(extensionOf(fileName));

  static bool isSheet(String fileName) =>
      sheetExtensions.contains(extensionOf(fileName));

  static bool isSlide(String fileName) =>
      slideExtensions.contains(extensionOf(fileName));

  static bool isText(String fileName) =>
      textExtensions.contains(extensionOf(fileName));

  static bool isUnsupportedLegacy(String fileName) =>
      unsupportedLegacyExtensions.contains(extensionOf(fileName));
}

/// Failed import with a message that can be shown in a dialog.
class DocumentImportException implements Exception {
  final String message;
  DocumentImportException(this.message);

  @override
  String toString() => message;
}
