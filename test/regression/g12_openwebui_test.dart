import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

/// Mirrors the decision made in [OpenWebuiPage]'s shouldOverrideUrlLoading:
/// same-host navigation stays in the webview, external hosts open in the
/// system browser via url_launcher before the navigation is cancelled.
Future<NavigationActionPolicy> decide(WebUri? url, String openwebuiUrl) async {
  if (url == null) return NavigationActionPolicy.CANCEL;

  final openwebuiHost = Uri.parse(openwebuiUrl).host;

  if (url.host == openwebuiHost || url.host.isEmpty) {
    return NavigationActionPolicy.ALLOW;
  }

  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
  return NavigationActionPolicy.CANCEL;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingUrlLauncher launcher;

  setUp(() {
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  test('external link is launched in the system browser before cancel',
      () async {
    final policy = await decide(
      WebUri('https://docs.example.com/guide'),
      'http://localhost:3000',
    );

    expect(policy, NavigationActionPolicy.CANCEL);
    expect(launcher.launched, ['https://docs.example.com/guide']);
  });

  test('same-host navigation stays in the webview and is not launched',
      () async {
    final policy = await decide(
      WebUri('http://localhost:3000/chat/abc'),
      'http://localhost:3000',
    );

    expect(policy, NavigationActionPolicy.ALLOW);
    expect(launcher.launched, isEmpty);
  });
}
