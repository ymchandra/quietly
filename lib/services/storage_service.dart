import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';

class BookProgress {
  final double percent;
  final int updatedAt;

  const BookProgress({required this.percent, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'percent': percent,
        'updatedAt': updatedAt,
      };

  factory BookProgress.fromJson(Map<String, dynamic> json) => BookProgress(
        percent: (json['percent'] as num).toDouble(),
        updatedAt: json['updatedAt'] as int,
      );
}

class StorageService {
  static const _prefix = 'quietly:';
  static const _wishlistKey = '${_prefix}wishlist';
  static const _readLaterKey = '${_prefix}readLater';
  static const _downloadedKey = '${_prefix}downloaded';
  static const _progressKey = '${_prefix}progress';
  static const _readerSettingsKey = '${_prefix}readerSettings';
  static const _onboardingDoneKey = '${_prefix}onboardingDone';
  static const _userAgeKey = '${_prefix}userAge';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Book>> getWishlist() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_wishlistKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveWishlist(List<Book> books) async {
    final prefs = await _prefs;
    await prefs.setString(
        _wishlistKey, json.encode(books.map((b) => b.toJson()).toList()));
  }

  Future<List<Book>> getReadLater() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_readLaterKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveReadLater(List<Book> books) async {
    final prefs = await _prefs;
    await prefs.setString(
        _readLaterKey, json.encode(books.map((b) => b.toJson()).toList()));
  }

  Future<List<Book>> getDownloaded() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_downloadedKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveDownloaded(List<Book> books) async {
    final prefs = await _prefs;
    await prefs.setString(
        _downloadedKey, json.encode(books.map((b) => b.toJson()).toList()));
  }

  Future<Map<int, BookProgress>> getProgress() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_progressKey);
    if (raw == null) return {};
    final map = json.decode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(
        int.parse(k), BookProgress.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> saveProgress(Map<int, BookProgress> progress) async {
    final prefs = await _prefs;
    final map = progress.map((k, v) => MapEntry(k.toString(), v.toJson()));
    await prefs.setString(_progressKey, json.encode(map));
  }

  Future<StoredReaderSettings> getReaderSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_readerSettingsKey);
    if (raw == null) return StoredReaderSettings.defaults();
    return StoredReaderSettings.fromJson(
        json.decode(raw) as Map<String, dynamic>);
  }

  Future<void> saveReaderSettings(StoredReaderSettings settings) async {
    final prefs = await _prefs;
    await prefs.setString(_readerSettingsKey, json.encode(settings.toJson()));
  }

  Future<File> _offlineFile(int bookId) async {
    final dir = await getApplicationDocumentsDirectory();
    final booksDir = Directory('${dir.path}/books');
    if (!booksDir.existsSync()) booksDir.createSync(recursive: true);
    return File('${booksDir.path}/$bookId.txt');
  }

  Future<void> saveOfflineText(int bookId, String text) async {
    final file = await _offlineFile(bookId);
    await file.writeAsString(text, flush: true);
  }

  Future<String?> getOfflineText(int bookId) async {
    final file = await _offlineFile(bookId);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  Future<void> deleteOfflineText(int bookId) async {
    final file = await _offlineFile(bookId);
    if (file.existsSync()) await file.delete();
  }

  Future<bool> hasOfflineText(int bookId) async {
    final file = await _offlineFile(bookId);
    return file.existsSync();
  }

  Future<bool> getOnboardingDone() async {
    final prefs = await _prefs;
    return prefs.getBool(_onboardingDoneKey) ?? false;
  }

  Future<void> saveOnboardingDone(bool done) async {
    final prefs = await _prefs;
    await prefs.setBool(_onboardingDoneKey, done);
  }

  Future<int?> getUserAge() async {
    final prefs = await _prefs;
    return prefs.getInt(_userAgeKey);
  }

  Future<void> saveUserAge(int age) async {
    final prefs = await _prefs;
    await prefs.setInt(_userAgeKey, age);
  }
}
