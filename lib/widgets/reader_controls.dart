import 'package:flutter/material.dart';

class ReaderControls extends StatelessWidget {
  final bool visible;
  final int currentPage;
  final int totalPages;
  final Color bgColor;
  final Color textColor;
  final Color accentColor;
  final bool showSettings;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const ReaderControls({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    required this.bgColor,
    required this.textColor,
    required this.accentColor,
    this.showSettings = true,
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
                      icon: Icon(Icons.arrow_back, color: textColor),
                      onPressed: onBack,
                    ),
                    if (showSettings)
                      IconButton(
                        icon: Icon(Icons.text_fields, color: textColor),
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
                        value: totalPages > 0 ? currentPage / totalPages : 0,
                        minHeight: 3,
                        backgroundColor: accentColor.withValues(alpha: 0.2),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Page $currentPage / $totalPages',
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
