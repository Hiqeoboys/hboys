import 'package:flutter/material.dart';

import '../typography.dart';
import 'hiqeo_nav_bar.dart';

/// Konfigurasi dan hasil perhitungan tata letak navbar lima tab lensa kaca.
@immutable
class NavBarSlotLayout {
  const NavBarSlotLayout({
    required this.index,
    required this.isActive,
    required this.left,
    required this.width,
    required this.iconXInSlot,
    required this.labelXInSlot,
    required this.labelWidth,
    required this.hPadding,
  });

  /// Indeks slot (0..4): 0 = Beranda, 1 = Peta, 2 = Track, 3 = Grup, 4 = Profil.
  final int index;

  /// Apakah slot ini adalah tab yang sedang aktif.
  final bool isActive;

  /// Posisi kiri slot relatif terhadap sisi kiri pill navbar (termasuk padding 5 dp).
  final double left;

  /// Lebar slot.
  final double width;

  /// Posisi x ikon di dalam slot.
  final double iconXInSlot;

  /// Posisi awal x label di dalam slot aktif.
  final double labelXInSlot;

  /// Lebar teks label yang diukur.
  final double labelWidth;

  /// Padding horizontal slot aktif (16 atau 12 dp).
  final double hPadding;

  /// Posisi tengah slot relatif terhadap pill navbar.
  double get center => left + width / 2.0;
}

@immutable
class NavBarLayout {
  const NavBarLayout({
    required this.pillWidth,
    required this.innerW,
    required this.activeTabIndex,
    required this.activeSlotIndex,
    required this.slots,
    required this.wA,
    required this.wI,
    required this.lensLeft,
    required this.lensWidth,
    required this.lensCenter,
    required this.reducedPadding,
  });

  final double pillWidth;
  final double innerW;

  /// Indeks tab yang aktif (0..4).
  final int activeTabIndex;

  /// Indeks slot aktif (sama dengan [activeTabIndex] pada tata letak 5 tab).
  final int activeSlotIndex;

  /// Daftar kelima slot [Beranda, Peta, Track, Grup, Profil].
  final List<NavBarSlotLayout> slots;

  /// Lebar slot tab aktif.
  final double wA;

  /// Lebar slot tab tidak aktif.
  final double wI;

  /// Posisi kiri lensa (mengikuti slot aktif).
  final double lensLeft;

  /// Lebar lensa (penuh slot aktif).
  final double lensWidth;

  /// Titik tengah lensa.
  final double lensCenter;

  /// Apakah padding tab aktif dikurangi menjadi 12 dp karena wI < 44 dp.
  final bool reducedPadding;

  /// Mengambil slot berdasarkan indeks slot (0..4).
  NavBarSlotLayout slotAt(int slotIndex) => slots[slotIndex];

  /// Mengambil slot berdasarkan indeks tab (0..4).
  NavBarSlotLayout tabSlotAt(int tabIndex) => slots[tabIndex];
}

/// Menghitung tata letak navbar lima tab lensa kaca berdasarkan lebar pill dan
/// tab yang aktif.
///
/// Algoritma lebar:
/// - `innerW = pillWidth - 10`
/// - `wA = 16 + 24 + 6 + lebarLabel + 16`
/// - `wI = (innerW - wA) / 4`, minimal 44 dp (kurangi padding ke 12 dp bila < 44)
NavBarLayout computeNavBarLayout({
  required double pillWidth,
  required int activeTabIndex,
  required List<HiqeoNavBarItem> items,
  TextStyle? labelStyle,
}) {
  assert(
    items.length == 5,
    'NavBar lensa kaca membutuhkan tepat 5 tab aktif.',
  );
  assert(
    activeTabIndex >= 0 && activeTabIndex < items.length,
    'Indeks tab aktif di luar rentang.',
  );

  const double pillPaddingHorizontal = 5.0;
  const double iconSize = 24.0;
  const double iconLabelGap = 6.0;
  const double minSlotWidth = 44.0;

  final innerW = pillWidth - (pillPaddingHorizontal * 2.0);

  final resolvedLabelStyle = labelStyle ??
      const TextStyle(
        fontFamily: HiqeoTypography.family,
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  // Ukur lebar teks label untuk tab aktif dengan TextPainter.
  final textPainter = TextPainter(
    text: TextSpan(
      text: items[activeTabIndex].label,
      style: resolvedLabelStyle,
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final labelWidth = textPainter.width;

  const double inactiveCount = 4.0;

  // Coba padding horizontal 16 dp terlebih dahulu.
  double hPadding = 16.0;
  double wA = hPadding + iconSize + iconLabelGap + labelWidth + hPadding;
  double wI = (innerW - wA) / inactiveCount;
  bool reduced = false;

  // Jika wI < 44 dp, kurangi padding horizontal tab aktif dari 16 menjadi 12 dp.
  if (wI < minSlotWidth) {
    hPadding = 12.0;
    wA = hPadding + iconSize + iconLabelGap + labelWidth + hPadding;
    wI = (innerW - wA) / inactiveCount;
    reduced = true;
  }

  final slots = <NavBarSlotLayout>[];
  double currentLeft = pillPaddingHorizontal;

  for (int slotIndex = 0; slotIndex < 5; slotIndex++) {
    final isActive = slotIndex == activeTabIndex;
    final double slotWidth = isActive ? wA : wI;
    final double iconX = isActive ? hPadding : (wI - iconSize) / 2.0;
    final double labelX = isActive ? hPadding + iconSize + iconLabelGap : 0.0;

    slots.add(
      NavBarSlotLayout(
        index: slotIndex,
        isActive: isActive,
        left: currentLeft,
        width: slotWidth,
        iconXInSlot: iconX,
        labelXInSlot: labelX,
        labelWidth: isActive ? labelWidth : 0.0,
        hPadding: isActive ? hPadding : 0.0,
      ),
    );

    currentLeft += slotWidth;
  }

  final activeSlot = slots[activeTabIndex];

  return NavBarLayout(
    pillWidth: pillWidth,
    innerW: innerW,
    activeTabIndex: activeTabIndex,
    activeSlotIndex: activeTabIndex,
    slots: slots,
    wA: wA,
    wI: wI,
    lensLeft: activeSlot.left,
    lensWidth: activeSlot.width,
    lensCenter: activeSlot.center,
    reducedPadding: reduced,
  );
}
