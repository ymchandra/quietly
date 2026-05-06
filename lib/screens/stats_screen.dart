import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/suggestions_provider.dart';
import '../models/reading_history.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final suggestions = context.watch<SuggestionsProvider>();
    final history = suggestions.history;

    final booksFinished = lib.finished.length;
    final booksReading = lib.reading.length;
    final booksSaved = lib.wishlist.length + lib.readLater.length;
    final uniqueOpened = history.map((e) => e.bookId).toSet().length;

    final topGenres = _topGenres(history, 12);
    final topAuthors = _topAuthors(history, 8);

    final hasAnyData =
        booksFinished > 0 || booksReading > 0 || history.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reading Stats',
          style: GoogleFonts.lora(fontWeight: FontWeight.w600),
        ),
      ),
      body: hasAnyData
          ? _buildBody(
              context,
              booksFinished: booksFinished,
              booksReading: booksReading,
              booksSaved: booksSaved,
              uniqueOpened: uniqueOpened,
              topGenres: topGenres,
              topAuthors: topAuthors,
              history: history,
            )
          : _buildEmpty(context),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required int booksFinished,
    required int booksReading,
    required int booksSaved,
    required int uniqueOpened,
    required List<MapEntry<String, int>> topGenres,
    required List<MapEntry<String, int>> topAuthors,
    required List<ReadingEvent> history,
  }) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Overview tiles ────────────────────────────────────────────────
        _SectionHeader(title: 'Overview'),
        const SizedBox(height: 12),
        _OverviewGrid(
          items: [
            _StatItem(
              icon: PhosphorIconsRegular.checkCircle,
              label: 'Finished',
              value: '$booksFinished',
              accent: cs.primary,
            ),
            _StatItem(
              icon: PhosphorIconsRegular.bookOpen,
              label: 'Reading',
              value: '$booksReading',
              accent: const Color(0xFF6BAF92),
            ),
            _StatItem(
              icon: PhosphorIconsRegular.bookmarks,
              label: 'Saved',
              value: '$booksSaved',
              accent: const Color(0xFF8B7EC8),
            ),
            _StatItem(
              icon: PhosphorIconsRegular.bookOpenText,
              label: 'Opened',
              value: '$uniqueOpened',
              accent: const Color(0xFFC08A3A),
            ),
          ],
        ),

        // ── Top Genres ────────────────────────────────────────────────────
        if (topGenres.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(title: 'Genres Explored'),
          const SizedBox(height: 12),
          _GenreChips(genres: topGenres),
        ],

        // ── Top Authors ───────────────────────────────────────────────────
        if (topAuthors.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(title: 'Authors Read'),
          const SizedBox(height: 12),
          _AuthorList(authors: topAuthors),
        ],

        // ── Recent reading ────────────────────────────────────────────────
        if (history.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeader(title: 'Recent Reading'),
          const SizedBox(height: 12),
          _RecentList(events: history.take(8).toList()),
        ],
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
              ),
              child: PhosphorIcon(
                PhosphorIconsRegular.chartBar,
                size: 40,
                color: cs.primary,
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.6, 0.6),
                  end: const Offset(1, 1),
                  duration: 400.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
            Text(
              'No reading data yet',
              style: GoogleFonts.lora(
                  fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            )
                .animate(delay: 120.ms)
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.1, end: 0, duration: 300.ms),
            const SizedBox(height: 8),
            Text(
              'Open a book to start tracking your reading journey.',
              style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.1, end: 0, duration: 300.ms),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static List<MapEntry<String, int>> _topGenres(
      List<ReadingEvent> history, int n) {
    final counts = <String, int>{};
    for (final event in history) {
      final seen = <String>{};
      for (final s in [...event.subjects, ...event.bookshelves]) {
        final clean = _cleanLabel(s);
        if (clean.isNotEmpty && seen.add(clean)) {
          counts[clean] = (counts[clean] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }

  static List<MapEntry<String, int>> _topAuthors(
      List<ReadingEvent> history, int n) {
    final counts = <String, int>{};
    for (final event in history) {
      for (final raw in event.authorNames) {
        final display = _formatAuthorName(raw);
        if (display.trim().isNotEmpty) {
          counts[display] = (counts[display] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }

  // Minimum character count for a genre label to be considered meaningful.
  static const _minLabelLength = 3;

  static String _cleanLabel(String raw) {
    const skip = {
      'fiction',
      'nonfiction',
      'non-fiction',
      'literature',
      'books',
      'readable',
    };
    final lower = raw.toLowerCase().trim();
    final segments = lower.split(RegExp(r'[&/]|--'));
    final first = segments.first.trim();
    if (first.length < _minLabelLength || skip.contains(first)) return '';
    return _capitalize(first);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

// Converts a stored author name ("Last, First") to display form ("First Last").
// If no comma is present the name is returned unchanged.
String _formatAuthorName(String raw) {
  final parts = raw.split(',');
  return parts.reversed.map((p) => p.trim()).join(' ').trim();
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.lora(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _StatItem {
  final PhosphorIconData icon;
  final String label;
  final String value;
  final Color accent;
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _OverviewGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _OverviewGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items
          .asMap()
          .entries
          .map((e) => _StatTile(item: e.value, delay: e.key * 80))
          .toList(),
    );
  }
}

class _StatTile extends StatelessWidget {
  final _StatItem item;
  final int delay;
  const _StatTile({required this.item, this.delay = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Center(child: PhosphorIcon(item.icon, size: 18, color: item.accent)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                style: GoogleFonts.lora(
                    fontSize: 26, fontWeight: FontWeight.bold,
                    color: cs.onSurface),
              ),
              Text(
                item.label,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }
}

class _GenreChips extends StatelessWidget {
  final List<MapEntry<String, int>> genres;
  const _GenreChips({required this.genres});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxCount = genres.isNotEmpty ? genres.first.value : 1;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: genres.asMap().entries.map((entry) {
        final i = entry.key;
        final genre = entry.value;
        final intensity = (genre.value / maxCount).clamp(0.25, 1.0);
        return _GenreChip(
          label: genre.key,
          count: genre.value,
          accentAlpha: intensity,
          delay: i * 40,
          cs: cs,
        );
      }).toList(),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final int count;
  final double accentAlpha;
  final int delay;
  final ColorScheme cs;

  const _GenreChip({
    required this.label,
    required this.count,
    required this.accentAlpha,
    required this.delay,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: accentAlpha * 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: cs.primary.withValues(alpha: accentAlpha * 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.primary.withValues(alpha: 0.9),
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: accentAlpha * 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.primary.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 250.ms)
        .scale(
          begin: const Offset(0.88, 0.88),
          end: const Offset(1, 1),
          duration: 250.ms,
          curve: Curves.easeOut,
        );
  }
}

class _AuthorList extends StatelessWidget {
  final List<MapEntry<String, int>> authors;
  const _AuthorList({required this.authors});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxCount = authors.isNotEmpty ? authors.first.value : 1;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: authors.asMap().entries.map((entry) {
          final i = entry.key;
          final author = entry.value;
          final isLast = i == authors.length - 1;
          final barFraction = (author.value / maxCount).clamp(0.05, 1.0);

          return _AuthorRow(
            rank: i + 1,
            name: author.key,
            count: author.value,
            barFraction: barFraction,
            isLast: isLast,
            delay: i * 60,
            cs: cs,
          );
        }).toList(),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final int rank;
  final String name;
  final int count;
  final double barFraction;
  final bool isLast;
  final int delay;
  final ColorScheme cs;

  const _AuthorRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.barFraction,
    required this.isLast,
    required this.delay,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: rank == 1
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 5),
                    LayoutBuilder(builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            height: 4,
                            width: constraints.maxWidth,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            height: 4,
                            width: constraints.maxWidth * barFraction,
                            decoration: BoxDecoration(
                              color: cs.primary
                                  .withValues(alpha: 0.6 + barFraction * 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )
                              .animate(
                                  delay: Duration(
                                      milliseconds: delay + 200))
                              .custom(
                                duration: 500.ms,
                                curve: Curves.easeOut,
                                builder: (context, value, child) =>
                                    ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: value,
                                    child: child,
                                  ),
                                ),
                              ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                count == 1 ? '1 book' : '$count books',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: cs.outline),
      ],
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 280.ms)
        .slideX(begin: 0.04, end: 0, duration: 280.ms, curve: Curves.easeOut);
  }
}

class _RecentList extends StatelessWidget {
  final List<ReadingEvent> events;
  const _RecentList({required this.events});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: events.asMap().entries.map((entry) {
          final i = entry.key;
          final event = entry.value;
          final isLast = i == events.length - 1;
          final date = DateTime.fromMillisecondsSinceEpoch(event.openedAt);
          final dateStr = _formatDate(date);
          return _RecentRow(
            event: event,
            dateStr: dateStr,
            isLast: isLast,
            delay: i * 50,
            cs: cs,
          );
        }).toList(),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${d.day} ${_monthShort(d.month)}';
  }

  static String _monthShort(int m) {
    // DateTime.month is guaranteed to be 1-12 by the Dart SDK.
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[m - 1];
  }
}

class _RecentRow extends StatelessWidget {
  final ReadingEvent event;
  final String dateStr;
  final bool isLast;
  final int delay;
  final ColorScheme cs;

  const _RecentRow({
    required this.event,
    required this.dateStr,
    required this.isLast,
    required this.delay,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final authorDisplay = event.authorNames.isEmpty
        ? 'Unknown Author'
        : _formatAuthorName(event.authorNames.first);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsRegular.bookOpen,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.bookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      authorDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.45)),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: cs.outline),
      ],
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 260.ms)
        .slideX(begin: 0.04, end: 0, duration: 260.ms, curve: Curves.easeOut);
  }
}
