import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../services/openlibrary_service.dart';
import '../services/storage_service.dart';
import '../widgets/book_card.dart';
import '../widgets/skeleton_widget.dart';

/// A group of related books with a display label.
class _RelatedGroup {
  final String label;
  final String queryType; // 'author' or 'subject'
  final List<Book> books;
  const _RelatedGroup({
    required this.label,
    required this.queryType,
    required this.books,
  });
}

class BookDetailScreen extends StatefulWidget {
  final int bookId;
  final Book? initialBook;
  const BookDetailScreen({
    super.key,
    required this.bookId,
    this.initialBook,
  });
  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final _service = OpenLibraryService();
  final _storage = StorageService();
  Book? _book;
  bool _loading = true;
  bool _downloading = false;
  // _checkingReadability is only true when we must do a network probe because
  // the ebook_access value is still unknown after loading.
  bool _checkingReadability = false;
  // _canRead is the final verdict used only in the network-probe fallback path.
  bool _canRead = true;
  String? _error;

  // Related books state
  List<_RelatedGroup> _relatedGroups = [];
  bool _relatedLoading = false;

  /// The resolved ebook access level. Updated whenever [_book] changes.
  EbookAccess get _ebookAccess => _book?.ebookAccess ?? EbookAccess.unknown;

  /// Whether the book can be read in-app (public domain).
  bool get _readEnabled =>
      _ebookAccess == EbookAccess.publicDomain ||
      (_ebookAccess == EbookAccess.unknown && _canRead);

  /// Whether we are still determining access (spinner state).
  bool get _accessPending =>
      _ebookAccess == EbookAccess.unknown && _checkingReadability;

