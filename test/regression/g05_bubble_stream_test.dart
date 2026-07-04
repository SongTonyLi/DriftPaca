import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_list_view.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

/// Collects the concatenated text of every [RichText]/[Text]/[EditableText]
/// currently in the tree, so tests can inspect what the typewriter reveal is
/// actually rendering on a given frame.
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(RichText).evaluate()) {
    final richText = element.widget as RichText;
    buffer.write(richText.text.toPlainText());
  }
  return buffer.toString();
}

/// True when [text] ends in (or contains at a boundary) an unpaired UTF-16
/// high surrogate — the corruption that flashes an emoji as a tofu box.
bool hasOrphanedSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // High surrogate must be immediately followed by a low surrogate.
      if (i + 1 >= text.length) return true;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      // Valid pair — skip the low surrogate half.
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // Lone low surrogate (not preceded by a high surrogate).
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Bug 1: streaming bubble shows first token without waiting', () {
    testWidgets('renders initial content on the first frame while streaming',
        (tester) async {
      final message = OllamaMessage(
        'Hello there, this is the first token batch.',
        role: OllamaMessageRole.assistant,
      );

      await tester.pumpWidget(
        buildTestApp(ChatBubble(message: message, isStreaming: true)),
      );
      // A single frame — no second token, no didUpdateWidget.
      await tester.pump();

      expect(renderedText(tester), contains('Hello there'),
          reason:
              'the first streaming build must reveal content seeded in initState');

      // Dispose the streaming widget so its ticker doesn't linger at teardown.
      await tester.pumpWidget(buildTestApp(const SizedBox.shrink()));
    });
  });

  group('Bug 2: reveal state survives index 0 -> 1 promotion', () {
    testWidgets('assistant bubble element is reused when a new message arrives',
        (tester) async {
      final assistant = OllamaMessage(
        'A streamed answer that was mid reveal.',
        role: OllamaMessageRole.assistant,
      );
      final messages = <OllamaMessage>[
        OllamaMessage('First question', role: OllamaMessageRole.user),
        assistant,
      ];

      await tester.pumpWidget(
        buildTestApp(
          SizedBox.expand(
            child: ChatListView(
              messages: messages,
              isAwaitingReply: false,
              isStreaming: true,
            ),
          ),
        ),
      );
      await tester.pump();

      Element assistantElement() {
        return find
            .byWidgetPredicate(
              (w) => w is ChatBubble && identical(w.message, assistant),
            )
            .evaluate()
            .single;
      }

      final before = assistantElement();

      // Stream ends, then the user sends a new message — the assistant bubble
      // shifts from reversed index 0 to index 1.
      messages.add(OllamaMessage('Second question', role: OllamaMessageRole.user));
      await tester.pumpWidget(
        buildTestApp(
          SizedBox.expand(
            child: ChatListView(
              messages: messages,
              isAwaitingReply: false,
              isStreaming: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final after = assistantElement();
      expect(identical(before, after), isTrue,
          reason:
              'the assistant bubble Element (and its reveal State) must be reused '
              'across the 0->1 promotion, not rebuilt from scratch');

      // Drain the reveal ticker and the resting-llama idle animation so no
      // timers remain pending at teardown.
      await tester.pumpAndSettle(const Duration(seconds: 13));
    });
  });

  group('Bug 3: typewriter never renders an orphaned surrogate', () {
    testWidgets('no frame emits a lone high surrogate while revealing emoji',
        (tester) async {
      // Emoji (surrogate pairs) interleaved with BMP text so the reveal cursor
      // repeatedly lands on surrogate boundaries.
      const full = 'a🦙b🎉c𝛼d🚀e🦙f🎉g𝛼h🚀i🦙j🎉k𝛼l🚀m';
      // Grow the message content token by token (as a stream would) so the
      // reveal cursor lags behind the target and must catch up through the
      // surrogate boundaries, rather than seeding the whole thing at once.
      final message = OllamaMessage(full.substring(0, 1),
          role: OllamaMessageRole.assistant);
      int target = 1;

      await tester.pumpWidget(
        buildTestApp(
          StatefulBuilder(
            builder: (context, setState) {
              return ChatBubble(message: message, isStreaming: true);
            },
          ),
        ),
      );

      // Drive the reveal frame by frame; on some frames append another code
      // unit to the message. Assert every frame is surrogate-safe.
      for (var i = 0; i < 160; i++) {
        if (i.isEven && target < full.length) {
          target++;
          message.content = full.substring(0, target);
          await tester.pumpWidget(
            buildTestApp(
              StatefulBuilder(
                builder: (context, setState) {
                  return ChatBubble(message: message, isStreaming: true);
                },
              ),
            ),
          );
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(hasOrphanedSurrogate(renderedText(tester)), isFalse,
            reason: 'frame $i rendered an orphaned surrogate half');
      }

      // Dispose the streaming widget so its ticker doesn't linger at teardown.
      await tester.pumpWidget(buildTestApp(const SizedBox.shrink()));
    });
  });

  group('Bug 4/5: preprocessing correctness is preserved', () {
    testWidgets('<br> renders and shared code-span skipping still applies',
        (tester) async {
      // `<br>` should force a break; a `$5` inside inline code must stay literal
      // (exercising the shared _codeSpanPattern skip path in preprocessing).
      final message = OllamaMessage(
        r'line one<br>line two and `cost is $5 here`',
        role: OllamaMessageRole.assistant,
      );

      await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
      await tester.pumpAndSettle();

      final text = renderedText(tester);
      expect(text, contains('line one'));
      expect(text, contains('line two'));
      expect(text, contains(r'cost is $5 here'),
          reason: 'inline code content must be left untouched by preprocessing');
    });
  });
}
