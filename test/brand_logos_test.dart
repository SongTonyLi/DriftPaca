import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Models/ollama_model.dart';

void main() {
  group('brandForFamilyName', () {
    test('maps known families/names to the right brand', () {
      expect(brandForFamilyName('qwen').key, 'qwen');
      expect(brandForFamilyName('qwen2.5-coder').key, 'qwen');
      expect(brandForFamilyName('gemma3').key, 'gemma');
      expect(brandForFamilyName('deepseek-r1').key, 'deepseek');
      expect(brandForFamilyName('mixtral').key, 'mistral');
      expect(brandForFamilyName('codestral').key, 'mistral');
      expect(brandForFamilyName('chatglm').key, 'chatglm');
      expect(brandForFamilyName('glm-4.6').key, 'chatglm');
      expect(brandForFamilyName('kimi-k2').key, 'kimi');
      expect(brandForFamilyName('nemotron').key, 'nvidia');
      expect(brandForFamilyName('minimax-m2').key, 'minimax');
      expect(brandForFamilyName('essential-web').key, 'essentialai');
      expect(brandForFamilyName('gemini-2.5-flash').key, 'gemini');
      expect(brandForFamilyName('gpt-oss').key, 'openai');
      expect(brandForFamilyName('gpt-oss:20b').key, 'openai');
    });

    test('the OpenAI mark is monochrome (tinted to the foreground)', () {
      expect(brandForFamilyName('gpt-oss:20b').tinted, isTrue);
      expect(brandForFamilyName('qwen3:8b').tinted, isFalse);
    });

    test('gemma and gemini do not collide', () {
      expect(brandForFamilyName('gemma2').key, 'gemma');
      expect(brandForFamilyName('gemini').key, 'gemini');
    });

    test('unknown families fall back to the Ollama mark', () {
      expect(brandForFamilyName('phi4').isFallback, isTrue);
      expect(brandForFamilyName('').isFallback, isTrue);
    });

    test('llama family names use the Llama mark', () {
      expect(brandForFamilyName('llama3.2').key, 'llama');
    });

    test('OpenRouter provider/model ids resolve to the right brand', () {
      expect(brandForFamilyName('openai openai/gpt-4o').key, 'openai');
      expect(brandForFamilyName('anthropic anthropic/claude-sonnet-4').key, 'anthropic');
      expect(brandForFamilyName('meta-llama meta-llama/llama-3.3-70b-instruct').key, 'llama');
      expect(brandForFamilyName('google google/gemini-2.5-flash').key, 'gemini');
      expect(brandForFamilyName('google google/gemma-3-27b-it').key, 'gemma');
      expect(brandForFamilyName('x-ai x-ai/grok-4').key, 'grok');
      expect(brandForFamilyName('qwen qwen/qwen3-32b').key, 'qwen');
      expect(brandForFamilyName('deepseek deepseek/deepseek-chat').key, 'deepseek');
      expect(brandForFamilyName('mistralai mistralai/mistral-large').key, 'mistral');
    });

    test('unrecognised OpenRouter ids use the OpenRouter mark, not Ollama', () {
      final brand = brandForModel(OllamaModel(
        name: 'acme/mystery-model',
        model: 'acme/mystery-model',
        modifiedAt: DateTime(2026, 1, 1),
        size: 0,
        digest: 'acme/mystery-model',
        parameterSize: '',
        family: 'acme',
        format: 'openrouter',
      ));
      expect(brand.key, 'openrouter');
      expect(brand.isFallback, isFalse);
    });
  });
}
