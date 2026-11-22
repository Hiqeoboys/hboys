import 'package:flutter/foundation.dart';

/// Konstanta tunggal untuk menyembunyikan navbar di seluruh layar peta rute.
///
/// Secara baku `true`: navbar tetap tampil di daftar peta (`/peta`) dan hanya
/// disembunyikan saat pengguna masuk ke halaman Peta Gunung yang Dipilih.
const bool kHideNavbarOnRouteScreen = true;

/// Mengatur visibilitas bottom navbar secara terpusat.
///
/// Navbar disembunyikan otomatis saat pengguna masuk ke Ruang Obrolan /
/// Lokasi Terakhir, saat memulai tracking rute pada layar Peta, atau pada
/// seluruh layar peta rute bila [kHideNavbarOnRouteScreen] disetel `true`.
class NavBarVisibilityController extends ChangeNotifier {
  NavBarVisibilityController._();

  static final NavBarVisibilityController instance =
      NavBarVisibilityController._();

  bool _hiddenInRoomChat = false;
  bool _hiddenInMapTracking = false;
  bool _onRouteScreen = false;

  bool get hiddenInRoomChat => _hiddenInRoomChat;
  bool get hiddenInMapTracking => _hiddenInMapTracking;
  bool get onRouteScreen => _onRouteScreen;

  bool get isHidden =>
      _hiddenInRoomChat ||
      _hiddenInMapTracking ||
      (kHideNavbarOnRouteScreen && _onRouteScreen);

  void setRoomChatOpen(bool open) {
    if (_hiddenInRoomChat == open) return;
    _hiddenInRoomChat = open;
    notifyListeners();
  }

  void setMapTrackingActive(bool active) {
    if (_hiddenInMapTracking == active) return;
    _hiddenInMapTracking = active;
    notifyListeners();
  }

  void setRouteScreenOpen(bool open) {
    if (_onRouteScreen == open) return;
    _onRouteScreen = open;
    notifyListeners();
  }

  void reset() {
    if (!_hiddenInRoomChat && !_hiddenInMapTracking && !_onRouteScreen) return;
    _hiddenInRoomChat = false;
    _hiddenInMapTracking = false;
    _onRouteScreen = false;
    notifyListeners();
  }
}
