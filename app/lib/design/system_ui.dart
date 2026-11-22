import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gaya bilah sistem transparan untuk aplikasi edge-to-edge.
///
/// Ikon status dan navigasi mengikuti [brightness]: latar terang memakai ikon
/// gelap, latar gelap memakai ikon terang. Di layar Peta, [brightness] diambil
/// dari tema aktif karena peredup navy membuat peta mode gelap lebih gelap.
SystemUiOverlayStyle hiqeoOverlayStyle(Brightness brightness) {
  final lightIcons = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
    // iOS memakai kebalikan dari Android: terang berarti ikon gelap.
    statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        lightIcons ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Memasang [hiqeoOverlayStyle] untuk seluruh isi layar di bawahnya.
class HiqeoSystemUiRegion extends StatelessWidget {
  const HiqeoSystemUiRegion({
    super.key,
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: hiqeoOverlayStyle(brightness),
        child: child,
      );
}

/// Inset sistem bawah mentah (gestur atau tombol navigasi) dari kerangka tab.
///
/// Di dalam [Scaffold] ber-`extendBody`, padding bawah `MediaQuery` sudah
/// dinaikkan setinggi navbar dan `viewPadding` bawah dibuang oleh Scaffold
/// karena ada navigasi bawah. Kerangka tab menaruh nilai mentahnya di sini
/// supaya layar Peta bisa menghitung jarak di atas navbar dengan tepat.
class HiqeoSystemInset extends InheritedWidget {
  const HiqeoSystemInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static bool isPresent(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HiqeoSystemInset>() != null;

  static double bottomOf(BuildContext context) {
    final inset = context.dependOnInheritedWidgetOfExactType<HiqeoSystemInset>();
    return inset?.bottom ?? MediaQuery.viewPaddingOf(context).bottom;
  }

  @override
  bool updateShouldNotify(HiqeoSystemInset oldWidget) =>
      oldWidget.bottom != bottom;
}

