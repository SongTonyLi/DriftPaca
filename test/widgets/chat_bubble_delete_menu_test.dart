import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_actions.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('del_menu_vm').path);
    if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
  });

  testWidgets('confirming the dialog calls viewModel.deleteExchange with the message',
      (tester) async {
    final fakeProvider = _RecordingChatProvider();
    final vm = ChatPageViewModel(
      chatProvider: fakeProvider,
      permissionService: _FakePerm(),
      imageService: _FakeImg(),
    );
    final msg = OllamaMessage('hi', role: OllamaMessageRole.user);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatPageViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ChatBubbleActions(msg).handleDeleteExchange(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this exchange?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fakeProvider.deleted, same(msg));
    vm.dispose();
  });

  testWidgets('cancelling the dialog does not call deleteExchange', (tester) async {
    final fakeProvider = _RecordingChatProvider();
    final vm = ChatPageViewModel(
      chatProvider: fakeProvider,
      permissionService: _FakePerm(),
      imageService: _FakeImg(),
    );
    final msg = OllamaMessage('hi', role: OllamaMessageRole.user);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatPageViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ChatBubbleActions(msg).handleDeleteExchange(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fakeProvider.deleted, isNull);
    vm.dispose();
  });
}

class _RecordingChatProvider extends ChangeNotifier implements ChatProvider {
  OllamaMessage? deleted;
  @override
  Future<void> deleteExchange(OllamaMessage anchor) async {
    deleted = anchor;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePerm implements PermissionService {
  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async => true;
}

class _FakeImg implements ImageService {
  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async => null;
  @override
  Future<void> deleteImage(File imageFile) async {}
  @override
  Future<void> deleteImages(List<File> imageFiles) async {}
  @override
  Future<Directory> getImagesDirectory() async => Directory.systemTemp;
}
