import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../providers/library_provider.dart';
import '../providers/reader_settings_provider.dart';
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

  String? _text;
  bool _loading = true;
  String? _error;
  final List<OpenLibraryDebugSnapshot> _debugSnapshots = [];
  bool _showDebugPanel = false;

  List<String> _pages = [];
  late PageController _pageController;
  int _currentPage = 0;
  bool _showControls = true;
  Timer? _hideTimer;
  Size? _lastSize;

  static const double _charWidthRatio = 0.52;
  static const double _pageFillFactor = 0.85;
  static const int _minCharsPerPage = 300;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _debugSnapshots.clear();
        _showDebugPanel = false;
      });
    }
    try {
      final offline = await _storage.getOfflineText(widget.bookId);
      if (offline != null) {
        _recordDebug(
          OpenLibraryDebugSnapshot(
            requestUrl: 'reader://book/${widget.bookId}/offline',
            statusCode: null,
            success: true,
            bodyLength: offline.length,
            bodyPreview: 'Loaded offline text from local storage.',
            resultCount: 1,
            error: null,
            timestamp: DateTime.now(),
          ),
        );
        if (mounted) {
          setState(() {
            _text = offline;
            _loading = false;
          });
          _buildPages();
        }
        return;
      }
      final initial = widget.initialBook;
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
      final book = initial ?? await _openLibrary.fetchBook(widget.bookId);
      final text = await _openLibrary.fetchBookText(
        book,
        onDebug: _recordDebug,
      );
      if (mounted) {
        setState(() {
          _text = text;
          _loading = false;
        });
        _buildPages();
      }
    } catch (e) {
      _recordDebug(
        OpenLibraryDebugSnapshot(
          requestUrl: 'reader://book/${widget.bookId}/load',
          statusCode: null,
          success: false,
          bodyLength: 0,
          bodyPreview: '',
          resultCount: null,
          error: e.toString(),
          timestamp: DateTime.now(),
        ),
      );
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _buildPages() {
    final size = MediaQuery.of(context).size;
    if (_text == null || size.isEmpty) return;
    final settings =
        context.read<ReaderSettingsProvider>().forBook(widget.bookId);
    final pages = _splitPages(
      text: _text!,
      textWidth: size.width - 40,
      textHeight: size.height - 120,
      fontSize: settings.fontSize,
      lineHeightFactor: settings.lineHeightValue,
    );
    final savedPercent =
        context.read<LibraryProvider>().getProgress(widget.bookId)?.percent ??
            0;
    final startPage =
        (savedPercent * pages.length).floor().clamp(0, pages.length - 1);
    setState(() {
      _pages = pages;
      _currentPage = startPage;
    });
    if (startPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(startPage);
      });
    }
    _scheduleHide();
  }

  List<String> _splitPages({
    required String text,
    required double textWidth,
    required double textHeight,
    required double fontSize,
    required double lineHeightFactor,
  }) {
    final lineHeight = fontSize * lineHeightFactor;
    final linesPerPage = (textHeight / lineHeight).floor();
    final charsPerLine = (textWidth / (fontSize * _charWidthRatio)).floor();
    final cpp = (charsPerLine * linesPerPage * _pageFillFactor)
        .floor()
        .clamp(_minCharsPerPage, 9999);

    final paragraphs = text.split('\n\n');
    final pages = <String>[];
    final buffer = StringBuffer();
    int currentChars = 0;

    for (final para in paragraphs) {
      if (para.trim().isEmpty) continue;
      if (currentChars + para.length + 2 <= cpp) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(para);
        currentChars += para.length + 2;
      } else if (para.length > cpp) {
        if (buffer.isNotEmpty) {
          pages.add(buffer.toString());
          buffer.clear();
          currentChars = 0;
        }
        final words = para.split(' ');
        final wb = StringBuffer();
        int wc = 0;
        for (final word in words) {
          if (wc + word.length + 1 > cpp && wb.isNotEmpty) {
            pages.add(wb.toString());
            wb.clear();
            wc = 0;
          }
          if (wb.isNotEmpty) {
            wb.write(' ');
            wc++;
          }
          wb.write(word);
          wc += word.length;
        }
        if (wb.isNotEmpty) {
          buffer.write(wb.toString());
          currentChars = wb.length;
        }
      } else {
        if (buffer.isNotEmpty) {
          pages.add(buffer.toString());
          buffer.clear();
        }
        buffer.write(para);
        currentChars = para.length;
      }
    }
    if (buffer.isNotEmpty) pages.add(buffer.toString());
    return pages.isEmpty ? [''] : pages;
  }

  void _onTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (_pages.isNotEmpty) {
      final percent = (index + 1) / _pages.length;
      context.read<LibraryProvider>().updateProgress(widget.bookId, percent);
    }
  }

  void _recordDebug(OpenLibraryDebugSnapshot snapshot) {
    if (!mounted) return;
    setState(() => _debugSnapshots.add(snapshot));
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          actions: [
            if (kDebugMode)
              IconButton(
                tooltip:
                    _showDebugPanel ? 'Hide API debug info' : 'Show API debug info',
                onPressed: () {
                  setState(() => _showDebugPanel = !_showDebugPanel);
                },
                icon: Icon(
                  _showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined,
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (kDebugMode && _showDebugPanel) _buildDebugPanel(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 12),
                        const Text('Failed to load book'),
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back'),
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

    final settingsProvider = context.watch<ReaderSettingsProvider>();
    final settings = settingsProvider.forBook(widget.bookId);
    final colors = _themeColors(settings);
    final bgColor = colors['bg']!;
    final textColor = colors['text']!;
    final accentColor = colors['accent']!;

    final size = MediaQuery.of(context).size;
    if (_lastSize != size && _text != null) {
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

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: _onTap,
        child: Stack(
          children: [
            _pages.isEmpty
                ? Center(child: Text('No content', style: textStyle))
                : PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: _pages.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 60, 20, 80),
                      child: Text(_pages[i], style: textStyle),
                    ),
                  ),
            ReaderControls(
              visible: _showControls,
              currentPage: _currentPage + 1,
              totalPages: _pages.length,
              bgColor: bgColor.withValues(alpha: 0.95),
              textColor: textColor,
              accentColor: accentColor,
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
                    ignoring: !_showControls,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _showControls ? 1 : 0,
                      child: IconButton(
                        tooltip: _showDebugPanel
                            ? 'Hide API debug info'
                            : 'Show API debug info',
                        onPressed: () {
                          setState(() => _showDebugPanel = !_showDebugPanel);
                        },
                        icon: Icon(
                          _showDebugPanel
                              ? Icons.bug_report
                              : Icons.bug_report_outlined,
                          color: textColor,
                        ),
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

