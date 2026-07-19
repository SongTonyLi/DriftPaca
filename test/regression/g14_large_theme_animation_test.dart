import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/chat_page.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/main_page.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/image_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/permission_service.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

class _EmptyChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  List<OllamaChat> get chats => const [];

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

class _AllowPermissionService implements PermissionService {
  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async => true;
}

class _NoopImageService implements ImageService {
  @override
  Future<Directory> getImagesDirectory() async => Directory.systemTemp.createTemp('large_theme_animation_images');

  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async => null;

  @override
  Future<void> deleteImage(File imageFile) async {}

  @override
  Future<void> deleteImages(List<File> images) async {}
}

void main() {
  late Directory tempDir;
  late _EmptyChatProvider chatProvider;
  late ChatPageViewModel viewModel;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('large_theme_animation');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    chatProvider = _EmptyChatProvider();
    viewModel = ChatPageViewModel(
      chatProvider: chatProvider,
      permissionService: _AllowPermissionService(),
      imageService: _NoopImageService(),
    );
  });

  tearDown(() async {
    viewModel.dispose();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('large layout animates theme colors when entering incognito mode', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatPageViewModel>.value(value: viewModel),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
          ChangeNotifierProvider<MemoryService>(
            create: (_) => MemoryService(db: DatabaseService()),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: const [
              Breakpoint(start: 0, end: 450, name: MOBILE),
              Breakpoint(start: 451, end: 800, name: TABLET),
              Breakpoint(start: 801, end: double.infinity, name: DESKTOP),
            ],
            useShortestSide: true,
          ),
          home: const DriftPacaMainPage(),
        ),
      ),
    );

    await tester.pump();

    final appAnimatedTheme = find.byWidgetPredicate(
      (widget) => widget is AnimatedTheme && widget.duration == const Duration(milliseconds: 400),
    );
    expect(appAnimatedTheme, findsOneWidget);
    final animatedTheme = tester.widget<AnimatedTheme>(appAnimatedTheme);
    expect(animatedTheme.duration, const Duration(milliseconds: 400));

    final before = Theme.of(tester.element(find.byType(ChatPage))).colorScheme.primary;
    viewModel.requestIncognito();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final during = Theme.of(tester.element(find.byType(ChatPage))).colorScheme.primary;
    expect(during, isNot(equals(before)));

    await tester.pump(const Duration(milliseconds: 250));
    final after = Theme.of(tester.element(find.byType(ChatPage))).colorScheme.primary;
    expect(after, isNot(equals(before)));
  });
}
