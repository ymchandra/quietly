/// Represents a book genre/subject from Open Library.
class Genre {
  /// The genre name (e.g., "Mystery", "Romance", "Science Fiction")
  final String name;

  /// A URL-safe identifier for the genre
  final String key;

  /// The number of books in this genre (approximate)
  final int bookCount;

  const Genre({
    required this.name,
    required this.key,
    required this.bookCount,
  });

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      name: json['name'] as String? ?? '',
      key: json['key'] as String? ?? '',
      bookCount: json['work_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'key': key,
    'work_count': bookCount,
  };

  @override
  String toString() => 'Genre(name=$name, key=$key, bookCount=$bookCount)';
}

