import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Providers/chat_provider.dart';

OllamaMessage _u(String c) => OllamaMessage(c, role: OllamaMessageRole.user);
OllamaMessage _a(String c) => OllamaMessage(c, role: OllamaMessageRole.assistant);

void main() {
  group('computeExchangeSpan', () {
    test('user anchor selects the user + its reply', () {
      final m = [_u('q1'), _a('a1'), _u('q2'), _a('a2')];
      final span = ChatProvider.computeExchangeSpan(m, m[0]);
      expect(span.start, 0);
      expect(span.end, 2);
    });

    test('assistant anchor selects the same pair', () {
      final m = [_u('q1'), _a('a1'), _u('q2'), _a('a2')];
      final span = ChatProvider.computeExchangeSpan(m, m[3]);
      expect(span.start, 2);
      expect(span.end, 4);
    });

    test('user with no reply yet selects only itself', () {
      final m = [_u('q1'), _a('a1'), _u('q2')];
      final span = ChatProvider.computeExchangeSpan(m, m[2]);
      expect(span.start, 2);
      expect(span.end, 3);
    });

    test('orphan assistant with no preceding user selects only itself', () {
      final m = [_a('a0'), _u('q1')];
      final span = ChatProvider.computeExchangeSpan(m, m[0]);
      expect(span.start, 0);
      expect(span.end, 1);
    });

    test('unknown anchor yields empty span', () {
      final m = [_u('q1'), _a('a1')];
      final span = ChatProvider.computeExchangeSpan(m, _u('not in list'));
      expect(span.end - span.start, 0);
    });
  });
}
