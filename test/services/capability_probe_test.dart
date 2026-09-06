import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Services/ollama_service.dart';

/// The capability probe sits on the critical path between pressing send and
/// a research run starting: `_streamOllamaMessage` awaits it to decide
/// whether the model can take native tools. Every probe is a round trip, and
/// `_showModel` waits 5s (10s remote) before giving up on one.
void main() {
  test('a server that reports no capabilities is probed once, not before '
      'every message', () async {
    var probes = 0;
    final service = OllamaService(client: MockClient((request) async {
      probes++;
      return http.Response('Not found', 404);
    }));
    addTearDown(service.dispose);

    expect(await service.getCapabilities('llama3.2'), isNull);
    expect(await service.getCapabilities('llama3.2'), isNull);
    expect(await service.getCapabilities('llama3.2'), isNull);

    expect(probes, 1,
        reason: 'null already means "assume capable", so re-asking can only '
            'stall research startup — it can never change the answer');
  });

  test('a successful probe is cached and answers later calls', () async {
    var probes = 0;
    final service = OllamaService(client: MockClient((request) async {
      probes++;
      return http.Response(
        jsonEncode({
          'capabilities': ['completion', 'tools'],
        }),
        200,
      );
    }));
    addTearDown(service.dispose);

    expect((await service.getCapabilities('llama3.2'))?.tools, isTrue);
    expect((await service.getCapabilities('llama3.2'))?.tools, isTrue);
    expect(probes, 1);
  });

  test('switching servers re-probes instead of inheriting the old answer',
      () async {
    final probed = <String>[];
    final service = OllamaService(client: MockClient((request) async {
      probed.add(request.url.host);
      return http.Response('Not found', 404);
    }));
    addTearDown(service.dispose);

    expect(await service.getCapabilities('llama3.2'), isNull);
    service.baseUrl = 'http://other-host:11434';
    expect(await service.getCapabilities('llama3.2'), isNull);

    expect(probed, ['localhost', 'other-host'],
        reason: 'a different server may well report capabilities this one '
            'could not');
  });
}
