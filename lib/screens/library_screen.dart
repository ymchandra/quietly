import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
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
    const segments = ['Reading', 'Downloaded', 'Finished'];
    final lists = [lib.reading, lib.downloaded, lib.finished];
    final books = lists[_selected];
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
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
