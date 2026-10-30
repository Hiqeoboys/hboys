import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../application/kartu_exporter.dart';
import '../application/kartu_photo_picker.dart';
import '../domain/kartu_data.dart';
import 'kartu_card.dart';

/// Layar Kartu Pendakian: ringkasan sesi yang benar-benar selesai, disimpan
/// sebagai PNG transparan atau dibagikan. Tanpa sesi selesai, layar menyatakan
/// keadaan kosong dan tombol ekspor dinonaktifkan.
class KartuPage extends StatefulWidget {
  const KartuPage({
    super.key,
    this.repository,
    this.exporter = const DeviceKartuExporter(),
    this.photoPicker = const GalleryKartuPhotoPicker(),
  });

  /// Disuntikkan untuk uji; produksi membuka basis data perangkat.
  final TrackingRepository? repository;
  final KartuExporter exporter;
  final KartuPhotoPicker photoPicker;

  @override
  State<KartuPage> createState() => _KartuPageState();
}

class _KartuPageState extends State<KartuPage> {
  final GlobalKey _boundaryKey = GlobalKey();

  AppDatabase? _database;
  bool _loading = true;
  KartuData? _data;
  String? _loadError;
  KartuStyle _style = KartuStyle.profil;
  bool _hideEndpoints = false;
  Uint8List? _photoBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final database = _database;
    if (database != null) unawaited(database.close());
    super.dispose();
  }

  Future<TrackingRepository?> _repository() async {
    final injected = widget.repository;
    if (injected != null) return injected;
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return null;
      }
      _database = database;
      return DriftTrackingRepository(database);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repository = await _repository();
    if (!mounted) return;
    if (repository == null) {
      setState(() {
        _loading = false;
        _loadError = 'Data pendakian lokal belum dapat dibuka.';
      });
      return;
    }
    try {
      final sessions = await repository.watchSessions().first;
      final completed = sessions
          .where((session) => session.status == TrackingSessionStatus.completed)
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
      if (completed.isEmpty) {
        setState(() {
          _loading = false;
          _data = null;
        });
        return;
      }
      final session = completed.first;
      final points = await repository.points(session.id);
      final data = KartuData.fromSession(session, points);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = data;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Data pendakian gagal dibaca dari HP ini.';
      });
    }
  }

  Future<void> _pickPhoto() async {
    final bytes = await widget.photoPicker.pick();
    if (!mounted || bytes == null) return;
    try {
      await precacheImage(MemoryImage(bytes), context);
    } catch (_) {
      // Berkas yang tidak bisa didekode tetap ditolak; kartu memakai gradasi.
      return;
    }
    if (!mounted) return;
    setState(() => _photoBytes = bytes);
  }

  String _fileName(KartuData data) {
    final local = data.startedAtUtc.toLocal();
    final stamp = '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}-'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}';
    return 'altracq-kartu-$stamp.png';
  }

  Future<Uint8List?> _capture() async {
    final bytes = await widget.exporter.capturePng(_boundaryKey);
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  Future<void> _savePng() async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    final bytes = await _capture();
    var saved = false;
    if (bytes != null) {
      saved = await widget.exporter.savePng(bytes, _fileName(data));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _showMessage(
      saved
          ? 'PNG tersimpan di Pictures/Altracq.'
          : (bytes == null
              ? 'PNG gagal dibuat. Coba lagi.'
              : 'PNG gagal disimpan. Coba Bagikan.'),
    );
  }

  Future<void> _sharePng() async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    final bytes = await _capture();
    var opened = false;
    if (bytes != null) {
      opened = await widget.exporter.sharePng(bytes, _fileName(data));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // Lembar berbagi tidak memberi tahu apakah pengguna benar-benar mengirim,
    // jadi layar tidak pernah mengklaim kartu sudah terkirim.
    if (!opened) {
      _showMessage(
        bytes == null
            ? 'PNG gagal dibuat. Coba lagi.'
            : 'Berbagi tidak tersedia di perangkat ini.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AltracqColors.of(context);
    final enabled = !_loading && _data != null && _loadError == null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: KartuCard.backgroundGradient,
          ),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: <Widget>[
                      _HeaderIconButton(
                        key: const ValueKey('kartu-close'),
                        icon: AltracqIcons.close,
                        label: 'Tutup kartu',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      _HeaderPill(
                        key: const ValueKey('kartu-photo-change'),
                        label: 'Ganti foto',
                        onTap: enabled ? () => unawaited(_pickPhoto()) : null,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AltracqRadius.hero),
                            child: _preview(theme, colors),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _panel(theme, colors, enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme, AltracqColors colors) {
    if (_loading) {
      return const ColoredBox(
        color: Color(0xFF4A5371),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFF6F3ED)),
        ),
      );
    }
    final data = _data;
    if (data != null && _loadError == null) {
      return KartuCard(
        data: data,
        style: _style,
        hideEndpoints: _hideEndpoints,
        photoBytes: _photoBytes,
      );
    }
    return _placeholder(theme);
  }

  Widget _placeholder(ThemeData theme) {
    final ink = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFFF6F3ED),
      height: 1.4,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFFF6F3ED).withValues(alpha: 0.75),
      height: 1.4,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: KartuCard.backgroundGradient),
      child: Padding(
        padding: const EdgeInsets.all(AltracqSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AltracqIcon(
              _loadError == null ? AltracqIcons.mountain : AltracqIcons.warning,
              size: 44,
              color: const Color(0xFFF6F3ED),
            ),
            const SizedBox(height: AltracqSpacing.lg),
            Text(
              _loadError != null
                  ? 'Kartu belum bisa dibuat'
                  : 'Belum ada pendakian selesai',
              textAlign: TextAlign.center,
              style: ink,
            ),
            const SizedBox(height: AltracqSpacing.sm),
            Text(
              _loadError ??
                  'Selesaikan pendakian di layar Lacak, lalu kembali ke sini '
                      'untuk membuat kartu dari data yang tersimpan.',
              textAlign: TextAlign.center,
              style: muted,
            ),
            if (_loadError != null) ...<Widget>[
              const SizedBox(height: AltracqSpacing.lg),
              _HeaderPill(
                label: 'Coba lagi',
                onTap: () => unawaited(_load()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _panel(ThemeData theme, AltracqColors colors, bool enabled) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AltracqRadius.hero),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.glassShadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final style in KartuStyle.values) ...<Widget>[
                if (style != KartuStyle.values.first)
                  const SizedBox(width: 8),
                Expanded(
                  child: _StylePill(
                    key: ValueKey<String>('kartu-style-${style.name}'),
                    label: switch (style) {
                      KartuStyle.profil => 'Profil',
                      KartuStyle.tengah => 'Tengah',
                      KartuStyle.peta => 'Peta',
                    },
                    selected: _style == style,
                    onTap: enabled
                        ? () => setState(() => _style = style)
                        : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Sembunyikan titik awal dan akhir',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Semantics(
                label: 'Sembunyikan titik awal dan akhir',
                child: Switch(
                  key: const ValueKey('kartu-hide-endpoints'),
                  value: _hideEndpoints,
                  onChanged: enabled
                      ? (value) => setState(() => _hideEndpoints = value)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _PanelButton(
                  key: const ValueKey('kartu-save'),
                  label: 'Simpan PNG',
                  background: colors.secondary,
                  foreground: colors.textPrimary,
                  onTap: enabled && !_busy ? () => unawaited(_savePng()) : null,
                ),
              ),
              const SizedBox(width: AltracqSpacing.md),
              Expanded(
                child: _PanelButton(
                  key: const ValueKey('kartu-share'),
                  label: 'Bagikan',
                  background: colors.primary,
                  foreground: colors.onPrimary,
                  onTap:
                      enabled && !_busy ? () => unawaited(_sharePng()) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AltracqIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x66F6F3ED)),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: AltracqIcon(
                icon,
                size: 20,
                color: const Color(0xFFF6F3ED),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: SizedBox(
        height: 44,
        child: Material(
          color: Colors.white.withValues(alpha: 0.08),
          shape: const StadiumBorder(
            side: BorderSide(color: Color(0x66F6F3ED)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AltracqSpacing.xl,
              ),
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFF6F3ED),
                    fontWeight: FontWeight.w500,
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

class _StylePill extends StatelessWidget {
  const _StylePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Gaya $label',
      child: SizedBox(
        height: 48,
        child: Material(
          color: selected ? colors.primary : Colors.transparent,
          shape: StadiumBorder(
            side: selected
                ? BorderSide.none
                : BorderSide(color: colors.hairline),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colors.onPrimary
                        : colors.textPrimary.withValues(alpha: enabled ? 1 : 0.5),
                    fontWeight: FontWeight.w500,
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

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: 52,
        child: Material(
          color: background.withValues(alpha: enabled ? 1 : 0.45),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground.withValues(alpha: enabled ? 1 : 0.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
