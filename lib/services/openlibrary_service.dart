import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/book.dart';

class OpenLibraryDebugSnapshot {
  final String requestUrl;
  final int? statusCode;
  final bool success;
  final int bodyLength;
  final String bodyPreview;
  final int? resultCount;
  final String? error;
  final DateTime timestamp;

  const OpenLibraryDebugSnapshot({
    required this.requestUrl,
    required this.statusCode,
    required this.success,
    required this.bodyLength,
    required this.bodyPreview,
    required this.resultCount,
    required this.error,
    required this.timestamp,
  });
}

class OpenLibraryService {
  static const _base = 'https://openlibrary.org';
  static const _timeout = Duration(seconds: 15);
  static const _textTimeout = Duration(seconds: 30);
  static const _maxAttempts = 3;
  static const _retryBaseDelay = Duration(milliseconds: 700);
  static const _pageSize = 20;
  final Map<int, Book> _bookCache = {};

  Future<OpenLibraryResponse> fetchBooks({
    String? topic,
    String? search,
    String languages = 'en',
    int page = 1,
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    final uri = _buildListUri(
      topic: topic,
      search: search,
      languages: languages,
      page: page,
    );
    http.Response? resp;
    var emitted = false;
    try {
      resp = await _getWithRetry(uri, timeout: _timeout);
      if (resp.statusCode != 200) {
        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: uri.toString(),
            statusCode: resp.statusCode,
            success: false,
            bodyLength: resp.bodyBytes.length,
            bodyPreview: _preview(resp.body),
            resultCount: null,
            error: 'HTTP ${resp.statusCode}',
            timestamp: DateTime.now(),
          ),
        );
        emitted = true;
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final parsed = _parseSearchResponse(data, uri, page);
      for (final book in parsed.results) {
        _bookCache[book.id] = book;
      }
      onDebug?.call(
        OpenLibraryDebugSnapshot(
          requestUrl: uri.toString(),
          statusCode: resp.statusCode,
          success: true,
          bodyLength: resp.bodyBytes.length,
          bodyPreview: _preview(resp.body),
          resultCount: parsed.results.length,
          error: null,
          timestamp: DateTime.now(),
        ),
      );
      return parsed;
    } catch (e) {
      final message = _friendlyNetworkError(e);
      if (!emitted) {
        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: uri.toString(),
            statusCode: resp?.statusCode,
            success: false,
            bodyLength: resp?.bodyBytes.length ?? 0,
            bodyPreview: resp == null ? '' : _preview(resp.body),
            resultCount: null,
            error: message,
            timestamp: DateTime.now(),
          ),
        );
      }
      throw Exception(message);
    }
  }

  Future<Book> fetchBook(int id) async {
    final cached = _bookCache[id];
    if (cached != null) return cached;

    final uri = Uri.parse('$_base/works/OL${id}W.json');
    final resp = await _getWithRetry(uri, timeout: _timeout);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data = json.decode(resp.body) as Map<String, dynamic>;
    var book = _mapWorkDetailsToBook(data, id);
    book = await _enrichBookFromSearch(book);
    _bookCache[id] = book;
    return book;
  }

  Future<bool> hasReadableText(Book book) async {
    if (_buildSources(book).isNotEmpty) return true;
    final discovered = await _discoverTextSources(book);
    return discovered.isNotEmpty;
  }

  Future<String> fetchBookText(
    Book book, {
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    final sources = _buildSources(book);
    onDebug?.call(
      OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://book/${book.id}/sources/initial',
        statusCode: null,
        success: true,
        bodyLength: sources.join('\n').length,
        bodyPreview: sources.isEmpty ? '(none)' : sources.join('\n'),
        resultCount: sources.length,
        error: null,
        timestamp: DateTime.now(),
      ),
    );
    if (sources.isEmpty) {
      final discovered = await _discoverTextSources(book);
      sources.addAll(discovered);
      onDebug?.call(
        OpenLibraryDebugSnapshot(
          requestUrl: 'openlibrary://book/${book.id}/sources/discovered',
          statusCode: null,
          success: discovered.isNotEmpty,
          bodyLength: discovered.join('\n').length,
          bodyPreview: discovered.isEmpty ? '(none)' : discovered.join('\n'),
          resultCount: discovered.length,
          error:
              discovered.isEmpty ? 'No additional text sources discovered.' : null,
          timestamp: DateTime.now(),
        ),
      );
    }
    if (sources.isEmpty) {
      onDebug?.call(
        OpenLibraryDebugSnapshot(
          requestUrl: 'openlibrary://book/${book.id}/sources/final',
          statusCode: null,
          success: false,
          bodyLength: 0,
          bodyPreview: '',
          resultCount: 0,
          error: 'No readable text source available for this book.',
          timestamp: DateTime.now(),
        ),
      );
      throw Exception('No readable text source available for this book.');
    }
    for (final url in sources) {
      try {
        final resp = await _getWithRetry(
          Uri.parse(url),
          timeout: _textTimeout,
          maxAttempts: 2,
        );
        if (resp.statusCode == 200) {
          final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: url,
              statusCode: resp.statusCode,
              success: true,
              bodyLength: resp.bodyBytes.length,
              bodyPreview: _preview(raw),
              resultCount: null,
              error: null,
              timestamp: DateTime.now(),
            ),
          );
          if (url.contains('.html') || url.contains('html')) {
            return cleanGutenbergText(htmlToPlainText(raw));
          }
          return cleanGutenbergText(raw);
        }
        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: url,
            statusCode: resp.statusCode,
            success: false,
            bodyLength: resp.bodyBytes.length,
            bodyPreview: _preview(resp.body),
            resultCount: null,
            error: 'HTTP ${resp.statusCode}',
            timestamp: DateTime.now(),
          ),
        );
      } catch (e) {
        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: url,
            statusCode: null,
            success: false,
            bodyLength: 0,
            bodyPreview: '',
            resultCount: null,
            error: _friendlyNetworkError(e),
            timestamp: DateTime.now(),
          ),
        );
        continue;
      }
    }
    throw Exception('Could not fetch book text');
  }

  Uri _buildListUri({
    String? topic,
    String? search,
    required String languages,
    required int page,
  }) {
    if (search != null && search.trim().isNotEmpty) {
      return Uri.parse('$_base/search.json').replace(queryParameters: {
        'q': search.trim(),
        'language': _openLibraryLang(languages),
        'page': page.toString(),
        'limit': _pageSize.toString(),
      });
    }
    final normalizedTopic = (topic == null || topic.isEmpty)
        ? 'fiction'
        : topic.trim().toLowerCase();
    return Uri.parse('$_base/search.json').replace(queryParameters: {
      'subject': normalizedTopic,
      'language': _openLibraryLang(languages),
      'page': page.toString(),
      'limit': _pageSize.toString(),
    });
  }


  OpenLibraryResponse _parseSearchResponse(
    Map<String, dynamic> json,
    Uri uri,
    int page,
  ) {
    final docs = (json['docs'] as List<dynamic>? ?? []);
    final results = docs
        .map((d) => _mapSearchDocToBook(d as Map<String, dynamic>))
        .whereType<Book>()
        .toList();
    final total = json['numFound'] as int? ?? results.length;
    final hasNext = page * _pageSize < total;
    return OpenLibraryResponse(
      count: total,
      next: hasNext
          ? uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'page': (page + 1).toString(),
              },
            ).toString()
          : null,
      previous: page > 1
          ? uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'page': (page - 1).toString(),
              },
            ).toString()
          : null,
      results: results,
    );
  }

  Book? _mapSearchDocToBook(Map<String, dynamic> doc) {
    final key = _pickWorkKey(doc);
    if (key == null) return null;
    final id = _workKeyToId(key);
    final authors = (doc['author_name'] as List<dynamic>? ?? [])
        .map((name) => Person(name: name.toString()))
        .toList();
    final subjects = _collectSubjects(doc);
    final languages = (doc['language'] as List<dynamic>? ?? [])
        .map((l) => l.toString())
        .toList();
    final formats = <String, String>{
      if (doc['cover_i'] != null)
        'image/jpeg': 'https://covers.openlibrary.org/b/id/${doc['cover_i']}-L.jpg',
      'openlibrary/work_key': key,
    };
    final textSources = _collectTextSources(doc);
    if (textSources.isNotEmpty) {
      formats['openlibrary/text_sources'] = textSources.join('|');
      formats['text/plain; charset=utf-8'] = textSources.first;
    }

    return Book(
      id: id,
      title: (doc['title'] as String? ?? '').trim(),
      authors: authors,
      subjects: subjects.take(12).toList(),
      bookshelves: subjects.take(6).toList(),
      languages: languages,
      formats: formats,
      downloadCount: doc['want_to_read_count'] as int? ??
          doc['ratings_count'] as int? ??
          doc['edition_count'] as int? ??
          0,
    );
  }


  Book _mapWorkDetailsToBook(Map<String, dynamic> data, int fallbackId) {
    final key = data['key'] as String? ?? '/works/OL${fallbackId}W';
    final id = _workKeyToId(key);
    final subjects = _collectSubjects(data);
    final covers = (data['covers'] as List<dynamic>? ?? []);
    return Book(
      id: id,
      title: data['title'] as String? ?? '',
      authors: const [],
      subjects: subjects.take(12).toList(),
      bookshelves: subjects.take(6).toList(),
      languages: const ['eng'],
      formats: {
        if (covers.isNotEmpty)
          'image/jpeg': 'https://covers.openlibrary.org/b/id/${covers.first}-L.jpg',
        'openlibrary/work_key': key,
      },
      downloadCount: 0,
    );
  }

  Future<Book> _enrichBookFromSearch(Book base) async {
    final workKey = _normalizeWorkKey(base.formats['openlibrary/work_key']) ??
        '/works/OL${base.id}W';
    final uri = Uri.parse('$_base/search.json').replace(queryParameters: {
      'q': 'key:$workKey',
      'limit': '1',
    });
    try {
      final resp = await _getWithRetry(uri, timeout: _timeout);
      if (resp.statusCode != 200) return base;
      final jsonData = json.decode(resp.body) as Map<String, dynamic>;
      final docs = jsonData['docs'] as List<dynamic>? ?? [];
      if (docs.isEmpty || docs.first is! Map<String, dynamic>) return base;
      final searchBook = _mapSearchDocToBook(docs.first as Map<String, dynamic>);
      if (searchBook == null) return base;
      return _mergeBooks(primary: searchBook, fallback: base);
    } catch (_) {
      return base;
    }
  }

  Book _mergeBooks({required Book primary, required Book fallback}) {
    final mergedSubjects =
        primary.subjects.isNotEmpty ? primary.subjects : fallback.subjects;
    final mergedShelves = primary.bookshelves.isNotEmpty
        ? primary.bookshelves
        : (mergedSubjects.isNotEmpty
            ? mergedSubjects.take(6).toList()
            : fallback.bookshelves);
    return Book(
      id: fallback.id,
      title: primary.title.isNotEmpty ? primary.title : fallback.title,
      authors: primary.authors.isNotEmpty ? primary.authors : fallback.authors,
      subjects: mergedSubjects,
      bookshelves: mergedShelves,
      languages:
          primary.languages.isNotEmpty ? primary.languages : fallback.languages,
      formats: {
        ...fallback.formats,
        ...primary.formats,
      },
      downloadCount: primary.downloadCount > 0
          ? primary.downloadCount
          : fallback.downloadCount,
    );
  }

  List<String> _collectSubjects(Map<String, dynamic> source) {
    final values = <String>{};
    void readList(String key) {
      final raw = source[key];
      if (raw is! List) return;
      for (final value in raw) {
        final cleaned = value.toString().trim();
        if (cleaned.isNotEmpty) values.add(cleaned);
      }
    }

    readList('subjects');
    readList('subject');
    readList('subject_facet');
    readList('subject_key');
    return values.take(20).toList();
  }

  List<String> _collectTextSources(Map<String, dynamic> source) {
    final results = <String>[];
    final ia = source['ia'];
    if (ia is List && ia.isNotEmpty) {
      for (final id in ia.take(3)) {
        final iaId = id.toString();
        results.add('https://archive.org/download/$iaId/${iaId}_djvu.txt');
        results.add('https://archive.org/download/$iaId/$iaId.txt');
      }
    }
    final gutenberg = source['id_project_gutenberg'];
    if (gutenberg is List && gutenberg.isNotEmpty) {
      final gid = gutenberg.first.toString();
      results.add('https://www.gutenberg.org/cache/epub/$gid/pg$gid.txt');
      results.add('https://www.gutenberg.org/files/$gid/$gid-0.txt');
    }
    return results.toSet().toList();
  }

  String? _pickWorkKey(Map<String, dynamic> doc) {
    final raw = doc['key'];
    if (raw is String && raw.startsWith('/works/')) return raw;
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first.toString();
      if (first.startsWith('/works/')) return first;
    }
    return null;
  }

  int _workKeyToId(String workKey) {
    final match = RegExp(r'OL(\d+)W').firstMatch(workKey);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null) return parsed;
    }
    return workKey.hashCode.abs();
  }

  String _openLibraryLang(String code) {
    if (code == 'en') return 'eng';
    return code;
  }

  List<String> _buildSources(Book book) {
    final sources = <String>[];
    final fmts = book.formats;
    final lowerFormatKeys = fmts.keys.map((k) => k.toLowerCase()).toList();
    for (final key in [
      'text/plain; charset=utf-8',
      'text/plain: charset=utf-8',
      'text/plain; charset=us-ascii',
      'text/plain',
    ]) {
      if (fmts.containsKey(key)) sources.add(fmts[key]!);
    }
    for (var i = 0; i < lowerFormatKeys.length; i++) {
      final lowerKey = lowerFormatKeys[i];
      if (lowerKey.startsWith('text/plain')) {
        final originalKey = fmts.keys.elementAt(i);
        sources.add(fmts[originalKey]!);
      }
    }
    for (final key in fmts.keys) {
      if (key.contains('html')) sources.add(fmts[key]!);
    }
    final openLibrarySources = fmts['openlibrary/text_sources'];
    if (openLibrarySources != null && openLibrarySources.isNotEmpty) {
      sources.addAll(openLibrarySources
          .split('|')
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim()));
    }
    return sources.toSet().toList();
  }

  Future<List<String>> _discoverTextSources(Book book) async {
    final sources = <String>{};
    final workKey = _normalizeWorkKey(book.formats['openlibrary/work_key']) ??
        '/works/OL${book.id}W';
    final editionsUri =
        Uri.parse('$_base$workKey/editions.json').replace(queryParameters: {
      'limit': '30',
    });

    try {
      final resp = await _getWithRetry(editionsUri, timeout: _timeout);
      if (resp.statusCode != 200) return const [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final entries = (data['entries'] as List<dynamic>? ?? []);
      for (final entry in entries.take(30)) {
        if (entry is! Map<String, dynamic>) continue;
        sources.addAll(_collectTextSources(entry));
        sources.addAll(_collectArchiveSources(entry));
        sources.addAll(_collectGutenbergSources(entry));
      }
    } catch (_) {
      // Best-effort only; caller will surface final failure if no source works.
    }

    return sources.toList();
  }

  String? _normalizeWorkKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final key = raw.trim();
    if (key.startsWith('/works/')) return key;
    if (key.startsWith('OL') && key.endsWith('W')) return '/works/$key';
    return null;
  }

  List<String> _collectArchiveSources(Map<String, dynamic> source) {
    final results = <String>[];
    final ocaid = source['ocaid'];
    if (ocaid is String && ocaid.trim().isNotEmpty) {
      final id = ocaid.trim();
      results.add('https://archive.org/download/$id/${id}_djvu.txt');
      results.add('https://archive.org/download/$id/$id.txt');
    }
    return results;
  }

  List<String> _collectGutenbergSources(Map<String, dynamic> source) {
    final results = <String>[];
    final identifiers = source['identifiers'];
    if (identifiers is! Map<String, dynamic>) return results;
    final ids = identifiers['project_gutenberg'];
    if (ids is List && ids.isNotEmpty) {
      for (final id in ids.take(2)) {
        final gid = id.toString().trim();
        if (gid.isEmpty) continue;
        results.add('https://www.gutenberg.org/cache/epub/$gid/pg$gid.txt');
        results.add('https://www.gutenberg.org/files/$gid/$gid-0.txt');
      }
    }
    return results;
  }

  String htmlToPlainText(String html) {
    var text = html.replaceAll(
        RegExp(r'<head[^>]*>.*?</head>', dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'</?(p|div|h[1-6]|li|tr|br|hr)[^>]*>',
            caseSensitive: false),
        '\n\n');
    text = text.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = _decodeEntities(text);
    return text;
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026')
        .replaceAll('&rsquo;', '\u2019')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rdquo;', '\u201D')
        .replaceAll('&ldquo;', '\u201C')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          if (code != null) return String.fromCharCode(code);
          return m.group(0)!;
        });
  }

  String cleanGutenbergText(String text) {
    final startRegex = RegExp(
        r'\*{3}\s*START OF (THE|THIS) PROJECT GUTENBERG[^\n]*\n',
        caseSensitive: false);
    final startMatch = startRegex.firstMatch(text);
    if (startMatch != null) {
      text = text.substring(startMatch.end);
    }
    final endRegex = RegExp(
        r'\*{3}\s*END OF (THE|THIS) PROJECT GUTENBERG',
        caseSensitive: false);
    final endMatch = endRegex.firstMatch(text);
    if (endMatch != null) {
      text = text.substring(0, endMatch.start);
    }
    text = text.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
    return text.trim();
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    required Duration timeout,
    int maxAttempts = _maxAttempts,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await http.get(uri).timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      }

      if (attempt < maxAttempts) {
        final delay = Duration(
          milliseconds: _retryBaseDelay.inMilliseconds * attempt,
        );
        await Future.delayed(delay);
      }
    }

    if (lastError is TimeoutException) {
      throw TimeoutException(
        'Request timed out after ${timeout.inSeconds}s '
        '($maxAttempts attempts).',
      );
    }
    if (lastError is SocketException) {
      throw Exception('Network connection failed. Please check internet.');
    }
    if (lastError is HttpException) {
      throw Exception('Network error while contacting server.');
    }
    throw Exception('Request failed after retries.');
  }

  String _friendlyNetworkError(Object error) {
    final msg = error.toString();
    if (error is TimeoutException || msg.contains('TimeoutException')) {
      return 'Request timed out. Please retry.';
    }
    if (error is SocketException || msg.contains('SocketException')) {
      return 'No internet connection.';
    }
    if (msg.contains('HTTP 429')) {
      return 'Rate limited by Open Library. Please retry shortly.';
    }
    return msg;
  }

  String _preview(String text, {int max = 350}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}


