import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/library_provider.dart';
import 'providers/reader_settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = LibraryProvider();
  final readerSettings = ReaderSettingsProvider();
  await Future.wait([
    library.init(),
    readerSettings.init(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: readerSettings),
      ],
      child: const QuietlyApp(),
    ),
  );
}
