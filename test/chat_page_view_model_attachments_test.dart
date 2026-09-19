import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatProvider chatProvider;
  late FakePermissionService permissions;
  late FakeImageService images;
  late FakeFilePickerService filePicker;
  late ChatPageViewModel viewModel;

  setUpAll(() async {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    final testDir = Directory.systemTemp.createTempSync('vm_attachments_test').path;
    Hive.init(testDir);
    await Hive.openBox('settings');
  });

  setUp(() async {
    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');
    chatProvider = FakeChatProvider();
    permissions = FakePermissionService();
    images = FakeImageService();
    filePicker = FakeFilePickerService();
    viewModel = ChatPageViewModel(
      chatProvider: chatProvider,
      permissionService: permissions,
      imageService: images,
      documentService: DocumentService(
        imageService: images,
        storageDirectory: Directory.systemTemp.createTempSync('vm_doc_images'),
      ),
      filePickerService: filePicker,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('pickDocuments attaches extracted text from a text file', () async {
    filePicker.next = PickedAttachmentFile(
      name: 'notes.txt',
      bytes: Uint8List.fromList(utf8.encode('Meeting notes')),
    );

    await viewModel.pickDocuments();

    expect(viewModel.hasAttachments, isTrue);
    expect(viewModel.attachments.single.fileName, 'notes.txt');
    expect(viewModel.attachments.single.extractedText, 'Meeting notes');
  });

  test('sendMessage can send an attachment with an empty prompt', () async {
    filePicker.next = PickedAttachmentFile(
      name: 'notes.txt',
      bytes: Uint8List.fromList(utf8.encode('Only the file')),
    );
    await viewModel.pickDocuments();
    chatProvider.setCurrentChat(createTestChat('chat-1'));

    final sent = await viewModel.sendMessage(
      onModelSelectionRequired: () async {},
      onServerNotConfigured: () {},
    );

    expect(sent, isTrue);
    expect(chatProvider.lastSentPrompt, '');
    expect(chatProvider.lastSentAttachments, isNotNull);
    expect(chatProvider.lastSentAttachments!.single.extractedText, 'Only the file');
    expect(viewModel.hasAttachments, isFalse);
  });

  test('still refuses to send when there is no text and no attachment', () async {
    final sent = await viewModel.sendMessage(
      onModelSelectionRequired: () async {},
      onServerNotConfigured: () {},
    );
    expect(sent, isFalse);
    expect(chatProvider.sendPromptCalled, isFalse);
  });

  test('reports an import failure instead of attaching the file', () async {
    filePicker.next = PickedAttachmentFile(
      name: 'legacy.doc',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    String? error;
    await viewModel.pickDocuments(onFailed: (message) => error = message);
    expect(viewModel.hasAttachments, isFalse);
    expect(error, contains('docx'));
  });
}

class FakeFilePickerService implements FilePickerService {
  PickedAttachmentFile? next;

  @override
  Future<PickedAttachmentFile?> pickDocument() async => next;
}

class FakeChatProvider extends ChangeNotifier implements ChatProvider {
  OllamaChat? _currentChat;
  final List<OllamaMessage> _messages = [];
  bool sendPromptCalled = false;
  String? lastSentPrompt;
  List<ChatAttachment>? lastSentAttachments;

  void setCurrentChat(OllamaChat chat) => _currentChat = chat;

  @override
  List<OllamaMessage> get messages => _messages;

  @override
  OllamaChat? get currentChat => _currentChat;

  @override
  bool get isCurrentChatStreaming => false;

  @override
  bool get isCurrentChatThinking => false;

  @override
  bool get isAwaitingClarification => false;

  @override
  OllamaException? get currentChatError => null;

  @override
  OllamaMessage displayUserMessage(
    String text, {
    List<File>? images,
    List<ChatAttachment>? attachments,
  }) {
    lastSentPrompt = text;
    lastSentAttachments = attachments;
    final message = OllamaMessage(
      text.trim(),
      images: images,
      attachments: attachments,
      role: OllamaMessageRole.user,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<void> sendPrompt(OllamaMessage prompt, {int searchAttemptsRemaining = 0}) async {
    sendPromptCalled = true;
  }

  @override
  Future<void> generateTitleForCurrentChat() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePermissionService implements PermissionService {
  @override
  Future<bool> requestPhotoPermission({void Function()? onDenied}) async => true;
}

class FakeImageService implements ImageService {
  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async =>
      File(sourcePath);

  @override
  Future<void> deleteImage(File imageFile) async {}

  @override
  Future<void> deleteImages(List<File> imageFiles) async {}

  @override
  Future<Directory> getImagesDirectory() async => Directory.systemTemp;
}

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.createTempSync('vm_attach_docs').path;
  }
}

OllamaChat createTestChat(String id) {
  return OllamaChat(
    id: id,
    model: 'llama3.2',
    title: 'Test',
  );
}
