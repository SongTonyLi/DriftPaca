import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('bubble markdown paragraphs are justified', (tester) async {
    final message = OllamaMessage(
      'This is a sufficiently long message that will wrap onto multiple '
      'lines inside the chat bubble so that justification has a visible effect.',
      role: OllamaMessageRole.user,
    );

    await tester.pumpWidget(_host(ChatBubble(message: message)));
    await tester.pumpAndSettle();

    final markdown = tester.widgetList<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown, isNotEmpty);
    expect(markdown.first.styleSheet?.textAlign, WrapAlignment.spaceBetween);
  });
}
