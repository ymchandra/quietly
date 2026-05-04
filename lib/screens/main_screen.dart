import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MainScreen extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MainScreen({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: PhosphorIcon(PhosphorIconsRegular.magnifyingGlass),
            selectedIcon: PhosphorIcon(PhosphorIconsFill.magnifyingGlass),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: PhosphorIcon(PhosphorIconsRegular.books),
            selectedIcon: PhosphorIcon(PhosphorIconsFill.books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: PhosphorIcon(PhosphorIconsRegular.bookmarks),
            selectedIcon: PhosphorIcon(PhosphorIconsFill.bookmarks),
            label: 'Lists',
          ),
          NavigationDestination(
            icon: PhosphorIcon(PhosphorIconsRegular.gear),
            selectedIcon: PhosphorIcon(PhosphorIconsFill.gear),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
