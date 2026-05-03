import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../services/storage_service.dart';

class LibraryProvider extends ChangeNotifier {
  final _storage = StorageService();

  List<Book> _wishlist = [];
  List<Book> _readLater = [];
  List<Book> _downloaded = [];
  Map<int, BookProgress> _progress = {};

  List<Book> get wishlist => List.unmodifiable(_wishlist);
  List<Book> get readLater => List.unmodifiable(_readLater);
  List<Book> get downloaded => List.unmodifiable(_downloaded);

  List<Book> get reading => _downloaded
      .where((b) {
        final p = _progress[b.id]?.percent ?? 0.0;
        return p > 0.0 && p < 1.0;
      })
      .toList();

  List<Book> get finished =>
      _downloaded.where((b) => (_progress[b.id]?.percent ?? 0.0) >= 1.0).toList();

  Future<void> init() async {
    _wishlist = await _storage.getWishlist();
    _readLater = await _storage.getReadLater();
    _downloaded = await _storage.getDownloaded();
    _progress = await _storage.getProgress();
  }

  bool isInWishlist(int id) => _wishlist.any((b) => b.id == id);
  bool isInReadLater(int id) => _readLater.any((b) => b.id == id);
  bool isDownloaded(int id) => _downloaded.any((b) => b.id == id);

  BookProgress? getProgress(int id) => _progress[id];

  Future<void> toggleWishlist(Book book) async {
    if (isInWishlist(book.id)) {
      _wishlist = _wishlist.where((b) => b.id != book.id).toList();
    } else {
      _wishlist = [..._wishlist, book];
    }
    await _storage.saveWishlist(_wishlist);
    notifyListeners();
  }

  Future<void> toggleReadLater(Book book) async {
    if (isInReadLater(book.id)) {
      _readLater = _readLater.where((b) => b.id != book.id).toList();
    } else {
      _readLater = [..._readLater, book];
    }
    await _storage.saveReadLater(_readLater);
    notifyListeners();
  }

  Future<void> addDownloaded(Book book) async {
    if (!isDownloaded(book.id)) {
      _downloaded = [..._downloaded, book];
      await _storage.saveDownloaded(_downloaded);
      notifyListeners();
    }
  }

  Future<void> removeDownloaded(int bookId) async {
    _downloaded = _downloaded.where((b) => b.id != bookId).toList();
    await _storage.saveDownloaded(_downloaded);
    await _storage.deleteOfflineText(bookId);
    notifyListeners();
  }

  Future<void> updateProgress(int bookId, double percent) async {
    _progress = Map.from(_progress)
      ..[bookId] = BookProgress(
        percent: percent,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    await _storage.saveProgress(_progress);
    notifyListeners();
  }
}
