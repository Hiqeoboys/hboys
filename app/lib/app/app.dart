import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../features/home/home_page.dart';

class NamaApp extends StatelessWidget {
  const NamaApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nama Aplikasi',
      debugShowCheckedModeBanner: config.flavor != Flavor.prod,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
      ),
      // TODO(tim): ganti dengan MaterialApp.router (go_router) + lokalisasi.
      home: const HomePage(),
    );
  }
}
