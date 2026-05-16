import 'package:flutter/material.dart';
import '../models/genre.dart';

/// Provider for curated static genres used in Discover.
class GenresProvider with ChangeNotifier {
  static const List<Genre> _curatedGenres = [
    Genre(name: 'Romance', key: 'romance', bookCount: 0),
    Genre(name: 'Mystery', key: 'mystery', bookCount: 0),
    Genre(name: 'Fantasy', key: 'fantasy', bookCount: 0),
    Genre(name: 'Science Fiction', key: 'science_fiction', bookCount: 0),
    Genre(name: 'Thriller', key: 'thriller', bookCount: 0),
    Genre(name: 'Horror', key: 'horror', bookCount: 0),
    Genre(name: 'Adventure', key: 'adventure', bookCount: 0),
    Genre(name: 'Historical Fiction', key: 'historical_fiction', bookCount: 0),
    Genre(name: 'Biography', key: 'biography', bookCount: 0),
    Genre(name: 'History', key: 'history', bookCount: 0),
    Genre(name: 'Philosophy', key: 'philosophy', bookCount: 0),
    Genre(name: 'Poetry', key: 'poetry', bookCount: 0),
    Genre(name: 'Children', key: 'children', bookCount: 0),
    Genre(name: 'Young Adult', key: 'young_adult', bookCount: 0),
  ];

  List<Genre> _genres = List<Genre>.from(_curatedGenres);
  bool _isLoading = false;
  String? _error;

  List<Genre> get genres => _genres;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Loads curated genres once.
  Future<void> loadGenres() async {
    // Kept for compatibility with existing call sites.
    return;
  }

  /// Re-applies curated genres immediately.
  Future<void> refreshGenres() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _genres = List<Genre>.from(_curatedGenres);
    _isLoading = false;
    notifyListeners();
  }
}