  @override
  void initState() {
    super.initState();
    _book = widget.initialBook;
    _loading = _book == null;
    if (_book != null && _ebookAccess == EbookAccess.unknown) {
      _checkReadability(_book!);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final book = await _service.fetchBook(widget.bookId);
      if (mounted) {
        setState(() {
          _book = book;
          _loading = false;
          _error = null;
        });
        // Only run network probe when access is still unknown after enrichment.
        if (_ebookAccess == EbookAccess.unknown) {
          _checkReadability(book);
        }
        _loadRelatedBooks(book);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_book == null) {
            _error = e.toString();
          }
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRelatedBooks(Book book) async {
    if (!mounted) return;
    setState(() => _relatedLoading = true);

    final groups = <_RelatedGroup>[];

    // --- Author group ---
    if (book.authors.isNotEmpty) {
      final rawName = book.authors.first.name;
      final displayName = _formatAuthorName(rawName);
      try {
        final resp = await _service.fetchBooks(search: displayName, page: 1);
        final books = resp.results
            .where((b) => b.id != book.id && _bookMatchesAuthor(b, rawName, displayName))
            .take(10)
            .toList();
        if (books.isNotEmpty) {
          groups.add(_RelatedGroup(
            label: 'More by $displayName',
            queryType: 'author',
            books: books,
          ));
        }
      } catch (_) {}
    }

    // --- Subject group ---
    final subject = _pickSubject(book);
    if (subject != null) {
      try {
        final resp = await _service.fetchBooks(topic: subject, page: 1);
        final books = resp.results
            .where((b) => b.id != book.id)
            .take(10)
            .toList();
        if (books.isNotEmpty) {
          groups.add(_RelatedGroup(
            label: 'More ${_capitalize(subject)}',
            queryType: 'subject',
            books: books,
          ));
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _relatedGroups = groups;
        _relatedLoading = false;
      });
    }
  }

  // ── Related-books helpers ─────────────────────────────────────────────────

  static String _formatAuthorName(String raw) {
    final parts = raw.split(',');
    return parts.reversed.map((p) => p.trim()).join(' ').trim();
  }

  static bool _bookMatchesAuthor(Book book, String rawName, String displayName) {
    final lastName = rawName.split(',').first.toLowerCase();
    final displayLower = displayName.toLowerCase();
    return book.authors.any((a) {
      final aLower = a.name.toLowerCase();
      return aLower.contains(lastName) ||
          displayLower.contains(a.name.split(',').first.toLowerCase());
    });
  }

  /// Pick the most representative subject from the book, skipping overly broad terms.
  static String? _pickSubject(Book book) {
    const skip = {
      'fiction',
      'nonfiction',
      'non-fiction',
      'literature',
      'books',
      'readable',
    };
    for (final raw in [...book.subjects, ...book.bookshelves]) {
      final lower = raw.toLowerCase().trim();
      final first = lower.split(RegExp(r'[&/]|--')).first.trim();
      if (first.length >= 3 && !skip.contains(first)) return first;
    }
    return null;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _download(LibraryProvider lib) async {
    if (_book == null || !_readEnabled) return;
    setState(() => _downloading = true);
    try {
      final text = await _service.fetchBookText(_book!);
      await _storage.saveOfflineText(_book!.id, text);
      await lib.addDownloaded(_book!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _checkReadability(Book book) async {
    if (!mounted) return;
    setState(() => _checkingReadability = true);
    final canRead = await _service.hasReadableText(book);
    if (!mounted) return;
    setState(() {
      _canRead = canRead;
      _checkingReadability = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final cs = Theme.of(context).colorScheme;
    if (_loading) return _buildSkeleton();
    if (_error != null || _book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error ?? 'Not found')),
      );
    }
    final book = _book!;
    final inWishlist = lib.isInWishlist(book.id);
    final inReadLater = lib.isInReadLater(book.id);
    final downloaded = lib.isDownloaded(book.id);
    final readDisabled = _accessPending || !_readEnabled;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: PhosphorIcon(
              inWishlist
                  ? PhosphorIconsFill.heart
                  : PhosphorIconsRegular.heart,
              color: inWishlist ? cs.error : null,
            ),
            onPressed: () => lib.toggleWishlist(book),
            tooltip: 'Wishlist',
          ),
          IconButton(
            icon: PhosphorIcon(
              inReadLater
                  ? PhosphorIconsFill.clockCounterClockwise
                  : PhosphorIconsRegular.clockCounterClockwise,
              color: inReadLater ? cs.primary : null,
            ),
            onPressed: () => lib.toggleReadLater(book),
            tooltip: 'Read Later',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(book: book),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title,
                          style: GoogleFonts.lora(
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(book.authorName,
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.7))),
                      const SizedBox(height: 8),
                      Row(children: [
                        PhosphorIcon(
                          PhosphorIconsRegular.downloadSimple,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text('${book.downloadCount} downloads',
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    cs.onSurface.withValues(alpha: 0.5))),
                      ]),
                      const SizedBox(height: 10),
                      _AvailabilityBadge(
                        ebookAccess: _ebookAccess,
                        checkingReadability: _accessPending,
                        canRead: _canRead,
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: readDisabled
                    ? null
                    : () => context.push('/reader/${book.id}', extra: book),
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: Text(
                  _readButtonLabel,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ).animate(delay: 100.ms).fadeIn(duration: 280.ms).slideY(begin: 0.06, end: 0),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: downloaded || _downloading || readDisabled
                    ? null
                    : () => _download(lib),
                child: _downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        downloaded
                            ? 'Saved Offline'
                            : _readEnabled
                                ? 'Save Offline'
                                : 'Unavailable Offline',
                      ),
              ),
            ).animate(delay: 160.ms).fadeIn(duration: 280.ms).slideY(begin: 0.06, end: 0),
            if (!_accessPending && !_readEnabled) ...[
              const SizedBox(height: 8),
              _AccessInfoBanner(ebookAccess: _ebookAccess),
            ],
            const SizedBox(height: 24),
            Text('Subjects',
                style:
                    GoogleFonts.lora(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (book.subjects.isEmpty)
              Text(
                'No subject information available for this title.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              )
            else
              _ChipWrap(items: book.subjects),
            const SizedBox(height: 16),
            Text('Bookshelves',
                style:
                    GoogleFonts.lora(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (book.bookshelves.isEmpty)
              Text(
                'No bookshelf tags available for this title.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              )
            else
              _ChipWrap(items: book.bookshelves),
            const SizedBox(height: 32),
            _RelatedBooksSection(
              loading: _relatedLoading,
              groups: _relatedGroups,
            ),
          ],
        ),
      ),
    );
  }

  String get _readButtonLabel {
    if (_accessPending) return 'Checking availability...';
    switch (_ebookAccess) {
      case EbookAccess.publicDomain:
        return 'Read';
      case EbookAccess.borrowable:
        return 'Borrowing Not Supported';
      case EbookAccess.printDisabled:
        return 'Restricted Access';
      case EbookAccess.noEbook:
        return 'No Ebook Available';
      case EbookAccess.unknown:
        return _canRead ? 'Read' : 'Text Not Available';
    }
  }

  Widget _buildSkeleton() {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonWidget(width: 120, height: 180, borderRadius: 8),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonWidget(
                      width: double.infinity, height: 20, borderRadius: 4),
                  const SizedBox(height: 8),
                  SkeletonWidget(width: 140, height: 16, borderRadius: 4),
                  const SizedBox(height: 8),
                  SkeletonWidget(width: 100, height: 14, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  final EbookAccess ebookAccess;
  final bool checkingReadability;
  final bool canRead;

  const _AvailabilityBadge({
    required this.ebookAccess,
    required this.checkingReadability,
    required this.canRead,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (checkingReadability) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: cs.outline),
          ),
          const SizedBox(width: 6),
          Text(
            'Checking availability...',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      );
    }

    switch (ebookAccess) {
      case EbookAccess.publicDomain:
        return _badge(
          context,
          icon: PhosphorIconsRegular.bookOpen,
          label: 'Free to read',
          bgColor: cs.primaryContainer,
          fgColor: cs.onPrimaryContainer,
        );
      case EbookAccess.borrowable:
        return _badge(
          context,
          icon: PhosphorIconsRegular.clockCounterClockwise,
          label: 'Borrowable only',
          bgColor: cs.secondaryContainer,
          fgColor: cs.onSecondaryContainer,
        );
      case EbookAccess.printDisabled:
        return _badge(
          context,
          icon: PhosphorIconsRegular.prohibit,
          label: 'Print-disabled only',
          bgColor: cs.tertiaryContainer,
          fgColor: cs.onTertiaryContainer,
        );
      case EbookAccess.noEbook:
        return _badge(
          context,
          icon: PhosphorIconsRegular.lock,
          label: 'No ebook',
          bgColor: cs.errorContainer,
          fgColor: cs.onErrorContainer,
        );
      case EbookAccess.unknown:
        // Fallback path: use the network-probe result.
        if (canRead) {
          return _badge(
            context,
            icon: PhosphorIconsRegular.bookOpen,
            label: 'Free to read',
            bgColor: cs.primaryContainer,
            fgColor: cs.onPrimaryContainer,
          );
        }
        return _badge(
          context,
          icon: PhosphorIconsRegular.lock,
          label: 'Not freely available',
          bgColor: cs.errorContainer,
          fgColor: cs.onErrorContainer,
        );
    }
  }

  Widget _badge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fgColor),
          ),
        ],
      ),
    );
  }
}

