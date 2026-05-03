import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  static const _previewCount = 10;
  final _service = GutendexService();
  final Map<String, List<Book>> _shelves = {};
  final Map<String, bool> _loading = {};
  String _query = '';
  List<Book> _searchResults = [];
  bool _searching = false;
  bool _searchLoading = false;
  String? _searchError;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    _loadAllShelves();
  }

  Future<void> _loadAllShelves() async {
    setState(() => _catalogError = null);
    final results = await Future.wait(
      _topics.map((t) => _loadShelf(t['topic']!)),
    );
    if (!mounted) return;
    if (results.every((ok) => !ok)) {
      setState(() {
        _catalogError = 'Could not load books. Check your internet and pull to retry.';
      });
    }
  }

  Future<bool> _loadShelf(String topic) async {
    setState(() => _loading[topic] = true);
    try {
      final resp = await _service.fetchBooks(topic: topic);
      if (mounted) {
        setState(() {
          _shelves[topic] = resp.results.take(_previewCount).toList();
        });
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _loading[topic] = false);
    }
  }

  Future<void> _onSearch(String q) async {
    setState(() {
      _query = q;
      _searching = q.isNotEmpty;
      _searchError = null;
      if (q.isEmpty) {
        _searchLoading = false;
        _searchResults = [];
      } else {
        _searchLoading = true;
      }
    });
    if (q.isEmpty) return;
    try {
      final resp = await _service.fetchBooks(search: q);
      if (mounted && _query == q) {
        setState(() {
          _searchResults = resp.results;
          _searchLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _query == q) {
        setState(() {
          _searchResults = [];
          _searchLoading = false;
          _searchError = 'Search failed. Check your internet and try again.';
        });
      }
    }
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
    final allEmpty = _topics.every((t) {
      final topic = t['topic']!;
      return (_shelves[topic] ?? []).isEmpty;
    });
    final anyLoading = _loading.values.any((v) => v);
    if (_catalogError != null && allEmpty && !anyLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  _catalogError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadAllShelves,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.lora(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(
                      '/discover/topic/$topic?label=${Uri.encodeComponent(label)}',
                    ),
                    child: const Text('Show all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 220,
              child: loading
                  ? _shelfSkeleton()
                  : books.isEmpty
                      ? const Center(
                          child: Text('No books for this shelf yet'),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: books.length + 1,
                          itemBuilder: (ctx, j) {
                            if (j == books.length) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _ShowAllCard(
                                  onTap: () => context.push(
                                    '/discover/topic/$topic?label=${Uri.encodeComponent(label)}',
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: BookCard(book: books[j]),
                            );
                          },
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
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _searchError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No books found'));
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

class _ShowAllCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ShowAllCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
          color: cs.surface,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_forward, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              'Show all',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
