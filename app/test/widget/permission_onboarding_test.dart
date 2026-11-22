import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/system_ui.dart';
import 'package:nama_app/features/onboarding/permission_onboarding_page.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';

class _FakePermissionService extends PermissionService {
  _FakePermissionService({required this.initial, required this.after});

  final PermissionReport initial;
  final PermissionReport after;
  int coreRequests = 0;

  @override
  Future<PermissionReport> check() async => initial;

  @override
  Future<PermissionReport> requestCore() async {
    coreRequests++;
    return after;
  }
}

void main() {
  testWidgets('menampilkan status izin dan panduan merek', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakePermissionService(
      initial: const PermissionReport(
        notificationGranted: false,
        locationWhileInUse: false,
        locationAlways: false,
        locationServiceEnabled: false,
        preciseLocation: false,
        ignoringBatteryOptimizations: false,
      ),
      after: const PermissionReport(
        notificationGranted: true,
        locationWhileInUse: true,
        locationAlways: true,
        locationServiceEnabled: true,
        preciseLocation: true,
        ignoringBatteryOptimizations: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PermissionOnboardingPage(
          service: service,
          supportedPlatform: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Izin belum lengkap'), findsOneWidget);
    expect(find.text('Aktifkan izin dasar'), findsOneWidget);
    expect(find.text('Xiaomi / Redmi / POCO (MIUI/HyperOS)'), findsOneWidget);
    expect(
      find.textContaining('Nama menu bisa sedikit berbeda'),
      findsOneWidget,
    );

    await tester.tap(find.text('Aktifkan izin dasar'));
    await tester.pumpAndSettle();

    expect(service.coreRequests, 1);
    expect(find.textContaining('Izin siap. Rekaman dapat berjalan'),
        findsOneWidget);
    expect(find.textContaining('Dikecualikan dari optimasi baterai'),
        findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('padding bawah ListView memperhitungkan tinggi navbar melayang',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final service = _FakePermissionService(
      initial: const PermissionReport(
        notificationGranted: true,
        locationWhileInUse: true,
        locationAlways: true,
        locationServiceEnabled: true,
        preciseLocation: true,
        ignoringBatteryOptimizations: true,
      ),
      after: const PermissionReport(
        notificationGranted: true,
        locationWhileInUse: true,
        locationAlways: true,
        locationServiceEnabled: true,
        preciseLocation: true,
        ignoringBatteryOptimizations: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HiqeoSystemInset(
          bottom: 24,
          child: PermissionOnboardingPage(
            service: service,
            supportedPlatform: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = listView.padding! as EdgeInsets;
    // 64 (tinggi navbar) + 12 (margin bawah) + 24 (system inset) + 16 (ruang napas) = 116
    expect(padding.bottom, 116);
    debugDefaultTargetPlatformOverride = null;
  });
}
