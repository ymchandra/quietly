import 'package:flutter/foundation.dart';
import '../models/reader_settings.dart';
import '../services/storage_service.dart';

class ReaderSettingsProvider extends ChangeNotifier {
  final _storage = StorageService();
  StoredReaderSettings _settings = StoredReaderSettings.defaults();

  StoredReaderSettings get settings => _settings;

  Future<void> init() async {
    _settings = await _storage.getReaderSettings();
  }

  ReaderSettings forBook(int bookId) => _settings.forBook(bookId);

  Future<void> updateGlobal(ReaderSettings s) async {
    _settings = _settings.withGlobal(s);
    await _storage.saveReaderSettings(_settings);
    notifyListeners();
  }

  Future<void> updateForBook(int bookId, Map<String, dynamic> overrides) async {
    _settings = _settings.withBookOverride(bookId, overrides);
    await _storage.saveReaderSettings(_settings);
    notifyListeners();
  }
}
