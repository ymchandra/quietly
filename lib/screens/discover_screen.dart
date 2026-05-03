import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/book.dart';
import '../services/gutendex_service.dart';
import '../widgets/book_card.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/skeleton_widget.dart';

const _topics = [
  {'label': 'Most Loved Classics', 'topic': 'fiction'},
  {'label': 'Romance', 'topic': 'love'},
  {'label': 'Mystery', 'topic': 'mystery'},
  {'label': 'Philosophy', 'topic': 'philosophy'},
  {'label': 'Poetry', 'topic': 'poetry'},
  {'label': 'Adventure', 'topic': 'adventure'},
];

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _service = GutendexService();
  final Map<String, List<Book>> _shelves = {};
  final Map<String, bool> _loading = {};
  String _query = '';
  List<Book> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadAllShelves();
  }

  Future<void> _loadAllShelves() async {
    for (final t in _topics) {
      _loadShelf(t['topic']!);
    }
  }

  Future<void> _loadShelf(String topic) async {
    setState(() => _loading[topic] = true);
    try {
      final resp = await _service.fetchBooks(topic: topic);
      if (mounted) setState(() => _shelves[topic] = resp.results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading[topic] = false);
    }
  }

  Future<void> _onSearch(String q) async {
    setState(() {
      _query = q;
      _searching = q.isNotEmpty;
    });
    if (q.isEmpty) return;
    try {
      final resp = await _service.fetchBooks(search: q);
      if (mounted && _query == q) {
        setState(() => _searchResults = resp.results);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Quietly',
                style: GoogleFonts.lora(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBarWidget(onChanged: _onSearch),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searching
                  ? _buildSearchResults()
                  : RefreshIndicator(
                      onRefresh: _loadAllShelves,
                      child: _buildShelves(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelves() {
    return ListView.builder(
      itemCount: _topics.length,
      itemBuilder: (context, i) {
        final t = _topics[i];
        final topic = t['topic']!;
        final label = t['label']!;
        final books = _shelves[topic] ?? [];
        final loading = _loading[topic] ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                label,
                style: GoogleFonts.lora(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 220,
              child: loading
                  ? _shelfSkeleton()
                  : books.isEmpty
                      ? const SizedBox()
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: books.length,
                          itemBuilder: (ctx, j) => Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: BookCard(book: books[j]),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _shelfSkeleton() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonWidget(width: 120, height: 180, borderRadius: 8),
            const SizedBox(height: 6),
            SkeletonWidget(width: 100, height: 14, borderRadius: 4),
            const SizedBox(height: 4),
            SkeletonWidget(width: 80, height: 12, borderRadius: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.55,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) => BookCard(book: _searchResults[i]),
    );
  }
}
