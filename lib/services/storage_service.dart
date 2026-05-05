import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../models/reading_history.dart';

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
  static const _readingHistoryKey = '${_prefix}readingHistory';
  static const _shelfCacheKey = '${_prefix}shelfCache';
  static const _suggestionsCacheKey = '${_prefix}suggestionsCache';

  static const _maxReadingHistorySize = 50;
  // Shelf cache expires after 24 hours (expressed in milliseconds).
  static const _shelfCacheMaxAgeMs = 24 * 60 * 60 * 1000;

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

  // ── Reading history ─────────────────────────────────────────────────────────

  Future<List<ReadingEvent>> getReadingHistory() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_readingHistoryKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => ReadingEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addReadingEvent(ReadingEvent event) async {
    final existing = await getReadingHistory();
    // Deduplicate: move existing entry for the same book to the front.
    final deduped = existing.where((e) => e.bookId != event.bookId).toList();
    final updated = [event, ...deduped].take(_maxReadingHistorySize).toList();
    final prefs = await _prefs;
    await prefs.setString(
        _readingHistoryKey, json.encode(updated.map((e) => e.toJson()).toList()));
  }

  // ── Shelf cache ─────────────────────────────────────────────────────────────

  /// Returns cached books for [topic] if they were stored less than 24 h ago.
  Future<List<Book>?> getShelfCache(String topic) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_shelfCacheKey);
    if (raw == null) return null;
    final map = json.decode(raw) as Map<String, dynamic>;
    final entry = map[topic] as Map<String, dynamic>?;
    if (entry == null) return null;
    final cachedAt = entry['cachedAt'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - cachedAt > _shelfCacheMaxAgeMs) {
      return null;
    }
    final bookList = entry['books'] as List<dynamic>? ?? [];
    return bookList
        .map((b) => Book.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveShelfCache(String topic, List<Book> books) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_shelfCacheKey);
    final map =
        raw != null ? json.decode(raw) as Map<String, dynamic> : <String, dynamic>{};
    map[topic] = {
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'books': books.map((b) => b.toJson()).toList(),
    };
    await prefs.setString(_shelfCacheKey, json.encode(map));
  }

  // ── Suggestions cache ────────────────────────────────────────────────────────

  Future<List<SuggestionGroup>> getCachedSuggestions() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_suggestionsCacheKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => SuggestionGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCachedSuggestions(List<SuggestionGroup> groups) async {
    final prefs = await _prefs;
    await prefs.setString(
        _suggestionsCacheKey,
        json.encode(groups.map((g) => g.toJson()).toList()));
  }
}
