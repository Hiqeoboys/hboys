#!/usr/bin/env bash
# Membuat folder android/ios, memasang dependensi, dan mengunduh paket.
# Jalankan dari mana saja: ./tools/bootstrap.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

( cd "$ROOT/packages/mesh_protocol" && dart pub get )
( cd "$ROOT/packages/geo_utils" && dart pub get )

cd "$ROOT/app"

# `flutter create` bisa menimpa main.dart dan menambah tes bawaan yang merujuk
# ke MyApp. Cadangkan lalu pulihkan agar kerangka kita tetap utuh.
BACKUP="$(mktemp -d)"
cp lib/main.dart "$BACKUP/main.dart"
flutter create . --org id.nama --project-name nama_app --platforms=android,ios
cp "$BACKUP/main.dart" lib/main.dart
rm -f test/widget_test.dart
rm -rf "$BACKUP"

"$ROOT/tools/add_dependencies.sh"
flutter pub get
echo "Selesai. Jalankan ./tools/test_all.sh untuk memastikan semua tes lolos."
