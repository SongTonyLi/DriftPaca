import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/settings_page/subwidgets/server_settings.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '.dart_tool/test_hive_openrouter_settings';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await Hive.initFlutter();
    await Hive.openBox('settings');
  });

  setUp(() async => Hive.box('settings').clear());

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ServerSettings())),
    ));
    await tester.pump();
  }

  testWidgets('settings offers Ollama and OpenRouter and persists the mode',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('Local'), findsNothing);
    expect(find.text('Ollama Server Address'), findsNothing);
    expect(find.text('Search Local Network'), findsNothing);
    expect(find.text('Cloud'), findsNothing);
    expect(find.text('Ollama'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);

    await tester.tap(find.text('OpenRouter'));
    await tester.pumpAndSettle();

    expect(Hive.box('settings').get('serverMode'), 'openrouter');
    expect(Hive.box('settings').get('isCloudMode'), isFalse);
    expect(find.text('Enter your OpenRouter API key'), findsOneWidget);
    expect(find.textContaining('openrouter.ai'), findsWidgets);
    expect(find.textContaining('OpenRouter'), findsWidgets);
  });

  testWidgets('stored local mode is not shown and migrates to Cloud',
      (tester) async {
    Hive.box('settings').put('serverMode', 'local');
    Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    await pumpSettings(tester);

    expect(find.text('Local'), findsNothing);
    expect(find.text('Ollama Server Address'), findsNothing);
    expect(find.text('Search Local Network'), findsNothing);
    expect(find.text('Enter your Ollama Cloud API key'), findsOneWidget);
    expect(Hive.box('settings').get('serverMode'), 'cloud');
    expect(Hive.box('settings').get('isCloudMode'), isTrue);
  });
}
