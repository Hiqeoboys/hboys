import 'package:flutter/material.dart';

import '../../core/constants/emergency_numbers.dart';
import '../auth/presentation/account_page.dart';
import '../map/presentation/map_page.dart';
import '../onboarding/permission_onboarding_page.dart';
import '../tracking/presentation/tracking_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nama Aplikasi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.emergency_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Darurat: Basarnas ${EmergencyNumbers.basarnas}, '
                      'terpadu ${EmergencyNumbers.unified}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.route_outlined,
            title: 'Rekam Perjalanan',
            subtitle:
                'Catat GPS, jarak, elevasi, dan profil daya. Sesi yang terputus '
                'dapat dilanjutkan.',
            actionLabel: 'Buka rekam',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TrackingPage()),
            ),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.map_outlined,
            title: 'Peta & Offline',
            subtitle:
                'Peta Mapbox, unduhan area per gunung, layer jalur dan jejak, '
                'kompas, serta deteksi keluar jalur.',
            actionLabel: 'Buka peta',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => MapPage()),
            ),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.battery_saver_outlined,
            title: 'Izin & Baterai',
            subtitle:
                'Langkah izin lokasi latar belakang dan panduan penghematan '
                'baterai per merek Android.',
            actionLabel: 'Buka panduan',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PermissionOnboardingPage(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.group_outlined,
            title: 'Akun & Grup',
            subtitle:
                'Masuk dengan Google/Apple, pilih username, terima undangan, '
                'dan kelola kunci grup. Memerlukan internet dan konfigurasi '
                'Supabase.',
            actionLabel: 'Buka akun',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => AccountPage()),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Rekaman GPS bergantung pada izin perangkat, kebijakan baterai '
            'merek, dan kualitas sinyal. Perilaku latar belakang wajib diuji '
            'di perangkat nyata sebelum dipakai di lapangan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
