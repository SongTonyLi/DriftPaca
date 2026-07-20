import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_configure_arguments.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Widgets/chat_configure_bottom_sheet.dart';
import 'package:provider/provider.dart';

class _ConfigureChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  OllamaChat? get currentChat => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({required bool disableAnimations}) {
  return ChangeNotifierProvider<ChatProvider>.value(
    value: _ConfigureChatProvider(),
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: ChatConfigureBottomSheet(
              arguments: ChatConfigureArguments.defaultArguments,
            ),
          ),
        ),
      ),
    ),
  );
}

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _showAdvanced(WidgetTester tester) {
  final content = find.byWidgetPredicate(
    (widget) =>
        widget.runtimeType.toString() == '_ChatConfigureBottomSheetContent',
  );
  final state = tester.state(content) as dynamic;
  state.debugToggleAdvancedConfigurations();
}

Future<void> _pumpAdvanced(WidgetTester tester) async {
  await tester.pump();
}

void main() {
  testWidgets('advanced settings expand smoothly after layout',
      (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_host(disableAnimations: false));
    _showAdvanced(tester);
    await _pumpAdvanced(tester);

    expect(find.byType(AnimatedSize), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Max Tokens'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced settings settle immediately with reduced motion',
      (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_host(disableAnimations: true));
    _showAdvanced(tester);
    await _pumpAdvanced(tester);

    expect(find.text('Max Tokens'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
