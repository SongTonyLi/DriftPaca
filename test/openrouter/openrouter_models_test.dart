import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Services/openrouter_codec.dart';

void main() {
  group('OpenRouterModelsResponse', () {
    test('maps chat models to OllamaModel with provider family and capabilities',
        () {
      final models = OpenRouterCodec.parseModels({
        'data': [
          {
            'id': 'openai/gpt-4o',
            'name': 'OpenAI: GPT-4o',
            'created': 1715367049,
            'description': 'Fast multimodal flagship.',
            'context_length': 128000,
            'architecture': {
              'modality': 'text+image->text',
              'input_modalities': ['text', 'image'],
              'output_modalities': ['text'],
            },
            'supported_parameters': ['tools', 'temperature'],
          },
          {
            'id': 'anthropic/claude-sonnet-4',
            'name': 'Anthropic: Claude Sonnet 4',
            'created': 1740000000,
            'description': 'Balanced Claude.',
            'context_length': 200000,
            'architecture': {
              'input_modalities': ['text', 'image'],
              'output_modalities': ['text'],
            },
            'supported_parameters': ['tools', 'reasoning'],
          },
          {
            'id': 'openai/text-embedding-3-small',
            'name': 'OpenAI: Text Embedding 3 Small',
            'architecture': {
              'input_modalities': ['text'],
              'output_modalities': ['embeddings'],
            },
          },
        ],
      });

      expect(models, hasLength(2),
          reason: 'embedding-only models must be filtered out');

      final gpt = models.firstWhere((m) => m.name == 'openai/gpt-4o');
      expect(gpt.family, 'openai');
      expect(gpt.description, 'Fast multimodal flagship.');
      expect(gpt.contextLength, 128000);
      expect(gpt.format, 'openrouter');
      expect(gpt.capabilities?.vision, isTrue);
      expect(gpt.capabilities?.tools, isTrue);
      expect(gpt.capabilities?.completion, isTrue);

      final claude =
          models.firstWhere((m) => m.name == 'anthropic/claude-sonnet-4');
      expect(claude.family, 'anthropic');
      expect(claude.capabilities?.thinking, isTrue);
      expect(claude.capabilities?.vision, isTrue);
    });

    test('extracts a parameter-size hint from the model id when present', () {
      final models = OpenRouterCodec.parseModels({
        'data': [
          {
            'id': 'meta-llama/llama-3.3-70b-instruct',
            'name': 'Meta: Llama 3.3 70B Instruct',
            'architecture': {
              'input_modalities': ['text'],
              'output_modalities': ['text'],
            },
          },
        ],
      });

      expect(models.single.parameterSize, '70B');
      expect(models.single.family, 'meta-llama');
    });
  });
}
