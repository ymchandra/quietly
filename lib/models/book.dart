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

class Book {
  final int id;
  final String title;
  final List<Person> authors;
  final List<String> subjects;
  final List<String> bookshelves;
  final List<String> languages;
  final Map<String, String> formats;
  final int downloadCount;

  const Book({
    required this.id,
    required this.title,
    required this.authors,
    required this.subjects,
    required this.bookshelves,
    required this.languages,
    required this.formats,
    required this.downloadCount,
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
      };
}

class GutendexResponse {
  final int count;
  final String? next;
  final String? previous;
  final List<Book> results;

  const GutendexResponse({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  factory GutendexResponse.fromJson(Map<String, dynamic> json) =>
      GutendexResponse(
        count: json['count'] as int? ?? 0,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>? ?? [])
            .map((b) => Book.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}
