import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_message.dart';

/// Most earlier turns the goal call is shown, and the most of each.
///
/// The derivation is a framing call with a short budget (see
/// `ChatProvider.goalDerivationBudget`), and its job is to read ONE
/// message. The turns before it are there to say what "it", "that one" or
/// a bare surname refers to and which reading of an ambiguous word the
/// user has already settled — a handful of recent exchanges, clipped,
/// carries that. A long answer sent whole would cost the call its budget
/// on a reasoning model and hand it far more text to drift into than the
/// message it is briefing.
const maxGoalContextMessages = 8;
const maxGoalContextCharsPerMessage = 600;

/// The turns before the message being briefed, as the goal call should see
/// them: user and assistant only, the ones a conversation summary does not
/// already cover, the most recent [maxGoalContextMessages] of those, each
/// clipped to [maxGoalContextCharsPerMessage].
///
/// [history] is the chat as sent, whose LAST user message is the one being
/// briefed; everything from it onward is excluded, since the message
/// itself travels separately (see [goalDerivationMessage]).
List<OllamaMessage> goalContextMessages(
  List<OllamaMessage> history, {
  ConversationMemory? conversationMemory,
}) {
  var lastUser = -1;
  for (var i = history.length - 1; i >= 0; i--) {
    if (history[i].role == OllamaMessageRole.user) {
      lastUser = i;
      break;
    }
  }
  if (lastUser <= 0) return const [];
  // The summary stands in for the turns it covers, exactly as the answering
  // turn's window does (see OllamaService.prepareMessagesWithSystemPrompt).
  var start = 0;
  final covered = conversationMemory?.summarizedMessageCount ?? 0;
  if (conversationMemory != null &&
      !conversationMemory.isEmpty &&
      covered > 0 &&
      covered < lastUser) {
    start = covered;
  }
  final prior = <OllamaMessage>[
    for (final m in history.sublist(start, lastUser))
      if ((m.role == OllamaMessageRole.user ||
              m.role == OllamaMessageRole.assistant) &&
          m.content.trim().isNotEmpty)
        m
  ];
  return prior.length > maxGoalContextMessages
      ? prior.sublist(prior.length - maxGoalContextMessages)
      : prior;
}

/// Everything the goal call is shown besides the message itself, rendered
/// as one block; empty when there is nothing to show. Three sources, each
/// labelled as context rather than as the question, so the derivation
/// prompt can tell the model in one sentence what they are for:
///
/// - the earlier turns ([goalContextMessages]), which is where "the second
///   one" and "his successor" get their referents;
/// - the conversation summary, which carries the same for turns the window
///   no longer holds — only when it covers turns the window omits, since
///   otherwise it repeats them;
/// - what is remembered about the user (the profile and whatever the
///   retrieval pass judged relevant to these turns), which is where "near
///   me" and "my model" get theirs.
///
/// None of it is the question. The message being briefed is appended by
/// [goalDerivationMessage] under its own label, last, so the model is
/// never left to guess which line it is restating.
String renderGoalDerivationContext({
  required List<OllamaMessage> history,
  ConversationMemory? conversationMemory,
  AgentMemory? profile,
  String relevantContext = '',
}) {
  final sections = <String>[];

  final turns = goalContextMessages(history, conversationMemory: conversationMemory);
  final summaryStandsIn = conversationMemory != null &&
      !conversationMemory.isEmpty &&
      conversationMemory.summarizedMessageCount > 0;
  if (summaryStandsIn) {
    final block = conversationMemory.toPromptBlock();
    if (block.isNotEmpty) {
      sections.add('Summary of the conversation before that:\n$block');
    }
  }
  if (turns.isNotEmpty) {
    final buffer = StringBuffer('Earlier turns of this conversation:\n');
    for (final m in turns) {
      final speaker = m.role == OllamaMessageRole.user ? 'User' : 'Assistant';
      buffer.writeln('$speaker: ${_clip(m.content)}');
    }
    sections.add(buffer.toString().trimRight());
  }

  final remembered = <String>[];
  final profileBlock = profile?.toPromptBlock() ?? '';
  if (profileBlock.isNotEmpty) remembered.add(profileBlock);
  if (relevantContext.trim().isNotEmpty) remembered.add(relevantContext.trim());
  if (remembered.isNotEmpty) {
    sections.add('What is remembered about the user:\n${remembered.join('\n')}');
  }

  // Summary first, then the turns it precedes, then the standing notes:
  // chronological where the sections are, so the block reads as a
  // transcript with its preface rather than a transcript interrupted.
  return sections.join('\n\n');
}

/// The user turn of the goal call: the message alone when there is no
/// context, exactly as before context existed — a bare question is the
/// shape the derivation prompt describes and the shape every test of the
/// parser was written against — or the context block followed by the
/// message under a label that names it as the thing being briefed.
String goalDerivationMessage(String userQuestion, String context) {
  if (context.trim().isEmpty) return userQuestion;
  return '$context\n\n'
      'The message to turn into a brief (this is the question; everything '
      'above is context):\n$userQuestion';
}

String _clip(String content) {
  final flat = content.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
  if (flat.length <= maxGoalContextCharsPerMessage) return flat;
  return '${flat.substring(0, maxGoalContextCharsPerMessage).trimRight()}…';
}
