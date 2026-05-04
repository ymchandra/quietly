import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/book.dart';

class BookListRow extends StatelessWidget {
  final Book book;
  final double? progress;
  final VoidCallback? onLongPress;
  final int? animationIndex;

  const BookListRow({
    super.key,
    required this.book,
    this.progress,
    this.onLongPress,
    this.animationIndex,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delay = ((animationIndex ?? 0) * 50).ms;
    return InkWell(
      onTap: () => context.push('/book/${book.id}', extra: book),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'book-cover-${book.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: book.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: book.coverUrl!,
                        width: 60,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(cs),
                        errorWidget: (_, __, ___) => _placeholder(cs),
                      )
                    : _placeholder(cs),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.lora(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(book.authorName,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 6),
                  if (!book.hasFullText)
                    Row(
                      children: [
                        PhosphorIcon(
                          PhosphorIconsRegular.lock,
                          size: 12,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Not freely available',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.45)),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        PhosphorIcon(
                          PhosphorIconsRegular.bookOpen,
                          size: 12,
                          color: cs.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Free to read',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.primary.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress!,
                        minHeight: 4,
                        backgroundColor: cs.secondary,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${(progress! * 100).toInt()}%',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.04, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 60,
        height: 90,
        decoration: BoxDecoration(
          color: cs.secondary,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: PhosphorIcon(
          PhosphorIconsRegular.book,
          size: 20,
          color: cs.onSurface.withValues(alpha: 0.3),
        ),
      );
}
