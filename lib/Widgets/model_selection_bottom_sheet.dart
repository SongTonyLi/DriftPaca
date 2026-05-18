import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:async/async.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Models/model_capabilities.dart';

import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/ollama_request_state.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/ollama_service.dart';

class ModelSelectionBottomSheet extends StatefulWidget {
  final String title;
  final String? currentModelName;

  const ModelSelectionBottomSheet({
    super.key,
    required this.title,
    this.currentModelName,
  });

  @override
  State<ModelSelectionBottomSheet> createState() =>
      _ModelSelectionBottomSheetState();
}

class _ModelSelectionBottomSheetState extends State<ModelSelectionBottomSheet> {
  static final _modelsBucket = PageStorageBucket();

  late final ChatProvider _chatProvider;

  List<OllamaModel> _models = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  var _state = OllamaRequestState.uninitialized;
  late CancelableOperation _fetchOperation;

  String get _cacheKey {
    final box = Hive.box('settings');
    final isCloud = box.get('isCloudMode', defaultValue: false);
    if (isCloud) return 'cloud';
    return box.get('serverAddress') ?? 'default';
  }

  bool get _isCloudMode =>
      Hive.box('settings').get('isCloudMode', defaultValue: false);

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _models = _modelsBucket.readState(context, identifier: _cacheKey) ?? [];
    _fetchOperation = CancelableOperation.fromFuture(_fetchModels());
  }

  List<OllamaModel> get _filteredModels {
    if (_searchQuery.isEmpty) return _models;
    final query = _searchQuery.toLowerCase();
    return _models.where((m) => m.name.toLowerCase().contains(query)).toList();
  }

  @override
  void dispose() {
    _fetchOperation.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    setState(() => _state = OllamaRequestState.loading);

    try {
      _models = await _chatProvider.fetchAvailableModels();
      _state = OllamaRequestState.success;
      if (mounted) {
        _modelsBucket.writeState(context, _models, identifier: _cacheKey);
      }
      // Pre-fetch readmes in background for all models
      _prefetchReadmes();
    } catch (e) {
      _state = OllamaRequestState.error;
    }

    if (mounted) setState(() {});
  }

  void _prefetchReadmes() {
    final service = _chatProvider.ollamaService;
    for (final model in _models) {
      if (service.getCachedReadme(model.name) == null) {
        service.fetchModelReadme(model.name); // fire-and-forget
      }
    }
  }

  void _selectModel(OllamaModel model) {
    Navigator.of(context).pop(model);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                if (_isCloudMode)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_outlined,
                            size: 13, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Cloud',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_models.isNotEmpty &&
                    _state == OllamaRequestState.loading)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search bar
          if (_models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: Icon(Icons.search,
                      size: 20,
                      color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          const SizedBox(height: 8),
          // Model list
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_state == OllamaRequestState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 32,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Could not load models.\nCheck your connection.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  _fetchOperation =
                      CancelableOperation.fromFuture(_fetchModels());
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_state == OllamaRequestState.loading && _models.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    } else if (_state == OllamaRequestState.success || _models.isNotEmpty) {
      if (_models.isEmpty) {
        return const Center(child: Text('No models found.'));
      }

      final filtered = _filteredModels;
      if (filtered.isEmpty) {
        return Center(
          child: Text(
            'No models match "$_searchQuery"',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () async {
          _fetchOperation = CancelableOperation.fromFuture(_fetchModels());
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final model = filtered[index];
            final isCurrent = model.name == widget.currentModelName;
            return _ModelTile(
              model: model,
              isCurrent: isCurrent,
              isCloudMode: _isCloudMode,
              onTap: () => _selectModel(model),
            );
          },
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}

class _ModelTile extends StatefulWidget {
  final OllamaModel model;
  final bool isCurrent;
  final bool isCloudMode;
  final VoidCallback onTap;

  const _ModelTile({
    required this.model,
    required this.isCurrent,
    required this.isCloudMode,
    required this.onTap,
  });

  @override
  State<_ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<_ModelTile>
    with SingleTickerProviderStateMixin {
  static const _maxSlide = 80.0;

  late final AnimationController _slideController;
  double _dragOffset = 0;
  double _snapStartOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _slideController.removeListener(_onSnapTick);
    _slideController.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    setState(() {
      _dragOffset = lerpDouble(
              _snapStartOffset, 0, Curves.easeOutCubic.transform(_slideController.value)) ??
          0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(-_maxSlide, 0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -400 || _dragOffset < -_maxSlide * 0.4) {
      _showInfoCard();
    }
    _snapBack();
  }

  void _snapBack() {
    _snapStartOffset = _dragOffset;
    _slideController.forward(from: 0);
  }

  void _showInfoCard() {
    final service = context.read<ChatProvider>().ollamaService;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, _, __) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
          reverseCurve: const Cubic(0.4, 0.0, 0.7, 0.2),
        );
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: const Interval(0.0, 0.7, curve: Curves.easeOut),
        );

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curve),
            child: _ModelInfoCard(
              model: widget.model,
              ollamaService: service,
              onSelect: () {
                Navigator.pop(dialogContext);
                widget.onTap();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final capabilities = widget.model.capabilities;
    // 0.0 = resting, 1.0 = fully slid
    final progress = (_dragOffset / -_maxSlide).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Info indicator revealed behind the card
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08 + 0.06 * progress),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.only(right: 20),
                child: Opacity(
                  opacity: progress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Info',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Front card that slides
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Material(
                  color: widget.isCurrent
                      ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                      : colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.model.name,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13.5,
                                    fontWeight: widget.isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: widget.isCurrent
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (capabilities != null &&
                                    _hasAnyCapability(capabilities))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: _buildCapabilityBadges(
                                          context, capabilities),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.isCurrent)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 22,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _hasAnyCapability(ModelCapabilities c) =>
      c.vision || c.tools || c.thinking;

  static List<Widget> _buildCapabilityBadges(
      BuildContext context, ModelCapabilities capabilities) {
    final badges = <Widget>[];
    if (capabilities.thinking) {
      badges.add(const _Badge(
          label: 'Think',
          icon: Icons.auto_awesome,
          color: Color(0xFF9C6ADE)));
    }
    if (capabilities.vision) {
      badges.add(const _Badge(
          label: 'Vision',
          icon: Icons.visibility_rounded,
          color: Color(0xFF3D8BD4)));
    }
    if (capabilities.tools) {
      badges.add(const _Badge(
          label: 'Tools',
          icon: Icons.handyman_rounded,
          color: Color(0xFFCF8523)));
    }
    return badges;
  }
}

class _ModelInfoCard extends StatefulWidget {
  final OllamaModel model;
  final OllamaService ollamaService;
  final VoidCallback onSelect;

  const _ModelInfoCard({
    required this.model,
    required this.ollamaService,
    required this.onSelect,
  });

  @override
  State<_ModelInfoCard> createState() => _ModelInfoCardState();
}

class _ModelInfoCardState extends State<_ModelInfoCard> {
  String? _readme;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _readme = widget.ollamaService.getCachedReadme(widget.model.name);
    if (_readme != null) {
      _loading = false;
    } else {
      _fetchReadme();
    }
  }

  Future<void> _fetchReadme() async {
    final result =
        await widget.ollamaService.fetchModelReadme(widget.model.name);
    if (mounted) {
      setState(() {
        _readme = result;
        _loading = false;
      });
    }
  }

  OllamaModel get model => widget.model;
  VoidCallback get onSelect => widget.onSelect;

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String _fallbackDescription(OllamaModel model) {
    final parts = <String>[];
    final baseName = model.name.contains(':')
        ? model.name.split(':').first
        : model.name;
    if (model.family.isNotEmpty) {
      parts.add(
          'A ${model.family}-family model');
    } else {
      parts.add('$baseName model');
    }
    if (model.parameterSize.isNotEmpty) {
      parts.add('with ${model.parameterSize} parameters');
    }
    if (model.quantizationLevel.isNotEmpty) {
      parts.add('quantized to ${model.quantizationLevel}');
    }
    final caps = <String>[];
    if (model.capabilities?.thinking == true) caps.add('extended thinking');
    if (model.capabilities?.vision == true) caps.add('vision');
    if (model.capabilities?.tools == true) caps.add('tool use');
    if (caps.isNotEmpty) {
      parts.add('supporting ${caps.join(', ')}');
    }
    return '${parts.join(', ')}.';
  }

  static String _formatContextLength(int ctx) {
    if (ctx >= 1000000) return '${(ctx / 1000000).toStringAsFixed(1)}M';
    if (ctx >= 1000) return '${(ctx / 1000).toStringAsFixed(0)}K';
    return ctx.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final capabilities = model.capabilities;
    final hasCapabilities = capabilities != null &&
        (capabilities.vision || capabilities.tools || capabilities.thinking);

    // Build spec entries with icons
    final specs = <({IconData icon, String label, String value})>[];
    if (model.family.isNotEmpty) {
      specs.add(
          (icon: Icons.account_tree_rounded, label: 'Family', value: model.family));
    }
    if (model.parameterSize.isNotEmpty) {
      specs.add(
          (icon: Icons.memory_rounded, label: 'Parameters', value: model.parameterSize));
    }
    if (model.quantizationLevel.isNotEmpty) {
      specs.add((
        icon: Icons.compress_rounded,
        label: 'Quantization',
        value: model.quantizationLevel
      ));
    }
    if (model.format.isNotEmpty) {
      specs.add((
        icon: Icons.inventory_2_outlined,
        label: 'Format',
        value: model.format.toUpperCase()
      ));
    }
    specs.add(
        (icon: Icons.sd_storage_outlined, label: 'Disk', value: _formatSize(model.size)));
    if (model.contextLength != null) {
      specs.add((
        icon: Icons.token_rounded,
        label: 'Context',
        value: '${_formatContextLength(model.contextLength!)} tokens'
      ));
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.68,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 50,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with warm accent bar
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Model name
                            Text(
                              model.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (model.family.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                model.family.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                            // Capability badges
                            if (hasCapabilities) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (capabilities.thinking)
                                    const _Badge(
                                        label: 'Think',
                                        icon: Icons.auto_awesome,
                                        color: Color(0xFF9C6ADE)),
                                  if (capabilities.vision)
                                    const _Badge(
                                        label: 'Vision',
                                        icon: Icons.visibility_rounded,
                                        color: Color(0xFF3D8BD4)),
                                  if (capabilities.tools)
                                    const _Badge(
                                        label: 'Tools',
                                        icon: Icons.handyman_rounded,
                                        color: Color(0xFFCF8523)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Description / readme
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                        child: _loading
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Loading readme...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                _readme ??
                                    (model.description.isNotEmpty
                                        ? model.description
                                        : _fallbackDescription(model)),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.55,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),

                      // Specs
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                        child: Text(
                          'SPECIFICATIONS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < specs.length; i++)
                                _SpecRow(
                                  icon: specs[i].icon,
                                  label: specs[i].label,
                                  value: specs[i].value,
                                  isLast: i == specs.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Digest
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                        child: Text(
                          model.digest.length > 16
                              ? 'sha256:${model.digest.substring(0, 12)}...'
                              : model.digest,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ),

                      // Select button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onSelect,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Select Model',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _SpecRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a model selection bottom sheet and returns the selected model.
Future<OllamaModel?> showModelSelectionBottomSheet({
  required BuildContext context,
  required String title,
  String? currentModelName,
}) async {
  return await showModalBottomSheet<OllamaModel?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.78),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: ModelSelectionBottomSheet(
                  title: title,
                  currentModelName: currentModelName,
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
