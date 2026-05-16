import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/user_profile_provider.dart';
import '../services/openlibrary_service.dart';
import '../widgets/book_list_row.dart';

class TopicBooksScreen extends StatefulWidget {
  final String label;
  final String? topic;
  final String? queryType;
  final String? queryValue;
  final bool readableOnly;

  const TopicBooksScreen({
    super.key,
    required this.label,
    this.topic,
    this.queryType,
    this.queryValue,
    this.readableOnly = false,
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
    final profile = context.read<UserProfileProvider>();
    final userAge = profile.userAge;
    final type = widget.queryType;
    final value = widget.queryValue;
    final ebookAccess = widget.readableOnly ? 'public_domain' : null;
    if (type == 'author' && value != null && value.trim().isNotEmpty) {
      final displayName = _formatAuthorName(value);
      return _service.fetchBooks(
        search: displayName,
        page: page,
        ebookAccess: ebookAccess,
        userAge: userAge,
      );
    }
    if (type == 'subject' && value != null && value.trim().isNotEmpty) {
      if (!profile.isTopicAllowed(value)) {
        return Future.value(
          const OpenLibraryResponse(
              count: 0, next: null, previous: null, results: []),
        );
      }
      return _service.fetchBooks(
        topic: value,
        page: page,
        ebookAccess: ebookAccess,
        userAge: userAge,
      );
    }
    final fallbackTopic = widget.topic;
    if (fallbackTopic != null && fallbackTopic.isNotEmpty) {
      if (!profile.isTopicAllowed(fallbackTopic)) {
        return Future.value(
          const OpenLibraryResponse(
              count: 0, next: null, previous: null, results: []),
        );
      }
      return _service.fetchBooks(
        topic: fallbackTopic,
        page: page,
        ebookAccess: ebookAccess,
        userAge: userAge,
      );
    }
    return _service.fetchBooks(
      topic: 'fiction',
      page: page,
      ebookAccess: ebookAccess,
      userAge: userAge,
    );
  }

  static String _formatAuthorName(String raw) {
    final parts = raw.split(',');
    return parts.reversed.map((p) => p.trim()).join(' ').trim();
  }

  List<Book> _filterForRoute(List<Book> books) {
    var filtered = books;

    // For the "Free to Read" route, keep only freely readable books client-side.
    // The API filter (ebook_access=public_domain) is unreliable and can return
    // borrowable or restricted books, so we enforce the same condition used by
    // BookListRow to show the "Free to read" badge.
    if (widget.readableOnly) {
      filtered = filtered
          .where((b) =>
              b.ebookAccess != EbookAccess.borrowable &&
              b.ebookAccess != EbookAccess.printDisabled &&
              b.ebookAccess != EbookAccess.noEbook &&
              b.hasFullText)
          .toList();
    }

    if (widget.queryType != 'author' ||
        widget.queryValue == null ||
        widget.queryValue!.trim().isEmpty) {
      return filtered;
    }
    final rawName = widget.queryValue!.toLowerCase();
    final display = _formatAuthorName(widget.queryValue!).toLowerCase();
    final lastName = rawName.split(',').first.trim();
    return filtered.where((book) {
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
