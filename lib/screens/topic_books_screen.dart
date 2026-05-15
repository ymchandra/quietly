import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/book.dart';
import '../services/openlibrary_service.dart';
import '../widgets/book_list_row.dart';

class TopicBooksScreen extends StatefulWidget {
  final String label;
  final String? topic;
  final String? queryType;
  final String? queryValue;

  const TopicBooksScreen({
    super.key,
    required this.label,
    this.topic,
    this.queryType,
    this.queryValue,
  });

  @override
  State<TopicBooksScreen> createState() => _TopicBooksScreenState();
}

class _TopicBooksScreenState extends State<TopicBooksScreen> {
  final _service = OpenLibraryService();
  final _scrollController = ScrollController();

  final List<Book> _books = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 400;
    if (_scrollController.position.pixels >= threshold) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final resp = await _fetchPage(_page);
      final pageBooks = _filterForRoute(resp.results);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _books
            ..clear()
            ..addAll(pageBooks);
        } else {
          _books.addAll(pageBooks);
        }
        _hasMore = resp.next != null && resp.results.isNotEmpty;
        if (_hasMore) _page += 1;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!reset && _books.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not load more books. Pull to retry.')),
        );
      }
      setState(() {
        _error = (reset || _books.isEmpty)
            ? 'Could not load this category right now.'
            : null;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<OpenLibraryResponse> _fetchPage(int page) {
    final type = widget.queryType;
    final value = widget.queryValue;
    if (type == 'author' && value != null && value.trim().isNotEmpty) {
      final displayName = _formatAuthorName(value);
      return _service.fetchBooks(search: displayName, page: page);
    }
    if (type == 'subject' && value != null && value.trim().isNotEmpty) {
      return _service.fetchBooks(topic: value, page: page);
    }
    final fallbackTopic = widget.topic;
    if (fallbackTopic != null && fallbackTopic.isNotEmpty) {
      return _service.fetchBooks(topic: fallbackTopic, page: page);
    }
    return _service.fetchBooks(topic: 'fiction', page: page);
  }

  static String _formatAuthorName(String raw) {
    final parts = raw.split(',');
    return parts.reversed.map((p) => p.trim()).join(' ').trim();
  }

  List<Book> _filterForRoute(List<Book> books) {
    if (widget.queryType != 'author' ||
        widget.queryValue == null ||
        widget.queryValue!.trim().isEmpty) {
      return books;
    }
    final rawName = widget.queryValue!.toLowerCase();
    final display = _formatAuthorName(widget.queryValue!).toLowerCase();
    final lastName = rawName.split(',').first.trim();
    return books.where((book) {
      return book.authors.any((a) {
        final aLower = a.name.toLowerCase();
        return aLower.contains(lastName) || display.contains(aLower);
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label,
            style: GoogleFonts.lora(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _books.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Text(
                                _error!,
                                style: TextStyle(color: cs.error),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _load(reset: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : _books.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                              child:
                                  Text('No books found in this category yet.')),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _books.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _books.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return BookListRow(book: _books[index]);
                        },
                      ),
      ),
    );
  }
}
