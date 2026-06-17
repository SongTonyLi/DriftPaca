import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:llamaseek/Utils/material_color_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_hive_gradient';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MaterialColorAdapter());
    }
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('grad_test');
  });

  test('defaults to first preset when nothing stored', () async {
    final box = await Hive.openBox('grad_test');
    expect(readGradientPair(box), kGradientPresets.first);
    await box.close();
  });

  test('round-trips an arbitrary custom color', () async {
    final box = await Hive.openBox('grad_test');
    const pair = GradientPair(Color(0xFF123456), Color(0xFF654321));
    writeGradientPair(box, pair);
    expect(readGradientPair(box), pair);
    await box.close();
  });

  test('migrates a legacy MaterialColor accent into c1', () async {
    final box = await Hive.openBox('grad_test');
    await box.put('color', Colors.blue); // legacy single-accent value
    final pair = readGradientPair(box);
    expect(pair.c1.value, Colors.blue.value);
    expect(pair.c2, kGradientPresets.first.c2);
    await box.close();
  });
}
