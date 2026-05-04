import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/reader_settings.dart';
import '../providers/reader_settings_provider.dart';
import '../widgets/segmented_control_widget.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<ReaderSettingsProvider>();
    final settings = provider.settings.global;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Settings',
              style: GoogleFonts.lora(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'Reader Appearance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('Theme'),
                  const SizedBox(height: 10),
                  _ThemeCircles(
                      current: settings.theme,
                      onSelect: (t) {
                        provider
                            .updateGlobal(settings.copyWith(theme: t));
                      }),
                  const SizedBox(height: 16),
                  const _Label('Font'),
                  const SizedBox(height: 10),
                  SegmentedControlWidget(
                    segments: const ['Lora', 'Inter'],
                    selectedIndex:
                        settings.fontFamily == FontFamily.lora ? 0 : 1,
                    onChanged: (i) => provider.updateGlobal(settings.copyWith(
                        fontFamily:
                            i == 0 ? FontFamily.lora : FontFamily.inter)),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Font Size'),
                  const SizedBox(height: 10),
                  _FontSizeRow(
                    size: settings.fontSize,
                    onMinus: settings.fontSize > 14
                        ? () => provider.updateGlobal(
                            settings.copyWith(fontSize: settings.fontSize - 2))
                        : null,
                    onPlus: settings.fontSize < 26
                        ? () => provider.updateGlobal(
                            settings.copyWith(fontSize: settings.fontSize + 2))
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const _Label('Line Height'),
                  const SizedBox(height: 10),
                  SegmentedControlWidget(
                    segments: const ['Compact', 'Comfortable', 'Airy'],
                    selectedIndex: settings.lineHeight.index,
                    onChanged: (i) => provider.updateGlobal(
                        settings.copyWith(lineHeight: LineHeight.values[i])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'About',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quietly',
                      style: GoogleFonts.lora(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'A calm, eye-friendly reading app for free public-domain books from Project Gutenberg. Enjoy classics without distractions.',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontWeight: FontWeight.w500,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.7)));
}

class _ThemeCircles extends StatelessWidget {
  final ThemeName current;
  final void Function(ThemeName) onSelect;
  const _ThemeCircles({required this.current, required this.onSelect});

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
      children: _themes.map((t) {
        final selected = current == t.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 10),
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

class _FontSizeRow extends StatelessWidget {
  final double size;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _FontSizeRow(
      {required this.size, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleBtn(icon: PhosphorIconsRegular.minus, onTap: onMinus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('${size.toInt()}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        _CircleBtn(icon: PhosphorIconsRegular.plus, onTap: onPlus),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final PhosphorIconData icon;
  final VoidCallback? onTap;
  const _CircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.secondary,
          border: Border.all(color: cs.outline),
        ),
        child: Center(
          child: PhosphorIcon(
            icon,
            size: 18,
            color: onTap != null
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
