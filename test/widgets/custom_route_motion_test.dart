import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_route.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:provider/provider.dart';

class _RecordingObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is TransitionRoute<dynamic>) {
      pushed = route;
    }
  }
}

class _RouteChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  Future<List<OllamaModel>> fetchAvailableModels() async => [_model];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _model = OllamaModel(
  name: 'qwen3:8b',
  model: 'qwen3:8b',
  modifiedAt: DateTime(2024),
  size: 1,
  digest: 'digest',
  parameterSize: '8B',
  family: 'qwen',
  quantizationLevel: 'Q4_K_M',
  format: 'gguf',
  contextLength: 32768,
  capabilities: const ModelCapabilities(completion: true),
);

Widget _host({
  required _RecordingObserver observer,
  required bool disableAnimations,
}) {
  return ChangeNotifierProvider<ChatProvider>.value(
    value: _RouteChatProvider(),
    child: MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModelSelectWheel(context: context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('model route preserves its normal timing', (tester) async {
    final observer = _RecordingObserver();
    await tester.pumpWidget(
      _host(observer: observer, disableAnimations: false),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(
      observer.pushed!.transitionDuration,
      const Duration(milliseconds: 340),
    );
    expect(
      observer.pushed!.reverseTransitionDuration,
      const Duration(milliseconds: 240),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('model route has zero timing with reduced motion',
      (tester) async {
    final observer = _RecordingObserver();
    await tester.pumpWidget(
      _host(observer: observer, disableAnimations: true),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(observer.pushed!.transitionDuration, Duration.zero);
    expect(observer.pushed!.reverseTransitionDuration, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
