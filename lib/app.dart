import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants/app_colors.dart';
import 'screens/discover_screen.dart';
import 'screens/library_screen.dart';
import 'screens/lists_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/main_screen.dart';
import 'screens/topic_books_screen.dart';
import 'screens/onboarding_screen.dart';
import 'models/book.dart';
import 'providers/user_profile_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

class QuietlyApp extends StatefulWidget {
  final UserProfileProvider userProfile;
  const QuietlyApp({super.key, required this.userProfile});

  @override
  State<QuietlyApp> createState() => _QuietlyAppState();
}

class _QuietlyAppState extends State<QuietlyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation:
          widget.userProfile.hasCompletedOnboarding ? '/' : '/onboarding',
      refreshListenable: widget.userProfile,
      redirect: (context, state) {
        final done = widget.userProfile.hasCompletedOnboarding;
        final onOnboarding = state.matchedLocation == '/onboarding';
        if (!done && !onOnboarding) return '/onboarding';
        if (done && onOnboarding) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => MainScreen(shell: shell),
          branches: [
            StatefulShellBranch(
              navigatorKey: _shellNavigatorKey,
              routes: [
                GoRoute(path: '/', builder: (_, __) => const DiscoverScreen()),
              ],
            ),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/library', builder: (_, __) => const LibraryScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/lists', builder: (_, __) => const ListsScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SettingsScreen()),
            ]),
          ],
        ),
        GoRoute(
          parentNavigatorKey: _rootNavigatorKey,
          path: '/book/:id',
          builder: (_, state) {
            final extra = state.extra;
            return BookDetailScreen(
              bookId: int.parse(state.pathParameters['id']!),
              initialBook: extra is Book ? extra : null,
            );
          },
        ),
        GoRoute(
          parentNavigatorKey: _rootNavigatorKey,
          path: '/reader/:id',
          builder: (_, state) {
            final extra = state.extra;
            return ReaderScreen(
              bookId: int.parse(state.pathParameters['id']!),
              initialBook: extra is Book ? extra : null,
            );
          },
        ),
        GoRoute(
          parentNavigatorKey: _rootNavigatorKey,
          path: '/discover/topic/:topic',
          builder: (_, state) => TopicBooksScreen(
            topic: state.pathParameters['topic']!,
            label: state.uri.queryParameters['label'] ?? 'Category',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quietly',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      routerConfig: _router,
    );
  }

  ThemeData _buildLightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.light(
        surface: AppColors.lightBg,
        onSurface: AppColors.lightFg,
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightSecondary,
        onSecondary: AppColors.lightFg,
        error: AppColors.lightDestructive,
        outline: AppColors.lightBorder,
      ),
      scaffoldBackgroundColor: AppColors.lightBg,
      cardColor: AppColors.lightCard,
      cardTheme: const CardThemeData(color: AppColors.lightCard),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.lightFg,
        displayColor: AppColors.lightFg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.lightFg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightCard,
        selectedItemColor: AppColors.lightPrimary,
        unselectedItemColor: AppColors.lightMutedFg,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerColor: AppColors.lightBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.dark(
        surface: AppColors.darkBg,
        onSurface: AppColors.darkFg,
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkSecondary,
        onSecondary: AppColors.darkFg,
        error: AppColors.lightDestructive,
        outline: AppColors.darkBorder,
      ),
      scaffoldBackgroundColor: AppColors.darkBg,
      cardColor: AppColors.darkCard,
      cardTheme: const CardThemeData(color: AppColors.darkCard),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.darkFg,
        displayColor: AppColors.darkFg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.darkFg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkCard,
        selectedItemColor: AppColors.darkPrimary,
        unselectedItemColor: AppColors.darkMutedFg,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerColor: AppColors.darkBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

