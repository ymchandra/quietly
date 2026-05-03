import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../services/gutendex_service.dart';
import '../services/storage_service.dart';
import '../widgets/skeleton_widget.dart';

class BookDetailScreen extends StatefulWidget {
  final int bookId;
  const BookDetailScreen({super.key, required this.bookId});
  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final _service = GutendexService();
  final _storage = StorageService();
  Book? _book;
  bool _loading = true;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final book = await _service.fetchBook(widget.bookId);
      if (mounted) {
        setState(() {
          _book = book;
          _loading = false;
        });
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

  Future<void> _download(LibraryProvider lib) async {
    if (_book == null) return;
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

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: Icon(inWishlist ? Icons.favorite : Icons.favorite_border,
                color: inWishlist ? cs.error : null),
            onPressed: () => lib.toggleWishlist(book),
            tooltip: 'Wishlist',
          ),
          IconButton(
            icon: Icon(
                inReadLater
                    ? Icons.watch_later
                    : Icons.watch_later_outlined,
                color: inReadLater ? cs.primary : null),
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
                        Icon(Icons.download,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text('${book.downloadCount} downloads',
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    cs.onSurface.withValues(alpha: 0.5))),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/reader/${book.id}'),
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: const Text('Read',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    downloaded || _downloading ? null : () => _download(lib),
                child: _downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(downloaded ? 'Saved Offline' : 'Save Offline'),
              ),
            ),
            const SizedBox(height: 24),
            if (book.subjects.isNotEmpty) ...[
              Text('Subjects',
                  style: GoogleFonts.lora(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _ChipWrap(items: book.subjects),
              const SizedBox(height: 16),
            ],
            if (book.bookshelves.isNotEmpty) ...[
              Text('Bookshelves',
                  style: GoogleFonts.lora(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _ChipWrap(items: book.bookshelves),
            ],
          ],
        ),
      ),
    );
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

class _Cover extends StatelessWidget {
  final Book book;
  const _Cover({required this.book});
  @override
  Widget build(BuildContext context) {
    final url = book.coverUrl;
    if (url == null) {
      return Container(
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
      );
    }
    return ClipRRect(
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
          child: const Icon(Icons.book),
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
