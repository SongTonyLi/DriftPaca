/// Shared test helpers for markdown/LaTeX rendering tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Future<List<FlutterErrorDetails>> pumpBubbleAndCollectErrors(
  WidgetTester tester,
  String content, {
  Size surfaceSize = const Size(400, 2000),
}) async {
  final originalOnError = FlutterError.onError;
  final errors = <FlutterErrorDetails>[];

  addTearDown(() {
    FlutterError.onError = originalOnError;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = surfaceSize;

  try {
    FlutterError.onError = (details) {
      errors.add(details);
    };

    final message = OllamaMessage(
      content,
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
    await tester.pumpAndSettle();
    return errors;
  } finally {
    FlutterError.onError = originalOnError;
  }
}

List<FlutterErrorDetails> overflowErrors(Iterable<FlutterErrorDetails> errors) {
  return errors.where((d) => d.exceptionAsString().contains('overflowed by')).toList();
}

List<FlutterErrorDetails> nonOverflowErrors(Iterable<FlutterErrorDetails> errors) {
  return errors.where((d) => !d.exceptionAsString().contains('overflowed by')).toList();
}
