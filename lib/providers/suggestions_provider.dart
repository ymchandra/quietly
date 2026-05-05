import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/reading_history.dart';
import '../services/openlibrary_service.dart';
import '../services/storage_service.dart';

class SuggestionsProvider extends ChangeNotifier {
  final _storage = StorageService();
  final _service = OpenLibraryService();

  List<ReadingEvent> _history = [];
  List<SuggestionGroup> _groups = [];
  bool _loading = false;
  bool _initialized = false;

  bool get isLoading => _loading;
  bool get hasHistory => _history.isNotEmpty;
  List<SuggestionGroup> get groups => List.unmodifiable(_groups);

  Future<void> init() async {
    _history = await _storage.getReadingHistory();
    _groups = await _storage.getCachedSuggestions();
    _initialized = true;
    notifyListeners();
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

    if (!_loading) {
      _refreshSuggestions();
    }
  }

  Future<void> _refreshSuggestions() async {
    if (_history.isEmpty) return;
    _loading = true;
    notifyListeners();

    final topSubjects = _topSubjects(2);
    final topAuthors = _topAuthors(1);

    final newGroups = <SuggestionGroup>[];

    for (final subject in topSubjects) {
      try {
        final resp = await _service.fetchBooks(topic: subject, page: 1);
        final books = resp.results.take(10).toList();
        if (books.isNotEmpty) {
          newGroups.add(SuggestionGroup(
            label: 'More ${_capitalize(subject)}',
            queryType: 'subject',
            queryValue: subject,
            bookJsons:
                books.map((b) => json.encode(b.toJson())).toList(),
          ));
        }
      } catch (_) {}
    }

    for (final author in topAuthors) {
      try {
        final displayName = _formatAuthorName(author);
        final resp = await _service.fetchBooks(search: displayName, page: 1);
        // Filter to books that actually feature this author.
        final books = resp.results
            .where((b) => _bookMatchesAuthor(b, author, displayName))
            .take(10)
            .toList();
        if (books.isNotEmpty) {
          newGroups.add(SuggestionGroup(
            label: 'More by $displayName',
            queryType: 'author',
            queryValue: author,
            bookJsons:
                books.map((b) => json.encode(b.toJson())).toList(),
          ));
        }
      } catch (_) {}
    }

    _groups = newGroups;
    await _storage.saveCachedSuggestions(newGroups);
    _loading = false;
    notifyListeners();
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
    final counts = <String, int>{};
    for (final event in _history) {
      for (final s in event.subjects) {
        // Clean up common subject strings.
        final clean = _cleanSubject(s);
        if (clean.isNotEmpty) {
          counts[clean] = (counts[clean] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  List<String> _topAuthors(int n) {
    final counts = <String, int>{};
    for (final event in _history) {
      for (final a in event.authorNames) {
        if (a.trim().isNotEmpty) {
          counts[a] = (counts[a] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
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

  /// Returns true when any of [book]'s authors match [rawName] (stored format,
  /// e.g. "Austen, Jane") or [displayName] (human-readable, e.g. "Jane Austen").
  static bool _bookMatchesAuthor(Book book, String rawName, String displayName) {
    final lastName = rawName.split(',').first.toLowerCase();
    final displayLower = displayName.toLowerCase();
    return book.authors.any((a) {
      final aLower = a.name.toLowerCase();
      return aLower.contains(lastName) || displayLower.contains(a.name.split(',').first.toLowerCase());
    });
  }
}
