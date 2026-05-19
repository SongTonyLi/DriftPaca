import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Extensions/markdown_stylesheet_extension.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_request_state.dart';
import 'package:llamaseek/Widgets/ollama_bottom_sheet_header.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ServerSettings extends StatefulWidget {
  final bool autoFocusServerAddress;

  const ServerSettings({super.key, this.autoFocusServerAddress = false});

  @override
  State<ServerSettings> createState() => _ServerSettingsState();
}

class _ServerSettingsState extends State<ServerSettings> {
  final _settingsBox = Hive.box('settings');

  final _serverAddressController = TextEditingController();
  final _apiKeyController = TextEditingController();

  OllamaRequestState _requestState = OllamaRequestState.uninitialized;
  OllamaRequestState _cloudRequestState = OllamaRequestState.uninitialized;
  get _isLoading => _requestState == OllamaRequestState.loading;
  get _isCloudLoading => _cloudRequestState == OllamaRequestState.loading;

  String? _serverAddressErrorText;
  String? _cloudErrorText;
  bool _obscureApiKey = true;

  List<String> _cloudModels = [];
  bool _isLoadingModels = false;

  String get _serverMode => _settingsBox.get('serverMode', defaultValue: 'local');

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  _initialize() {
    final serverAddress = _settingsBox.get('serverAddress');
    final cloudApiKey = _settingsBox.get('cloudApiKey');

    if (serverAddress != null) {
      _serverAddressController.text = serverAddress;
      if (_serverMode == 'local') {
        _handleConnectButton();
      }
    }

    if (cloudApiKey != null) {
      _apiKeyController.text = cloudApiKey;
      if (_serverMode == 'cloud') {
        _handleCloudConnectButton();
      }
    }

  }

  @override
  void dispose() {
    _serverAddressController.dispose();
    _apiKeyController.dispose();

    super.dispose();
  }

