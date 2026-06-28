import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';
import 'subwidgets/logo_wheel.dart';
import 'subwidgets/model_info_card.dart';
import 'subwidgets/wheel_center_disc.dart';

/// Full-screen "wheeler" model selector. The user's available [models] orbit a
/// central glass disc as provider-logo nodes; turning the ring snaps one under
/// the notch and the mesh background tints to that brand. A search field at the
/// top filters the ring live. Confirming returns the chosen [OllamaModel] — via
/// [onConfirm] if given, otherwise `Navigator.pop`.
class ModelSelectPage extends StatefulWidget {
  final List<OllamaModel> models;
  final String? currentModelName;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  /// Called with the chosen model on confirm. When null, the page pops with the
  /// model as its route result (the in-app contract).
  final ValueChanged<OllamaModel>? onConfirm;

  final String title;

  const ModelSelectPage({
    super.key,
    required this.models,
    this.currentModelName,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onConfirm,
    this.title = 'Choose a model',
  });

  @override
  State<ModelSelectPage> createState() => _ModelSelectPageState();
}

class _ModelSelectPageState extends State<ModelSelectPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// The docked model is tracked by name so it survives filtering (it stays
  /// docked while it still matches; otherwise the top match docks).
  late String _selectedName;
  late Color _firstAccent;

  // Drives the logo→info-card flip (0 = logo, 1 = info window).
  late final AnimationController _infoCtrl;

  // Measured position/size of the real center disc, so the flip animates from
  // exactly where the disc sits (it isn't screen-centred) — no snap on close.
  final GlobalKey _discKey = GlobalKey();
  Offset? _discCenter;

  @override
  void initState() {
    super.initState();
    _selectedName = _initialName();
    // Guard the empty case: the in-app loader builds this page with an empty
    // list while models are still loading, and `_modelByName` would otherwise
    // call `.first` on an empty list ("Bad state: No element").
    _firstAccent = widget.models.isEmpty
        ? kOllamaBrand.accent
        : brandForModel(_modelByName(_selectedName)).accent;
    _infoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
  }

  @override
  void didUpdateWidget(ModelSelectPage old) {
    super.didUpdateWidget(old);
    // Models arrived (loading → loaded): dock the requested current model
    // instead of staying on the empty-state placeholder.
    if (!identical(old.models, widget.models) &&
        widget.models.isNotEmpty &&
        !widget.models.any((m) => m.name == _selectedName)) {
      _selectedName = _initialName();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _infoCtrl.dispose();
    super.dispose();
  }

  void _openInfo() {
    FocusScope.of(context).unfocus(); // drop the keyboard before the flip
    // Capture where the disc actually is so the flip is anchored to it.
    final discBox = _discKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (discBox != null && selfBox != null && discBox.hasSize) {
      final topLeft = discBox.localToGlobal(Offset.zero, ancestor: selfBox);
      _discCenter = topLeft + discBox.size.center(Offset.zero);
    }
    _infoCtrl.forward();
  }

  void _closeInfo() => _infoCtrl.reverse();

  String _initialName() {
    final name = widget.currentModelName;
    if (name != null && widget.models.any((m) => m.name == name)) return name;
    return widget.models.isNotEmpty ? widget.models.first.name : '';
  }

  OllamaModel _modelByName(String name) => widget.models.firstWhere(
        (m) => m.name == name,
        orElse: () => widget.models.first,
      );

  /// Models matching the current query (all tokens must appear in the model's
  /// name / family / brand label). Empty query → every model.
  List<OllamaModel> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.models;
    final tokens = q.split(RegExp(r'\s+'));
    return widget.models.where((m) {
      final hay = '${m.name} ${m.family} ${brandForModel(m).label}'.toLowerCase();
      return tokens.every(hay.contains);
    }).toList();
  }

  int _selectedIndexIn(List<OllamaModel> filtered) {
    final i = filtered.indexWhere((m) => m.name == _selectedName);
    return i < 0 ? 0 : i;
  }

  void _onSearchChanged(String v) {
    setState(() {
      _query = v;
      final f = _filtered;
      // If the docked model fell out of the results, dock the new top match.
      if (f.isNotEmpty && f.indexWhere((m) => m.name == _selectedName) < 0) {
        _selectedName = f.first.name;
      }
    });
  }

  void _onWheelSelected(int i) {
    final f = _filtered;
    if (i < 0 || i >= f.length) return;
    setState(() => _selectedName = f[i].name);
  }

  void _confirm() {
    final f = _filtered;
    if (f.isEmpty) return;
    final model = f[_selectedIndexIn(f)];
    if (widget.onConfirm != null) {
      widget.onConfirm!(model);
    } else {
      Navigator.of(context).pop(model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.models.isEmpty
        ? kOllamaBrand.accent
        : brandForModel(_modelByName(_selectedName)).accent;
    final brightness = Theme.of(context).brightness;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed background OUTSIDE the Scaffold, so the keyboard resizing
        // the body can't shrink it (which left a black gap above the keyboard).
        // It animates its tint as the docked brand changes.
        TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          tween: ColorTween(begin: _firstAccent, end: accent),
          builder: (context, c, _) {
            final acc = c ?? accent;
            final m = _MeshColors.fromAccent(acc, brightness);
            return Stack(
              fit: StackFit.expand,
              children: [
                FloatingGradientBackground(
                  meshA: m.a,
                  meshB: m.b,
                  canvas: m.canvas,
                  idleColor: m.idle,
                  // Power-restrained: a brief corner-breathe intro on open, then
                  // the mesh settles to a flat brand-tinted idle and the ticker
                  // stops. The brand tint still shifts (cheaply) on selection.
                  isGenerating: false,
                  isWelcome: true,
                ),
                // Static brand-tinted spotlight behind the wheel for depth.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.08),
                        radius: 0.95,
                        colors: [
                          acc.withValues(
                              alpha:
                                  brightness == Brightness.light ? 0.16 : 0.22),
                          acc.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            forceMaterialTransparency: true,
            centerTitle: true,
            title: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          body: SafeArea(child: _buildBody(context, accent)),
        ),
        // Logo→info flip overlay (full-screen, above the Scaffold).
        if (widget.models.isNotEmpty)
          Positioned.fill(
            child: _InfoOverlay(
              animation: _infoCtrl,
              center: _discCenter,
              model: _modelByName(_selectedName),
              brand: brandForModel(_modelByName(_selectedName)),
              onClose: _closeInfo,
              onSelect: () {
                _closeInfo();
                _confirm();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Color accent) {
    if (widget.isLoading) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 16),
            Text('Loading models…',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7))),
          ],
        ),
      );
    }

    if (widget.error != null) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(widget.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: widget.onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }

    if (widget.models.isEmpty) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.5,
              child: Icon(Icons.blur_on,
                  size: 48, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 14),
            Text('No models found',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: _SearchField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchCtrl.clear();
              _onSearchChanged('');
            },
            hasQuery: _query.isNotEmpty,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _NoMatch(query: _query)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wheelD = [
                      constraints.maxWidth * 0.92,
                      constraints.maxHeight * 0.86,
                      440.0,
                    ].reduce((a, b) => a < b ? a : b);
                    final holeD = wheelD * 0.52;
                    final sel = _selectedIndexIn(filtered);
                    final model = filtered[sel];
                    final brand = brandForModel(model);
                    final caps = model.capabilities;

                    return Center(
                      child: SizedBox(
                        width: wheelD,
                        height: wheelD,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            LogoWheel(
                              // Re-key when the result set changes so the ring
                              // re-lays-out and docks the current match.
                              key: ValueKey(
                                  filtered.map((m) => m.name).join('|')),
                              nodes: [
                                for (final m in filtered)
                                  _nodeFor(m),
                              ],
                              initialIndex: sel,
                              diameter: wheelD,
                              centerHole: holeD,
                              onSelectedChanged: _onWheelSelected,
                            ),
                            WheelCenterDisc(
                              key: _discKey,
                              diameter: holeD,
                              asset: brand.asset,
                              accent: accent,
                              tinted: brand.tinted,
                              modelName: model.name,
                              paramSize: model.parameterSize,
                              think: caps?.thinking ?? false,
                              vision: caps?.vision ?? false,
                              tools: caps?.tools ?? false,
                              onTap: _confirm,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (filtered.isNotEmpty) ...[
          const _Hint(),
          const SizedBox(height: 10),
          // Info (Details) button alongside the primary confirm action.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              _InfoActionButton(onTap: _openInfo),
              _ConfirmPill(accent: accent, onTap: _confirm),
            ],
          ),
          const SizedBox(height: 22),
        ] else
          const SizedBox(height: 40),
      ],
    );
  }

  WheelNode _nodeFor(OllamaModel m) {
    final b = brandForModel(m);
    return WheelNode(asset: b.asset, accent: b.accent, tinted: b.tinted);
  }
}

