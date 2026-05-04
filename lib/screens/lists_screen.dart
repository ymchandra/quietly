import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/book.dart';
import '../widgets/book_list_row.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/segmented_control_widget.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});
  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final lists = [lib.wishlist, lib.readLater];
    final books = lists[_selected];
    return Scaffold(
      appBar: AppBar(title: const Text('Lists')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedControlWidget(
              segments: const ['Wishlist', 'Read Later'],
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
        (PhosphorIconsRegular.heart, 'Your wishlist is empty', 'Add books you want to read'),
        (PhosphorIconsRegular.clockCounterClockwise, 'Read Later is empty', 'Save books to read when you have time'),
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
        return BookListRow(
          book: book,
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
        title: Text(
            _selected == 0 ? 'Remove from Wishlist' : 'Remove from Read Later'),
        content: Text('Remove "${book.title}"?'),
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
    if (confirm == true) {
      if (_selected == 0) {
        await lib.toggleWishlist(book);
      } else {
        await lib.toggleReadLater(book);
      }
    }
  }
}
