import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_actions.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_menu.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/services.dart';

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

GestureDetector _detector(WidgetTester tester) => tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(ChatBubbleMenu),
        matching: find.byType(GestureDetector),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('del_menu_vm').path);
    if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
  });

  testWidgets('long-press reveals a Delete exchange item that fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(
      ChatBubbleMenu(
        menuChildren: [
          MenuItemButton(
            onPressed: () => tapped = true,
            child: const Text('Delete exchange'),
          ),
        ],
        child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Delete exchange'), findsNothing);

    _detector(tester).onLongPressStart!(
      const LongPressStartDetails(localPosition: Offset(20, 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete exchange'), findsOneWidget);

    await tester.tap(find.text('Delete exchange'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('a disabled (streaming) Delete item does not fire', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(
      ChatBubbleMenu(
        menuChildren: [
          MenuItemButton(
            onPressed: null, // streaming -> disabled
            child: const Text('Delete exchange'),
          ),
        ],
        child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
      ),
    ));
    await tester.pumpAndSettle();

    _detector(tester).onLongPressStart!(
      const LongPressStartDetails(localPosition: Offset(20, 20)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete exchange'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, isFalse);
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
