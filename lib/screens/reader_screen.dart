import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:epubx/epubx.dart' show EpubReader;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../providers/library_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../providers/suggestions_provider.dart';
import '../services/openlibrary_service.dart';
import '../services/storage_service.dart';
import '../widgets/reader_controls.dart';
import '../widgets/reader_settings_sheet.dart';

class ReaderScreen extends StatefulWidget {
  final int bookId;
  final Book? initialBook;
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.initialBook,
  });
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _openLibrary = OpenLibraryService();
  final _storage = StorageService();

  BookContent? _content;
  Book? _book;
  EpubController? _epubController;
  EpubSource? _epubSource;
  EpubLocation? _epubLocation;
  List<EpubChapter> _epubChapters = const [];
  bool _epubViewerLoaded = false;
  bool _loading = true;
  String? _error;
  final List<OpenLibraryDebugSnapshot> _debugSnapshots = [];
  bool _showDebugPanel = false;


  bool get _isEpubBased => _content?.isEpubBased ?? false;
  bool get _isHtmlBased => _content?.isHtmlBased ?? false;

  List<String> _allPages = [];
  List<String> _pages = [];
  late PageController _pageController;
  late ScrollController _scrollController;
  int _currentPage = 0;
  double _scrollPercent = 0.0;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _scrollDebounce;
  Timer? _epubLoadTimeoutTimer;
  bool _epubFallbackTriggered = false;
  bool _epubEmptyContentLogged = false;
  Size? _lastSize;
  bool _loadingCancelled = false;

  /// Session tracking — set when content finishes loading.
  int? _sessionStartMs;
  int _sessionStartPage = 0;
  SuggestionsProvider? _suggestionsProvider;

  static const int _pageChunkSize = 10;
  // Upper bound on pages counted per session to guard against stale state.
  static const int _maxPagesPerSession = 999999;
  // Padding applied to each text page — must stay in sync with the Container
  // padding used in the page builder below so the layout calculation is accurate.
  static const double _pageHorizontalPadding = 24.0;
  static const double _pageTopPadding = 64.0;
  static const double _pageBottomPadding = 88.0;
  // Tap-zone thresholds: left zone = 0..30%, right zone = 70%..100% of screen width.
  static const double _leftZoneThreshold = 0.30;
  static const double _rightZoneThreshold = 0.70;
  // Fraction of screen height scrolled per tap in continuous-scroll mode.
  static const double _scrollPageFraction = 0.90;
  // Minimum scroll-percent change before updating progress and triggering setState.
  static const double _scrollProgressThreshold = 0.005;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pageController = PageController();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _scrollDebounce?.cancel();
    _epubLoadTimeoutTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    _clearEpubController();
    // Persist session stats (fire-and-forget; context is no longer available).
    final sp = _suggestionsProvider;
    if (sp != null && _sessionStartMs != null) {
      final elapsed =
          (DateTime.now().millisecondsSinceEpoch - _sessionStartMs!) ~/ 1000;
      final pages = (_currentPage - _sessionStartPage)
          .clamp(0, _maxPagesPerSession)
          .toInt();
      sp.recordSessionStats(
        widget.bookId,
        pagesRead: pages,
        sessionSeconds: elapsed,
      );
    }
    super.dispose();
  }

  void _cancelLoading() {
    _loadingCancelled = true;
    Navigator.pop(context);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _debugSnapshots.clear();
        _showDebugPanel = false;
      });
    }
    try {
      final initial = widget.initialBook;
      Book? book = initial;
      if (initial != null) {
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/initial-book',
            statusCode: null,
            success: true,
            bodyLength: initial.formats.length,
            bodyPreview: initial.formats.keys.join(', '),
            resultCount: initial.formats.length,
            error: null,
            timestamp: DateTime.now(),
          ),
        );
      }
      if (_loadingCancelled) return;
      final offlineEpub = await _storage.getOfflineEpubFile(widget.bookId);
      if (offlineEpub != null) {
        if (_loadingCancelled) return;
        // ...existing code...
      }

      if (_loadingCancelled) return;
      final offline = await _storage.getOfflineText(widget.bookId);
      if (offline != null) {
        // ...existing code...
      }

      if (_loadingCancelled) return;
      book ??= await _openLibrary.fetchBook(widget.bookId);
      if (_loadingCancelled) return;
      final content = await _openLibrary.fetchBookContent(
        book,
        onDebug: _recordDebug,
      );
      if (_loadingCancelled) return;
      if (mounted) {
        // ...existing code...
      }
    } catch (e) {
      // ...existing code...
    }
  }

  /// Restores reading position for HTML spine mode.
  void _restoreHtmlProgress() {
    final spine = _content?.htmlSpine;
    if (spine == null || spine.isEmpty) return;
    final savedPercent =
        context.read<LibraryProvider>().getProgress(widget.bookId)?.percent ?? 0;
    final startPage = savedPercent == 0
        ? 0
        : (savedPercent * spine.length)
            .floor()
            .clamp(0, spine.length - 1)
            .toInt();
    setState(() => _currentPage = startPage);
    if (startPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(startPage);
        }
      });
    }
    _scheduleHide();
  }

  Future<void> _setEpubController(Uint8List bytes) async {
    _clearEpubController();
    final sourceChecksum = _quickChecksum(bytes);
    final sourceLooksZip =
        bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    final sourceInspection = await _inspectEpubBytes(bytes);

    final file = await _writeTempEpub(bytes);
    final fileBytes = await file.readAsBytes();
    final fileChecksum = _quickChecksum(fileBytes);
    final bytesRoundTripOk =
        bytes.length == fileBytes.length && sourceChecksum == fileChecksum;

    final controller = EpubController();
    _epubController = controller;
    _epubSource = EpubSource.fromFile(file);
    _epubLocation = null;
    _epubChapters = const [];
    _epubViewerLoaded = false;
    _epubFallbackTriggered = false;
    _epubEmptyContentLogged = false;
    _recordDebug(
      OpenLibraryDebugSnapshot(
        requestUrl: 'reader://book/${widget.bookId}/epub-viewer-state',
        statusCode: null,
        success: bytesRoundTripOk,
        bodyLength: bytes.length,
        bodyPreview: 'state=initializing source=${file.path}\n'
            'sourceZip=$sourceLooksZip sourceBytes=${bytes.length} sourceChecksum=$sourceChecksum\n'
            'fileBytes=${fileBytes.length} fileChecksum=$fileChecksum roundTripOk=$bytesRoundTripOk\n'
            '$sourceInspection',
        resultCount: null,
        error: bytesRoundTripOk
            ? null
            : 'EPUB bytes changed when writing/reading temp file.',
        timestamp: DateTime.now(),
      ),
    );
    _epubLoadTimeoutTimer = Timer(const Duration(seconds: 14), () {
      if (!mounted || _epubFallbackTriggered) return;
      if (!_epubViewerLoaded) {
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/epub-timeout',
            statusCode: null,
            success: false,
            bodyLength: 0,
            bodyPreview: '',
            resultCount: null,
            error: 'EPUB viewer timed out before onEpubLoaded callback.',
            timestamp: DateTime.now(),
          ),
        );
        _fallbackFromEpub(
          reason: 'EPUB viewer timed out before finishing initial load.',
        );
      }
    });
  }

  Future<File> _writeTempEpub(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}\\quietly_reader_${widget.bookId}_${DateTime.now().millisecondsSinceEpoch}.epub',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  int _quickChecksum(Uint8List bytes) {
    var hash = 2166136261;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<String> _inspectEpubBytes(Uint8List bytes) async {
    try {
      final book = await EpubReader.readBook(bytes);
      final chapterCount = book.Chapters?.length ?? 0;
      final htmlCount = book.Content?.Html?.length ?? 0;
      final cssCount = book.Content?.Css?.length ?? 0;
      final imageCount = book.Content?.Images?.length ?? 0;
      return 'epubInspection chapters=$chapterCount htmlFiles=$htmlCount cssFiles=$cssCount images=$imageCount';
    } catch (e) {
      return 'epubInspection failed: $e';
    }
  }

  void _clearEpubController() {
    _epubLoadTimeoutTimer?.cancel();
    _epubLoadTimeoutTimer = null;
    final controller = _epubController;
    controller?.webViewController = null;
    _epubController = null;
    _epubSource = null;
    _epubLocation = null;
    _epubChapters = const [];
    _epubViewerLoaded = false;
  }

  Future<void> _fallbackFromEpub({required String reason}) async {
    if (_epubFallbackTriggered) return;
    _epubFallbackTriggered = true;
    _epubLoadTimeoutTimer?.cancel();

    _recordDebug(
      OpenLibraryDebugSnapshot(
        requestUrl: 'reader://book/${widget.bookId}/epub-fallback',
        statusCode: null,
        success: false,
        bodyLength: 0,
        bodyPreview: '',
        resultCount: null,
        error: '$reason Switching to PDF/text fallback.',
        timestamp: DateTime.now(),
      ),
    );

    try {
      final epubUrl = _content?.epubSourceUrl;
      if (epubUrl != null && epubUrl.isNotEmpty) {
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/pdf-fallback-start',
            statusCode: null,
            success: true,
            bodyLength: epubUrl.length,
            bodyPreview: epubUrl,
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );

        String? pdfText;
        try {
          pdfText = await _openLibrary
              .fetchPdfTextForEpubUrl(
                epubUrl,
                onDebug: _recordDebug,
              )
              .timeout(const Duration(seconds: 95));
        } on TimeoutException {
          _recordDebug(
            OpenLibraryDebugSnapshot(
              requestUrl:
                  'reader://book/${widget.bookId}/pdf-fallback-timeout',
              statusCode: null,
              success: false,
              bodyLength: 0,
              bodyPreview: '',
              resultCount: null,
              error:
                  'PDF fallback exceeded 95s budget. Continuing with EPUB text extraction.',
              timestamp: DateTime.now(),
            ),
          );
        }

        if (pdfText != null && pdfText.length >= 500) {
          if (!mounted) return;
          _clearEpubController();
          final resolvedPdfText = pdfText;
          _recordDebug(
            OpenLibraryDebugSnapshot(
              requestUrl: 'reader://book/${widget.bookId}/pdf-text-fallback',
              statusCode: null,
              success: true,
              bodyLength: resolvedPdfText.length,
              bodyPreview:
                  resolvedPdfText.length > 240
                      ? resolvedPdfText.substring(0, 240)
                      : resolvedPdfText,
              resultCount: null,
              error: null,
              timestamp: DateTime.now(),
            ),
          );
          setState(() {
            _content = BookContent.text(resolvedPdfText);
            _error = null;
          });
          _buildPages();
          return;
        }
      }

      final extracted = await _extractTextFromCurrentEpub();
      if (extracted != null && extracted.length >= 500) {
        if (!mounted) return;
        _clearEpubController();
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/epub-text-extract-fallback',
            statusCode: null,
            success: true,
            bodyLength: extracted.length,
            bodyPreview: extracted.length > 240
                ? extracted.substring(0, 240)
                : extracted,
            resultCount: null,
            error: null,
            timestamp: DateTime.now(),
          ),
        );
        setState(() {
          _content = BookContent.text(extracted);
          _error = null;
        });
        _buildPages();
        return;
      }

      final book = _book ?? widget.initialBook ?? await _openLibrary.fetchBook(widget.bookId);
      final fallback = await _openLibrary.fetchBookContent(
        book,
        onDebug: _recordDebug,
        preferEpub: false,
      );
      if (!mounted) return;

      _clearEpubController();
      setState(() {
        _book = book;
        _content = fallback;
        _error = null;
      });
      _buildPages();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'EPUB viewer failed and fallback could not be loaded: $e';
      });
    }
  }

  Future<String?> _extractTextFromCurrentEpub() async {
    final bytes = _content?.epubBytes;
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final epub = await EpubReader.readBook(bytes);
      final htmlFiles = epub.Content?.Html;
      if (htmlFiles == null || htmlFiles.isEmpty) {
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/epub-text-extract',
            statusCode: null,
            success: false,
            bodyLength: 0,
            bodyPreview: '',
            resultCount: 0,
            error: 'EPUB had no HTML content map to extract text from.',
            timestamp: DateTime.now(),
          ),
        );
        return null;
      }

      final keys = htmlFiles.keys.toList()..sort();
      final buffer = StringBuffer();
      for (final key in keys) {
        final lower = key.toLowerCase();
        if (lower.contains('toc') ||
            lower.contains('nav') ||
            lower.contains('contents')) {
          continue;
        }
        final html = htmlFiles[key]?.Content;
        if (html == null || html.trim().isEmpty) continue;
        final text = _openLibrary.cleanGutenbergText(
          _openLibrary.htmlToPlainText(html),
        );
        if (text.trim().isEmpty) continue;
        buffer.writeln(text.trim());
        buffer.writeln();
      }

      final extracted = buffer.toString().trim();
      _recordDebug(
        OpenLibraryDebugSnapshot(
          requestUrl: 'reader://book/${widget.bookId}/epub-text-extract',
          statusCode: null,
          success: extracted.isNotEmpty,
          bodyLength: extracted.length,
          bodyPreview: extracted.isEmpty
              ? '(empty)'
              : (extracted.length > 220
                  ? extracted.substring(0, 220)
                  : extracted),
          resultCount: keys.length,
          error: extracted.isEmpty
              ? 'EPUB HTML files were present but no readable text was extracted.'
              : null,
          timestamp: DateTime.now(),
        ),
      );
      return extracted.isEmpty ? null : extracted;
    } catch (e) {
      _recordDebug(
        OpenLibraryDebugSnapshot(
          requestUrl: 'reader://book/${widget.bookId}/epub-text-extract',
          statusCode: null,
          success: false,
          bodyLength: 0,
          bodyPreview: '',
          resultCount: null,
          error: 'EPUB text extraction failed: $e',
          timestamp: DateTime.now(),
        ),
      );
      return null;
    }
  }

  void _buildPages() {
    final content = _content;
    if (content == null) return;


    final size = MediaQuery.of(context).size;
    if (content.text == null || size.isEmpty) return;
    final settings =
        context.read<ReaderSettingsProvider>().forBook(widget.bookId);

    if (settings.scrollMode) {
      final savedPercent =
          context.read<LibraryProvider>().getProgress(widget.bookId)?.percent ??
              0;
      setState(() {
        _scrollPercent = savedPercent;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _restoreScrollPosition(savedPercent));
      _scheduleHide();
      return;
    }

    final allPages = _splitPages(
      text: content.text!,
      textWidth: size.width - _pageHorizontalPadding * 2,
      textHeight: size.height - _pageTopPadding - _pageBottomPadding,
      fontSize: settings.fontSize,
      lineHeightFactor: settings.lineHeightValue,
      fontFamily: _fontFamilyName(settings.fontFamily),
    );
    if (allPages.isEmpty) {
      _recordDebug(
        OpenLibraryDebugSnapshot(
          requestUrl: 'reader://book/${widget.bookId}/text-empty-pages',
          statusCode: null,
          success: false,
          bodyLength: content.text?.length ?? 0,
          bodyPreview: content.text == null ? '' : content.text!.substring(0, content.text!.length > 200 ? 200 : content.text!.length),
          resultCount: 0,
          error: 'Text content was loaded, but no readable pages were generated.',
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    final savedPercent =
        context.read<LibraryProvider>().getProgress(widget.bookId)?.percent ??
            0;
    final startPage = allPages.isEmpty
        ? 0
        : (savedPercent * allPages.length)
            .floor()
            .clamp(0, allPages.length - 1)
            .toInt();
    final initialCount = allPages.length <= _pageChunkSize
        ? allPages.length
        : (startPage + _pageChunkSize > allPages.length
            ? allPages.length
            : startPage + _pageChunkSize);

    setState(() {
      _allPages = allPages;
      _pages = allPages.sublist(0, initialCount);
      _currentPage = startPage;
    });
    if (startPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(startPage);
      });
    }
    _scheduleHide();
  }

  void _loadMorePages() {
    if (_pages.length >= _allPages.length) return;
    final nextEnd = (_pages.length + _pageChunkSize)
        .clamp(0, _allPages.length)
        .toInt();
    setState(() {
      _pages = _allPages.sublist(0, nextEnd);
    });
  }

  List<String> _splitPages({
    required String text,
    required double textWidth,
    required double textHeight,
    required double fontSize,
    required double lineHeightFactor,
    required String? fontFamily,
  }) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return [''];

    final paragraphs = normalized.split(RegExp(r'\n{2,}'));
    final pages = <String>[];
    var current = '';

    for (final rawPara in paragraphs) {
      final para = rawPara.trim();
      if (para.isEmpty) continue;

      final candidate = current.isEmpty ? para : '$current\n\n$para';
      if (_pageTextFits(
        candidate,
        textWidth: textWidth,
        textHeight: textHeight,
        fontSize: fontSize,
        lineHeightFactor: lineHeightFactor,
        fontFamily: fontFamily,
      )) {
        current = candidate;
        continue;
      }

      if (current.isNotEmpty) {
        pages.add(current);
        current = '';
      }

      if (_pageTextFits(
        para,
        textWidth: textWidth,
        textHeight: textHeight,
        fontSize: fontSize,
        lineHeightFactor: lineHeightFactor,
        fontFamily: fontFamily,
      )) {
        current = para;
        continue;
      }

      pages.addAll(_splitParagraphIntoPages(
        para,
        textWidth: textWidth,
        textHeight: textHeight,
        fontSize: fontSize,
        lineHeightFactor: lineHeightFactor,
        fontFamily: fontFamily,
      ));
    }

    if (current.isNotEmpty) pages.add(current);
    return pages.isEmpty ? [''] : pages;
  }

  List<String> _splitParagraphIntoPages(
    String paragraph, {
    required double textWidth,
    required double textHeight,
    required double fontSize,
    required double lineHeightFactor,
    required String? fontFamily,
  }) {
    final words = paragraph
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];

    final pages = <String>[];
    var start = 0;

    while (start < words.length) {
      var low = start + 1;
      var high = words.length;
      var best = start + 1;

      while (low <= high) {
        final mid = (low + high) >> 1;
        final candidate = words.sublist(start, mid).join(' ');
        if (_pageTextFits(
          candidate,
          textWidth: textWidth,
          textHeight: textHeight,
          fontSize: fontSize,
          lineHeightFactor: lineHeightFactor,
          fontFamily: fontFamily,
        )) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      if (best <= start) best = start + 1;
      final chunk = words.sublist(start, best).join(' ');

      if (_pageTextFits(
        chunk,
        textWidth: textWidth,
        textHeight: textHeight,
        fontSize: fontSize,
        lineHeightFactor: lineHeightFactor,
        fontFamily: fontFamily,
      )) {
        pages.add(chunk);
        start = best;
        continue;
      }

      pages.addAll(_splitLongToken(
        words[start],
        textWidth: textWidth,
        textHeight: textHeight,
        fontSize: fontSize,
        lineHeightFactor: lineHeightFactor,
        fontFamily: fontFamily,
      ));
      start += 1;
    }

    return pages;
  }

  List<String> _splitLongToken(
    String token, {
    required double textWidth,
    required double textHeight,
    required double fontSize,
    required double lineHeightFactor,
    required String? fontFamily,
  }) {
    final pages = <String>[];
    var start = 0;

    while (start < token.length) {
      var low = start + 1;
      var high = token.length;
      var best = start + 1;

      while (low <= high) {
        final mid = (low + high) >> 1;
        final candidate = token.substring(start, mid);
        if (_pageTextFits(
          candidate,
          textWidth: textWidth,
          textHeight: textHeight,
          fontSize: fontSize,
          lineHeightFactor: lineHeightFactor,
          fontFamily: fontFamily,
        )) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      if (best <= start) best = start + 1;
      pages.add(token.substring(start, best));
      start = best;
    }

    return pages;
  }

  bool _pageTextFits(
    String text, {
    required double textWidth,
    required double textHeight,
    required double fontSize,
    required double lineHeightFactor,
    required String? fontFamily,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: lineHeightFactor,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.justify,
      maxLines: null,
    )..layout(maxWidth: textWidth);
    return painter.height <= (textHeight - 2.0);
  }

  String? _fontFamilyName(FontFamily family) {
    switch (family) {
      case FontFamily.lora:
        return GoogleFonts.lora().fontFamily;
      case FontFamily.inter:
        return GoogleFonts.inter().fontFamily;
    }
  }

  void _restoreScrollPosition(double savedPercent) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0 && savedPercent > 0) {
      _scrollController.jumpTo((savedPercent * maxExtent).clamp(0, maxExtent));
    }
  }

  void _onTapUp(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dx = details.localPosition.dx;

    final settings =
        context.read<ReaderSettingsProvider>().forBook(widget.bookId);

    if (_isEpubBased) {
      setState(() => _showControls = !_showControls);
      if (_showControls) _scheduleHide();
      return;
    }

    if (settings.scrollMode) {
      // In scroll mode: left/right zones scroll up/down by one screen.
      if (!_scrollController.hasClients) return;
      if (dx < screenWidth * _leftZoneThreshold) {
        _scrollController.animateTo(
          (_scrollController.offset - screenHeight * _scrollPageFraction)
              .clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else if (dx > screenWidth * _rightZoneThreshold) {
        _scrollController.animateTo(
          (_scrollController.offset + screenHeight * _scrollPageFraction)
              .clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() => _showControls = !_showControls);
        if (_showControls) _scheduleHide();
      }
      return;
    }

    // Page mode (also handles HTML spine navigation): left = prev, right = next.
    final pageCount = _isHtmlBased
        ? (_content?.htmlSpine?.length ?? 0)
        : _pages.length;
    if (dx < screenWidth * _leftZoneThreshold) {
      if (_currentPage > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    } else if (dx > screenWidth * _rightZoneThreshold) {
      if (_currentPage < pageCount - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    } else {
      setState(() => _showControls = !_showControls);
      if (_showControls) _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    // Load more text pages when near the end of the loaded window.
    if (!_isHtmlBased && _pages.length > 3 && index >= _pages.length - 3) {
      _loadMorePages();
    }
    final total = _isHtmlBased
        ? (_content?.htmlSpine?.length ?? 0)
        : _allPages.length;
    if (total > 0) {
      final percent = (index + 1) / total;
      context.read<LibraryProvider>().updateProgress(widget.bookId, percent);
    }
  }

  void _recordDebug(OpenLibraryDebugSnapshot snapshot) {
    if (!mounted) return;
    setState(() => _debugSnapshots.add(snapshot));
  }

  List<OpenLibraryDebugSnapshot> get _debugErrorSnapshots => _debugSnapshots
      .where((s) => !s.success && (s.error?.trim().isNotEmpty ?? false))
      .toList();

  String get _debugTooltip {
    if (_showDebugPanel) return 'Hide API debug info';
    final errors = _debugErrorSnapshots;
    if (errors.isEmpty) return 'Show API debug info';
    final latest = errors.last.error!.trim();
    return 'Show API debug info (${errors.length} error${errors.length == 1 ? '' : 's'})\nLatest: $latest';
  }

  Widget _buildDebugButton({Color? color}) {
    final errorCount = _debugErrorSnapshots.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: _debugTooltip,
          onPressed: () {
            setState(() => _showDebugPanel = !_showDebugPanel);
          },
          icon: PhosphorIcon(
            _showDebugPanel ? PhosphorIconsFill.bug : PhosphorIconsRegular.bug,
            color: color,
          ),
        ),
        if (errorCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                errorCount > 9 ? '9+' : '$errorCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _friendlyReaderError(String error) {
    if (error.contains('No readable content') ||
        error.contains('image-only') ||
        error.contains('No readable text source') ||
        error.contains('Could not load text')) {
      return 'This book\'s content is not publicly accessible. '
          'The edition may be restricted or temporarily unavailable.';
    }
    if (error.contains('timed out') || error.contains('TimeoutException')) {
      return 'The download timed out. Please check your connection and try again.';
    }
    if (error.contains('No internet') ||
        error.contains('Network') ||
        error.contains('SocketException')) {
      return 'No internet connection. Please check your network and retry.';
    }
    return error;
  }

  Widget _buildEpubReader(
    BuildContext context,
    Color bgColor,
    Color textColor,
    Color accentColor,
  ) {
    final controller = _epubController;
    final source = _epubSource;
    if (controller == null || source == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final progress = (_epubLocation?.progress ?? 0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _onTapUp,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: bgColor,
                child: EpubViewer(
                  epubController: controller,
                  epubSource: source,
                  onEpubLoaded: () {
                    if (!mounted) return;
                    _epubViewerLoaded = true;
                    _epubLoadTimeoutTimer?.cancel();
                    _recordDebug(
                      OpenLibraryDebugSnapshot(
                        requestUrl:
                            'reader://book/${widget.bookId}/epub-viewer-state',
                        statusCode: null,
                        success: true,
                        bodyLength: 0,
                        bodyPreview: 'state=loaded',
                        resultCount: _epubChapters.length,
                        error: null,
                        timestamp: DateTime.now(),
                      ),
                    );
                  },
                  onChaptersLoaded: (chapters) {
                    if (!mounted) return;
                    setState(() => _epubChapters = chapters);
                    if (chapters.isEmpty && !_epubEmptyContentLogged) {
                      _epubEmptyContentLogged = true;
                      _recordDebug(
                        OpenLibraryDebugSnapshot(
                          requestUrl:
                              'reader://book/${widget.bookId}/epub-empty-content',
                          statusCode: null,
                          success: false,
                          bodyLength: 0,
                          bodyPreview: '',
                          resultCount: 0,
                          error:
                              'EPUB viewer loaded, but no chapters/paragraphs were parsed. Continuing with relocation-based progress.',
                          timestamp: DateTime.now(),
                        ),
                      );
                    }
                  },
                  onRelocated: (location) {
                    if (!mounted) return;
                    final pct = location.progress.clamp(0.0, 1.0);
                    setState(() {
                      _epubLocation = location;
                      _currentPage = (pct * 100).round();
                    });
                    _scrollDebounce?.cancel();
                    _scrollDebounce = Timer(
                      const Duration(milliseconds: 500),
                      () => context.read<LibraryProvider>().updateProgress(
                            widget.bookId,
                            pct,
                          ),
                    );
                  },
                  onTouchUp: (_, __) {
                    if (!mounted) return;
                    setState(() => _showControls = !_showControls);
                    if (_showControls) _scheduleHide();
                  },
                  onSelectionChanging: () {
                    if (_showControls) setState(() => _showControls = false);
                  },
                  onInitialPositionLoading: (kind) {
                    _recordDebug(
                      OpenLibraryDebugSnapshot(
                        requestUrl:
                            'reader://book/${widget.bookId}/epub-viewer-state',
                        statusCode: null,
                        success: true,
                        bodyLength: 0,
                        bodyPreview: 'state=initial-position-loading:$kind',
                        resultCount: _epubChapters.length,
                        error: null,
                        timestamp: DateTime.now(),
                      ),
                    );
                  },
                  onLocationLoaded: () {
                    _recordDebug(
                      OpenLibraryDebugSnapshot(
                        requestUrl:
                            'reader://book/${widget.bookId}/epub-viewer-state',
                        statusCode: null,
                        success: true,
                        bodyLength: 0,
                        bodyPreview: 'state=location-map-ready',
                        resultCount: _epubChapters.length,
                        error: null,
                        timestamp: DateTime.now(),
                      ),
                    );
                  },
                ),
              ),
            ),
            ReaderControls(
              visible: _showControls,
              // EPUB mode uses relocation progress; chapter count can be empty
              // or misleading for some books, so avoid chapter-based paging.
              currentPage: (progress * 100).round().clamp(0, 100),
              totalPages: 100,
              readPercent: progress,
              bgColor: bgColor.withValues(alpha: 0.95),
              textColor: textColor,
              accentColor: accentColor,
              showSettings: false,
              bookTitle: _book?.title,
              bookAuthor: _book?.authorName,
              onBack: () => Navigator.pop(context),
              onSettings: () {},
            ),
            if (kDebugMode)
              Positioned(
                top: 4,
                right: 8,
                child: SafeArea(
                  child: IgnorePointer(
                    ignoring: !_showControls && _debugErrorSnapshots.isEmpty,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity:
                          (_showControls || _debugErrorSnapshots.isNotEmpty)
                              ? 1
                              : 0,
                      child: _buildDebugButton(color: textColor),
                    ),
                  ),
                ),
              ),
            if (!_epubViewerLoaded)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: true,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: bgColor.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Loading EPUB…',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (kDebugMode && _showDebugPanel)
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                child: SafeArea(child: _buildDebugPanel()),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildHtmlReader(
    BuildContext context,
    Color bgColor,
    Color textColor,
    Color accentColor,
  ) {
    final spine = _content!.htmlSpine!;
    final total = spine.length;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTapUp: _onTapUp,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: total,
              itemBuilder: (ctx, i) {
                final screenHeight = MediaQuery.of(ctx).size.height;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    _pageHorizontalPadding,
                    _pageTopPadding,
                    _pageHorizontalPadding,
                    _pageBottomPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: screenHeight - _pageTopPadding - _pageBottomPadding,
                    ),
                    child: Html(
                      data: spine[i],
                      style: {
                        'body': Style(color: textColor),
                        'p': Style(color: textColor),
                        'span': Style(color: textColor),
                        'div': Style(color: textColor),
                        'h1': Style(color: textColor, fontWeight: FontWeight.bold),
                        'h2': Style(color: textColor, fontWeight: FontWeight.bold),
                        'h3': Style(color: textColor, fontWeight: FontWeight.bold),
                        'h4': Style(color: textColor, fontWeight: FontWeight.bold),
                        'a': Style(color: accentColor),
                      },
                    ),
                  ),
                );
              },
            ),
            ReaderControls(
              visible: _showControls,
              currentPage: _currentPage + 1,
              totalPages: total,
              readPercent: total > 0 ? (_currentPage + 1) / total : 0.0,
              bgColor: bgColor.withValues(alpha: 0.95),
              textColor: textColor,
              accentColor: accentColor,
              showSettings: false,
              bookTitle: _book?.title,
              bookAuthor: _book?.authorName,
              onBack: () => Navigator.pop(context),
              onSettings: () {},
            ),
            if (kDebugMode)
              Positioned(
                top: 4,
                right: 8,
                child: SafeArea(
                  child: IgnorePointer(
                    ignoring: !_showControls && _debugErrorSnapshots.isEmpty,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity:
                          (_showControls || _debugErrorSnapshots.isNotEmpty)
                              ? 1
                              : 0,
                      child: _buildDebugButton(color: textColor),
                    ),
                  ),
                ),
              ),
            if (kDebugMode && _showDebugPanel)
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                child: SafeArea(child: _buildDebugPanel()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 6),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              'Reader debug responses',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (_debugSnapshots.isEmpty)
            const ListTile(
              dense: true,
              title: Text('No debug events captured yet.'),
            )
          else
            ..._debugSnapshots.map(
              (snapshot) => _ReaderDebugSnapshotTile(snapshot: snapshot),
            ),
        ],
      ),
    );
  }

  Map<String, Color> _themeColors(ReaderSettings s) {
    switch (s.theme) {
      case ThemeName.cream:
        return {
          'bg': AppColors.readerCreamBg,
          'text': AppColors.readerCreamText,
          'accent': AppColors.readerCreamAccent
        };
      case ThemeName.paper:
        return {
          'bg': AppColors.readerPaperBg,
          'text': AppColors.readerPaperText,
          'accent': AppColors.readerPaperAccent
        };
      case ThemeName.sepia:
        return {
          'bg': AppColors.readerSepiaBg,
          'text': AppColors.readerSepiaText,
          'accent': AppColors.readerSepiaAccent
        };
      case ThemeName.slate:
        return {
          'bg': AppColors.readerSlateBg,
          'text': AppColors.readerSlateText,
          'accent': AppColors.readerSlateAccent
        };
      case ThemeName.midnight:
        return {
          'bg': AppColors.readerMidnightBg,
          'text': AppColors.readerMidnightText,
          'accent': AppColors.readerMidnightAccent
        };
    }
  }

  Widget _buildLoadingScreen(Book? book) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Book Cover with Hero Animation
                    if (book?.coverUrl != null)
                      Hero(
                        tag: 'book-cover-${book!.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: book.coverUrl!,
                            width: 100,
                            height: 150,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 100,
                              height: 150,
                              decoration: BoxDecoration(
                                color: cs.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 100,
                              height: 150,
                              decoration: BoxDecoration(
                                color: cs.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: PhosphorIcon(
                                PhosphorIconsRegular.book,
                                size: 40,
                                color: cs.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 100,
                        height: 150,
                        decoration: BoxDecoration(
                          color: cs.secondary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: PhosphorIcon(
                          PhosphorIconsRegular.book,
                          size: 40,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    const SizedBox(height: 24),
                    // Book Title
                    if (book != null)
                      Text(
                        book.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lora(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 6),
                    // Book Author
                    if (book != null)
                      Text(
                        book.authorName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 32),
                    // Loading Indicator with Text
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 4,
                            width: 60,
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              backgroundColor: cs.primary.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Preparing your book...',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loading content & setting up reader',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Back button in top-left
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: IconButton(
                  onPressed: _cancelLoading,
                  icon: const PhosphorIcon(PhosphorIconsRegular.arrowLeft),
                  tooltip: 'Cancel',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If loading, allow user to cancel via back button
    if (_loading) {
      return WillPopScope(
        onWillPop: () async {
          _cancelLoading();
          return true;
        },
        child: _buildLoadingScreen(widget.initialBook),
      );
    }
    if (_error != null) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          actions: [
            if (kDebugMode) _buildDebugButton(),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (kDebugMode && _showDebugPanel) _buildDebugPanel(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PhosphorIcon(
                          PhosphorIconsRegular.bookOpen,
                          size: 64,
                          color: cs.onSurface.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Content Not Available',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _friendlyReaderError(_error!),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: 0.65),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const PhosphorIcon(
                                  PhosphorIconsRegular.arrowLeft,
                                  size: 18),
                              label: const Text('Go Back'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                  _loadingCancelled = false;
                                });
                                _load();
                              },
                              icon: const PhosphorIcon(
                                  PhosphorIconsRegular.arrowClockwise,
                                  size: 18),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }


    if (_isEpubBased) {
      final controller = _epubController;
      final source = _epubSource;
      final cs = Theme.of(context).colorScheme;
      if (controller == null || source == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return _buildEpubReader(
        context,
        cs.surface,
        cs.onSurface,
        cs.primary,
      );
    }

    if (_isHtmlBased) {
      final settingsProvider = context.watch<ReaderSettingsProvider>();
      final settings = settingsProvider.forBook(widget.bookId);
      final colors = _themeColors(settings);
      return _buildHtmlReader(
        context,
        colors['bg']!,
        colors['text']!,
        colors['accent']!,
      );
    }

    final settingsProvider = context.watch<ReaderSettingsProvider>();
    final settings = settingsProvider.forBook(widget.bookId);
    final colors = _themeColors(settings);
    final bgColor = colors['bg']!;
    final textColor = colors['text']!;
    final accentColor = colors['accent']!;

    final size = MediaQuery.of(context).size;
    if (_lastSize != size && _content?.text != null) {
      _lastSize = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => _buildPages());
    }

    final textStyle = settings.fontFamily == FontFamily.lora
        ? GoogleFonts.lora(
            fontSize: settings.fontSize,
            height: settings.lineHeightValue,
            color: textColor)
        : GoogleFonts.inter(
            fontSize: settings.fontSize,
            height: settings.lineHeightValue,
            color: textColor);

    final useScrollMode = settings.scrollMode;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTapUp: _onTapUp,
        child: Stack(
          children: [
            if (useScrollMode && _content?.text != null)
              NotificationListener<ScrollNotification>(
                onNotification: (notif) {
                  if (notif is ScrollUpdateNotification &&
                      _scrollController.hasClients) {
                    final pos = _scrollController.position;
                    if (pos.maxScrollExtent > 0) {
                      final pct =
                          (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
                      if ((pct - _scrollPercent).abs() >
                          _scrollProgressThreshold) {
                        setState(() => _scrollPercent = pct);
                        _scrollDebounce?.cancel();
                        _scrollDebounce = Timer(
                          const Duration(milliseconds: 500),
                          () => context
                              .read<LibraryProvider>()
                              .updateProgress(widget.bookId, pct),
                        );
                      }
                    }
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _pageHorizontalPadding,
                        _pageTopPadding,
                        _pageHorizontalPadding,
                        _pageBottomPadding,
                      ),
                      child: Text(
                        _content!.text!,
                        style: textStyle,
                        textAlign: TextAlign.justify,
                      ),
                    ),
                  ),
                ),
              )
            else if (_pages.isEmpty)
              Center(child: Text('No content', style: textStyle))
            else
              PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (ctx, i) => Container(
                        color: bgColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            _pageHorizontalPadding,
                            _pageTopPadding,
                            _pageHorizontalPadding,
                            _pageBottomPadding,
                          ),
                          child: Text(
                            _pages[i],
                            style: textStyle,
                            textAlign: TextAlign.justify,
                          ),
                        ),
                      ),
              ),
            ReaderControls(
              visible: _showControls,
              currentPage: _currentPage + 1,
              totalPages: _allPages.length,
              readPercent: useScrollMode ? _scrollPercent : null,
              bgColor: bgColor.withValues(alpha: 0.95),
              textColor: textColor,
              accentColor: accentColor,
              showSettings: true,
              bookTitle: _book?.title,
              bookAuthor: _book?.authorName,
              onBack: () => Navigator.pop(context),
              onSettings: () {
                _hideTimer?.cancel();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: bgColor,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  builder: (_) =>
                      ReaderSettingsSheet(bookId: widget.bookId),
                ).then((_) => _buildPages());
              },
            ),
            if (kDebugMode)
              Positioned(
                top: 4,
                right: 8,
                child: SafeArea(
                  child: IgnorePointer(
                    ignoring: !_showControls && _debugErrorSnapshots.isEmpty,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity:
                          (_showControls || _debugErrorSnapshots.isNotEmpty)
                              ? 1
                              : 0,
                      child: _buildDebugButton(color: textColor),
                    ),
                  ),
                ),
              ),
            if (kDebugMode && _showDebugPanel)
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                child: SafeArea(child: _buildDebugPanel()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderDebugSnapshotTile extends StatelessWidget {
  final OpenLibraryDebugSnapshot snapshot;

  const _ReaderDebugSnapshotTile({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusText = snapshot.statusCode == null
        ? 'status: n/a'
        : 'status: ${snapshot.statusCode}';
    final resultText = snapshot.resultCount == null
        ? 'results: n/a'
        : 'results: ${snapshot.resultCount}';
    final timeText =
        '${snapshot.timestamp.hour.toString().padLeft(2, '0')}:${snapshot.timestamp.minute.toString().padLeft(2, '0')}:${snapshot.timestamp.second.toString().padLeft(2, '0')}';

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      title: Text(snapshot.requestUrl, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        '${snapshot.success ? 'ok' : 'error'} | $statusText | $resultText | $timeText',
        style: TextStyle(
          fontSize: 12,
          color: snapshot.success ? cs.primary : cs.error,
        ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            'URL: ${snapshot.requestUrl}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 6),
        if (snapshot.error != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Body (${snapshot.bodyLength} bytes):',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            snapshot.bodyPreview.isEmpty ? '(empty body)' : snapshot.bodyPreview,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ],
    );
  }
}
