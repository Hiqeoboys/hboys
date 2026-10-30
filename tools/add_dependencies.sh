#!/usr/bin/env bash
# Memasang kandidat dependensi dengan versi terbaru yang kompatibel.
# Setiap paket HARUS dinilai dulu (lisensi, perawatan, dukungan Android+iOS) di pub.dev.
set -euo pipefail
cd "$(dirname "$0")/../app"

flutter pub add \
  geolocator permission_handler flutter_compass sensors_plus pedometer \
  flutter_riverpod go_router \
  drift sqlite3_flutter_libs path_provider path \
  flutter_secure_storage shared_preferences \
  connectivity_plus battery_plus \
  flutter_foreground_task \
  flutter_local_notifications \
  record just_audio image_picker flutter_image_compress \
  share_plus \
  cryptography \
  flutter_blue_plus \
  mapbox_maps_flutter \
  supabase_flutter

flutter pub add --dev flutter_lints drift_dev build_runner
echo "Catatan: backend dipilih Supabase (2026-10-25); Firebase tidak dipakai."
