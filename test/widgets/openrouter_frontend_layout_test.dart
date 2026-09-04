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
      '.dart_tool/test_hive_frontend_layout';
}

/// Frontend-design layout inspection for the OpenRouter settings surfaces.
///
/// Asserts the three-way server control fits phone widths without overflow
/// and that Cloud and OpenRouter key panels share the same form geometry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await Hive.initFlutter();
    await Hive.openBox('settings');
  });

  setUp(() async => Hive.box('settings').clear());

  Future<void> pumpPhone(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: true),
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5B8DEF),
              brightness: Brightness.dark,
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  List<FlutterErrorDetails> _captureOverflows(WidgetTester tester) {
    final overflows = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) {
        overflows.add(details);
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    return overflows;
  }

  testWidgets('three server segments fit a 320pt phone without overflow', (
    tester,
  ) async {
    final overflows = _captureOverflows(tester);

    await pumpPhone(
      tester,
      const ServerSettings(),
      size: const Size(320, 568),
    );

    final segmented = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(segmented.segments, hasLength(3));
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);

    final control = tester.getRect(find.byType(SegmentedButton<String>));
    expect(
      control.width,
      lessThanOrEqualTo(320 - 32),
      reason: 'segmented control must stay inside the 16px settings padding',
    );
    expect(overflows, isEmpty);
    expect(tester.takeException(), isNull);

    // iPhone SE content width is 288pt — icons drop so the labels fit.
    expect(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.byIcon(Icons.dns_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('iPhone 14 width keeps 18px mode icons like Themes', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const ServerSettings(),
      size: const Size(430, 932),
    );

    expect(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.byIcon(Icons.hub_outlined),
      ),
      findsOneWidget,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.byIcon(Icons.hub_outlined),
      ),
    );
    expect(icon.size, 18);
  });

  testWidgets('OpenRouter and Cloud key panels share field and button size', (
    tester,
  ) async {
    await pumpPhone(tester, const ServerSettings());

    await tester.tap(find.text('Cloud'));
    await tester.pump();
    final cloudField = tester.getSize(find.byType(TextField));
    final cloudButton =
        tester.getSize(find.widgetWithText(ElevatedButton, 'Connect'));

    await tester.tap(find.text('OpenRouter'));
    await tester.pump();
    final orField = tester.getSize(find.byType(TextField));
    final orButton =
        tester.getSize(find.widgetWithText(ElevatedButton, 'Connect'));

    expect(orField.width, closeTo(cloudField.width, 0.5));
    expect(orField.height, closeTo(cloudField.height, 0.5));
    expect(orButton.width, closeTo(cloudButton.width, 0.5));
    expect(orButton.height, closeTo(cloudButton.height, 0.5));
    expect(orButton.height, greaterThanOrEqualTo(40));
  });
}
