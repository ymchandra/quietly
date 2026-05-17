import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/book.dart';

/// Represents book content that can be read in the reader.
class BookContent {
  /// Plain text of the book. Used only for legacy text sources.
  final String? text;

  /// Raw EPUB bytes. Non-null when [isEpubBased] is true.
  final Uint8List? epubBytes;

  /// The URL used to fetch [epubBytes].
  final String? epubSourceUrl;

  /// Ordered HTML strings extracted from the EPUB spine.
  /// Non-null when [isHtmlBased] is true.
  final List<String>? htmlSpine;

  const BookContent.text(String text)
      : text = text,
        epubBytes = null,
        epubSourceUrl = null,
        htmlSpine = null;

  const BookContent.epub(Uint8List bytes, {this.epubSourceUrl})
      : epubBytes = bytes,
        text = null,
        htmlSpine = null;

  BookContent.html(List<String> spine, {this.epubSourceUrl})
      : htmlSpine = List.unmodifiable(spine),
        text = null,
        epubBytes = null;

  bool get isEpubBased => epubBytes != null;
  bool get isHtmlBased => htmlSpine != null && htmlSpine!.isNotEmpty;
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
  static const _pdfTimeout = Duration(seconds: 45);
  static const _pdfExtractTimeout = Duration(seconds: 30);
  static const _maxAttempts = 3;
  static const _pdfMaxAttempts = 2;
  static const _maxPdfBytes = 30 * 1024 * 1024;
  static const _retryBaseDelay = Duration(milliseconds: 700);
  static const _pageSize = 20;
  static const _defaultUserAgent = 'Quietly/1.0 (+mailto:contact@example.org)';
  final Map<int, Book> _bookCache = {};
  final String _userAgent;

  OpenLibraryService({String? userAgent})
      : _userAgent = (userAgent != null && userAgent.trim().isNotEmpty)
            ? userAgent.trim()
            : _defaultUserAgent;
  static const Set<String> _minorBlockedTopics = {
    'erotica',
    'adult',
    'adult_fiction',
    'sex',
    'sexuality',
    'pornography',
  };
  static const Set<String> _childBlockedTopics = {
    ..._minorBlockedTopics,
    'romance',
    'horror',
    'thriller',
  };
  static const List<String> _minorUnsafeKeywords = [
    'erotic',
    'erotica',
    'sex',
    'sexual',
    'porn',
    'pornography',
    'adult only',
    'adultery',
    'nsfw',
    'incest',
    'bdsm',
  ];
  static const List<String> _childUnsafeKeywords = [
    ..._minorUnsafeKeywords,
    'violence',
    'violent',
    'murder',
    'serial killer',
    'gore',
    'graphic',
    'horror',
    'thriller',
  ];

