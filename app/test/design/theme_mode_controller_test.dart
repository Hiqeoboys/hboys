import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/theme_mode_controller.dart';

void main() {
  test('bawaan adalah ikuti sistem', () async {
    final controller = ThemeModeController(store: InMemoryThemeModeStore());
    expect(controller.mode, ThemeMode.system);
    await controller.load();
    expect(controller.mode, ThemeMode.system);
  });

  test('pilihan disimpan dan pendengar diberi tahu', () async {
    final store = InMemoryThemeModeStore();
    final controller = ThemeModeController(store: store);
    int notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMode(ThemeMode.dark);
    expect(controller.mode, ThemeMode.dark);
    expect(store.mode, ThemeMode.dark);
    expect(store.writes, 1);
    expect(notifications, 1);

    await controller.setMode(ThemeMode.dark);
    expect(store.writes, 1, reason: 'nilai sama tidak ditulis ulang');
    expect(notifications, 1);
  });

  test('pilihan tersimpan dibaca kembali saat mulai', () async {
    final store = InMemoryThemeModeStore(ThemeMode.light);
    final controller = ThemeModeController(store: store);
    await controller.load();
    expect(controller.mode, ThemeMode.light);
  });

  test('nama mode dipetakan dua arah', () {
    expect(themeModeFromName('light'), ThemeMode.light);
    expect(themeModeFromName('dark'), ThemeMode.dark);
    expect(themeModeFromName(null), ThemeMode.system);
    expect(themeModeFromName('acak'), ThemeMode.system);
    expect(ThemeMode.dark.name, 'dark');
  });
}
