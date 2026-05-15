import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/reading_history.dart';
import '../services/openlibrary_service.dart';
import '../services/storage_service.dart';

class SuggestionsProvider extends ChangeNotifier {
  final _storage = StorageService();
  final _service = OpenLibraryService();

  static const _subjectGroupCount = 3;
  static const _authorGroupCount = 2;
  static const _booksPerGroup = 10;
  static const _noveltyRatio = 0.30;
  static const _cacheStaleMs = 12 * 60 * 60 * 1000;
  static const _minRefreshIntervalMs = 5 * 60 * 1000;
  static const _refreshPagesThreshold = 10;
  static const _refreshSecondsThreshold = 10 * 60;

  static const _starterTopics = [
    ('Quick Starters', 'fiction'),
    ('Popular Mysteries', 'mystery'),
    ('Light Adventure', 'adventure'),
  ];

  List<ReadingEvent> _history = [];
  List<SuggestionGroup> _groups = [];
  bool _loading = false;
  bool _initialized = false;
  int? _cacheTimestampMs;
  int _lastRefreshMs = 0;

  bool get isLoading => _loading;
  bool get hasHistory => _history.isNotEmpty;
  List<SuggestionGroup> get groups => List.unmodifiable(_groups);
  List<ReadingEvent> get history => List.unmodifiable(_history);

  Future<void> init() async {
    _history = await _storage.getReadingHistory();
    _groups = await _storage.getCachedSuggestions();
    _cacheTimestampMs = await _storage.getSuggestionsCacheTimestamp();
    _initialized = true;
    notifyListeners();

    unawaited(_maybeRefreshSuggestions(reason: 'init'));
  }

