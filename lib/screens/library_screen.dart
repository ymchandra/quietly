import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/suggestions_provider.dart';
import '../models/book.dart';
import '../widgets/book_list_row.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/segmented_control_widget.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final suggestions = context.watch<SuggestionsProvider>();
    const segments = ['Reading', 'Downloaded', 'Finished'];
    final lists = [lib.reading, lib.downloaded, lib.finished];
    final books = lists[_selected];
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: [
          _StatsBar(lib: lib, suggestions: suggestions),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedControlWidget(
              segments: segments,
              selectedIndex: _selected,
              onChanged: (i) => setState(() => _selected = i),
            ),
          ),
          Expanded(child: _buildList(books, lib)),
        ],
      ),
    );
  }

  Widget _buildList(List<Book> books, LibraryProvider lib) {
    if (books.isEmpty) {
      final msgs = [
        (PhosphorIconsRegular.bookOpen, 'No books in progress', 'Start reading to see books here'),
        (PhosphorIconsRegular.downloadSimple, 'No downloads', 'Save books offline to read without internet'),
        (PhosphorIconsRegular.checkCircle, 'No finished books', 'Books you complete will appear here'),
      ];
      return EmptyStateWidget(
        icon: msgs[_selected].$1,
        title: msgs[_selected].$2,
        subtitle: msgs[_selected].$3,
      );
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final book = books[i];
        final progress = lib.getProgress(book.id)?.percent;
        return BookListRow(
          book: book,
          progress: progress,
          animationIndex: i,
          onLongPress: () => _confirmRemove(ctx, book, lib),
        );
      },
    );
  }

  Future<void> _confirmRemove(
      BuildContext ctx, Book book, LibraryProvider lib) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remove Download'),
        content: Text('Remove "${book.title}" from downloads?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm == true) await lib.removeDownloaded(book.id);
  }
}

// ── Stats summary bar ─────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final LibraryProvider lib;
  final SuggestionsProvider suggestions;
  const _StatsBar({required this.lib, required this.suggestions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final finished = lib.finished.length;
    final reading = lib.reading.length;
    final uniqueOpened =
        suggestions.history.map((e) => e.bookId).toSet().length;

    // Only show the bar when there is something to display.
    if (finished == 0 && reading == 0 && uniqueOpened == 0) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => context.push('/stats'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            PhosphorIcon(
              PhosphorIconsRegular.chartBar,
              size: 18,
              color: cs.primary,
            ),
            const SizedBox(width: 10),
            _MiniStat(label: 'Finished', value: '$finished', cs: cs),
            _Divider(cs: cs),
            _MiniStat(label: 'Reading', value: '$reading', cs: cs),
            _Divider(cs: cs),
            _MiniStat(label: 'Opened', value: '$uniqueOpened', cs: cs),
            const Spacer(),
            Text(
              'View stats',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 2),
            PhosphorIcon(
              PhosphorIconsRegular.arrowRight,
              size: 13,
              color: cs.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _MiniStat(
      {required this.label, required this.value, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final ColorScheme cs;
  const _Divider({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: cs.outline,
    );
  }
}
