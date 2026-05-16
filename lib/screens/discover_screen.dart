import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/genre.dart';
import '../models/reading_history.dart';
import '../providers/genres_provider.dart';
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
  static const _shelfHeight = 272.0;
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
  Timer? _searchDebounce;
  static const _searchDebounceMs = 500;

  // Readable books shelf
  List<Book> _readableBooks = [];
  bool _readableBooksLoading = false;
  String? _readableBooksError;

  List<Map<String, String>> _topics = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = context.read<UserProfileProvider>().allowedTopics.toSet();
    _topics = _allTopics.where((t) => allowed.contains(t['topic'])).toList();
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
    final results = await Future.wait([
      ...initialTopics.map((t) => _loadShelf(t['topic']!)),
      _loadReadableShelf(),
    ]);
    if (!mounted) return;
    if (results.take(initialTopics.length).every((ok) => !ok)) {
      setState(() {
        _catalogError =
            'Could not load books. Check your internet and pull to retry.';
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
    final results = await Future.wait([
      ..._topics.map((t) => _loadShelf(t['topic']!)),
      _loadReadableShelf(),
    ]);
    if (!mounted) return;
    if (results.take(_topics.length).every((ok) => !ok)) {
      setState(() {
        _catalogError =
            'Could not load books. Check your internet and pull to retry.';
      });
    }
  }

  Future<bool> _loadShelf(String topic) async {
    final userAge = context.read<UserProfileProvider>().userAge;
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
        userAge: userAge,
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

  Future<bool> _loadReadableShelf() async {
    final userAge = context.read<UserProfileProvider>().userAge;
    final cached = await _storage.getShelfCache('readable');
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _readableBooks =
            cached.where(_isFreeToRead).take(_previewCount).toList();
        _readableBooksLoading = false;
        _readableBooksError = null;
      });
    } else {
      setState(() {
        _readableBooksLoading = true;
        _readableBooksError = null;
      });
    }

    try {
      final resp = await _service.fetchBooks(
        topic: 'fiction',
        ebookAccess: 'public_domain',
        userAge: userAge,
      );
      if (mounted) {
        final books =
            resp.results.where(_isFreeToRead).take(_previewCount).toList();
        setState(() {
          _readableBooks = books;
          _readableBooksLoading = false;
        });
        _storage.saveShelfCache('readable', books);
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _readableBooksLoading = false;
          if (_readableBooks.isEmpty) {
            _readableBooksError = 'Could not load this shelf.';
          }
        });
      }
      return _readableBooks.isNotEmpty;
    }
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      _executeSearch('');
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: _searchDebounceMs),
      () => _executeSearch(q),
    );
  }

  void _onSearchSubmitted(String q) {
    _searchDebounce?.cancel();
    _executeSearch(q);
  }

  Future<void> _executeSearch(String q) async {
    final userAge = context.read<UserProfileProvider>().userAge;
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
        userAge: userAge,
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
        if (resp.results.isEmpty) {
          _storage.incrementDiscoverMetric('discover_search_no_results');
        }
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
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
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
              child: SearchBarWidget(
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
              ),
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
    final showSuggestions = suggestionGroups.isNotEmpty;
    final showSuggestionsLoading =
        suggestions.isLoading && suggestionGroups.isEmpty;

    final genres = context.watch<GenresProvider>();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      physics: const AlwaysScrollableScrollPhysics(),
      // Structure:
      // - "For You" header + suggestion shelves (or shimmer)
      // - Topic shelves
      // - "Free to Read" shelf
      // - "Explore Genres" shelf (at the bottom)
      itemCount: _topics.length +
          (showSuggestions
              ? 1 + suggestionGroups.length
              : showSuggestionsLoading
                  ? 2
                  : 0) +
          1 + // readable shelf
          1, // genres shelf (always visible at bottom)
      itemBuilder: (context, i) {
        // ── For You section ────────────────────────────────────────────────
        final forYouCount = showSuggestions
            ? 1 + suggestionGroups.length
            : showSuggestionsLoading
                ? 2
                : 0;

        if (showSuggestions || showSuggestionsLoading) {
          if (i == 0) {
            return _buildForYouHeader();
          }
          if (showSuggestionsLoading && i == 1) {
            return _buildSuggestionShelfSkeleton();
          }
          if (showSuggestions && i <= suggestionGroups.length) {
            return _buildSuggestionShelf(suggestionGroups[i - 1], suggestions);
          }
        }

        // ── Topic shelves ──────────────────────────────────────────────────
        // Offset for topics = forYouCount (after "For You" section)
        if (i < forYouCount + _topics.length) {
          final topicIndex = i - forYouCount;
          final t = _topics[topicIndex];
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
                      onPressed: () {
                        _storage.incrementDiscoverMetric(
                            'discover_show_all_topic_tap');
                        context.push(
                          '/discover/topic/$topic?label=${Uri.encodeComponent(label)}',
                        );
                      },
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
        }

        // ── Free to Read shelf ─────────────────────────────────────────────
        final readableIndex = forYouCount + _topics.length;
        if (i == readableIndex) {
          return _buildReadableShelf();
        }

        // ── Genres shelf (always last) ──────────────────────────────────────
        if (i == readableIndex + 1) {
          return _buildGenresShelf(genres);
        }

        return const SizedBox.shrink();
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
                context.read<SuggestionsProvider>().hasHistory
                    ? 'Based on your reading'
                    : 'Popular picks to get started',
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
    final books = _dedupSuggestionBooks(suggestions.booksForGroup(group));
    final cs = Theme.of(context).colorScheme;
    final sourceTitle = group.sourceBookTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PhosphorIcon(
                    group.queryType == 'author'
                        ? PhosphorIconsRegular.user
                        : PhosphorIconsRegular.books,
                    size: 14,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lora(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  _storage.incrementDiscoverMetric(
                      'discover_show_all_suggestion_tap');
                  context.push(
                    '/discover/suggestions?type=${Uri.encodeComponent(group.queryType)}&value=${Uri.encodeComponent(group.queryValue)}&label=${Uri.encodeComponent(group.label)}',
                  );
                },
                child: const Text('Show all'),
              ),
            ],
          ),
        ),
        if (sourceTitle != null && sourceTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              'Because you read "$sourceTitle"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.50),
                fontStyle: FontStyle.italic,
              ),
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

  Widget _buildReadableShelf() {
    final cs = Theme.of(context).colorScheme;
    const label = 'Free to Read';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsRegular.bookOpen,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.lora(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () {
                  _storage.incrementDiscoverMetric(
                      'discover_show_all_readable_tap');
                  context.push('/discover/readable');
                },
                child: const Text('Show all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _shelfHeight,
          child: _readableBooksLoading
              ? _shelfSkeleton()
              : _readableBooksError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _readableBooksError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _loadReadableShelf,
                            child: const Text('Retry shelf'),
                          ),
                        ],
                      ),
                    )
                  : _readableBooks.isEmpty
                      ? const Center(
                          child: Text('No readable books available yet'))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _readableBooks.length + 1,
                          itemBuilder: (ctx, j) {
                            if (j == _readableBooks.length) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _ShowAllCard(
                                  onTap: () {
                                    _storage.incrementDiscoverMetric(
                                        'discover_show_all_readable_tap');
                                    context.push('/discover/readable');
                                  },
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: BookCard(
                                book: _readableBooks[j],
                                animationIndex: j,
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildGenresShelf(GenresProvider genresProvider) {
    final cs = Theme.of(context).colorScheme;
    const label = 'Explore Genres';
    final profile = context.watch<UserProfileProvider>();
    final genres = genresProvider.genres
        .where((g) => profile.isGenreAllowed(g.key))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsRegular.tag,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.lora(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Pick a mood and dive into your next read',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 156,
          child: genres.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No genres available',
                      style:
                          TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: genres.length,
                  itemBuilder: (ctx, j) => _buildGenreCard(genres[j], j, cs),
                ),
        ),
      ],
    );
  }

  Widget _buildGenreCard(Genre genre, int index, ColorScheme cs) {
    final icon = _genreIconForGenre(genre, index);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 220,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              _storage.incrementDiscoverMetric('discover_genre_tap');
              context.push(
                '/discover/genre/${Uri.encodeComponent(genre.key)}?name=${Uri.encodeComponent(genre.name)}',
              );
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.16),
                    cs.secondary.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: cs.outline.withValues(alpha: 0.40)),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child:
                                PhosphorIcon(icon, size: 18, color: cs.primary),
                          ),
                        ),
                        const Spacer(),
                        PhosphorIcon(
                          PhosphorIconsRegular.arrowUpRight,
                          size: 16,
                          color: cs.primary.withValues(alpha: 0.90),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      genre.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.lora(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Browse collection',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.66),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PhosphorIconData _genreIconForGenre(Genre genre, int index) {
    switch (genre.key) {
      case 'history':
      case 'historical_fiction':
        return PhosphorIconsRegular.clockCounterClockwise;
      case 'biography':
        return PhosphorIconsRegular.user;
      case 'mystery':
        return PhosphorIconsRegular.magnifyingGlass;
      case 'science_fiction':
        return PhosphorIconsRegular.books;
      case 'adventure':
      case 'thriller':
        return PhosphorIconsRegular.arrowRight;
      case 'horror':
        return PhosphorIconsRegular.lock;
      case 'fantasy':
      case 'philosophy':
        return PhosphorIconsRegular.sparkle;
      case 'children':
      case 'young_adult':
        return PhosphorIconsRegular.book;
      case 'poetry':
      case 'romance':
      default:
        const fallback = [
          PhosphorIconsRegular.bookOpen,
          PhosphorIconsRegular.book,
          PhosphorIconsRegular.tag,
        ];
        return fallback[index % fallback.length];
    }
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

  /// Mirrors the "Free to read" condition used in [BookListRow]:
  /// a book is freely readable when it is not borrowable/print-disabled/no-ebook
  /// AND has a full-text source available.
  static bool _isFreeToRead(Book b) =>
      b.ebookAccess != EbookAccess.borrowable &&
      b.ebookAccess != EbookAccess.printDisabled &&
      b.ebookAccess != EbookAccess.noEbook &&
      b.hasFullText;

  List<Book> _dedupSuggestionBooks(List<Book> suggestions) {
    final staticIds = <int>{
      for (final shelf in _shelves.values)
        for (final b in shelf) b.id,
    };
    final seen = <int>{};
    final filtered = <Book>[];
    for (final b in suggestions) {
      if (filtered.length >= _previewCount) break;
      if (staticIds.contains(b.id)) continue;
      if (seen.add(b.id)) filtered.add(b);
    }
    if (filtered.isNotEmpty) return filtered;
    for (final b in suggestions) {
      if (filtered.length >= _previewCount) break;
      if (seen.add(b.id)) filtered.add(b);
    }
    return filtered;
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
            snapshot.bodyPreview.isEmpty
                ? '(empty body)'
                : snapshot.bodyPreview,
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
    final storage = StorageService();
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          storage.incrementDiscoverMetric('discover_show_all_topic_tap');
          onTap();
        },
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
