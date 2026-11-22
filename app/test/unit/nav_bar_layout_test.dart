import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/typography.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/design/widgets/nav_bar_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final items = <HiqeoNavBarItem>[
    HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
    HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
    HiqeoNavBarItem(
      label: 'Track',
      icon: HiqeoIcons.activity,
      route: '/lacak',
    ),
    HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
    HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
  ];

  const screenWidths = <double>[320.0, 360.0, 412.0];
  const labelStyle = TextStyle(
    fontFamily: HiqeoTypography.family,
    fontSize: 12.0,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  group('NavBarLayout Unit Tests (5 tab tanpa slot logo)', () {
    for (final screenWidth in screenWidths) {
      final pillWidth = screenWidth - 32.0;
      final expectedInnerW = pillWidth - 10.0;

      group(
        'Layar $screenWidth dp (pillWidth: $pillWidth dp, innerW: $expectedInnerW dp)',
        () {
          for (int tabIndex = 0; tabIndex < 5; tabIndex++) {
            final tabLabel = items[tabIndex].label;

            test(
              'Tab aktif $tabIndex ($tabLabel): innerW = pill - 10, wA = 16+24+6+label+16, wI = (innerW-wA)/4',
              () {
                final layout = computeNavBarLayout(
                  pillWidth: pillWidth,
                  activeTabIndex: tabIndex,
                  items: items,
                  labelStyle: labelStyle,
                );

                expect(layout.innerW, closeTo(expectedInnerW, 0.001));
                expect(layout.slots.length, 5);
                expect(layout.activeSlotIndex, tabIndex);
                expect(layout.slots[tabIndex].isActive, isTrue);
                expect(layout.slots[tabIndex].index, tabIndex);
                expect(layout.slots[tabIndex].width, closeTo(layout.wA, 0.001));

                // Jumlah lebar semua slot tepat sama dengan innerW
                final totalWidth = layout.slots.fold<double>(
                  0.0,
                  (sum, slot) => sum + slot.width,
                );
                expect(totalWidth, closeTo(expectedInnerW, 0.001));

                // Semua tab tidak aktif memiliki lebar wI = (innerW - wA) / 4
                expect(
                  layout.wI,
                  closeTo((expectedInnerW - layout.wA) / 4.0, 0.001),
                );
                for (int i = 0; i < 5; i++) {
                  if (i != tabIndex) {
                    expect(layout.slots[i].isActive, isFalse);
                    expect(layout.slots[i].width, closeTo(layout.wI, 0.001));
                  }
                }

                // Lensa mengikuti slot aktif secara presisi
                expect(layout.lensLeft, layout.slots[tabIndex].left);
                expect(layout.lensWidth, layout.slots[tabIndex].width);
                expect(layout.lensCenter, layout.slots[tabIndex].center);

                // Minimal wI >= 44 dp bila lebar layar mencukupi, atau padding diperkecil ke 12 dp
                if (layout.reducedPadding) {
                  expect(layout.slots[tabIndex].hPadding, 12.0);
                } else {
                  expect(layout.slots[tabIndex].hPadding, 16.0);
                  expect(layout.wI, greaterThanOrEqualTo(44.0));
                }
              },
            );
          }
        },
      );
    }

    test('Tab Track di indeks 2 (tengah) menjadi tab interaktif biasa', () {
      final layout = computeNavBarLayout(
        pillWidth: 360.0 - 32.0,
        activeTabIndex: 2,
        items: items,
        labelStyle: labelStyle,
      );
      expect(layout.slots.length, 5);
      expect(layout.activeSlotIndex, 2);
      expect(layout.slots[2].index, 2);
      expect(layout.slots[2].isActive, isTrue);
      expect(layout.wI, greaterThanOrEqualTo(44.0));
    });
  });
}
