class ReadingEvent {
  final int bookId;
  final String bookTitle;
  final List<String> authorNames;
  final List<String> subjects;
  final List<String> bookshelves;
  final int openedAt;
  /// Cumulative pages turned across all sessions for this book.
  final int pagesRead;
  /// Cumulative seconds spent reading this book across all sessions.
  final int sessionSeconds;

  const ReadingEvent({
    required this.bookId,
    required this.bookTitle,
    required this.authorNames,
    required this.subjects,
    required this.bookshelves,
    required this.openedAt,
    this.pagesRead = 0,
    this.sessionSeconds = 0,
  });

  ReadingEvent copyWith({
    int? pagesRead,
    int? sessionSeconds,
  }) =>
      ReadingEvent(
        bookId: bookId,
        bookTitle: bookTitle,
        authorNames: authorNames,
        subjects: subjects,
        bookshelves: bookshelves,
        openedAt: openedAt,
        pagesRead: pagesRead ?? this.pagesRead,
        sessionSeconds: sessionSeconds ?? this.sessionSeconds,
      );

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'bookTitle': bookTitle,
        'authorNames': authorNames,
        'subjects': subjects,
        'bookshelves': bookshelves,
        'openedAt': openedAt,
        'pagesRead': pagesRead,
        'sessionSeconds': sessionSeconds,
      };

  factory ReadingEvent.fromJson(Map<String, dynamic> json) => ReadingEvent(
        bookId: json['bookId'] as int,
        bookTitle: json['bookTitle'] as String? ?? '',
        authorNames: List<String>.from(json['authorNames'] as List? ?? []),
        subjects: List<String>.from(json['subjects'] as List? ?? []),
        bookshelves: List<String>.from(json['bookshelves'] as List? ?? []),
        openedAt: json['openedAt'] as int,
        pagesRead: json['pagesRead'] as int? ?? 0,
        sessionSeconds: json['sessionSeconds'] as int? ?? 0,
      );
}

class SuggestionGroup {
  final String label;
  final String queryType; // 'subject' or 'author'
  final String queryValue;
  final List<String> bookJsons;

  const SuggestionGroup({
    required this.label,
    required this.queryType,
    required this.queryValue,
    required this.bookJsons,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'queryType': queryType,
        'queryValue': queryValue,
        'bookJsons': bookJsons,
      };

  factory SuggestionGroup.fromJson(Map<String, dynamic> json) =>
      SuggestionGroup(
        label: json['label'] as String? ?? '',
        queryType: json['queryType'] as String? ?? 'subject',
        queryValue: json['queryValue'] as String? ?? '',
        bookJsons: List<String>.from(json['bookJsons'] as List? ?? []),
      );
}
