import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

import 'suraksharide_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop = !kIsWeb && {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);

  if (isDesktop) {
    sqflite_ffi.sqfliteFfiInit();
    sqflite.databaseFactory = sqflite_ffi.databaseFactoryFfi;
  }

  runApp(const SurakshaRideApp());
}
