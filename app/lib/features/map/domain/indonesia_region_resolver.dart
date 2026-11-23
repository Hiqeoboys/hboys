class _RegionBox {
  const _RegionBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.label,
  });

  final double south;
  final double west;
  final double north;
  final double east;
  final String label;

  bool contains(double lat, double lon) =>
      lat >= south && lat <= north && lon >= west && lon <= east;
}

/// Menentukan label wilayah (Kabupaten/Provinsi/Pulau di Indonesia) secara
/// 100% offline dari koordinat GPS titik awal jalur GPX, disertai fallback
/// `<region>` dan `<desc>` pada metadata GPX.
class IndonesiaRegionResolver {
  const IndonesiaRegionResolver._();

  static const List<_RegionBox> _specificZones = <_RegionBox>[
    // Jawa Barat
    _RegionBox(
      south: -7.42,
      west: 107.68,
      north: -7.08,
      east: 108.05,
      label: 'Garut, Jawa Barat',
    ),
    _RegionBox(
      south: -6.98,
      west: 108.30,
      north: -6.82,
      east: 108.50,
      label: 'Kuningan, Jawa Barat',
    ),
    _RegionBox(
      south: -6.88,
      west: 106.88,
      north: -6.68,
      east: 107.12,
      label: 'Cianjur, Jawa Barat',
    ),
    _RegionBox(
      south: -7.25,
      west: 107.25,
      north: -6.70,
      east: 107.75,
      label: 'Bandung, Jawa Barat',
    ),
    // Jawa Tengah
    _RegionBox(
      south: -7.44,
      west: 109.85,
      north: -7.14,
      east: 110.16,
      label: 'Wonosobo, Jawa Tengah',
    ),
    _RegionBox(
      south: -7.60,
      west: 110.34,
      north: -7.40,
      east: 110.55,
      label: 'Boyolali, Jawa Tengah',
    ),
    _RegionBox(
      south: -7.32,
      west: 109.12,
      north: -7.16,
      east: 109.36,
      label: 'Purbalingga, Jawa Tengah',
    ),
    _RegionBox(
      south: -7.72,
      west: 111.08,
      north: -7.56,
      east: 111.26,
      label: 'Karanganyar, Jawa Tengah',
    ),
    // Jawa Timur
    _RegionBox(
      south: -8.18,
      west: 112.82,
      north: -7.88,
      east: 113.06,
      label: 'Lumajang, Jawa Timur',
    ),
    _RegionBox(
      south: -7.96,
      west: 112.38,
      north: -7.66,
      east: 112.74,
      label: 'Malang, Jawa Timur',
    ),
    _RegionBox(
      south: -8.28,
      west: 113.45,
      north: -7.88,
      east: 114.38,
      label: 'Banyuwangi, Jawa Timur',
    ),
    // Sumatera
    _RegionBox(
      south: -1.86,
      west: 101.16,
      north: -1.58,
      east: 101.38,
      label: 'Kerinci, Jambi',
    ),
    _RegionBox(
      south: -4.18,
      west: 103.02,
      north: -3.92,
      east: 103.24,
      label: 'Pagar Alam, Sumatera Selatan',
    ),
    _RegionBox(
      south: -1.15,
      west: 100.22,
      north: -0.25,
      east: 100.78,
      label: 'Sumatera Barat',
    ),
    _RegionBox(
      south: 3.05,
      west: 98.28,
      north: 3.35,
      east: 98.62,
      label: 'Karo, Sumatera Utara',
    ),
    // Bali & Nusa Tenggara
    _RegionBox(
      south: -8.52,
      west: 116.32,
      north: -8.26,
      east: 116.62,
      label: 'Lombok Timur, Nusa Tenggara Barat',
    ),
    _RegionBox(
      south: -8.40,
      west: 117.88,
      north: -8.12,
      east: 118.18,
      label: 'Dompu, Nusa Tenggara Barat',
    ),
    _RegionBox(
      south: -8.65,
      west: 114.95,
      north: -8.10,
      east: 115.72,
      label: 'Bali',
    ),
    // Sulawesi
    _RegionBox(
      south: -5.58,
      west: 119.75,
      north: -3.20,
      east: 120.32,
      label: 'Sulawesi Selatan',
    ),
    _RegionBox(
      south: 1.02,
      west: 124.65,
      north: 1.60,
      east: 125.15,
      label: 'Sulawesi Utara',
    ),
  ];

  static const List<_RegionBox> _broadZones = <_RegionBox>[
    _RegionBox(south: -7.10, west: 105.05, north: -5.85, east: 106.45, label: 'Banten'),
    _RegionBox(south: -7.85, west: 106.45, north: -5.90, east: 108.85, label: 'Jawa Barat'),
    _RegionBox(south: -8.25, west: 108.85, north: -6.40, east: 111.65, label: 'Jawa Tengah'),
    _RegionBox(south: -8.85, west: 111.00, north: -6.75, east: 114.70, label: 'Jawa Timur'),
    _RegionBox(south: 1.80, west: 95.00, north: 5.95, east: 98.20, label: 'Aceh'),
    _RegionBox(south: -6.00, west: 95.00, north: 5.95, east: 106.05, label: 'Sumatera'),
    _RegionBox(south: -8.85, west: 114.40, north: -8.00, east: 115.75, label: 'Bali'),
    _RegionBox(south: -9.15, west: 115.75, north: -8.00, east: 119.25, label: 'Nusa Tenggara Barat'),
    _RegionBox(south: -11.05, west: 119.25, north: -8.00, east: 125.20, label: 'Nusa Tenggara Timur'),
    _RegionBox(south: -4.25, west: 108.80, north: 4.45, east: 119.00, label: 'Kalimantan'),
    _RegionBox(south: -5.85, west: 118.70, north: 2.10, east: 125.45, label: 'Sulawesi'),
    _RegionBox(south: -8.40, west: 125.45, north: 2.85, east: 135.00, label: 'Maluku'),
    _RegionBox(south: -9.20, west: 129.00, north: 0.55, east: 141.05, label: 'Papua'),
  ];

  static String resolve({
    required double lat,
    required double lon,
    String? regionHint,
    String? description,
  }) {
    final hint = regionHint?.trim();
    if (hint != null && hint.isNotEmpty) {
      return hint;
    }

    if (lat.isFinite && lon.isFinite) {
      for (final zone in _specificZones) {
        if (zone.contains(lat, lon)) return zone.label;
      }
      for (final zone in _broadZones) {
        if (zone.contains(lat, lon)) return zone.label;
      }
    }

    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) {
      final firstLine = desc.split('\n').first.trim();
      if (firstLine.isNotEmpty && firstLine.length <= 48) {
        return firstLine;
      }
    }
    return 'Indonesia';
  }
}
