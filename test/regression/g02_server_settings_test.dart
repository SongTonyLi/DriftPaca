import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/settings_page/subwidgets/server_settings.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '.dart_tool/test_hive_g02_server_settings';
}

/// A completer the current test controls to decide when the pending
/// connection request resolves.
Completer<void>? _requestGate;

/// Routes every connection check through a client that resolves only once
/// [_requestGate] completes, so a request can be left in flight while the
/// widget is disposed and then resolved afterwards.
class _GatedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _GatedHttpClient();
}

class _GatedHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    await _requestGate!.future;
    return _GatedHttpClientRequest();
  }

  @override
  bool get autoUncompress => true;

  @override
  set autoUncompress(bool value) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedHttpClientRequest implements HttpClientRequest {
  @override
  HttpHeaders get headers => _GatedHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => throw const SocketException('gated');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedHttpHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await Hive.initFlutter();
    await Hive.openBox('settings');
    HttpOverrides.global = _GatedHttpOverrides();
  });

  setUp(() async => Hive.box('settings').clear());

  testWidgets(
    'disposing while a connection check is in flight does not setState after dispose',
    (tester) async {
      _requestGate = Completer<void>();

      Hive.box('settings').put('serverMode', 'local');
      Hive.box('settings').put('serverAddress', 'http://localhost:11434');

      // Mounting triggers the initial connection check, whose request stays
      // parked on the gate.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ServerSettings())),
      ));
      await tester.pump();

      // Navigate away while the request is still in flight, disposing the State.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ));
      await tester.pump();

      // Resolve the request now that the State is defunct. The connection
      // method's finally block runs on the disposed State; without the mounted
      // guard this reports 'setState() called after dispose()' and fails the
      // test.
      _requestGate!.complete();
      await tester.pumpAndSettle();
    },
  );
}
