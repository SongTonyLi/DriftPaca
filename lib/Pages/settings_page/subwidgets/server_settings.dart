import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_request_state.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';

class ServerSettings extends StatefulWidget {
  final bool autoFocusServerAddress;

  const ServerSettings({super.key, this.autoFocusServerAddress = false});

  @override
  State<ServerSettings> createState() => _ServerSettingsState();
}

class _ServerSettingsState extends State<ServerSettings> {
  final _settingsBox = Hive.box('settings');

  final _apiKeyController = TextEditingController();
  final _openRouterApiKeyController = TextEditingController();

  OllamaRequestState _cloudRequestState = OllamaRequestState.uninitialized;
  OllamaRequestState _openRouterRequestState = OllamaRequestState.uninitialized;
  get _isCloudLoading => _cloudRequestState == OllamaRequestState.loading;
  get _isOpenRouterLoading =>
      _openRouterRequestState == OllamaRequestState.loading;

  String? _cloudErrorText;
  String? _openRouterErrorText;
  bool _obscureApiKey = true;
  bool _obscureOpenRouterApiKey = true;

  String get _serverMode {
    final mode = _settingsBox.get('serverMode', defaultValue: 'cloud');
    if (mode == 'local' || mode == 'openwebui') return 'cloud';
    return mode;
  }

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  _initialize() {
    final storedMode = _settingsBox.get('serverMode', defaultValue: 'cloud');
    if (storedMode == 'local' || storedMode == 'openwebui') {
      _settingsBox.put('serverMode', 'cloud');
      _settingsBox.put('isCloudMode', true);
    }

    final cloudApiKey = _settingsBox.get('cloudApiKey');

    if (cloudApiKey != null) {
      _apiKeyController.text = cloudApiKey;
      if (_serverMode == 'cloud') {
        _handleCloudConnectButton(silent: true);
      }
    }

    final openRouterApiKey = _settingsBox.get('openrouterApiKey');
    if (openRouterApiKey != null) {
      _openRouterApiKeyController.text = openRouterApiKey;
      if (_serverMode == 'openrouter') {
        _handleOpenRouterConnectButton(silent: true);
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _openRouterApiKeyController.dispose();

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
        _ServerModeControl(
          mode: _serverMode == 'openrouter' ? 'openrouter' : 'cloud',
          onChanged: _setServerMode,
        ),
        const SizedBox(height: 16),
        if (_serverMode == 'openrouter')
          _buildOpenRouterSettings(context)
        else
          _buildCloudSettings(context),
        const SizedBox(height: 16),
        Text('Memory Model', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildMemoryModelSelector(context),
      ],
    );
  }

  Widget _buildCloudSettings(BuildContext context) {
    return _RemoteApiKeyPanel(
      controller: _apiKeyController,
      obscure: _obscureApiKey,
      onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
      onChanged: (_) {
        setState(() {
          _cloudErrorText = null;
          _cloudRequestState = OllamaRequestState.uninitialized;
          _settingsBox.put('cloudDataConsented', false);
        });
      },
      errorText: _cloudErrorText,
      hintText: 'Enter your Ollama Cloud API key',
      helpText: 'Get your API key from ollama.com/settings',
      privacyText:
          'Your conversations will be sent to Ollama Cloud (ollama.com) for AI processing. Only data you enter in chats is transmitted. No data is collected by DriftPaca.',
      isLoading: _isCloudLoading,
      onConnect: () => _handleCloudConnectWithConsent(context),
      statusColor: _cloudConnectionStatusColor,
    );
  }

  Widget _buildOpenRouterSettings(BuildContext context) {
    return _RemoteApiKeyPanel(
      controller: _openRouterApiKeyController,
      obscure: _obscureOpenRouterApiKey,
      onToggleObscure: () =>
          setState(() => _obscureOpenRouterApiKey = !_obscureOpenRouterApiKey),
      onChanged: (_) {
        setState(() {
          _openRouterErrorText = null;
          _openRouterRequestState = OllamaRequestState.uninitialized;
          _settingsBox.put('openrouterDataConsented', false);
        });
      },
      errorText: _openRouterErrorText,
      hintText: 'Enter your OpenRouter API key',
      helpText: 'Get your API key from openrouter.ai/keys',
      privacyText:
          'Your conversations will be sent to OpenRouter (openrouter.ai) for AI processing. Only data you enter in chats is transmitted. No data is collected by DriftPaca.',
      isLoading: _isOpenRouterLoading,
      onConnect: () => _handleOpenRouterConnectWithConsent(context),
      statusColor: _openRouterConnectionStatusColor,
    );
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

  Color get _openRouterConnectionStatusColor {
    switch (_openRouterRequestState) {
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

  void _handleCloudConnectWithConsent(BuildContext context) {
    final consented = _settingsBox.get('cloudDataConsented', defaultValue: false);
    if (consented) {
      _handleCloudConnectButton();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data Sharing'),
        content: const Text(
          'By connecting to Ollama Cloud, the following data will be sent to ollama.com for AI processing:\n\n'
          '• Your chat messages and conversation history\n'
          '• System prompts you configure\n'
          '• Images you attach to messages\n\n'
          'Your API key is stored only on your device and is never shared with DriftPaca or any other party. No data is collected by this app. DriftPaca is fully open source, and you can verify the implementation in the source code.\n\n'
          'If you have questions, reach out at:\nhttps://github.com/SongTonyLi/DriftPaca/issues',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _settingsBox.put('cloudDataConsented', true);
              Navigator.pop(ctx);
              _handleCloudConnectButton();
            },
            child: const Text('Agree & Connect'),
          ),
        ],
      ),
    );
  }

  void _handleOpenRouterConnectWithConsent(BuildContext context) {
    final consented =
        _settingsBox.get('openrouterDataConsented', defaultValue: false);
    if (consented) {
      _handleOpenRouterConnectButton();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data Sharing'),
        content: const Text(
          'By connecting to OpenRouter, the following data will be sent to openrouter.ai for AI processing:\n\n'
          '• Your chat messages and conversation history\n'
          '• System prompts you configure\n'
          '• Images you attach to messages\n\n'
          'OpenRouter may then route the request to the model provider you select. Your API key is stored only on your device and is never shared with DriftPaca or any other party. No data is collected by this app. DriftPaca is fully open source, and you can verify the implementation in the source code.\n\n'
          'If you have questions, reach out at:\nhttps://github.com/SongTonyLi/DriftPaca/issues',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _settingsBox.put('openrouterDataConsented', true);
              Navigator.pop(ctx);
              _handleOpenRouterConnectButton();
            },
            child: const Text('Agree & Connect'),
          ),
        ],
      ),
    );
  }

  _handleOpenRouterConnectButton({bool silent = false}) async {
    setState(() {
      _openRouterErrorText = null;
      if (!silent) {
        _openRouterRequestState = OllamaRequestState.loading;
      }
    });

    try {
      final apiKey = _openRouterApiKeyController.text.trim();
      if (apiKey.isEmpty) {
        throw OllamaException('Please enter an API key.');
      }

      final url = Uri.parse('https://openrouter.ai/api/v1/key');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://github.com/SongTonyLi/DriftPaca',
        'X-Title': 'DriftPaca',
      }).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        _openRouterErrorText = 'Invalid API key.';
        _openRouterRequestState = OllamaRequestState.error;
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        _openRouterRequestState = OllamaRequestState.success;
        _settingsBox.put('openrouterApiKey', apiKey);
      } else {
        _openRouterErrorText = 'Could not connect to OpenRouter.';
        _openRouterRequestState = OllamaRequestState.error;
      }
    } on OllamaException catch (error) {
      _openRouterErrorText = error.message;
      _openRouterRequestState = OllamaRequestState.error;
    } catch (_) {
      _openRouterErrorText = 'Could not connect to OpenRouter.';
      _openRouterRequestState = OllamaRequestState.error;
    } finally {
      if (mounted) setState(() {});
    }
  }

  _handleCloudConnectButton({bool silent = false}) async {
    setState(() {
      _cloudErrorText = null;
      if (!silent) {
        _cloudRequestState = OllamaRequestState.loading;
      }
    });

    try {
      final apiKey = _apiKeyController.text.trim();
      if (apiKey.isEmpty) {
        throw OllamaException('Please enter an API key.');
      }

      // Use /api/chat to validate the key — /api/tags returns 200 for any key
      final url = Uri.parse('https://ollama.com/api/chat');
      final response = await http.post(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }, body: '{"model":"","messages":[]}').timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        _cloudErrorText = 'Invalid API key.';
        _cloudRequestState = OllamaRequestState.error;
      } else {
        // Any non-401 response means the key is valid (even 400 for bad model)
        _cloudRequestState = OllamaRequestState.success;
        _settingsBox.put('cloudApiKey', apiKey);
      }
    } on OllamaException catch (error) {
      _cloudErrorText = error.message;
      _cloudRequestState = OllamaRequestState.error;
    } catch (_) {
      _cloudErrorText = 'Could not connect to Ollama Cloud.';
      _cloudRequestState = OllamaRequestState.error;
    } finally {
      if (mounted) setState(() {});
    }
  }

  Widget _buildMemoryModelSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentModel = _settingsBox.get('memoryModel', defaultValue: MemoryConstants.defaultModel) as String;

    return InkWell(
      onTap: () => _showMemoryModelPicker(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentModel,
                    style: TextStyle(fontSize: 15, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _serverMode == 'openrouter'
                        ? 'Used for memory summarization via OpenRouter'
                        : 'Used for memory summarization via Ollama Cloud',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  void _showMemoryModelPicker(BuildContext context) async {
    final currentModel = _settingsBox.get('memoryModel', defaultValue: MemoryConstants.defaultModel) as String;

    final selected = await showModelSelectionBottomSheet(
      context: context,
      title: 'Memory Model',
      currentModelName: currentModel,
    );

    if (!mounted) return;

    if (selected != null) {
      _settingsBox.put('memoryModel', selected.name);
      setState(() {});
    }
  }
}

/// Ollama / OpenRouter control, matched to Themes' Light / Dark / Auto
/// segmented button: 18px icons, compact density, full-width.
class _ServerModeControl extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _ServerModeControl({required this.mode, required this.onChanged});

  static const _iconBreakpoint = 348.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showIcons = constraints.maxWidth >= _iconBreakpoint;
        return SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              iconSize: const WidgetStatePropertyAll(18),
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelMedium,
              ),
            ),
            segments: [
              ButtonSegment(
                value: 'cloud',
                tooltip: 'Ollama',
                icon: showIcons
                    ? const Icon(Icons.cloud_outlined, size: 18)
                    : null,
                label: const Text('Ollama'),
              ),
              ButtonSegment(
                value: 'openrouter',
                tooltip: 'OpenRouter',
                icon: showIcons
                    ? const Icon(Icons.hub_outlined, size: 18)
                    : null,
                label: const Text('OpenRouter'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        );
      },
    );
  }
}

/// Shared Cloud / OpenRouter key form so both remote backends keep the same
/// field, help line, privacy box, and Connect button geometry.
class _RemoteApiKeyPanel extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final String hintText;
  final String helpText;
  final String privacyText;
  final bool isLoading;
  final VoidCallback onConnect;
  final Color statusColor;

  const _RemoteApiKeyPanel({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onChanged,
    required this.errorText,
    required this.hintText,
    required this.helpText,
    required this.privacyText,
    required this.isLoading,
    required this.onConnect,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            errorText: errorText,
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggleObscure,
            ),
          ),
          onTapOutside: (PointerDownEvent event) {
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        const SizedBox(height: 8),
        Text(
          helpText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  privacyText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isLoading || controller.text.isEmpty ? null : onConnect,
            child: _ConnectionStatusIndicator(color: statusColor),
          ),
        ),
      ],
    );
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