/// Frosted search field that filters the wheel live.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasQuery;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search,
              size: 19, color: cs.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: cs.primary,
              style: TextStyle(fontSize: 14.5, color: cs.onSurface),
              decoration: InputDecoration.collapsed(
                hintText: 'Search models',
                hintStyle: TextStyle(
                    fontSize: 14.5,
                    color: cs.onSurface.withValues(alpha: 0.4)),
              ),
            ),
          ),
          if (hasQuery)
            IconButton(
              splashRadius: 18,
              iconSize: 18,
              icon: Icon(Icons.close,
                  color: cs.onSurface.withValues(alpha: 0.55)),
              onPressed: onClear,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  final String query;
  const _NoMatch({required this.query});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 42, color: cs.onSurface.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('No models match “$query”',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Mesh colours derived from a brand accent, lightness-clamped per brightness so
/// the background reads in both light and dark — mirrors `mode_palette`.
class _MeshColors {
  final Color a;
  final Color b;
  final Color canvas;
  final Color idle;
  const _MeshColors(this.a, this.b, this.canvas, this.idle);

  factory _MeshColors.fromAccent(Color accent, Brightness brightness) {
    final b2 = _hueShift(accent, 22);
    if (brightness == Brightness.light) {
      return _MeshColors(
        _clampL(accent, 0.45, 0.72),
        _clampL(b2, 0.45, 0.72),
        _setL(accent, 0.90),
        // Slightly richer than the chat idle: the static background carries the
        // brand tint on its own now, so make it perceptible (but still soft).
        _idleTint(accent, 0.91, satScale: 0.6),
      );
    }
    return _MeshColors(
      _clampL(_scaleSL(accent, s: 0.85, l: 0.5), 0.18, 0.40),
      _clampL(_scaleSL(b2, s: 0.85, l: 0.5), 0.18, 0.40),
      _setL(accent, 0.08),
      _idleTint(accent, 0.12, satScale: 0.55),
    );
  }

  static Color _clampL(Color c, double lo, double hi) {
    final h = HSLColor.fromColor(c);
    return h.withLightness(h.lightness.clamp(lo, hi)).toColor();
  }

  static Color _setL(Color c, double l) =>
      HSLColor.fromColor(c).withLightness(l.clamp(0.0, 1.0)).toColor();

  static Color _hueShift(Color c, double deg) {
    final h = HSLColor.fromColor(c);
    return h.withHue((h.hue + deg) % 360).toColor();
  }

  static Color _scaleSL(Color c, {double s = 1, double l = 1}) {
    final h = HSLColor.fromColor(c);
    return HSLColor.fromAHSL(h.alpha, h.hue,
            (h.saturation * s).clamp(0.0, 1.0), (h.lightness * l).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _idleTint(Color base, double l, {double satScale = 0.45}) {
    final h = HSLColor.fromColor(base);
    return HSLColor.fromAHSL(
            1.0, h.hue, (h.saturation * satScale).clamp(0.0, 1.0), l)
        .toColor();
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(32), child: child));
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_outlined, size: 14, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Turn the wheel · tap a logo to jump',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoActionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoActionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.7),
      shape: StadiumBorder(
        side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: cs.onSurface.withValues(alpha: 0.75)),
              const SizedBox(width: 7),
              Text('Details',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: cs.onSurface.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmPill extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;
  const _ConfirmPill({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = HSLColor.fromColor(accent);
    final bg = h.withLightness(h.lightness.clamp(0.42, 0.56)).toColor();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 22,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 19, color: Colors.white),
              SizedBox(width: 8),
              Text('Use this model',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo→info-card flip overlay. As [progress] runs 0→1 the center logo disc
/// rotates about Y; past 90° it swaps to the original info window, which faces
/// the user at progress 1. A dimmed, dismissible barrier sits behind it.
class _InfoOverlay extends StatelessWidget {
  final Animation<double> animation;
  final Offset? center; // real disc centre (overlay coords); null → screen centre
  final OllamaModel model;
  final BrandLogo brand;
  final VoidCallback onClose;
  final VoidCallback onSelect;
  const _InfoOverlay({
    required this.animation,
    this.center,
    required this.model,
    required this.brand,
    required this.onClose,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardW = math.min(size.width * 0.86, 380.0);
    final cardMaxH = size.height * 0.66;
    final screenCenter = Offset(size.width / 2, size.height / 2);
    final shift = (center ?? screenCenter) - screenCenter;

    // Built once and cached, so the zoom only transforms a texture.
    final card = RepaintBoundary(
      child: ModelInfoCard(
        model: model,
        brand: brand,
        maxWidth: cardW,
        maxHeight: cardMaxH,
        onSelect: onSelect,
        onClose: onClose,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final p = animation.value.clamp(0.0, 1.0).toDouble();
        if (p == 0) return const SizedBox.shrink();
        final cp = Curves.easeOutCubic.transform(p);
        final scale = 0.6 + 0.4 * cp; // zoom the window out of the disc
        return Stack(
          children: [
            ModalBarrier(
              color: Colors.black.withValues(alpha: 0.5 * cp),
              dismissible: true,
              onDismiss: onClose,
            ),
            // Anchored at the disc, so the window grows out of where it sits.
            Transform.translate(
              offset: shift,
              child: Center(
                child: Opacity(
                  opacity: cp,
                  child: Transform.scale(scale: scale, child: card),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
