import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/subwidgets/logo_wheel.dart';

/// One stop on the model wheel: every model that shares a company / brand.
class WheelCatalogEntry {
  final String brandKey;
  final List<OllamaModel> models;

  const WheelCatalogEntry({
    required this.brandKey,
    required this.models,
  });

  BrandLogo get brand => brandByKey(brandKey);

  WheelNode get node => WheelNode(
        asset: brand.asset,
        accent: brand.accent,
        tinted: brand.tinted,
        label: brand.label,
      );
}

/// Lays models onto the selector wheel as one node per company / brand.
/// Specific models of that brand are chosen from the sibling strip, not the ring.
class WheelCatalog {
  final List<WheelCatalogEntry> entries;
  final String? selectedName;

  const WheelCatalog._(this.entries, this.selectedName);

  factory WheelCatalog.fromModels(
    List<OllamaModel> models, {
    String? selectedName,
  }) {
    if (models.isEmpty) {
      return const WheelCatalog._([], null);
    }

    final groups = <String, List<OllamaModel>>{};
    final order = <String>[];
    for (final model in models) {
      final key = brandForModel(model).key;
      if (groups.putIfAbsent(key, () => []).isEmpty) {
        order.add(key);
      }
      groups[key]!.add(model);
    }
    final entries = [
      for (final key in order)
        WheelCatalogEntry(brandKey: key, models: groups[key]!),
    ];
    return WheelCatalog._(entries, selectedName);
  }

  int get selectedIndex {
    if (entries.isEmpty) return 0;
    if (selectedName == null) return 0;
    final index = entries.indexWhere(
      (entry) => entry.models.any((model) => model.name == selectedName),
    );
    return index < 0 ? 0 : index;
  }

  WheelCatalogEntry get selectedEntry => entries[selectedIndex];

  OllamaModel get dockedModel {
    final entry = selectedEntry;
    return entry.models.firstWhere(
      (model) => model.name == selectedName,
      orElse: () => entry.models.first,
    );
  }

  List<OllamaModel> get siblingsOfDocked =>
      entries.isEmpty ? const [] : selectedEntry.models;

  String nameForIndex(int index) {
    final entry = entries[index];
    if (selectedName != null &&
        entry.models.any((model) => model.name == selectedName)) {
      return selectedName!;
    }
    return entry.models.first.name;
  }
}
