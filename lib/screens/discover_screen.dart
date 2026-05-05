import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/reading_history.dart';
import '../providers/suggestions_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/openlibrary_service.dart';
import '../services/storage_service.dart';
import '../widgets/book_card.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/skeleton_widget.dart';

const _allTopics = [
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
  static const _initialTopicBatch = 2;
  static const _shelfHeight = 252.0;
  final _service = OpenLibraryService();
  final _storage = StorageService();
  final Map<String, List<Book>> _shelves = {};
  final Map<String, bool> _loading = {};
  final Set<String> _requestedTopics = <String>{};
  final Map<String, String> _shelfErrors = {};
  String _query = '';
  List<Book> _searchResults = [];
  bool _searching = false;
  bool _searchLoading = false;
  String? _searchError;
  String? _catalogError;
  final Map<String, OpenLibraryDebugSnapshot> _shelfDebug = {};
  OpenLibraryDebugSnapshot? _searchDebug;
  bool _showDebugPanel = false;

  List<Map<String, String>> _topics = [];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed =
        context.read<UserProfileProvider>().allowedTopics.toSet();
    _topics = _allTopics
        .where((t) => allowed.contains(t['topic']))
        .toList();
    if (!_initialized) {
      _initialized = true;
      _loadInitialShelves();
    }
  }

  Future<void> _loadInitialShelves() async {
    setState(() => _catalogError = null);
    final initialTopics = _topics.take(_initialTopicBatch).toList();
    for (final t in initialTopics) {
      _requestedTopics.add(t['topic']!);
    }
    final results = await Future.wait(
      initialTopics.map((t) => _loadShelf(t['topic']!)),
    );
    if (!mounted) return;
    if (results.every((ok) => !ok)) {
      setState(() {
        _catalogError = 'Could not load books. Check your internet and pull to retry.';
      });
    }
  }

  Future<void> _loadAllShelves() async {
    setState(() {
      _catalogError = null;
      _shelfErrors.clear();
      _requestedTopics.clear();
    });
    for (final t in _topics) {
      _requestedTopics.add(t['topic']!);
    }
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
    // Serve from cache immediately if available, then refresh in background.
    final cached = await _storage.getShelfCache(topic);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _shelves[topic] = cached.take(_previewCount).toList();
        _loading[topic] = false;
        _shelfErrors.remove(topic);
      });
    } else {
      setState(() {
        _loading[topic] = true;
        _shelfErrors.remove(topic);
      });
    }

    try {
      final resp = await _service.fetchBooks(
        topic: topic,
        onDebug: (snapshot) {
          if (!mounted) return;
          setState(() => _shelfDebug[topic] = snapshot);
        },
      );
      if (mounted) {
        final books = resp.results.take(_previewCount).toList();
        setState(() {
          _shelves[topic] = books;
          _loading[topic] = false;
        });
        // Persist updated cache in background.
        _storage.saveShelfCache(topic, books);
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading[topic] = false;
          // Only show error banner when there is no cached data to display.
          if ((_shelves[topic] ?? []).isEmpty) {
            _shelfErrors[topic] = 'Could not load this shelf.';
          }
        });
      }
      return (_shelves[topic] ?? []).isNotEmpty;
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
      final resp = await _service.fetchBooks(
        search: q,
        onDebug: (snapshot) {
          if (!mounted || _query != q) return;
          setState(() => _searchDebug = snapshot);
        },
      );
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quietly',
                      style: GoogleFonts.lora(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (kDebugMode)
                    IconButton(
                      tooltip: _showDebugPanel
                          ? 'Hide API debug info'
                          : 'Show API debug info',
                      onPressed: () {
                        setState(() => _showDebugPanel = !_showDebugPanel);
                      },
                      icon: PhosphorIcon(
                        _showDebugPanel
                            ? PhosphorIconsFill.bug
                            : PhosphorIconsRegular.bug,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBarWidget(onChanged: _onSearch),
            ),
            if (kDebugMode && _showDebugPanel) _buildDebugPanel(),
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

    final suggestions = context.watch<SuggestionsProvider>();
    final suggestionGroups = suggestions.groups;
    final showSuggestions =
        suggestions.hasHistory && suggestionGroups.isNotEmpty;
    final showSuggestionsLoading =
        suggestions.hasHistory && suggestions.isLoading && suggestionGroups.isEmpty;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      physics: const AlwaysScrollableScrollPhysics(),
      // Extra items for the "For You" header + suggestion shelves (or shimmer).
      itemCount: _topics.length +
          (showSuggestions
              ? 1 + suggestionGroups.length
              : showSuggestionsLoading
                  ? 2
                  : 0),
      itemBuilder: (context, i) {
        // ── For You section ────────────────────────────────────────────────
        if (showSuggestions || showSuggestionsLoading) {
          if (i == 0) {
            return _buildForYouHeader();
          }
          if (showSuggestionsLoading && i == 1) {
            return _buildSuggestionShelfSkeleton();
          }
          if (showSuggestions && i <= suggestionGroups.length) {
            return _buildSuggestionShelf(
                suggestionGroups[i - 1], suggestions);
          }
          // Offset the raw ListView index to get the _topics index.
          // When showing suggestions: offset = 1 (header) + N (suggestion shelves).
          // When showing loading skeleton: offset = 2 (header + skeleton shelf).
          i -= (showSuggestions ? 1 + suggestionGroups.length : 2);
        }

        // ── Genre shelves ──────────────────────────────────────────────────
        final t = _topics[i];
        final topic = t['topic']!;
        final label = t['label']!;
        if (!_requestedTopics.contains(topic)) {
          _requestedTopics.add(topic);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadShelf(topic);
          });
        }
        final books = _shelves[topic] ?? [];
        final loading = _loading[topic] ?? false;
        final shelfError = _shelfErrors[topic];
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
              height: _shelfHeight,
              child: loading
                  ? _shelfSkeleton()
                  : shelfError != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                shelfError,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () => _loadShelf(topic),
                                child: const Text('Retry shelf'),
                              ),
                            ],
                          ),
                        )
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
                              child: BookCard(
                                book: books[j],
                                animationIndex: j,
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildForYouHeader() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: PhosphorIcon(
                PhosphorIconsRegular.sparkle,
                size: 18,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For You',
                style: GoogleFonts.lora(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              Text(
                'Based on your reading',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: -0.06, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }

  Widget _buildSuggestionShelf(
      SuggestionGroup group, SuggestionsProvider suggestions) {
    final books = suggestions.booksForGroup(group);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      group.queryType == 'author'
                          ? PhosphorIconsRegular.user
                          : PhosphorIconsRegular.books,
                      size: 12,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.label,
                      style: GoogleFonts.lora(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _shelfHeight,
          child: books.isEmpty
              ? _shelfSkeleton()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: books.length,
                  itemBuilder: (ctx, j) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: BookCard(book: books[j], animationIndex: j),
                  ),
                ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 80.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Widget _buildSuggestionShelfSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: SkeletonWidget(width: 160, height: 22, borderRadius: 20),
        ),
        SizedBox(height: _shelfHeight, child: _shelfSkeleton()),
      ],
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
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PhosphorIcon(PhosphorIconsRegular.magnifyingGlass,
                  size: 36, color: cs.outline),
              const SizedBox(height: 10),
              Text(
                'No books found for "$_query"',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Try a different title, author, or keyword.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.55,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) =>
          BookCard(book: _searchResults[i], animationIndex: i),
    );
  }

  Widget _buildDebugPanel() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              'Open Library debug responses',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_searchDebug != null)
            _DebugSnapshotTile(
              title: 'Search: ${_query.isEmpty ? '(none)' : _query}',
              snapshot: _searchDebug!,
            ),
          ..._topics.map((topicData) {
            final topic = topicData['topic']!;
            final label = topicData['label']!;
            final snapshot = _shelfDebug[topic];
            if (snapshot == null) {
              return ListTile(
                dense: true,
                title: Text('$label ($topic)'),
                subtitle: const Text('No response captured yet.'),
              );
            }
            return _DebugSnapshotTile(
              title: '$label ($topic)',
              snapshot: snapshot,
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _DebugSnapshotTile extends StatelessWidget {
  final String title;
  final OpenLibraryDebugSnapshot snapshot;

  const _DebugSnapshotTile({required this.title, required this.snapshot});

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
      title: Text(title, style: const TextStyle(fontSize: 13)),
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

class _ShowAllCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ShowAllCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 120,
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsRegular.arrowRight,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Show all',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
