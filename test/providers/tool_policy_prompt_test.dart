import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Providers/chat_provider.dart';

void main() {
  test('the research system prompt asks the answering model to cover every part of the question', () {
    // This string is live on every answering turn, including the final
    // one, so it is the only place completeness pressure can reach the
    // model that actually writes the answer. Three to five other surfaces
    // tell it to stop and answer now — one repeated per search round — and
    // before this nothing pushed the other way; the completeness gate's
    // "every part" wording lives in a separate, tool-less call the
    // answering model never sees. Pinning the phrases is the point: it
    // stops a future prompt edit from silently dropping the only
    // counter-pressure in the system.
    final prompt = toolPolicyInstruction().toLowerCase();

    expect(prompt, contains('each one'));
    expect(prompt, contains('could not be established'));
  });
}
