import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

const appDatabaseFileName = 'nama_app.sqlite';

AppDatabase openAppDatabase(File file) =>
    AppDatabase(NativeDatabase.createInBackground(file));

AppDatabase openInMemoryAppDatabase() => AppDatabase(NativeDatabase.memory());

/// Lokasi DB yang sama dipakai isolate utama dan TaskHandler Android.
Future<File> defaultAppDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File(p.join(dir.path, appDatabaseFileName));
}

Future<AppDatabase> openDefaultAppDatabase() async =>
    openAppDatabase(await defaultAppDatabaseFile());