  /// Call whenever the user opens a book to read. Records the event and
  /// triggers a background suggestion refresh.
  Future<void> recordBookOpened(Book book) async {
    final event = ReadingEvent(
      bookId: book.id,
      bookTitle: book.title,
      authorNames: book.authors.map((a) => a.name).toList(),
      subjects: book.subjects.take(5).toList(),
      bookshelves: book.bookshelves.take(3).toList(),
      openedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.addReadingEvent(event);
    _history = await _storage.getReadingHistory();
    notifyListeners();
    unawaited(_maybeRefreshSuggestions(reason: 'book_opened'));
  }

  /// Updates the stored stats for [bookId] after a reading session ends.
  /// [pagesRead] is the number of pages turned this session; [sessionSeconds]
  /// is the elapsed time in seconds.
  Future<void> recordSessionStats(
    int bookId, {
    required int pagesRead,
    required int sessionSeconds,
  }) async {
    await _storage.updateReadingEventStats(
      bookId,
      addPages: pagesRead,
      addSeconds: sessionSeconds,
    );
    _history = await _storage.getReadingHistory();
    notifyListeners();

    if (pagesRead >= _refreshPagesThreshold ||
        sessionSeconds >= _refreshSecondsThreshold) {
      unawaited(_maybeRefreshSuggestions(reason: 'session_stats'));
    }
  }

  Future<void> _maybeRefreshSuggestions({required String reason}) async {
    if (_loading) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isStale =
        _cacheTimestampMs == null || now - _cacheTimestampMs! > _cacheStaleMs;
    final cooldownElapsed = now - _lastRefreshMs > _minRefreshIntervalMs;

    if (_groups.isEmpty || isStale || cooldownElapsed) {
      await _refreshSuggestions(reason: reason);
    }
  }

  Future<void> _refreshSuggestions({required String reason}) async {
    _loading = true;
    notifyListeners();
    try {
      final newGroups = <SuggestionGroup>[];
      final seenBookIds = <int>{};

      if (_history.isEmpty) {
        await _buildStarterGroups(newGroups, seenBookIds);
      } else {
        final topSubjects = _topSubjects(_subjectGroupCount);
        final topAuthors = _topAuthors(_authorGroupCount);

        for (final subject in topSubjects) {
          try {
            final books = await _fetchMixedTopicBooks(subject);
            if (books.isNotEmpty) {
              final unique = _takeUnique(books, seenBookIds, _booksPerGroup);
              if (unique.isEmpty) continue;
              final sourceTitle = _sourceBookForSubject(subject);
              newGroups.add(SuggestionGroup(
                label: 'More ${_capitalize(subject)}',
                queryType: 'subject',
                queryValue: subject,
                bookJsons: unique.map((b) => json.encode(b.toJson())).toList(),
                sourceBookTitle: sourceTitle,
              ));
            }
          } catch (_) {
            await _storage.incrementDiscoverMetric('suggestions_refresh_fail');
          }
        }

        for (final author in topAuthors) {
          try {
            final displayName = _formatAuthorName(author);
            final books = await _fetchMixedAuthorBooks(author, displayName);
            if (books.isNotEmpty) {
              final unique = _takeUnique(books, seenBookIds, _booksPerGroup);
              if (unique.isEmpty) continue;
              final sourceTitle = _sourceBookForAuthor(author);
              newGroups.add(SuggestionGroup(
                label: 'More by $displayName',
                queryType: 'author',
                queryValue: author,
                bookJsons: unique.map((b) => json.encode(b.toJson())).toList(),
                sourceBookTitle: sourceTitle,
              ));
            }
          } catch (_) {
            await _storage.incrementDiscoverMetric('suggestions_refresh_fail');
          }
        }
      }

      _groups = newGroups;
      await _storage.saveCachedSuggestions(newGroups);
      _cacheTimestampMs = await _storage.getSuggestionsCacheTimestamp();
      _lastRefreshMs = DateTime.now().millisecondsSinceEpoch;
      await _storage.incrementDiscoverMetric('suggestions_refresh_success');
      if (kDebugMode) {
        debugPrint(
            'Suggestions refreshed (${newGroups.length} groups) from trigger: $reason');
      }
    } catch (_) {
      await _storage.incrementDiscoverMetric('suggestions_refresh_fail');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<Book> booksForGroup(SuggestionGroup group) {
    return group.bookJsons
        .map((j) {
          try {
            return Book.fromJson(json.decode(j) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Book>()
        .toList();
  }

  bool get isInitialized => _initialized;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<String> _topSubjects(int n) {
    final scores = <String, double>{};
    for (final event in _history) {
      final weight = _eventWeight(event);
      final seen = <String>{};
      for (final s in [...event.subjects, ...event.bookshelves]) {
        final clean = _cleanSubject(s);
        if (clean.isNotEmpty && seen.add(clean)) {
          scores[clean] = (scores[clean] ?? 0) + weight;
        }
      }
    }

    if (scores.isEmpty) return [];

    final byScore = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = <String>[];
    final used = <String>{};
    for (final entry in byScore) {
      if (result.length >= n) break;
      result.add(entry.key);
      used.add(entry.key);
    }

    for (final event in _history) {
      if (result.length >= n) break;
      for (final s in [...event.subjects, ...event.bookshelves]) {
        final clean = _cleanSubject(s);
        if (clean.isNotEmpty && used.add(clean)) {
          result.add(clean);
          break; // one representative subject per event for diversity
        }
      }
    }

    return result;
  }

  List<String> _topAuthors(int n) {
    final scores = <String, double>{};
    for (final event in _history) {
      final weight = _eventWeight(event);
      for (final a in event.authorNames) {
        if (a.trim().isNotEmpty) {
          scores[a] = (scores[a] ?? 0) + weight;
        }
      }
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  double _eventWeight(ReadingEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageDays = (now - event.openedAt) / (1000 * 60 * 60 * 24);
    final recency = 1 / (1 + (ageDays / 7).clamp(0, 30));
    final pagesBoost = 1 + math.log(event.pagesRead + 1) / math.ln10;
    final timeBoost = 1 + math.log((event.sessionSeconds / 60) + 1) / math.ln10;
    return recency * pagesBoost * timeBoost;
  }

  Future<void> _buildStarterGroups(
    List<SuggestionGroup> groups,
    Set<int> seenBookIds,
  ) async {
    for (final starter in _starterTopics) {
      try {
        final resp = await _service.fetchBooks(topic: starter.$2, page: 1);
        final unique = _takeUnique(resp.results, seenBookIds, _booksPerGroup);
        if (unique.isEmpty) continue;
        groups.add(SuggestionGroup(
          label: starter.$1,
          queryType: 'subject',
          queryValue: starter.$2,
          bookJsons: unique.map((b) => json.encode(b.toJson())).toList(),
        ));
      } catch (_) {
        await _storage.incrementDiscoverMetric('suggestions_refresh_fail');
      }
    }
  }

  Future<List<Book>> _fetchMixedTopicBooks(String topic) async {
    final primary = await _service.fetchBooks(topic: topic, page: 1);
    final explore = await _service.fetchBooks(topic: topic, page: 2);
    return _mixAffinityAndNovelty(primary.results, explore.results);
  }

  Future<List<Book>> _fetchMixedAuthorBooks(
    String rawAuthor,
    String displayName,
  ) async {
    final primaryResp = await _service.fetchBooks(search: displayName, page: 1);
    final exploreResp = await _service.fetchBooks(search: displayName, page: 2);
    final primary = primaryResp.results
        .where((b) => _bookMatchesAuthor(b, rawAuthor, displayName))
        .toList();
    final explore = exploreResp.results
        .where((b) => _bookMatchesAuthor(b, rawAuthor, displayName))
        .toList();
    return _mixAffinityAndNovelty(primary, explore);
  }

  List<Book> _mixAffinityAndNovelty(List<Book> affinity, List<Book> novelty) {
    final total = _booksPerGroup;
    final noveltyCount = (total * _noveltyRatio).round();
    final affinityCount = total - noveltyCount;
    final merged = <Book>[];
    final ids = <int>{};

    for (final b in affinity) {
      if (merged.length >= affinityCount) break;
      if (ids.add(b.id)) merged.add(b);
    }
    for (final b in novelty) {
      if (merged.length >= total) break;
      if (ids.add(b.id)) merged.add(b);
    }
    for (final b in affinity) {
      if (merged.length >= total) break;
      if (ids.add(b.id)) merged.add(b);
    }
    return merged;
  }

  List<Book> _takeUnique(List<Book> input, Set<int> seenBookIds, int max) {
    final out = <Book>[];
    for (final b in input) {
      if (out.length >= max) break;
      if (seenBookIds.add(b.id)) {
        out.add(b);
      }
    }
    return out;
  }

  static String _cleanSubject(String raw) {
    // Strip overly broad or useless subjects.
    const skip = {
      'fiction',
      'nonfiction',
      'non-fiction',
      'literature',
      'books',
      'readable',
    };
    final lower = raw.toLowerCase().trim();
    // Take only the first segment if split by &, /, or --.
    final segments = lower.split(RegExp(r'[&/]|--'));
    final first = segments.first.trim();
    if (first.length < 3 || skip.contains(first)) return '';
    return first;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _formatAuthorName(String raw) {
    final parts = raw.split(',');
    return parts.reversed.map((p) => p.trim()).join(' ').trim();
  }

  /// Returns the title of the most-recently-read book that contributed to [subject].
  String? _sourceBookForSubject(String subject) {
    for (final event in _history) {
      for (final s in [...event.subjects, ...event.bookshelves]) {
        if (_cleanSubject(s) == subject) {
          final title = event.bookTitle.trim();
          return title.isNotEmpty ? title : null;
        }
      }
    }
    return null;
  }

  /// Returns the title of the most-recently-read book by [rawAuthor].
  String? _sourceBookForAuthor(String rawAuthor) {
    for (final event in _history) {
      if (event.authorNames.any((a) => a == rawAuthor)) {
        final title = event.bookTitle.trim();
        return title.isNotEmpty ? title : null;
      }
    }
    return null;
  }

  /// Returns true when any of [book]'s authors match [rawName] (stored format,
  /// e.g. "Austen, Jane") or [displayName] (human-readable, e.g. "Jane Austen").
  static bool _bookMatchesAuthor(
      Book book, String rawName, String displayName) {
    final lastName = rawName.split(',').first.toLowerCase();
    final displayLower = displayName.toLowerCase();
    return book.authors.any((a) {
      final aLower = a.name.toLowerCase();
      return aLower.contains(lastName) ||
          displayLower.contains(a.name.split(',').first.toLowerCase());
    });
  }
}
