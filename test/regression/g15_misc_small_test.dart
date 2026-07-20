import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_welcome.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/welcome_scaffold.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:llamaseek/Utils/http_error_formatter.dart';
import 'package:llamaseek/Utils/material_color_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_hive_g15';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug 1: HTTP error body is capped and HTML pages are dropped', () {
    test('short plain-text bodies are still appended verbatim', () {
      final message = HttpErrorFormatter.formatHttpError(500, body: 'model not loaded');
      expect(message, contains('model not loaded'));
    });

    test('an oversized proxy body is truncated well below its original length', () {
      final huge = 'x' * 50000;
      final message = HttpErrorFormatter.formatHttpError(502, body: huge);
      expect(message.length, lessThan(700));
      expect(message, contains('…'));
    });

    test('a full HTML error page is not embedded in the message', () {
      const html =
          '<!DOCTYPE html><html><head><title>502 Bad Gateway</title></head>'
          '<body><center><h1>502 Bad Gateway</h1></center></body></html>';
      final message = HttpErrorFormatter.formatHttpError(502, body: html);
      expect(message, isNot(contains('<html')));
      expect(message, isNot(contains('<body')));
      expect(message, contains('(HTTP 502)'));
    });
  });

  group('Bug 3: gradient persistence stays byte-compatible without Color.value', () {
    setUpAll(() async {
      PathProviderPlatform.instance = _FakePathProvider();
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(MaterialColorAdapter());
      }
    });

    setUp(() async {
      await Hive.deleteBoxFromDisk('grad_g15_test');
    });

    test('writes the exact ARGB32 ints and round-trips a custom pair', () async {
      final box = await Hive.openBox('grad_g15_test');
      const pair = GradientPair(Color(0xFF123456), Color(0xFF654321));
      await writeGradientPair(box, pair);

      expect(box.get(kBgColor1Key), 0xFF123456);
      expect(box.get(kBgColor2Key), 0xFF654321);
      expect(readGradientPair(box), pair);
      await box.close();
    });
  });

  group('Bug 4: server-not-configured warning icon uses a contrasting theme color', () {
    Widget host(ThemeData theme) => MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ChatWelcome(
                  showingState: CrossFadeState.showSecond,
                  secondChildScale: 1.0,
                ),
              ),
            ),
          ),
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => const SizedBox.shrink(),
            settings: settings,
          ),
        );

    testWidgets('warning icon is not the near-invisible amber in light mode', (tester) async {
      final theme = ThemeData(brightness: Brightness.light);
      await tester.pumpWidget(host(theme));
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      expect(icon.color, isNot(Colors.amber));
      expect(icon.color, theme.colorScheme.error);
    });
  });

  group('Bug 5: WelcomeScaffold entrance does not leak per-frame CurvedAnimation listeners', () {
    Widget host() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: WelcomeScaffold(
                eyebrow: 'WELCOME',
                title: 'Start a conversation',
                ctaLabel: 'Select a model to start',
                accent: Colors.blue,
                onCta: () {},
              ),
            ),
          ),
        );

    testWidgets('renders across the entrance and settles to a static screen', (tester) async {
      await tester.pumpWidget(host());
      // Pump through the mid-animation frames that used to spawn orphaned listeners.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'entrance is one-shot; idle welcome must not keep animating');
      expect(find.text('Start a conversation'), findsOneWidget);
    });
  });
}
