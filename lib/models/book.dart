class Person {
  final String name;
  final int? birthYear;
  final int? deathYear;

  const Person({required this.name, this.birthYear, this.deathYear});

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        name: json['name'] as String? ?? '',
        birthYear: json['birth_year'] as int?,
        deathYear: json['death_year'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (birthYear != null) 'birth_year': birthYear,
        if (deathYear != null) 'death_year': deathYear,
      };
}

/// Access level values returned by the Open Library `ebook_access` field.
enum EbookAccess {
  /// Freely available — public domain text that can be read without restriction.
  publicDomain,

  /// Available via controlled digital lending (borrowing), not freely readable.
  borrowable,

  /// Only accessible to users with print disabilities.
  printDisabled,

  /// No ebook edition is available through Open Library.
  noEbook,

  /// Access status is unknown or not yet fetched.
  unknown;

  static EbookAccess fromString(String? value) {
    switch (value) {
      case 'public_domain':
        return EbookAccess.publicDomain;
      case 'borrowable':
        return EbookAccess.borrowable;
      case 'printdisabled':
        return EbookAccess.printDisabled;
      case 'no_ebook':
        return EbookAccess.noEbook;
      default:
        return EbookAccess.unknown;
    }
  }

  String toJson() {
    switch (this) {
      case EbookAccess.publicDomain:
        return 'public_domain';
      case EbookAccess.borrowable:
        return 'borrowable';
      case EbookAccess.printDisabled:
        return 'printdisabled';
      case EbookAccess.noEbook:
        return 'no_ebook';
      case EbookAccess.unknown:
        return 'unknown';
    }
  }
}

class Book {
  final int id;
  final String title;
  final List<Person> authors;
  final List<String> subjects;
  final List<String> bookshelves;
  final List<String> languages;
  final Map<String, String> formats;
  final int downloadCount;

  /// Whether this book is known to have publicly accessible full text.
  /// Derived from the Open Library `public_scan_b` / `has_fulltext` fields.
  final bool hasFullText;

  /// The ebook access level reported by the Open Library `ebook_access` field.
  /// [EbookAccess.unknown] means the value has not been fetched yet.
  final EbookAccess ebookAccess;

  const Book({
    required this.id,
    required this.title,
    required this.authors,
    required this.subjects,
    required this.bookshelves,
    required this.languages,
    required this.formats,
    required this.downloadCount,
    this.hasFullText = false,
    this.ebookAccess = EbookAccess.unknown,
  });

  String? get coverUrl => formats['image/jpeg'];

  String get authorName {
    if (authors.isEmpty) return 'Unknown Author';
    final raw = authors[0].name;
    final parts = raw.split(',');
    return parts.reversed.join(' ').trim();
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    final rawFormats = json['formats'] as Map<String, dynamic>? ?? {};
    return Book(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      authors: (json['authors'] as List<dynamic>? ?? [])
          .map((a) => Person.fromJson(a as Map<String, dynamic>))
          .toList(),
      subjects: List<String>.from(json['subjects'] as List? ?? []),
      bookshelves: List<String>.from(json['bookshelves'] as List? ?? []),
      languages: List<String>.from(json['languages'] as List? ?? []),
      formats: rawFormats.map((k, v) => MapEntry(k, v.toString())),
      downloadCount: json['download_count'] as int? ?? 0,
      hasFullText: json['has_full_text'] as bool? ?? false,
      ebookAccess: EbookAccess.fromString(json['ebook_access'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authors': authors.map((a) => a.toJson()).toList(),
        'subjects': subjects,
        'bookshelves': bookshelves,
        'languages': languages,
        'formats': formats,
        'download_count': downloadCount,
        'has_full_text': hasFullText,
        'ebook_access': ebookAccess.toJson(),
      };
}

class OpenLibraryResponse {
  final int count;
  final String? next;
  final String? previous;
  final List<Book> results;

  const OpenLibraryResponse({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory OpenLibraryResponse.fromJson(Map<String, dynamic> json) =>
      OpenLibraryResponse(
        count: json['count'] as int? ?? 0,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>? ?? [])
            .map((b) => Book.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}
