import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../providers/library_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/gutendex_service.dart';
import '../services/storage_service.dart';
import '../widgets/reader_controls.dart';
import '../widgets/reader_settings_sheet.dart';

class ReaderScreen extends StatefulWidget {
  final int bookId;
  const ReaderScreen({super.key, required this.bookId});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _gutendex = GutendexService();
  final _storage = StorageService();

  String? _text;
  Book? _book;
  bool _loading = true;
  String? _error;

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
    try {
      final offline = await _storage.getOfflineText(widget.bookId);
      if (offline != null) {
        final lib = context.read<LibraryProvider>();
        final book = lib.downloaded.firstWhere(
          (b) => b.id == widget.bookId,
          orElse: () => Book(
              id: widget.bookId,
              title: '',
              authors: [],
              subjects: [],
              bookshelves: [],
              languages: [],
              formats: {},
              downloadCount: 0),
        );
        if (mounted) {
          setState(() {
            _text = offline;
            _book = book;
            _loading = false;
          });
          _buildPages();
        }
        return;
      }
      final book = await _gutendex.fetchBook(widget.bookId);
      final text = await _gutendex.fetchBookText(book);
      if (mounted) {
        setState(() {
          _text = text;
          _book = book;
          _loading = false;
        });
        _buildPages();
      }
    } catch (e) {
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Failed to load book'),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back')),
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
          ],
        ),
      ),
    );
  }
}
