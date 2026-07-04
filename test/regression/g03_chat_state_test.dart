import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatProvider fakeChatProvider;
  late FakePermissionService fakePermissionService;
  late FakeImageService fakeImageService;
  late ChatPageViewModel viewModel;

  setUpAll(() async {
    PathProviderPlatform.instance = FakePathProviderPlatform();

    final testDir = path.join(Directory.current.path, 'test', 'assets');
    Hive.init(testDir);
    if (!Hive.isBoxOpen('settings')) {
      await Hive.openBox('settings');
    }
  });

  setUp(() async {
    fakeChatProvider = FakeChatProvider();
    fakePermissionService = FakePermissionService();
    fakeImageService = FakeImageService();

    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    viewModel = ChatPageViewModel(
      chatProvider: fakeChatProvider,
      permissionService: fakePermissionService,
      imageService: fakeImageService,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('web search callback race after cancel + rapid re-send', () {
    setUp(() {
      viewModel.acceptWebSearchConsent(); // enables web search
      fakeChatProvider.setCurrentChat(createTestChat('chat-1'));
    });

    test('a cancelled request must not clear the new request callbacks', () async {
      // 1. First send with web search enabled. sendPrompt suspends.
      viewModel.setTextFieldValue('first question');
      final firstSend = viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
      await Future.microtask(() {});

      final firstCallbacks = fakeChatProvider.activeCallbacks;
      expect(firstCallbacks, isNotNull);

      // 2. User taps Stop.
      viewModel.cancelStreaming();
      fakeChatProvider.setIsStreaming(false);

      // 3. New send before the old stream resumes. Fresh callbacks installed.
      viewModel.setTextFieldValue('second question');
      final secondSend = viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
      await Future.microtask(() {});

      final secondCallbacks = fakeChatProvider.activeCallbacks;
      expect(secondCallbacks, isNotNull);
      expect(identical(secondCallbacks, firstCallbacks), isFalse);

      // 4. Old cancelled stream resumes and completes. Its finally runs.
      fakeChatProvider.completeSendPrompt(0);
      await firstSend;

      // 5. The new request's callbacks must still be installed.
      expect(fakeChatProvider.activeCallbacks, isNotNull);
      expect(identical(fakeChatProvider.activeCallbacks, secondCallbacks), isTrue);

      fakeChatProvider.completeSendPrompt(1);
      await secondSend;

      // Once the newer request finishes normally, callbacks are torn down.
      expect(fakeChatProvider.activeCallbacks, isNull);
    });

    test('a request that finishes normally clears its own callbacks', () async {
      viewModel.setTextFieldValue('only question');
      final send = viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
      await Future.microtask(() {});

      expect(fakeChatProvider.activeCallbacks, isNotNull);

      fakeChatProvider.completeSendPrompt(0);
      await send;

      expect(fakeChatProvider.activeCallbacks, isNull);
    });
  });

  group('failed image compression', () {
    setUp(() {
      ImagePickerPlatform.instance = FakeImagePickerPlatform();
    });

    test('does not attach an empty-path file', () async {
      fakeImageService.compressedFile = null; // simulate compression failure

      await viewModel.pickImages();

      expect(viewModel.imageFiles, isEmpty);
      expect(viewModel.hasImageAttachments, isFalse);
    });

    test('reports the failure to the caller', () async {
      fakeImageService.compressedFile = null;
      var failureReported = false;

      await viewModel.pickImages(onCompressionFailed: () => failureReported = true);

      expect(failureReported, isTrue);
    });

    test('leaves the chat sendable after a compression failure', () async {
      fakeImageService.compressedFile = null;
      await viewModel.pickImages();

      viewModel.setTextFieldValue('describe this');
      fakeChatProvider.setCurrentChat(createTestChat('chat-1'));

      final send = viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );
      await Future.microtask(() {});
      fakeChatProvider.completeSendPrompt(0);
      final result = await send;

      expect(result, isTrue);
      expect(fakeChatProvider.lastSentImages, isEmpty);
    });
  });
}

// ============================================================
// Test Helpers
// ============================================================

OllamaModel createTestModel(String name) {
  return OllamaModel(
    name: name,
    model: name,
    modifiedAt: DateTime.now(),
    size: 1000,
    digest: 'test-digest-$name',
    parameterSize: '1B',
  );
}

OllamaChat createTestChat(String id) {
  return OllamaChat(
    id: id,
    model: 'llama3.2',
    title: 'Test Chat',
    options: OllamaChatOptions(),
    systemPrompt: null,
  );
}

// ============================================================
// Fake Classes
// ============================================================

/// Records the currently installed web-search callback set so the test can
/// assert whether a stale teardown erased a newer request's callbacks.
class WebSearchCallbackSet {
  final void Function(String query) onSearchStart;
  WebSearchCallbackSet(this.onSearchStart);
}

class FakeChatProvider extends ChangeNotifier implements ChatProvider {
  final List<OllamaMessage> _messages = [];
  OllamaChat? _currentChat;
  bool _isStreaming = false;

  WebSearchCallbackSet? activeCallbacks;
  List<File>? lastSentImages;

  final List<Completer<void>> _sendPromptCompleters = [];

  void setCurrentChat(OllamaChat? chat) {
    _currentChat = chat;
  }

  void setIsStreaming(bool value) {
    _isStreaming = value;
  }

  void completeSendPrompt(int index) {
    _sendPromptCompleters[index].complete();
  }

  @override
  List<OllamaMessage> get messages => _messages;

  @override
  OllamaChat? get currentChat => _currentChat;

  @override
  bool get isCurrentChatStreaming => _isStreaming;

  @override
  bool get isCurrentChatThinking => false;

  @override
  OllamaException? get currentChatError => null;

  @override
  void cancelCurrentStreaming() {
    _isStreaming = false;
  }

  @override
  void setWebSearchCallbacks({
    required void Function(String thinking) onSearchThinking,
    required void Function(String query) onSearchStart,
    required void Function(String query) onSearchQueryUpdate,
    required void Function(List<WebSearchResult> results) onSearchComplete,
    required List<MessageSegment> Function() segmentsProvider,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
  }) {
    activeCallbacks = WebSearchCallbackSet(onSearchStart);
  }

  @override
  void clearWebSearchCallbacks() {
    activeCallbacks = null;
  }

  @override
  Future<void> createNewChat(OllamaModel model, {bool isIncognito = false}) async {
    _currentChat = createTestChat('new-chat-id');
  }

  @override
  OllamaMessage displayUserMessage(String text, {List<File>? images}) {
    lastSentImages = images;
    final message = OllamaMessage(text.trim(), images: images, role: OllamaMessageRole.user);
    _messages.add(message);
    return message;
  }

  @override
  Future<void> sendPrompt(OllamaMessage prompt, {int searchAttemptsRemaining = 0}) {
    final completer = Completer<void>();
    _sendPromptCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<void> generateTitleForCurrentChat() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePermissionService implements PermissionService {
  bool shouldGrantPermission = true;

  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async {
    if (!shouldGrantPermission) {
      onDenied?.call();
    }
    return shouldGrantPermission;
  }
}

class FakeImageService implements ImageService {
  List<File> deletedImages = [];
  File? compressedFile;

  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async {
    return compressedFile;
  }

  @override
  Future<void> deleteImage(File imageFile) async {
    deletedImages.add(imageFile);
  }

  @override
  Future<void> deleteImages(List<File> imageFiles) async {
    deletedImages.addAll(imageFiles);
  }

  @override
  Future<Directory> getImagesDirectory() async {
    return Directory.systemTemp;
  }
}

class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return path.join(Directory.current.path, 'test', 'assets');
  }
}

class FakeImagePickerPlatform extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    return XFile(path.join(Directory.systemTemp.path, 'picked.jpg'));
  }
}
