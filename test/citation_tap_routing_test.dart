/// Regression: tapping the favicon that replaces an inline citation link
/// must launch its URL, but tapping the surrounding prose (or the trailing
/// whitespace on a line that ends in a favicon) must NOT.
///
/// flutter_markdown attaches the link's TapGestureRecognizer to the prose
/// spans that FOLLOW the link. Because TextSpan is a HitTestTarget, that
/// prose becomes tappable and would open the favicon's URL — the "tap text,
/// logo opens" misclick. These tests pin the intended behaviour.
///
// url_launcher_platform_interface / plugin_platform_interface are pulled in
// transitively by url_launcher; importing them directly is the standard way
// to mock URL launches in a test.
// ignore_for_file: depend_on_referenced_packages
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

Finder _faviconFinder() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_LinkFavicon',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = original;
  });

  Future<void> pumpBubble(WidgetTester tester, String content) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 2000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChatBubble(
            message: OllamaMessage(content, role: OllamaMessageRole.assistant),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the favicon launches its URL (positive control)',
      (tester) async {
    await pumpBubble(tester, 'See [¹](http://example.com) for details.');

    expect(_faviconFinder(), findsOneWidget);
    await tester.tap(_faviconFinder());
    await tester.pumpAndSettle();

    expect(launcher.launched, contains('http://example.com'),
        reason: 'Tapping directly on the favicon should launch its URL.');
  });

  testWidgets('tapping prose that FOLLOWS a favicon does not launch',
      (tester) async {
    // The favicon ends line 1; "and the rest ..." is the prose after it, the
    // span that inherits the leaked recognizer.
    await pumpBubble(
      tester,
      'Intro [¹](http://one.com) and the rest of this sentence is plain prose '
      'that should never open a link no matter where you tap it.',
    );

    expect(_faviconFinder(), findsOneWidget);
    final faviconRect = tester.getRect(_faviconFinder());

    // A point well to the right of the favicon, on the trailing whitespace of
    // its line (favicon sits at the end of line 1; everything to its right is
    // empty space on that line).
    await tester.tapAt(Offset(faviconRect.right + 40, faviconRect.center.dy));
    await tester.pumpAndSettle();

    expect(launcher.launched, isEmpty,
        reason: 'Trailing space after a line-ending favicon must not launch. '
            'faviconRect=$faviconRect');
  });

  testWidgets('grid sweep: only favicon boxes are tappable, not prose',
      (tester) async {
    const content =
        'According to recent studies the global temperature has risen by '
        '1.1 degrees since pre-industrial times [¹](http://one.com). This is '
        'consistent with projections [²](http://two.com), which predict '
        'further increases of several degrees by 2100 [³](http://three.com).';
    await pumpBubble(tester, content);

    expect(_faviconFinder(), findsNWidgets(3));

    final faviconRects = <Rect>[];
    for (final e in _faviconFinder().evaluate()) {
      faviconRects.add(tester.getRect(find.byWidget(e.widget)));
    }
    final bounds = faviconRects.reduce((a, b) => a.expandToInclude(b));

    final misfires = <String>[];
    for (var dy = bounds.top; dy <= bounds.bottom; dy += 4) {
      for (var dx = 16.0; dx <= 384; dx += 6) {
        final p = Offset(dx, dy);
        // Skip taps that land on (or right at the edge of) a favicon.
        if (faviconRects.any((r) => r.inflate(1).contains(p))) continue;
        final before = launcher.launched.length;
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 1));
        if (launcher.launched.length != before) {
          misfires.add('$p -> ${launcher.launched.last}');
        }
      }
    }
    await tester.pumpAndSettle();

    expect(misfires, isEmpty,
        reason: 'These prose taps wrongly launched a URL:\n'
            '${misfires.join('\n')}\nFavicon rects: $faviconRects');
  });
}