  void _setServerMode(String value) {
    _settingsBox.put('serverMode', value);
    // Backward compat: keep isCloudMode for existing code that reads it
    _settingsBox.put('isCloudMode', value == 'cloud');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'local',
                label: Text('Local'),
                icon: Icon(Icons.dns_outlined),
              ),
              ButtonSegment(
                value: 'cloud',
                label: Text('Cloud'),
                icon: Icon(Icons.cloud_outlined),
              ),
            ],
            selected: {_serverMode == 'openwebui' ? 'local' : _serverMode},
            onSelectionChanged: (selection) {
              _setServerMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_serverMode == 'cloud')
          _buildCloudSettings(context)
        else
          _buildLocalSettings(context),
        const SizedBox(height: 16),
        Text('Memory Model', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildMemoryModelSelector(context),
      ],
    );
  }

  Widget _buildLocalSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          autofocus: widget.autoFocusServerAddress,
          controller: _serverAddressController,
          keyboardType: TextInputType.url,
          onChanged: (_) {
            setState(() {
              _serverAddressErrorText = null;
              _requestState = OllamaRequestState.uninitialized;
            });
          },
          decoration: InputDecoration(
            labelText: 'Ollama Server Address',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            errorText: _serverAddressErrorText,
            suffixIcon: IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: () => _showOllamaInfoBottomSheet(context),
            ),
          ),
          onTapOutside: (PointerDownEvent event) {
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: (Platform.isAndroid || Platform.isIOS)
                ? WrapAlignment.spaceEvenly
                : WrapAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: _isLoading ? null : _handleSearchLocalNetwork,
                child: const Text('Search Local Network'),
              ),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleConnectButton,
                child: _ConnectionStatusIndicator(
                  color: _connectionStatusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloudSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: _obscureApiKey,
          onChanged: (_) {
            setState(() {
              _cloudErrorText = null;
              _cloudRequestState = OllamaRequestState.uninitialized;
            });
          },
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'Enter your Ollama Cloud API key',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            errorText: _cloudErrorText,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureApiKey ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscureApiKey = !_obscureApiKey;
                });
              },
            ),
          ),
          onTapOutside: (PointerDownEvent event) {
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Get your API key from ollama.com/settings',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                _isCloudLoading || _apiKeyController.text.isEmpty ? null : _handleCloudConnectButton,
            child: _ConnectionStatusIndicator(
              color: _cloudConnectionStatusColor,
            ),
          ),
        ),
      ],
    );
  }

  Color get _connectionStatusColor {
    switch (_requestState) {
      case OllamaRequestState.error:
        return Colors.red;
      case OllamaRequestState.loading:
        return Colors.orange;
      case OllamaRequestState.success:
        return Colors.green;
      case OllamaRequestState.uninitialized:
        return Colors.grey;
    }
  }

  Color get _cloudConnectionStatusColor {
    switch (_cloudRequestState) {
      case OllamaRequestState.error:
        return Colors.red;
      case OllamaRequestState.loading:
        return Colors.orange;
      case OllamaRequestState.success:
        return Colors.green;
      case OllamaRequestState.uninitialized:
        return Colors.grey;
    }
  }

  _handleCloudConnectButton() async {
    setState(() {
      _cloudErrorText = null;
      _cloudRequestState = OllamaRequestState.loading;
    });

    try {
      final apiKey = _apiKeyController.text.trim();
      if (apiKey.isEmpty) {
        throw OllamaException('Please enter an API key.');
      }

      final url = Uri.parse('https://ollama.com/api/tags');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }).timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        _cloudRequestState = OllamaRequestState.success;
        _settingsBox.put('cloudApiKey', apiKey);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _cloudErrorText = 'Invalid API key.';
        _cloudRequestState = OllamaRequestState.error;
      } else {
        _cloudErrorText = 'Connection failed (${response.statusCode}).';
        _cloudRequestState = OllamaRequestState.error;
      }
    } on OllamaException catch (error) {
      _cloudErrorText = error.message;
      _cloudRequestState = OllamaRequestState.error;
    } catch (_) {
      _cloudErrorText = 'Could not connect to Ollama Cloud.';
      _cloudRequestState = OllamaRequestState.error;
    } finally {
      setState(() {});
    }
  }

  _handleConnectButton() async {
    setState(() {
      _serverAddressErrorText = null;
      _requestState = OllamaRequestState.loading;
    });

    try {
      // Validate the server address.
      final newAddress = _validateServerAddress(_serverAddressController.text);
      // Establish a connection to the server.
      final result = await _establishServerConnection(Uri.parse(newAddress));

      if (!mounted) return;

      _requestState = result.$1;
      _saveServerAddressWith(result);
    } on OllamaException catch (error) {
      _serverAddressErrorText = error.message;
      _requestState = OllamaRequestState.error;
    } catch (_) {
      _serverAddressErrorText =
          'Invalid URL format. Use: http(s)://<host>:<port>';
      _requestState = OllamaRequestState.error;
    } finally {
      setState(() {});
    }
  }

  void _saveServerAddressWith((OllamaRequestState, Uri) result) {
    final state = result.$1;
    final newAddress = result.$2.toString();

    final currentAddress = _settingsBox.get('serverAddress');
    if (state == OllamaRequestState.success && newAddress != currentAddress) {
      _settingsBox.put('serverAddress', newAddress);
    }
  }

  /// Establishes a connection to the Ollama server.
  ///
  /// Returns a tuple of the request state and the given server address.
  static Future<(OllamaRequestState, Uri)> _establishServerConnection(
    Uri serverAddress,
  ) async {
    try {
      final response =
          await http.get(serverAddress).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        return (OllamaRequestState.success, serverAddress);
      } else {
        return (OllamaRequestState.error, serverAddress);
      }
    } catch (e) {
      return (OllamaRequestState.error, serverAddress);
    }
  }

  String _validateServerAddress(String address) {
    if (address.isEmpty) {
      throw OllamaException('Please enter a server address.');
    }

    final url = Uri.parse(address);

    if (url.scheme.isEmpty) {
      throw OllamaException(
        'Please include the scheme. e.g. http://localhost:11434',
      );
    }

    // If user don't include the scheme and just enter host and port like 'localhost:11434'.
    // The parser will consider the host as the scheme, so host will be empty. But actually the scheme is empty.
    if (url.scheme != 'http' && url.scheme != 'https' && url.host.isEmpty) {
      throw OllamaException(
        'Please include the scheme. e.g. http://localhost:11434',
      );
    }

    if (url.host.isEmpty) {
      throw OllamaException(
        'Please include the host. e.g. http://localhost:11434',
      );
    }

    if (url.scheme != 'http' && url.scheme != 'https') {
      throw OllamaException(
        'Invalid scheme. Only http and https are supported.',
      );
    }

    final String formattedAddress =
        "${url.scheme}://${url.host}${url.hasPort ? ":${url.port}" : ""}${url.path}";
    return formattedAddress;
  }

  Widget _buildMemoryModelSelector(BuildContext context) {
    final currentModel = _settingsBox.get('memoryModel', defaultValue: MemoryConstants.defaultModel) as String;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _cloudModels.contains(currentModel) || _cloudModels.isEmpty
                    ? currentModel
                    : null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'Model used for memory summarization (via Ollama Cloud)',
                ),
                hint: Text(currentModel),
                items: [
                  if (!_cloudModels.contains(currentModel))
                    DropdownMenuItem(value: currentModel, child: Text(currentModel)),
                  for (final model in _cloudModels)
                    DropdownMenuItem(value: model, child: Text(model)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _settingsBox.put('memoryModel', value);
                    setState(() {});
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isLoadingModels ? null : _fetchCloudModels,
              icon: _isLoadingModels
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              tooltip: 'Refresh model list',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _fetchCloudModels() async {
    final apiKey = _settingsBox.get('cloudApiKey') as String?;
    if (apiKey == null || apiKey.isEmpty) return;

    setState(() => _isLoadingModels = true);

    try {
      final url = Uri.parse('https://ollama.com/api/tags');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final models = (json['models'] as List?)
            ?.map((m) => m['name'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
        if (models != null && mounted) {
          setState(() => _cloudModels = models);
        }
      }
    } catch (_) {
      // Silently fail — user can retry
    } finally {
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  void _showOllamaInfoBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return _OllamaInfoBottomSheet();
      },
    );
  }

  void _handleSearchLocalNetwork() async {
    setState(() {
      _serverAddressErrorText = null;
      _requestState = OllamaRequestState.loading;
    });

    try {
      final result = await Isolate.run(() => _searchLocalNetwork());
      final foundAddress = result.$2.toString();

      if (!mounted) return;

      // Update the server address text field with the found address.
      _serverAddressController.text = foundAddress;

      _requestState = result.$1;
      _saveServerAddressWith(result);
    } on OllamaException catch (e) {
      _serverAddressErrorText = e.message;
      _requestState = OllamaRequestState.error;
    } catch (e) {
      _serverAddressErrorText = 'Something went wrong while searching.';
      _requestState = OllamaRequestState.error;
    } finally {
      setState(() {});
    }
  }

  static Future<(OllamaRequestState, Uri)> _searchLocalNetwork() async {
    final networkInterfaces = await NetworkInterface.list(
      includeLoopback: true,
      type: InternetAddressType.IPv4,
    );

    final futures = <Future<(OllamaRequestState, Uri)>>[];
    for (var interface in networkInterfaces) {
      for (var address in interface.addresses) {
        if (address.isLoopback) {
          final url = Uri.parse('http://${address.address}:11434');
          futures.add(_establishServerConnection(url));
        } else {
          final segments = address.address.split('.');
          for (int i = 1; i < 255; i++) {
            final url = Uri.parse(
              'http://${segments[0]}.${segments[1]}.${segments[2]}.$i:11434',
            );
            futures.add(_establishServerConnection(url));
          }
        }
      }
    }

    final results = await Future.wait(futures);

    final result = results.firstWhere(
      (result) => result.$1 == OllamaRequestState.success,
      orElse: () =>
          throw OllamaException('No Ollama server found on the local network.'),
    );

    return result;
  }
}

class _ConnectionStatusIndicator extends StatelessWidget {
  final Color color;

  const _ConnectionStatusIndicator({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = color == Colors.green;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isConnected ? 'Connected' : 'Connect'),
        const SizedBox(width: 10),
        Container(
          width: MediaQuery.of(context).textScaler.scale(10),
          height: MediaQuery.of(context).textScaler.scale(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _OllamaInfoBottomSheet extends StatelessWidget {
  const _OllamaInfoBottomSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      minimum: EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OllamaBottomSheetHeader(title: 'What is Ollama?'),
          Divider(),
          Expanded(
            child: ListView(
              children: [
                MarkdownBody(
                  data:
                      "Ollama is a free platform that enables you to run advanced large language models (LLMs) like Llama 3.3, Phi 3, Mistral, Gemma 2, and more directly on your local machine. This setup enhances privacy, security, and control over your AI interactions. Ollama also allows you to customize and create your own models.\n\nTo get started with Ollama, visit their official website: [ollama.com](https://ollama.com). Here, you can explore various models and download the platform to begin using Ollama.",
                  styleSheet: context.markdownStyleSheet,
                  onTapLink: (_, href, __) => launchUrlString(href!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
