import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/book.dart';

/// Represents book content that can be read in the reader — either plain text
/// or an ordered list of image page URLs (e.g. scanned pages from archive.org).
class BookContent {
  /// Plain text of the book. Non-null when [isImageBased] is false.
  final String? text;

  /// Ordered list of image URLs, one per scanned page. Non-null when
  /// [isImageBased] is true.
  final List<String>? images;

  const BookContent.text(String text)
      : text = text,
        images = null;

  const BookContent.images(List<String> images)
      : images = images,
        text = null;

  bool get isImageBased => images != null;
}

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
          // Skip responses with a non-text content-type (e.g. image/jpeg, application/pdf).
          final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
          final isNonText = contentType.isNotEmpty &&
              !contentType.contains('text/') &&
              !contentType.contains('application/octet-stream');
          if (isNonText) {
            onDebug?.call(
              OpenLibraryDebugSnapshot(
                requestUrl: url,
                statusCode: resp.statusCode,
                success: false,
                bodyLength: resp.bodyBytes.length,
                bodyPreview: 'Content-Type: $contentType',
                resultCount: null,
                error: 'Non-text content type: $contentType',
                timestamp: DateTime.now(),
              ),
            );
            continue;
          }

          // Skip binary files detected by magic bytes (PDF, images, ZIP/EPUB, etc.).
          if (_isBinaryContent(resp.bodyBytes)) {
            onDebug?.call(
              OpenLibraryDebugSnapshot(
                requestUrl: url,
                statusCode: resp.statusCode,
                success: false,
                bodyLength: resp.bodyBytes.length,
                bodyPreview: 'Binary content detected (magic bytes)',
                resultCount: null,
                error: 'Binary/image content — not readable text',
                timestamp: DateTime.now(),
              ),
            );
            continue;
          }

          final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);

          // A plain-text URL that returns an HTML page is almost certainly an
          // error page (e.g. archive.org 404).  Detect and handle it.
          final trimmedLower = raw.trimLeft().toLowerCase();
          final looksLikeHtml = trimmedLower.startsWith('<!doctype') ||
              trimmedLower.startsWith('<html');
          final expectHtml =
              url.contains('.html') || url.contains('/html');

          String processedText;
          if (expectHtml || looksLikeHtml) {
            processedText = cleanGutenbergText(htmlToPlainText(raw));
          } else {
            processedText = cleanGutenbergText(raw);
          }

          // Skip results that are too short to be genuine book content
          // (likely an error page or an empty/stub file).
          if (processedText.length < 500) {
            onDebug?.call(
              OpenLibraryDebugSnapshot(
                requestUrl: url,
                statusCode: resp.statusCode,
                success: false,
                bodyLength: resp.bodyBytes.length,
                bodyPreview: processedText.isEmpty ? '(empty)' : processedText,
                resultCount: null,
                error:
                    'Insufficient content (${processedText.length} chars after cleaning)',
                timestamp: DateTime.now(),
              ),
            );
            continue;
          }

          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: url,
              statusCode: resp.statusCode,
              success: true,
              bodyLength: resp.bodyBytes.length,
              bodyPreview: _preview(processedText),
              resultCount: null,
              error: null,
              timestamp: DateTime.now(),
            ),
          );
          return processedText;
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
    throw Exception('Could not load text for this book. '
        'The available sources may be image-only or temporarily unavailable.');
  }

  /// Fetches the IIIF manifest for the given archive.org item and returns an
  /// ordered list of page image URLs, or an empty list if unavailable.
  Future<List<String>> _fetchIIIFImagePages(
    String iaId, {
    void Function(OpenLibraryDebugSnapshot)? onDebug,
  }) async {
    // The '\$' is a literal '$' that is part of archive.org's IIIF URL format:
    // https://iiif.archive.org/iiif/{item_id}$/manifest.json
    final manifestUrl = 'https://iiif.archive.org/iiif/$iaId\$/manifest.json';
    try {
      final resp =
          await _getWithRetry(Uri.parse(manifestUrl), timeout: _timeout);
      if (resp.statusCode != 200) {
        onDebug?.call(OpenLibraryDebugSnapshot(
          requestUrl: manifestUrl,
          statusCode: resp.statusCode,
          success: false,
          bodyLength: resp.bodyBytes.length,
          bodyPreview: _preview(resp.body),
          resultCount: 0,
          error: 'HTTP ${resp.statusCode}',
          timestamp: DateTime.now(),
        ));
        return const [];
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final sequences = data['sequences'] as List<dynamic>? ?? [];
      if (sequences.isEmpty) return const [];

      final canvases = (sequences.first is Map<String, dynamic>
              ? (sequences.first as Map<String, dynamic>)['canvases']
              : null) as List<dynamic>? ??
          [];
      final imageUrls = <String>[];

      for (final canvas in canvases) {
        if (canvas is! Map<String, dynamic>) continue;
        final images = canvas['images'] as List<dynamic>? ?? [];
        if (images.isEmpty) continue;
        final first = images.first;
        if (first is! Map<String, dynamic>) continue;
        final resource = first['resource'];
        if (resource == null) continue;

        String? imageUrl;
        if (resource is Map<String, dynamic>) {
          imageUrl = resource['@id'] as String?;
        } else if (resource is String) {
          imageUrl = resource;
        }

        if (imageUrl != null && imageUrl.isNotEmpty) {
          imageUrls.add(imageUrl);
        }
      }

      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: manifestUrl,
        statusCode: resp.statusCode,
        success: imageUrls.isNotEmpty,
        bodyLength: resp.bodyBytes.length,
        bodyPreview: imageUrls.isEmpty
            ? 'No image pages found in manifest'
            : 'Found ${imageUrls.length} page(s)',
        resultCount: imageUrls.length,
        error: imageUrls.isEmpty ? 'Manifest contained no image URLs' : null,
        timestamp: DateTime.now(),
      ));

      return imageUrls;
    } catch (e) {
      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: manifestUrl,
        statusCode: null,
        success: false,
        bodyLength: 0,
        bodyPreview: '',
        resultCount: 0,
        error: 'IIIF manifest error: ${_friendlyNetworkError(e)}',
        timestamp: DateTime.now(),
      ));
      return const [];
    }
  }

  /// Returns the archive.org identifiers stored in [book] formats, or extracted
  /// from its text-source URLs as a fallback.
  List<String> _getIaIds(Book book) {
    final stored = book.formats['openlibrary/ia_ids'];
    if (stored != null && stored.isNotEmpty) {
      return stored
          .split('|')
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList();
    }
    // Fallback: derive IDs from text_sources URLs
    final textSources = book.formats['openlibrary/text_sources'];
    if (textSources == null || textSources.isEmpty) return const [];
    final iaIds = <String>{};
    for (final url in textSources.split('|')) {
      final match =
          RegExp(r'archive\.org/download/([^/]+)/').firstMatch(url.trim());
      if (match != null) iaIds.add(match.group(1)!);
    }
    return iaIds.toList();
  }

  /// Loads book content — first as plain text, falling back to scanned image
  /// pages when text is unavailable. Throws if neither is accessible.
  Future<BookContent> fetchBookContent(
    Book book, {
    void Function(OpenLibraryDebugSnapshot)? onDebug,
  }) async {
    // Try text first.
    try {
      final text = await fetchBookText(book, onDebug: onDebug);
      return BookContent.text(text);
    } catch (e) {
      // Text not available; record and proceed to image fallback.
      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://book/${book.id}/text-fetch-failed',
        statusCode: null,
        success: false,
        bodyLength: 0,
        bodyPreview: '',
        resultCount: 0,
        error: 'Text unavailable, trying image pages: $e',
        timestamp: DateTime.now(),
      ));
    }

    // Try scanned image pages from archive.org via IIIF.
    final iaIds = _getIaIds(book);
    for (final iaId in iaIds) {
      final pages = await _fetchIIIFImagePages(iaId, onDebug: onDebug);
      if (pages.isNotEmpty) return BookContent.images(pages);
    }

    throw Exception(
      'No readable content available for this book. '
      'The edition may be restricted or temporarily unavailable.',
    );
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
        'has_fulltext': 'true',
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
      'has_fulltext': 'true',
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
    final iaIds = _collectIaIds(doc);
    if (iaIds.isNotEmpty) {
      formats['openlibrary/ia_ids'] = iaIds.join('|');
    }

    // A book is considered to have accessible full text when the API marks it
    // as a public scan, has full text, or has associated archive.org / Gutenberg IDs.
    final publicScan = doc['public_scan_b'] == true;
    final apiHasFulltext = doc['has_fulltext'] == true;
    final hasIa = (doc['ia'] is List && (doc['ia'] as List).isNotEmpty);
    final hasGutenberg = (doc['id_project_gutenberg'] is List &&
        (doc['id_project_gutenberg'] as List).isNotEmpty);
    final hasFullText = publicScan || apiHasFulltext || hasIa || hasGutenberg;

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
      hasFullText: hasFullText,
      ebookAccess: EbookAccess.fromString(doc['ebook_access'] as String?),
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
    // Prefer the most informative ebook access value: a known non-unknown value
    // from primary takes precedence; otherwise fall back to primary's value,
    // then fallback's value.
    final mergedEbookAccess =
        primary.ebookAccess != EbookAccess.unknown
            ? primary.ebookAccess
            : fallback.ebookAccess;
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
      // Use OR so that availability detected in either source is preserved:
      // primary may carry the fresh `public_scan_b` flag while fallback may
      // have IA identifiers discovered earlier.
      hasFullText: primary.hasFullText || fallback.hasFullText,
      ebookAccess: mergedEbookAccess,
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

  List<String> _collectIaIds(Map<String, dynamic> source) {
    final ia = source['ia'];
    if (ia is! List || ia.isEmpty) return const [];
    // Limit to 3 identifiers: each may trigger a IIIF request, so we
    // avoid excessive network calls while still covering alternate editions.
    return ia.take(3).map((id) => id.toString()).toList();
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

  /// Returns `true` when [bytes] has magic bytes indicating a binary format
  /// (PDF, JPEG, PNG, GIF, ZIP/EPUB, DjVu, …).  Such files are not readable
  /// as plain text and should be skipped.
  bool _isBinaryContent(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // PDF: %PDF
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) return true;
    // JPEG: FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG: 89 PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) return true;
    // GIF: GIF8
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) return true;
    // ZIP / EPUB: PK
    if (bytes[0] == 0x50 && bytes[1] == 0x4B) return true;
    // DjVu: AT&T
    if (bytes[0] == 0x41 &&
        bytes[1] == 0x54 &&
        bytes[2] == 0x26 &&
        bytes[3] == 0x54) return true;
    // Heuristic: >5 % null bytes in the first 512 bytes → binary
    final sample = bytes.length < 512 ? bytes.length : 512;
    int nulls = 0;
    for (var i = 0; i < sample; i++) {
      if (bytes[i] == 0) nulls++;
    }
    return nulls > (sample * 0.05).floor();
  }

  String _preview(String text, {int max = 350}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}


