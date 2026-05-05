import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/library_provider.dart';
import 'providers/reader_settings_provider.dart';
import 'providers/suggestions_provider.dart';
import 'providers/user_profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = LibraryProvider();
  final readerSettings = ReaderSettingsProvider();
  final userProfile = UserProfileProvider();
  final suggestions = SuggestionsProvider();
  await Future.wait([
    library.init(),
    readerSettings.init(),
    userProfile.init(),
    suggestions.init(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: readerSettings),
        ChangeNotifierProvider.value(value: userProfile),
        ChangeNotifierProvider.value(value: suggestions),
      ],
      child: QuietlyApp(userProfile: userProfile),
    ),
  );
}
