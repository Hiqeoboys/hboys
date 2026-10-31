import 'package:flutter/material.dart';

import '../../../../design/app_theme.dart';
import '../../../../design/gooey/gooey_switch.dart';
import '../../../../design/tokens.dart';
import '../../../../design/typography.dart';
import '../../../../design/widgets/hiqeo_button.dart';
import '../../../../design/widgets/line_icons.dart';
import 'plus_widgets.dart';

/// Panel persetujuan papan nasional.
///
/// Selalu memakai kaca terang di atas papan yang diredupkan, sesuai rancangan
/// D9, apa pun tema halaman saat itu. Mengembalikan `true` bila nama boleh
/// tampil, `false` bila disembunyikan, dan `null` bila panel ditutup tanpa
/// menyimpan.
Future<bool?> showLeaderboardConsentSheet(
  BuildContext context, {
  required String displayName,
  required bool? storedVisible,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: HiqeoColors.light.primary.withValues(alpha: 0.55),
    builder: (sheetContext) => Theme(
      data: buildHiqeoTheme(HiqeoColors.light),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HiqeoSpacing.md),
          child: _ConsentSheet(
            displayName: displayName,
            storedVisible: storedVisible,
          ),
        ),
      ),
    ),
  );
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({
    required this.displayName,
    required this.storedVisible,
  });

  final String displayName;
  final bool? storedVisible;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  late bool _visible;

  bool get _firstTime => widget.storedVisible == null;

  @override
  void initState() {
    super.initState();
    // Saklar mulai mati karena umur belum diverifikasi. Pengguna menyalakannya
    // sendiri bila ingin namanya tampil.
    _visible = widget.storedVisible ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      radius: HiqeoRadius.hero,
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.xl,
        HiqeoSpacing.md,
        HiqeoSpacing.xl,
        HiqeoSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(HiqeoRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(
            _firstTime ? 'Ikut Leaderboard Nasional?' : 'Papan nasional',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Hanya pengguna Plus yang bersaing. Semua orang bisa melihat '
            'papannya.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _FactsColumn(
                  title: 'YANG TAMPIL',
                  items: <_Fact>[
                    _Fact(
                      text: 'Nama profil: ${widget.displayName}',
                      shown: true,
                    ),
                    const _Fact(text: 'Gunung dan angka', shown: true),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              const Expanded(
                child: _FactsColumn(
                  title: 'TIDAK TAMPIL',
                  items: <_Fact>[
                    _Fact(text: 'Titik awal', shown: false),
                    _Fact(text: 'Jalur lengkap', shown: false),
                    _Fact(text: 'Tanggal selain bulan', shown: false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Divider(color: colors.hairline, height: 1),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Tampilkan saya di papan',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              GooeySwitch(
                key: const ValueKey('leaderboard-consent-switch'),
                value: _visible,
                semanticsLabel: 'Tampilkan saya di papan',
                onChanged: (value) => setState(() => _visible = value),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Bisa ditarik kapan saja di Profil. Pengguna di bawah 18 tahun '
            'tidak tampil secara default. Setiap baris punya tombol laporkan '
            'dan blokir.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          HiqeoButton(
            key: const ValueKey('leaderboard-consent-agree'),
            label: _firstTime ? 'Setuju dan ikut' : 'Simpan pengaturan',
            onPressed: () => Navigator.of(context).pop(_visible),
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Center(
            child: TextButton(
              key: const ValueKey('leaderboard-consent-hide'),
              onPressed: () => Navigator.of(context).pop(
                _firstTime ? false : null,
              ),
              child: Text(
                _firstTime ? 'Tidak tampilkan saya' : 'Tutup',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact {
  const _Fact({required this.text, required this.shown});

  final String text;
  final bool shown;
}

class _FactsColumn extends StatelessWidget {
  const _FactsColumn({required this.title, required this.items});

  final String title;
  final List<_Fact> items;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: HiqeoTypography.overline(colors.textSecondary),
        ),
        const SizedBox(height: HiqeoSpacing.xs),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: HiqeoIcon(
                    item.shown ? HiqeoIcons.check : HiqeoIcons.close,
                    size: 14,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: HiqeoSpacing.xs),
                Expanded(
                  child: Text(
                    item.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
