import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/chat_page.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_attachment/chat_attachment_preset.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _EmptyChatProvider chatProvider;
  late ChatPageViewModel viewModel;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('chat_page_prompt_tabs_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    chatProvider = _EmptyChatProvider();
    viewModel = ChatPageViewModel(
      chatProvider: chatProvider,
      permissionService: _FakePermissionService(),
      imageService: _FakeImageService(),
    );
  });

  tearDown(() async {
    viewModel.dispose();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('welcome prompt tabs are hidden while composer is expanded',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
          ChangeNotifierProvider<ChatPageViewModel>.value(value: viewModel),
        ],
        child: MaterialApp(
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: const [
              Breakpoint(start: 0, end: 600, name: MOBILE),
              Breakpoint(start: 601, end: double.infinity, name: DESKTOP),
            ],
          ),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: ChatPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatAttachmentPreset), findsWidgets);
    expect(find.byType(ChatAttachmentPreset).hitTestable(), findsWidgets);

    await tester.tap(find.text('Message').last);
    await tester.pumpAndSettle();

    expect(find.byType(ChatAttachmentPreset), findsWidgets);
    expect(find.byType(ChatAttachmentPreset).hitTestable(), findsNothing);
  });
}

class _EmptyChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  List<OllamaMessage> get messages => const [];

  @override
  OllamaChat? get currentChat => null;

  @override
  bool get isCurrentChatStreaming => false;

  @override
  bool get isCurrentChatThinking => false;

  @override
  OllamaException? get currentChatError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissionService implements PermissionService {
  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async => true;
}

class _FakeImageService implements ImageService {
  @override
  Future<Directory> getImagesDirectory() async =>
      Directory.systemTemp.createTemp('chat_page_prompt_tabs_images');

  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async =>
      null;

  @override
  Future<void> deleteImage(File imageFile) async {}

  @override
  Future<void> deleteImages(List<File> imageFiles) async {}
}