/// Info banner shown below the action buttons when the book is not freely readable.
class _AccessInfoBanner extends StatelessWidget {
  final EbookAccess ebookAccess;
  const _AccessInfoBanner({required this.ebookAccess});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final message = _messageFor(ebookAccess);
    if (message == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(PhosphorIconsRegular.info,
              size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _messageFor(EbookAccess access) {
    switch (access) {
      case EbookAccess.borrowable:
        return 'This title is available for controlled digital lending only. '
            'In-app reading requires a public domain edition.';
      case EbookAccess.printDisabled:
        return 'Access to this title is restricted to users with print disabilities '
            'and cannot be read in-app.';
      case EbookAccess.noEbook:
        return 'No ebook edition is available through Open Library for this title.';
      case EbookAccess.unknown:
        return 'This title is not available as readable text in Open Library. '
            'Only text-based books are supported by the reader.';
      case EbookAccess.publicDomain:
        return null;
    }
  }
}

class _Cover extends StatelessWidget {
  final Book book;
  const _Cover({required this.book});
  @override
  Widget build(BuildContext context) {
    final url = book.coverUrl;
    if (url == null) {
      return Hero(
        tag: 'book-cover-${book.id}',
        child: Container(
          width: 120,
          height: 180,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
              book.title.substring(0, book.title.length > 2 ? 2 : 1),
              style: const TextStyle(fontSize: 24)),
        ),
      );
    }
    return Hero(
      tag: 'book-cover-${book.id}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 120,
          height: 180,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
              width: 120,
              height: 180,
              color: Theme.of(context).colorScheme.secondary),
          errorWidget: (_, __, ___) => Container(
            width: 120,
            height: 180,
            color: Theme.of(context).colorScheme.secondary,
            alignment: Alignment.center,
            child: const PhosphorIcon(PhosphorIconsRegular.book),
          ),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  final List<String> items;
  const _ChipWrap({required this.items});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map((s) => Chip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: cs.secondary,
                side: BorderSide(color: cs.outline),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }
}

/// Displays zero or more horizontal shelves of books related to the current
/// book (by author and/or subject). While fetching, shows skeleton shelves.
class _RelatedBooksSection extends StatelessWidget {
  static const _shelfHeight = 252.0;

  final bool loading;
  final List<_RelatedGroup> groups;

  const _RelatedBooksSection({
    required this.loading,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show and not loading.
    if (!loading && groups.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsRegular.books,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You Might Also Like',
                    style: GoogleFonts.lora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    'Based on this book',
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
            .slideY(begin: -0.06, end: 0, duration: 350.ms, curve: Curves.easeOut),

        // ── Skeleton shown while loading ─────────────────────────────────
        if (loading) ...[
          _buildGroupSkeleton(context),
          _buildGroupSkeleton(context),
        ],

        // ── Loaded groups ────────────────────────────────────────────────
        for (final group in groups) _buildGroup(context, group, cs),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGroup(BuildContext context, _RelatedGroup group, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        ),
        SizedBox(
          height: _shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: group.books.length,
            itemBuilder: (ctx, j) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: BookCard(book: group.books[j], animationIndex: j),
            ),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 80.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Widget _buildGroupSkeleton(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: SkeletonWidget(width: 160, height: 22, borderRadius: 20),
        ),
        SizedBox(
          height: _shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
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
          ),
        ),
      ],
    );
  }
}
