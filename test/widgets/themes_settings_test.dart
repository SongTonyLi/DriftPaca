import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Pages/settings_page/subwidgets/themes_settings.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_hive_themes';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await Hive.initFlutter();
    await Hive.openBox('settings');
  });

  setUp(() async => Hive.box('settings').clear());

  testWidgets('tapping a preset swatch writes that pair', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ThemesSettings())),
    ));
    await tester.pumpAndSettle();

    final swatch = find.byKey(const ValueKey('gradient-preset-1'));
    expect(swatch, findsOneWidget);
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    expect(readGradientPair(Hive.box('settings')), kGradientPresets[1]);
  });
}