  Future<OpenLibraryResponse> fetchBooks({
    String? topic,
    String? search,
    String languages = 'en',
    int page = 1,
    String? ebookAccess,
    int? userAge,
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    final uri = _buildListUri(
      topic: topic,
      search: search,
      languages: languages,
      page: page,
      ebookAccess: ebookAccess,
    );
    if (!_isTopicAllowedForAge(topic, userAge)) {
      return OpenLibraryResponse(
        count: 0,
        next: null,
        previous: null,
        results: const [],
      );
    }
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
      final parsed = _parseSearchResponse(data, uri, page, userAge: userAge);
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

  Future<bool> hasReadableText(Book book, {int? userAge}) async {
    if (!_isBookAllowedForAge(book, userAge)) return false;
    if (_buildEpubSources(book).isNotEmpty) return true;
    if (_buildSources(book).isNotEmpty) return true;
    final discovered = await _discoverTextSources(book);
    if (discovered.isNotEmpty) return true;
    final discoveredEpub = await _discoverEpubSources(book);
    return discoveredEpub.isNotEmpty;
  }

  Future<(Uint8List, String)?> _fetchBookEpubBytes(
    Book book, {
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    final sources = _buildEpubSources(book).toSet().toList();
    if (sources.isEmpty) {
      final discovered = await _discoverEpubSources(book);
      sources.addAll(discovered);
      onDebug?.call(
        OpenLibraryDebugSnapshot(
          requestUrl: 'openlibrary://book/${book.id}/epub-sources/discovered',
          statusCode: null,
          success: discovered.isNotEmpty,
          bodyLength: discovered.join('\n').length,
          bodyPreview: discovered.isEmpty ? '(none)' : discovered.join('\n'),
          resultCount: discovered.length,
          error: discovered.isEmpty ? 'No EPUB sources discovered.' : null,
          timestamp: DateTime.now(),
        ),
      );
    }
    if (sources.isEmpty) return null;

    for (final url in sources) {
      try {
        final resp = await _getWithRetry(
          Uri.parse(url),
          timeout: _textTimeout,
          maxAttempts: 2,
        );
        if (resp.statusCode != 200) {
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
          continue;
        }

        final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
        final looksLikeZip = resp.bodyBytes.length >= 2 &&
            resp.bodyBytes[0] == 0x50 &&
            resp.bodyBytes[1] == 0x4B;
        final likelyEpub = url.toLowerCase().endsWith('.epub') ||
            contentType.contains('epub') ||
            looksLikeZip;
        if (!likelyEpub) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: url,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview: 'Content-Type: $contentType',
              resultCount: null,
              error: 'Source is not EPUB content',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }

        try {
          await EpubReader.readBook(resp.bodyBytes);
        } catch (e) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: url,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview: _preview(resp.body),
              resultCount: null,
              error: 'EPUB validation failed: $e',
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
            bodyPreview: 'EPUB bytes downloaded and validated',
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );
        return (resp.bodyBytes, url);
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
      }
    }

    return null;
  }

  Future<String> fetchBookText(
    Book book, {
    int? userAge,
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    if (!_isBookAllowedForAge(book, userAge)) {
      throw Exception('This title is restricted for the selected age profile.');
    }
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
          error: discovered.isEmpty
              ? 'No additional text sources discovered.'
              : null,
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
          final contentType =
              (resp.headers['content-type'] ?? '').toLowerCase();
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

          final raw = _decodeTextBytes(resp.bodyBytes);

          // A plain-text URL that returns an HTML page is almost certainly an
          // error page (e.g. archive.org 404).  Detect and handle it.
          final trimmedLower = raw.trimLeft().toLowerCase();
          final looksLikeHtml = trimmedLower.startsWith('<!doctype') ||
              trimmedLower.startsWith('<html');
          final expectHtml = url.contains('.html') || url.contains('/html');

          String processedText;
          if (expectHtml || looksLikeHtml) {
            processedText = cleanGutenbergText(htmlToPlainText(raw));
          } else {
            processedText = cleanGutenbergText(raw);
          }

          // Skip results that are too short or too noisy to be genuine book
          // content (likely an error page, OCR garbage, or an empty/stub file).
          if (processedText.length < 500 ||
              !_looksLikeReadableText(processedText)) {
            onDebug?.call(
              OpenLibraryDebugSnapshot(
                requestUrl: url,
                statusCode: resp.statusCode,
                success: false,
                bodyLength: resp.bodyBytes.length,
                bodyPreview: processedText.isEmpty ? '(empty)' : processedText,
                resultCount: null,
                error: processedText.length < 500
                    ? 'Insufficient content (${processedText.length} chars after cleaning)'
                    : 'Low-quality text source (likely OCR or encoding noise)',
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

  String _decodeTextBytes(Uint8List bytes) {
    final candidates = <String>[];
    try {
      candidates.add(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {}
    try {
      candidates.add(latin1.decode(bytes));
    } catch (_) {}
    candidates.add(utf8.decode(bytes, allowMalformed: true));

    final unique = <String>[];
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && !unique.contains(candidate)) {
        unique.add(candidate);
      }
    }
    unique.sort((a, b) => _textQualityScore(b).compareTo(_textQualityScore(a)));
    return unique.isNotEmpty ? unique.first : '';
  }

  double _textQualityScore(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return double.negativeInfinity;
    final wordMatches = RegExp(r"[A-Za-z][A-Za-z'\-]{2,}").allMatches(trimmed);
    final alphaCount = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    final replacementCount = RegExp(r'\uFFFD').allMatches(trimmed).length;
    final controlCount = RegExp(r'[\x00-\x1F]').allMatches(trimmed).length;
    final shortTokens = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.length <= 2)
        .length;
    return wordMatches.length * 3 +
        alphaCount / 25 -
        replacementCount * 6 -
        controlCount * 4 -
        shortTokens * 0.3;
  }

  bool _looksLikeReadableText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 50) return false;
    final readableWords = words.where((w) => w.length >= 3).length;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    final symbolCount =
        RegExp(r'[^A-Za-z0-9\s\.,;:!?()\[\]\-]').allMatches(trimmed).length;
    final readableRatio = readableWords / words.length;
    final letterRatio = letterCount / trimmed.length;
    return readableRatio >= 0.55 &&
        letterRatio >= 0.35 &&
        symbolCount / trimmed.length <= 0.15;
  }

  /// Fetches the IIIF manifest for the given archive.org item and returns an
  /// ordered list of page image URLs, or an empty list if unavailable.
  Future<List<String>> _fetchIIIFImagePages(
    String iaId, {
    void Function(OpenLibraryDebugSnapshot)? onDebug,
  }) async {
    // Archive.org IIIF manifest URL format:
    // https://iiif.archive.org/iiif/{item_id}/manifest.json
    final manifestUrl = 'https://iiif.archive.org/iiif/$iaId/manifest.json';
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
          .map(_normalizeIaId)
          .whereType<String>()
          .toSet()
          .toList();
    }
    // Fallback: derive IDs from text_sources URLs
    final textSources = book.formats['openlibrary/text_sources'];
    if (textSources == null || textSources.isEmpty) return const [];
    final iaIds = <String>{};
    for (final url in textSources.split('|')) {
      final match =
          RegExp(r'archive\.org/download/([^/]+)/').firstMatch(url.trim());
      if (match != null) {
        final normalized = _normalizeIaId(match.group(1)!);
        if (normalized != null) iaIds.add(normalized);
      }
    }
    return iaIds.toList();
  }

  /// Loads book content — EPUB bytes first, then legacy plain-text fallback.
  Future<BookContent> fetchBookContent(
    Book book, {
    void Function(OpenLibraryDebugSnapshot)? onDebug,
    bool preferEpub = true,
    int? userAge,
  }) async {
    if (!_isBookAllowedForAge(book, userAge)) {
      throw Exception('This title is restricted for the selected age profile.');
    }
    if (preferEpub) {
      // Prefer formatted EPUB bytes first so the viewer can preserve layout.
      final epubPayload = await _fetchBookEpubBytes(book, onDebug: onDebug);
      if (epubPayload != null && epubPayload.$1.isNotEmpty) {
        return BookContent.epub(
          epubPayload.$1,
          epubSourceUrl: epubPayload.$2,
        );
      }
    }

    // Fallback: legacy plain-text sources.
    try {
      final text = await fetchBookText(
        book,
        onDebug: onDebug,
        userAge: userAge,
      );
      return BookContent.text(text);
    } catch (e) {
      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://book/${book.id}/text-fetch-failed',
        statusCode: null,
        success: false,
        bodyLength: 0,
        bodyPreview: '',
        resultCount: 0,
        error: 'Text unavailable after EPUB fallback: $e',
        timestamp: DateTime.now(),
      ));
    }

    throw Exception(
      'No readable content available for this book. '
      'The edition may be restricted or temporarily unavailable.',
    );
  }

