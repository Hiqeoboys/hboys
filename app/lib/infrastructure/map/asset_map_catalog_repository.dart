import 'package:flutter/services.dart';

import '../../features/map/domain/map_package.dart';

class AssetMapCatalogRepository {
  AssetMapCatalogRepository({
    AssetBundle? bundle,
    this.catalogAsset = 'assets/map_packs/catalog.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String catalogAsset;

  Future<MapPackageCatalog> load({
    MapGuardrails guardrails = const MapGuardrails(),
  }) async {
    final raw = await _bundle.loadString(catalogAsset);
    return MapPackageParser.parseCatalog(
      raw,
      loadAsset: _bundle.loadString,
      guardrails: guardrails,
    );
  }
}
