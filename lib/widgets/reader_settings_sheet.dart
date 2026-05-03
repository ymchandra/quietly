import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/reader_settings.dart';
import '../providers/reader_settings_provider.dart';
import 'segmented_control_widget.dart';

class ReaderSettingsSheet extends StatelessWidget {
  final int bookId;
  const ReaderSettingsSheet({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReaderSettingsProvider>();
    final settings = provider.forBook(bookId);
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Appearance',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
          ),
          const SizedBox(height: 16),
          const _SheetLabel('Theme'),
          const SizedBox(height: 10),
          _ThemeCirclesSheet(
              current: settings.theme,
              onSelect: (t) {
                provider.updateForBook(bookId, {'theme': t.name});
              }),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SheetLabel('Font'),
                    const SizedBox(height: 8),
                    SegmentedControlWidget(
                      segments: const ['Lora', 'Inter'],
                      selectedIndex:
                          settings.fontFamily == FontFamily.lora ? 0 : 1,
                      onChanged: (i) => provider.updateForBook(bookId, {
                        'fontFamily': (i == 0 ? FontFamily.lora : FontFamily.inter)
                            .name
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetLabel('Size'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SmallBtn(
                        icon: Icons.remove,
                        onTap: settings.fontSize > 14
                            ? () => provider.updateForBook(bookId,
                                {'fontSize': settings.fontSize - 2})
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('${settings.fontSize.toInt()}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      _SmallBtn(
                        icon: Icons.add,
                        onTap: settings.fontSize < 26
                            ? () => provider.updateForBook(bookId,
                                {'fontSize': settings.fontSize + 2})
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _SheetLabel('Line Height'),
          const SizedBox(height: 8),
          SegmentedControlWidget(
            segments: const ['Compact', 'Comfortable', 'Airy'],
            selectedIndex: settings.lineHeight.index,
            onChanged: (i) => provider.updateForBook(
                bookId, {'lineHeight': LineHeight.values[i].name}),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7))),
    );
  }
}

class _ThemeCirclesSheet extends StatelessWidget {
  final ThemeName current;
  final void Function(ThemeName) onSelect;
  const _ThemeCirclesSheet({required this.current, required this.onSelect});

  static const _themes = [
    (ThemeName.cream, AppColors.readerCreamBg, AppColors.readerCreamText),
    (ThemeName.paper, AppColors.readerPaperBg, AppColors.readerPaperText),
    (ThemeName.sepia, AppColors.readerSepiaBg, AppColors.readerSepiaText),
    (ThemeName.slate, AppColors.readerSlateBg, AppColors.readerSlateText),
    (ThemeName.midnight, AppColors.readerMidnightBg,
        AppColors.readerMidnightText),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _themes.map((t) {
        final selected = current == t.$1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => onSelect(t.$1),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.$2,
                border: Border.all(
                  color: selected ? primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text('Aa',
                  style: TextStyle(
                      color: t.$3,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SmallBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.secondary,
          border: Border.all(color: cs.outline),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap != null
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.3)),
      ),
    );
  }
}
