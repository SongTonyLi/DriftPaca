import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'model_select_page.dart';

/// Pushes the wheeler model selector and resolves to the chosen [OllamaModel]
/// (or null if dismissed). Same return contract as `showModelSelectionBottomSheet`
/// — a drop-in swap for the chat-facing selectors.
Future<OllamaModel?> showModelSelectWheel({
  required BuildContext context,
  String? currentModelName,
  String title = 'Choose a model',
}) {
  return Navigator.of(context).push<OllamaModel>(
    PageRouteBuilder<OllamaModel>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) =>
          _ModelSelectLoader(currentModelName: currentModelName, title: title),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

/// Fetches the available models (with loading / error / retry) and hands them to
/// [ModelSelectPage], which pops with the chosen model.
class _ModelSelectLoader extends StatefulWidget {
  final String? currentModelName;
  final String title;
  const _ModelSelectLoader({this.currentModelName, required this.title});

  @override
  State<_ModelSelectLoader> createState() => _ModelSelectLoaderState();
}

class _ModelSelectLoaderState extends State<_ModelSelectLoader> {
  late final ChatProvider _chatProvider;
  List<OllamaModel> _models = [];
  bool _loading = true;
  String? _error;
  CancelableOperation<List<OllamaModel>>? _op;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _fetch();
  }

  void _fetch() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _op?.cancel();
    final op =
        CancelableOperation.fromFuture(_chatProvider.fetchAvailableModels());
    _op = op;
    op.value.then((models) {
      if (!mounted) return;
      setState(() {
        _models = models;
        _loading = false;
      });
    }).catchError((Object _) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load models. Check your server or connection.";
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _op?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModelSelectPage(
      models: _models,
      currentModelName: widget.currentModelName,
      isLoading: _loading,
      error: _error,
      onRetry: _fetch,
      title: widget.title,
    );
  }
}
