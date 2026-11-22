import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/auth/active_account_scope.dart';
import '../../tracking/domain/calorie_estimator.dart';

/// Tinggi badan bawaan (cm) bila pengguna belum mengisi profil fisik.
const double kDefaultHeightCm = 170;

/// Penyimpan berat dan tinggi badan pengguna untuk perhitungan kalori ACSM
/// dan perkiraan langkah berbasis jarak.
class BodyMetricsStore extends ChangeNotifier {
  BodyMetricsStore();

  static final BodyMetricsStore instance = BodyMetricsStore();

  static const String _weightKey = 'hiqeo.body.weight_kg';
  static const String _heightKey = 'hiqeo.body.height_cm';

  double? _weightKg;
  double? _heightCm;
  bool _loaded = false;
  String? _loadedNamespace;

  double? get weightKg => _weightKg;
  double? get heightCm => _heightCm;
  bool get hasCustomWeight => _weightKg != null && _weightKg! > 0;
  bool get hasCustomHeight => _heightCm != null && _heightCm! > 0;

  double get effectiveWeightKg =>
      hasCustomWeight ? _weightKg! : kDefaultWeightKg;
  double get effectiveHeightCm =>
      hasCustomHeight ? _heightCm! : kDefaultHeightCm;

  Future<void> load() async {
    final ns = ActiveAccountScope.storageNamespace();
    if (_loaded && _loadedNamespace == ns) return;
    _loaded = true;
    _loadedNamespace = ns;
    _weightKg = null;
    _heightCm = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final w = prefs.getDouble(ActiveAccountScope.namespacedKey(_weightKey));
      final h = prefs.getDouble(ActiveAccountScope.namespacedKey(_heightKey));
      if (w != null && w >= 25 && w <= 250) _weightKg = w;
      if (h != null && h >= 100 && h <= 240) _heightCm = h;
      notifyListeners();
    } catch (_) {
      // Tetap gunakan nilai bawaan jika SharedPreferences belum siap di uji.
    }
  }

  Future<void> update({double? weightKg, double? heightCm}) async {
    _loadedNamespace = ActiveAccountScope.storageNamespace();
    _weightKg = (weightKg != null && weightKg >= 25 && weightKg <= 250)
        ? weightKg
        : _weightKg;
    _heightCm = (heightCm != null && heightCm >= 100 && heightCm <= 240)
        ? heightCm
        : _heightCm;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_weightKg != null) {
        await prefs.setDouble(
          ActiveAccountScope.namespacedKey(_weightKey),
          _weightKg!,
        );
      }
      if (_heightCm != null) {
        await prefs.setDouble(
          ActiveAccountScope.namespacedKey(_heightKey),
          _heightCm!,
        );
      }
    } catch (_) {}
  }

  /// Mengosongkan metrik fisik di memori lalu memuat data milik akun aktif.
  Future<void> resetForAccountChange() async {
    _weightKg = null;
    _heightCm = null;
    _loaded = false;
    _loadedNamespace = null;
    notifyListeners();
    await load();
  }

  /// Hanya untuk pengujian agar state dapat diatur ulang.
  @visibleForTesting
  void setForTesting({double? weightKg, double? heightCm}) {
    _loaded = true;
    _weightKg = weightKg;
    _heightCm = heightCm;
    notifyListeners();
  }
}

/// Dialog ringkas untuk mengisi berat dan tinggi badan pengguna.
Future<void> showBodyMetricsDialog(
  BuildContext context, {
  BodyMetricsStore? store,
}) async {
  final target = store ?? BodyMetricsStore.instance;
  await target.load();
  if (!context.mounted) return;
  final weightController = TextEditingController(
    text: target.weightKg?.round().toString() ?? '',
  );
  final heightController = TextEditingController(
    text: target.heightCm?.round().toString() ?? '',
  );

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Data fisik pendaki'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const ValueKey('body-weight-input'),
            controller: weightController,
            maxLength: 5,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Berat badan (kg)',
              hintText: '65',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('body-height-input'),
            controller: heightController,
            maxLength: 5,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tinggi badan (cm)',
              hintText: '170',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey('body-metrics-save'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  if (saved == true) {
    final w = double.tryParse(weightController.text.trim().replaceAll(',', '.'));
    final h = double.tryParse(heightController.text.trim().replaceAll(',', '.'));
    await target.update(weightKg: w, heightCm: h);
  }
  weightController.dispose();
  heightController.dispose();
}

