import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/brand_logos.dart';

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
      expect(brandForFamilyName('llama3.2').isFallback, isTrue);
      expect(brandForFamilyName('phi4').isFallback, isTrue);
      expect(brandForFamilyName('').isFallback, isTrue);
    });
  });
}