  /// Extracts ordered HTML strings from an EPUB zip.
  ///
  /// Reads container.xml → OPF → spine → HTML files in spine order.
  /// Uses lenient UTF-8 decoding so malformed bytes never throw.
  /// Returns null if the EPUB cannot be parsed or yields no readable HTML.
  Future<List<String>?> extractEpubHtmlSpine(
    Uint8List epubBytes, {
    void Function(OpenLibraryDebugSnapshot)? onDebug,
  }) async {
    try {
      final archive = ZipDecoder().decodeBytes(epubBytes);

      // 1. container.xml → OPF path
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) return null;
      final containerXml = utf8.decode(
        containerFile.content as List<int>,
        allowMalformed: true,
      );
      final opfPathMatch = RegExp(
        r'full-path="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(containerXml);
      if (opfPathMatch == null) return null;
      final opfPath = opfPathMatch.group(1)!;
      final opfDir = opfPath.contains('/')
          ? '${opfPath.substring(0, opfPath.lastIndexOf('/') + 1)}'
          : '';

      // 2. OPF → manifest + spine
      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) return null;
      final opfContent =
          utf8.decode(opfFile.content as List<int>, allowMalformed: true);

      // Detect whether this is an Internet Archive auto-generated EPUB.
      // IA always stamps the OPF with their name in dc:publisher, dc:creator,
      // dc:contributor, or a <meta> referencing archive.org / Internet Archive.
      final isInternetArchive = _isInternetArchiveOpf(opfContent);

      // Parse manifest: id → href
      final idToHref = <String, String>{};
      for (final m in RegExp(
        r'<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"',
        caseSensitive: false,
      ).allMatches(opfContent)) {
        idToHref[m.group(1)!] = m.group(2)!;
      }
      for (final m in RegExp(
        r'<item\b[^>]*\bhref="([^"]+)"[^>]*\bid="([^"]+)"',
        caseSensitive: false,
      ).allMatches(opfContent)) {
        idToHref.putIfAbsent(m.group(2)!, () => m.group(1)!);
      }

      // Parse spine order
      final spineSection = RegExp(
            r'<spine\b[^>]*>(.*?)</spine>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(opfContent)?.group(1) ??
          '';
      final spineIds = RegExp(
        r'<itemref\b[^>]*\bidref="([^"]+)"',
        caseSensitive: false,
      ).allMatches(spineSection).map((m) => m.group(1)!).toList();

      // 3. Read HTML files in spine order
      final htmlPages = <String>[];
      final seen = <String>{};
      var skippedEmptyPages = 0;
      var scannedSpinePages = 0;

      for (final id in spineIds) {
        var href = idToHref[id];
        if (href == null) continue;
        if (href.contains('#')) href = href.split('#').first;
        if (!seen.add(href)) continue;

        final lower = href.toLowerCase();
        // Skip nav / toc files — these are structural, not content
        if (lower.contains('toc') ||
            lower.contains('ncx') ||
            lower == 'nav.xhtml' ||
            lower == 'nav.html' ||
            lower.endsWith('/nav.xhtml') ||
            lower.endsWith('/nav.html')) continue;

        scannedSpinePages++;

        final fullPath = opfDir.isEmpty ? href : '$opfDir$href';
        final file = archive.findFile(fullPath) ?? archive.findFile(href);
        if (file == null) continue;

        final raw = utf8.decode(
          file.content as List<int>,
          allowMalformed: true,
        );
        if (raw.trim().isEmpty) continue;
        final cleaned =
            isInternetArchive ? _cleanInternetArchiveHtml(raw) : raw;
        if (isInternetArchive &&
            _isInternetArchiveIntroPage(cleaned,
                spinePosition: scannedSpinePages)) {
          skippedEmptyPages++;
          continue;
        }
        if (_isMeaningfulHtmlPage(cleaned)) {
          htmlPages.add(cleaned);
        } else {
          skippedEmptyPages++;
        }
      }

      // Fallback: if spine parsing gave nothing, collect all HTML files sorted
      if (htmlPages.isEmpty) {
        final fallbackFiles = archive.files.where((f) {
          final n = f.name.toLowerCase();
          return (n.endsWith('.html') ||
                  n.endsWith('.xhtml') ||
                  n.endsWith('.htm')) &&
              !n.contains('toc') &&
              !n.contains('ncx') &&
              !n.endsWith('nav.xhtml') &&
              !n.endsWith('nav.html');
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        for (final f in fallbackFiles) {
          final raw = utf8.decode(f.content as List<int>, allowMalformed: true);
          if (raw.trim().isNotEmpty) {
            final cleaned =
                isInternetArchive ? _cleanInternetArchiveHtml(raw) : raw;
            if (_isMeaningfulHtmlPage(cleaned)) {
              htmlPages.add(cleaned);
            } else {
              skippedEmptyPages++;
            }
          }
        }
      }

      // Fail-open: if filtering removed everything, retry without filtering so
      // we never hide an entire book due to a strict heuristic.
      if (htmlPages.isEmpty && skippedEmptyPages > 0) {
        for (final id in spineIds) {
          var href = idToHref[id];
          if (href == null) continue;
          if (href.contains('#')) href = href.split('#').first;
          final lower = href.toLowerCase();
          if (lower.contains('toc') ||
              lower.contains('ncx') ||
              lower == 'nav.xhtml' ||
              lower == 'nav.html' ||
              lower.endsWith('/nav.xhtml') ||
              lower.endsWith('/nav.html')) {
            continue;
          }
          final fullPath = opfDir.isEmpty ? href : '$opfDir$href';
          final file = archive.findFile(fullPath) ?? archive.findFile(href);
          if (file == null) continue;
          final raw =
              utf8.decode(file.content as List<int>, allowMalformed: true);
          if (raw.trim().isEmpty) continue;
          htmlPages
              .add(isInternetArchive ? _cleanInternetArchiveHtml(raw) : raw);
        }
      }

      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://epub-html-spine',
        statusCode: null,
        success: htmlPages.isNotEmpty,
        bodyLength: htmlPages.fold(0, (s, h) => s + h.length),
        bodyPreview:
            'spineItems=${spineIds.length} htmlPages=${htmlPages.length} skippedEmpty=$skippedEmptyPages',
        resultCount: htmlPages.length,
        error: htmlPages.isEmpty
            ? 'No readable HTML pages found in EPUB spine.'
            : null,
        timestamp: DateTime.now(),
      ));

      return htmlPages.isEmpty ? null : htmlPages;
    } catch (e) {
      onDebug?.call(OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://epub-html-spine',
        statusCode: null,
        success: false,
        bodyLength: 0,
        bodyPreview: '',
        resultCount: 0,
        error: 'EPUB HTML spine extraction failed: $e',
        timestamp: DateTime.now(),
      ));
      return null;
    }
  }

  Future<String?> fetchPdfTextForEpubUrl(
    String epubUrl, {
    void Function(OpenLibraryDebugSnapshot snapshot)? onDebug,
  }) async {
    final pdfUrls = _buildPdfFallbackSourcesFromEpub(epubUrl);
    if (pdfUrls.isEmpty) return null;

    onDebug?.call(
      OpenLibraryDebugSnapshot(
        requestUrl: 'openlibrary://pdf-fallback/candidates',
        statusCode: null,
        success: true,
        bodyLength: pdfUrls.join('\n').length,
        bodyPreview: pdfUrls.join('\n'),
        resultCount: pdfUrls.length,
        error: null,
        timestamp: DateTime.now(),
      ),
    );

    for (final pdfUrl in pdfUrls) {
      final sw = Stopwatch()..start();
      try {
        final resp = await _getWithRetry(
          Uri.parse(pdfUrl),
          timeout: _pdfTimeout,
          maxAttempts: _pdfMaxAttempts,
          onAttemptStart: (attempt) {
            onDebug?.call(
              OpenLibraryDebugSnapshot(
                requestUrl: pdfUrl,
                statusCode: null,
                success: true,
                bodyLength: 0,
                bodyPreview:
                    'stage=request-attempt attempt=$attempt/$_pdfMaxAttempts timeoutSec=${_pdfTimeout.inSeconds}',
                resultCount: null,
                error: null,
                timestamp: DateTime.now(),
              ),
            );
          },
        );
        sw.stop();

        if (resp.statusCode != 200) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: pdfUrl,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview:
                  'elapsedMs=${sw.elapsedMilliseconds}\n${_preview(resp.body)}',
              resultCount: null,
              error: 'HTTP ${resp.statusCode}',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }

        final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
        final looksLikePdf = resp.bodyBytes.length >= 4 &&
            resp.bodyBytes[0] == 0x25 &&
            resp.bodyBytes[1] == 0x50 &&
            resp.bodyBytes[2] == 0x44 &&
            resp.bodyBytes[3] == 0x46;

        if (resp.bodyBytes.length > _maxPdfBytes) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: pdfUrl,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview:
                  'elapsedMs=${sw.elapsedMilliseconds}\nContent-Type: $contentType',
              resultCount: null,
              error:
                  'PDF is too large (${resp.bodyBytes.length} bytes) for fallback extraction budget.',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }

        if (!contentType.contains('pdf') && !looksLikePdf) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: pdfUrl,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview:
                  'elapsedMs=${sw.elapsedMilliseconds}\nContent-Type: $contentType',
              resultCount: null,
              error: 'Source is not PDF content',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }

        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: pdfUrl,
            statusCode: resp.statusCode,
            success: true,
            bodyLength: resp.bodyBytes.length,
            bodyPreview:
                'stage=extract-start elapsedMs=${sw.elapsedMilliseconds} bytes=${resp.bodyBytes.length}',
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );

        final parseSw = Stopwatch()..start();
        final rawText = await Isolate.run<String>(
          () => _extractPdfText(resp.bodyBytes),
        ).timeout(_pdfExtractTimeout);
        parseSw.stop();

        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: pdfUrl,
            statusCode: resp.statusCode,
            success: true,
            bodyLength: rawText.length,
            bodyPreview:
                'stage=extract-finished parseMs=${parseSw.elapsedMilliseconds}',
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );

        final cleaned = cleanGutenbergText(rawText).trim();
        if (cleaned.length < 500 || !_looksLikeReadableText(cleaned)) {
          onDebug?.call(
            OpenLibraryDebugSnapshot(
              requestUrl: pdfUrl,
              statusCode: resp.statusCode,
              success: false,
              bodyLength: resp.bodyBytes.length,
              bodyPreview:
                  'elapsedMs=${sw.elapsedMilliseconds}\n${cleaned.isEmpty ? '(empty)' : _preview(cleaned)}',
              resultCount: null,
              error: cleaned.length < 500
                  ? 'PDF extracted insufficient content (${cleaned.length} chars)'
                  : 'PDF extracted text quality is too low',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }

        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: pdfUrl,
            statusCode: resp.statusCode,
            success: true,
            bodyLength: resp.bodyBytes.length,
            bodyPreview:
                'elapsedMs=${sw.elapsedMilliseconds}\n${_preview(cleaned)}',
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );
        return cleaned;
      } catch (e) {
        sw.stop();
        onDebug?.call(
          OpenLibraryDebugSnapshot(
            requestUrl: pdfUrl,
            statusCode: null,
            success: false,
            bodyLength: 0,
            bodyPreview: 'elapsedMs=${sw.elapsedMilliseconds}',
            resultCount: null,
            error: 'PDF fallback failed: ${_friendlyNetworkError(e)}',
            timestamp: DateTime.now(),
          ),
        );
      }
    }

    return null;
  }

  List<String> _buildPdfFallbackSourcesFromEpub(String epubUrl) {
    final urls = <String>{};
    final derived = _derivePdfUrlFromEpub(epubUrl);
    if (derived != null) urls.add(derived);

    final uri = Uri.tryParse(epubUrl);
    if (uri != null && uri.host.toLowerCase().contains('archive.org')) {
      final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length >= 3 && parts.first.toLowerCase() == 'download') {
        final iaId = parts[1];
        urls.add('https://archive.org/download/$iaId/$iaId.pdf');
      }
    }

    return urls.toList();
  }

  String? _derivePdfUrlFromEpub(String epubUrl) {
    final uri = Uri.tryParse(epubUrl);
    if (uri == null) return null;
    final path = uri.path;
    if (!path.toLowerCase().endsWith('.epub')) return null;
    final pdfPath = '${path.substring(0, path.length - 5)}.pdf';
    return uri.replace(path: pdfPath).toString();
  }

  Uri _buildListUri({
    String? topic,
    String? search,
    required String languages,
    required int page,
    String? ebookAccess,
  }) {
    if (search != null && search.trim().isNotEmpty) {
      return Uri.parse('$_base/search.json').replace(queryParameters: {
        'q': search.trim(),
        'language': _openLibraryLang(languages),
        'page': page.toString(),
        'limit': _pageSize.toString(),
        'has_fulltext': 'true',
        if (ebookAccess != null) 'ebook_access': ebookAccess,
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
      if (ebookAccess != null) 'ebook_access': ebookAccess,
    });
  }

  OpenLibraryResponse _parseSearchResponse(
      Map<String, dynamic> json, Uri uri, int page,
      {int? userAge}) {
    final docs = (json['docs'] as List<dynamic>? ?? []);
    final results = docs
        .map((d) => _mapSearchDocToBook(d as Map<String, dynamic>))
        .whereType<Book>()
        .where((b) => _isBookAllowedForAge(b, userAge))
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
        'image/jpeg':
            'https://covers.openlibrary.org/b/id/${doc['cover_i']}-L.jpg',
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
          'image/jpeg':
              'https://covers.openlibrary.org/b/id/${covers.first}-L.jpg',
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
      final searchBook =
          _mapSearchDocToBook(docs.first as Map<String, dynamic>);
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
    final mergedEbookAccess = primary.ebookAccess != EbookAccess.unknown
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
    final ids = <String>[];
    for (final id in ia.take(3)) {
      final normalized = _normalizeIaId(id.toString());
      if (normalized != null) ids.add(normalized);
    }
    return ids.toSet().toList();
  }

  Future<List<String>> _discoverIaIds(Book book) async {
    final ids = <String>{};
    final workKey = _normalizeWorkKey(book.formats['openlibrary/work_key']) ??
        '/works/OL${book.id}W';
    final editionsUri =
        Uri.parse('$_base$workKey/editions.json').replace(queryParameters: {
      'limit': '50',
    });
    try {
      final resp = await _getWithRetry(editionsUri, timeout: _timeout);
      if (resp.statusCode != 200) return const [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final entries = (data['entries'] as List<dynamic>? ?? []);
      for (final entry in entries.take(50)) {
        if (entry is! Map<String, dynamic>) continue;
        ids.addAll(_collectIaIds(entry));
        final ocaid = entry['ocaid'];
        if (ocaid is String) {
          final normalized = _normalizeIaId(ocaid);
          if (normalized != null) ids.add(normalized);
        }
      }
    } catch (_) {
      // Best-effort only; caller handles image fallback semantics.
    }
    return ids.toList();
  }

  List<String> _collectTextSources(Map<String, dynamic> source) {
    final results = <String>[];
    final ia = source['ia'];
    if (ia is List && ia.isNotEmpty) {
      for (final id in ia.take(3)) {
        final iaId = _normalizeIaId(id.toString());
        if (iaId == null) continue;
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

  List<String> _collectEpubSources(Map<String, dynamic> source) {
    final results = <String>[];
    final ia = source['ia'];
    if (ia is List && ia.isNotEmpty) {
      for (final id in ia.take(3)) {
        final iaId = _normalizeIaId(id.toString());
        if (iaId == null) continue;
        results.add('https://archive.org/download/$iaId/$iaId.epub');
      }
    }
    final gutenberg = source['id_project_gutenberg'];
    if (gutenberg is List && gutenberg.isNotEmpty) {
      final gid = gutenberg.first.toString();
      results.add('https://www.gutenberg.org/cache/epub/$gid/pg$gid.epub');
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

  /// Normalizes raw archive.org item IDs into a IIIF-safe identifier.
  /// Accepts raw IDs, archive URLs (`/details/` or `/download/`), trims
  /// query/fragment/trailing `$`, and validates allowed characters.
  String? _normalizeIaId(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    final urlMatch = RegExp(r'archive\.org/(?:details|download)/([^/?#]+)',
            caseSensitive: false)
        .firstMatch(value);
    if (urlMatch != null) {
      value = urlMatch.group(1) ?? value;
    }

    value = value.split('?').first.split('#').first;
    value = value.replaceAll(r'$', '').trim();
    value = value.replaceFirst(RegExp(r'^/+'), '');
    value = value.split('/').first;

    if (value.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) return null;
    if (value.length < 3) return null;
    return value;
  }

  String _openLibraryLang(String code) {
    if (code == 'en') return 'eng';
    return code;
  }

  bool _isTopicAllowedForAge(String? topic, int? userAge) {
    if (topic == null || topic.trim().isEmpty) return true;
    final normalized = topic.trim().toLowerCase();
    if (userAge == null || userAge < 13) {
      return !_childBlockedTopics.contains(normalized);
    }
    if (userAge < 18) {
      return !_minorBlockedTopics.contains(normalized);
    }
    return true;
  }

  bool _isBookAllowedForAge(Book book, int? userAge) {
    if (userAge == null || userAge < 13) {
      return !_containsUnsafeKeywords(book, _childUnsafeKeywords);
    }
    if (userAge < 18) {
      return !_containsUnsafeKeywords(book, _minorUnsafeKeywords);
    }
    return true;
  }

  bool _containsUnsafeKeywords(Book book, List<String> unsafeKeywords) {
    final buffer = StringBuffer(book.title.toLowerCase());
    for (final s in book.subjects) {
      buffer.write(' ');
      buffer.write(s.toLowerCase());
    }
    for (final s in book.bookshelves) {
      buffer.write(' ');
      buffer.write(s.toLowerCase());
    }
    final text = buffer.toString();
    for (final keyword in unsafeKeywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
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

  List<String> _buildEpubSources(Book book) {
    final sources = <String>{};
    final fmts = book.formats;
    final entries = fmts.entries.toList();
    for (final entry in entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('epub') || entry.value.toLowerCase().endsWith('.epub')) {
        sources.add(entry.value);
      }
    }
    final serialized = fmts['openlibrary/epub_sources'];
    if (serialized != null && serialized.isNotEmpty) {
      sources.addAll(serialized
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty));
    }
    for (final iaId in _getIaIds(book)) {
      sources.add('https://archive.org/download/$iaId/$iaId.epub');
    }
    return sources.toList();
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

  Future<List<String>> _discoverEpubSources(Book book) async {
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
        sources.addAll(_collectEpubSources(entry));
        final ocaid = entry['ocaid'];
        if (ocaid is String && ocaid.trim().isNotEmpty) {
          final normalized = _normalizeIaId(ocaid);
          if (normalized != null) {
            sources.add(
                'https://archive.org/download/$normalized/$normalized.epub');
          }
        }
      }
    } catch (_) {
      // Best-effort only; caller handles fallback semantics.
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
        RegExp(r'</?(p|div|h[1-6]|li|tr|br|hr)[^>]*>', caseSensitive: false),
        '\n\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = _decodeEntities(text);
    return text;
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&nbsp;', '\u00A0')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026')
        .replaceAll('&rsquo;', '\u2019')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rdquo;', '\u201D')
        .replaceAll('&ldquo;', '\u201C')
        .replaceAll('&thinsp;', '\u2009')
        .replaceAll('&ensp;', '\u2002')
        .replaceAll('&emsp;', '\u2003')
        // Hex numeric character references &#xNN; or &#XNN;
        .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code != null) return String.fromCharCodes([code]);
      return m.group(0)!;
    })
        // Decimal numeric character references &#NN;
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code != null) return String.fromCharCodes([code]);
      return m.group(0)!;
    });
  }

  /// Returns true if an EPUB HTML page has meaningful visible content.
  ///
  /// This intentionally uses conservative thresholds to keep short chapter
  /// title pages while removing whitespace/placeholder pages.
  bool _isMeaningfulHtmlPage(String html) {
    if (html.trim().isEmpty) return false;

    final plain = htmlToPlainText(html)
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) return false;

    // Keep heading-only pages such as "Chapter I".
    final hasHeadingTag =
        RegExp(r'<h[1-6]\b', caseSensitive: false).hasMatch(html);
    final alphaCount = RegExp(r'[A-Za-z]').allMatches(plain).length;
    if (hasHeadingTag && alphaCount >= 3) return true;

    // Reject pages that are effectively only punctuation/digits.
    final hasLetter = alphaCount > 0;
    final hasDigit = RegExp(r'\d').hasMatch(plain);
    final hasOnlyPunctOrSpace = RegExp(r'^[^A-Za-z0-9]*$').hasMatch(plain);
    if (hasOnlyPunctOrSpace) return false;
    if (!hasLetter && hasDigit && plain.length <= 3) return false;

    // Keep even short textual pages, but require some actual letters.
    return hasLetter || plain.length >= 4;
  }

  String cleanGutenbergText(String text) {
    // Strip Project Gutenberg header and footer.
    final startRegex = RegExp(
        r'\*{3}\s*START OF (THE|THIS) PROJECT GUTENBERG[^\n]*\n',
        caseSensitive: false);
    final startMatch = startRegex.firstMatch(text);
    if (startMatch != null) {
      text = text.substring(startMatch.end);
    }
    final endRegex = RegExp(r'\*{3}\s*END OF (THE|THIS) PROJECT GUTENBERG',
        caseSensitive: false);
    final endMatch = endRegex.firstMatch(text);
    if (endMatch != null) {
      text = text.substring(0, endMatch.start);
    }

    // Normalize Windows / old-Mac line endings to Unix newlines.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Replace form-feed characters (0x0C) — used as page separators in DJVU /
    // archive.org text layers — with a paragraph break so they don't appear
    // as visible "gibberish" glyphs.
    text = text.replaceAll('\f', '\n\n');

    // Remove UTF-8 replacement characters that arise from malformed byte
    // sequences decoded with allowMalformed:true.
    text = text.replaceAll('\uFFFD', '');

    // Strip remaining ASCII control characters (except newlines and tabs).
    text = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0E-\x1F\x7F]'), '');

    // Convert tabs to a single space.
    text = text.replaceAll('\t', ' ');

    // Join hard-wrapped prose lines.  Project Gutenberg and archive.org plain-
    // text files wrap long lines at ~72 characters using single newlines, while
    // true paragraph breaks are marked with two or more newlines.  Collapsing
    // each single newline to a space reunites split sentences so the Flutter
    // Text widget can re-flow them at the correct screen width.
    final paragraphBreak = RegExp(r'\n{2,}');
    final paragraphs = text.split(paragraphBreak);
    text = paragraphs
        .map((para) =>
            para.replaceAll('\n', ' ').replaceAll(RegExp(r' {2,}'), ' ').trim())
        .where((para) => para.isNotEmpty)
        .join('\n\n');

    // Collapse any leftover runs of 4+ blank lines to at most three.
    text = text.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
    return text.trim();
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    required Duration timeout,
    int maxAttempts = _maxAttempts,
    void Function(int attempt)? onAttemptStart,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        onAttemptStart?.call(attempt);
        // Keep User-Agent stable and non-identifying (no username/device name).
        return await http.get(uri, headers: {
          'User-Agent': _userAgent,
        }).timeout(timeout);
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

  static String _extractPdfText(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
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

  /// Returns true when the OPF metadata identifies this as an Internet Archive
  /// auto-generated EPUB. IA always stamps their EPUBs with their name in one
  /// or more of the Dublin Core metadata elements.
  bool _isInternetArchiveOpf(String opfContent) {
    final metadata = RegExp(
          r'<metadata\b[^>]*>(.*?)</metadata>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(opfContent)?.group(1) ??
        opfContent;

    // Restrict checks to metadata field values to avoid false positives from
    // unrelated URLs elsewhere in the OPF.
    const fields = [
      'publisher',
      'creator',
      'contributor',
      'source',
      'description'
    ];
    for (final field in fields) {
      final value = RegExp(
            '<(?:dc:)?$field\\b[^>]*>(.*?)</(?:dc:)?$field>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(metadata)?.group(1) ??
          '';
      final normalized = value.toLowerCase();
      if (normalized.contains('internet archive') ||
          normalized.contains('archive.org') ||
          normalized.contains('internetarchive')) {
        return true;
      }
    }

    // Fallback to explicit metadata tags mentioning IA.
    return RegExp(
      r'<meta\b[^>]*(?:internet\s*archive|archive\.org|internetarchive)[^>]*>',
      caseSensitive: false,
    ).hasMatch(metadata);
  }

  /// Cleans Internet Archive-specific boilerplate from an EPUB HTML page.
  ///
  /// Uses structural markers that IA itself embeds rather than fragile text
  /// matching of arbitrary content:
  ///
  /// 1. IA pages include `<meta name="generator"` or `<meta name="ocr_…">`
  ///    tags — we use that to confirm this is indeed an IA page before cleaning.
  /// 2. The accuracy disclaimer is always the very first `<p>` or `<div>` in
  ///    `<body>` that contains a percentage marker near the word "accurate".
  ///    IA does not put any other content before it on the page.
  /// 3. IA introductory pages (the "This book was produced in EPUB format…"
  ///    notice) are identified by the absence of any substantial text outside
  ///    that block, and skipped entirely if they have less than 200 chars of
  ///    real content after stripping.
  String _cleanInternetArchiveHtml(String html) {
    // Only apply cleaning if this page carries clear IA markers.
    final headMatch = RegExp(
          r'<head\b[^>]*>(.*?)</head>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(html)?.group(1) ??
        '';

    final hasIaMeta = RegExp(
      r'<meta\b[^>]*(?:ocr[_-]|archive\.org|internetarchive|internet\s*archive)[^>]*>',
      caseSensitive: false,
    ).hasMatch(headMatch);

    // If the page has no explicit IA marker, do not modify it.
    if (!hasIaMeta) return html;

    final originalVisibleText = html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    var cleaned = html;

    // Remove IA OCR accuracy disclaimer block.
    cleaned = cleaned.replaceAllMapped(
      RegExp(
        r'<(p|div|section)\b([^>]*)>((?:(?!</\1>).)*?estimated\s+to\s+be\s+only(?:(?!</\1>).)*?%(?:(?!</\1>).)*?accurat(?:(?!</\1>).)*?)</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) {
        final inner = m.group(3) ?? '';
        final strippedText = inner
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (strippedText.length < 220) {
          return '';
        }
        return m.group(0)!;
      },
    );

    // Fail-safe: if cleanup wipes nearly all visible text, keep original page.
    final cleanedVisibleText = cleaned
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (originalVisibleText.isNotEmpty &&
        cleanedVisibleText.length <
            (originalVisibleText.length * 0.1).floor().clamp(40, 999999)) {
      return html;
    }

    return cleaned;
  }

  /// Returns true when a page looks like IA introductory boilerplate.
  ///
  /// This is intentionally conservative and only applies to early spine pages
  /// to avoid dropping legitimate front-matter or chapter content.
  bool _isInternetArchiveIntroPage(
    String html, {
    required int spinePosition,
  }) {
    // IA boilerplate appears at the beginning; do not inspect deep pages.
    if (spinePosition > 8) return false;

    final plain = htmlToPlainText(html)
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) return true;

    final lower = plain.toLowerCase();
    final hasHeading =
        RegExp(r'<h[1-6]\b', caseSensitive: false).hasMatch(html);
    final hasChapterLikeText = RegExp(
      r'\b(chapter|prologue|epilogue|part\s+[ivx0-9]+|preface|foreword|introduction)\b',
      caseSensitive: false,
    ).hasMatch(plain);

    // Keep likely real content/title pages.
    if (hasHeading && hasChapterLikeText) return false;

    // Multi-signal score for IA boilerplate wording variants.
    var score = 0;
    if (lower.contains('internet archive') || lower.contains('archive.org')) {
      score += 2;
    }
    if (lower.contains('epub format')) score += 1;
    if (lower.contains('scanned')) score += 1;
    if (lower.contains('ocr')) score += 1;
    if (lower.contains('estimated to be only') ||
        (lower.contains('%') && lower.contains('accurat'))) {
      score += 2;
    }
    if (lower.contains('converted') && lower.contains('automatically')) {
      score += 1;
    }
    if (lower.contains('digitiz')) score += 1;

    final wordCount =
        plain.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    // Drop pages with strong IA boilerplate signal and short explanatory text.
    if (score >= 4 && !hasChapterLikeText && wordCount <= 380) return true;

    // Extra-safe high-confidence shortcut for known IA lead-in wording.
    if ((lower.contains('produced in epub format') ||
            lower.contains('scanned and converted')) &&
        lower.contains('internet archive') &&
        wordCount <= 500 &&
        !hasChapterLikeText) {
      return true;
    }

    return false;
  }

  /// Strips Internet Archive boilerplate from EPUB HTML pages.
  ///
  /// Kept for backward compatibility; delegates to [_cleanInternetArchiveHtml].
  @Deprecated('Use _cleanInternetArchiveHtml with OPF-based detection instead.')
  String _cleanArchiveHtml(String html) => _cleanInternetArchiveHtml(html);
}
