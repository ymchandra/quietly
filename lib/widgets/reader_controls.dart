import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ReaderControls extends StatelessWidget {
  final bool visible;
  final int currentPage;
  final int totalPages;
  /// When provided (scroll mode), this overrides the page-based progress value
  /// and changes the label to show percentage read instead of page numbers.
  final double? readPercent;
  final Color bgColor;
  final Color textColor;
  final Color accentColor;
  final bool showSettings;
  final String? bookTitle;
  final String? bookAuthor;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const ReaderControls({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    this.readPercent,
    required this.bgColor,
    required this.textColor,
    required this.accentColor,
    this.showSettings = true,
    this.bookTitle,
    this.bookAuthor,
    required this.onBack,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: bgColor,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 4,
                  right: 4,
                  bottom: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: PhosphorIcon(PhosphorIconsRegular.arrowLeft,
                          color: textColor),
                      onPressed: onBack,
                    ),
                    // Book title and author in center
                    if (bookTitle != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                bookTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.lora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              if (bookAuthor != null)
                                Text(
                                  bookAuthor!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textColor.withValues(alpha: 0.65),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (showSettings)
                      IconButton(
                        icon: PhosphorIcon(PhosphorIconsRegular.textT,
                            color: textColor),
                        onPressed: onSettings,
                      ),
                  ],
                ),
              ),
            ),
            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: bgColor,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8,
                  left: 20,
                  right: 20,
                  top: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: readPercent ??
                            (totalPages > 0 ? currentPage / totalPages : 0),
                        minHeight: 3,
                        backgroundColor: accentColor.withValues(alpha: 0.2),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      readPercent != null
                          ? '${(readPercent! * 100).round()}% read'
                          : 'Page $currentPage / $totalPages',
                      style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
