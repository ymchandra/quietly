import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/book.dart';

class GutendexService {
  static const _base = 'https://gutendex.com';
  static const _timeout = Duration(seconds: 15);
  static const _textTimeout = Duration(seconds: 30);

  Future<GutendexResponse> fetchBooks({
    String? topic,
    String? search,
    String languages = 'en',
    String sort = 'popular',
    int page = 1,
  }) async {
    final params = <String, String>{
      'languages': languages,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
      if (search != null && search.isNotEmpty) 'search': search,
      'sort': sort,
      if (page > 1) 'page': page.toString(),
    };
    final uri = Uri.parse('$_base/books').replace(queryParameters: params);
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return GutendexResponse.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<Book> fetchBook(int id) async {
    final uri = Uri.parse('$_base/books/$id');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return Book.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<String> fetchBookText(Book book) async {
    final sources = _buildSources(book);
    for (final url in sources) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(_textTimeout);
        if (resp.statusCode == 200) {
          final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
          if (url.contains('.html') || url.contains('html')) {
            return cleanGutenbergText(htmlToPlainText(raw));
          }
          return cleanGutenbergText(raw);
        }
      } catch (_) {
        continue;
      }
    }
    throw Exception('Could not fetch book text');
  }

  List<String> _buildSources(Book book) {
    final sources = <String>[];
    final fmts = book.formats;
    for (final key in [
      'text/plain; charset=utf-8',
      'text/plain; charset=us-ascii',
      'text/plain',
    ]) {
      if (fmts.containsKey(key)) sources.add(fmts[key]!);
    }
    for (final key in fmts.keys) {
      if (key.contains('html')) sources.add(fmts[key]!);
    }
    final id = book.id;
    sources.addAll([
      'https://www.gutenberg.org/cache/epub/$id/pg$id.txt',
      'https://www.gutenberg.org/files/$id/$id-0.txt',
      'https://www.gutenberg.org/files/$id/$id.txt',
      'https://www.gutenberg.org/cache/epub/$id/pg$id-images.html',
    ]);
    return sources;
  }

  String htmlToPlainText(String html) {
    var text = html.replaceAll(
        RegExp(r'<head[^>]*>.*?</head>', dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
        '');
    text = text.replaceAll(
        RegExp(r'</?(p|div|h[1-6]|li|tr|br|hr)[^>]*>',
            caseSensitive: false),
        '\n\n');
    text = text.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = _decodeEntities(text);
    return text;
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026')
        .replaceAll('&rsquo;', '\u2019')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rdquo;', '\u201D')
        .replaceAll('&ldquo;', '\u201C')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          if (code != null) return String.fromCharCode(code);
          return m.group(0)!;
        });
  }

  String cleanGutenbergText(String text) {
    final startRegex = RegExp(
        r'\*{3}\s*START OF (THE|THIS) PROJECT GUTENBERG[^\n]*\n',
        caseSensitive: false);
    final startMatch = startRegex.firstMatch(text);
    if (startMatch != null) {
      text = text.substring(startMatch.end);
    }
    final endRegex = RegExp(
        r'\*{3}\s*END OF (THE|THIS) PROJECT GUTENBERG',
        caseSensitive: false);
    final endMatch = endRegex.firstMatch(text);
    if (endMatch != null) {
      text = text.substring(0, endMatch.start);
    }
    text = text.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
    return text.trim();
  }
}
