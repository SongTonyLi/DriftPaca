import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Widgets/memory_status_indicator.dart';

class _FakeDb extends DatabaseService {
  @override
  Future<List<MemoryTopic>> getAllTopics() async => [];

  @override
  Future<List<EphemeralContext>> getAllEphemeralContexts() async => [];
}

class _FakeMemoryService extends MemoryService {
  _FakeMemoryService() : super(db: _FakeDb());

  bool _enabled = true;
  bool _updating = false;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isUpdating => _updating;

  void setState({bool? enabled, bool? updating}) {
    if (enabled != null) _enabled = enabled;
    if (updating != null) _updating = updating;
    notifyListeners();
  }
}

Widget _host(
  _FakeMemoryService service, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ChangeNotifierProvider<MemoryService>.value(
        value: service,
        child: const Scaffold(body: MemoryStatusIndicator()),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('g07_mem_test').path);
    await Hive.openBox('settings');
  });

  setUp(() {
    Hive.box('settings').put('cloudApiKey', 'test-key');
  });

  testWidgets('finishing an update does not throw and stops animating',
      (tester) async {
    final service = _FakeMemoryService();
    await tester.pumpWidget(_host(service));

    service.setState(updating: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'an in-progress update should pulse the indicator');

    service.setState(updating: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'a finished update should settle the indicator');
  });

  testWidgets('rebuild while idle does not throw during build', (tester) async {
    final service = _FakeMemoryService();
    await tester.pumpWidget(_host(service));

    service.setState(updating: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when memory is disabled', (tester) async {
    final service = _FakeMemoryService()..setState(enabled: false);
    await tester.pumpWidget(_host(service));
    await tester.pump();

    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the indicator while updating', (tester) async {
    final service = _FakeMemoryService();
    await tester.pumpWidget(_host(service));

    service.setState(updating: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows updating state without pulsing',
      (tester) async {
    final service = _FakeMemoryService()..setState(updating: true);
    await tester.pumpWidget(_host(service, disableAnimations: true));
    await tester.pump();

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
