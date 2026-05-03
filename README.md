# Quietly

**Quietread** — a calm, eye-friendly mobile reading app for free public-domain books. Built with Flutter.

Books are sourced from the [Project Gutenberg](https://gutenberg.org/) catalog via the [Gutendex API](https://gutendex.com/). Offline reading and all user state (wishlist, read-later, library, progress, and reader settings) are stored locally on the device — no account or server required.

## Features

- **Discover** — Browse curated topic shelves (Classics, Romance, Mystery, Philosophy, Poetry, Adventure) or search by title/author
- **Library** — Track in-progress reads, downloaded books, and finished titles with progress bars
- **Lists** — Wishlist and Read Later collections
- **Settings** — Global reader configuration: theme, font family, font size, line height
- **Book Detail** — Cover art, subjects/bookshelves, offline download, wishlist and read-later toggles
- **Reader** — Full-screen horizontal page-swipe reader with tap-to-show controls, progress tracking, and per-book appearance settings
- **Reader Settings** — Per-book overrides: 5 themes (Cream, Paper, Sepia, Slate, Midnight), Lora/Inter fonts, font size 14–26, compact/comfortable/airy line height

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Flutter SDK | 3.27 |
| Dart | 3.4.0 |
| Android Studio | Latest (for Android) |
| Xcode | 15 (for iOS, macOS only) |

Install Flutter: https://flutter.dev/docs/get-started/install

## Getting started

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Run on a specific platform
flutter run -d android
flutter run -d ios
flutter run -d chrome   # web
```

## Building

```bash
# Android APK (release)
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS IPA (no code signing — for CI/testing)
flutter build ipa --no-codesign

# Web
flutter build web --release
```

## Architecture

```
lib/
├── main.dart                    # Bootstrap: initialises providers, runs app
├── app.dart                     # MaterialApp.router, go_router config, light/dark themes
├── constants/
│   └── app_colors.dart          # Colour tokens for UI + 5 reader theme palettes
├── models/
│   ├── book.dart                # Book, Person, GutendexResponse (JSON serialisation)
│   └── reader_settings.dart     # ReaderSettings, StoredReaderSettings, enums
├── services/
│   ├── gutendex_service.dart    # Gutendex API client; multi-source text fetch + HTML stripping
│   └── storage_service.dart     # SharedPreferences CRUD; offline book file I/O via path_provider
├── providers/
│   ├── library_provider.dart    # Wishlist / Read Later / Downloaded / Progress (ChangeNotifier)
│   └── reader_settings_provider.dart  # Global + per-book appearance settings (ChangeNotifier)
├── screens/
│   ├── main_screen.dart         # Bottom navigation shell (StatefulShellRoute)
│   ├── discover_screen.dart     # Topic shelves + debounced search
│   ├── library_screen.dart      # Reading / Downloaded / Finished segments
│   ├── lists_screen.dart        # Wishlist / Read Later segments
│   ├── settings_screen.dart     # Global reader settings UI
│   ├── book_detail_screen.dart  # Book metadata, download, read action
│   └── reader_screen.dart       # Full-screen page-swipe reader
└── widgets/
    ├── book_card.dart            # Vertical cover card (120 × 180)
    ├── book_list_row.dart        # Horizontal row with optional progress bar
    ├── search_bar_widget.dart    # Rounded search input with 350 ms debounce
    ├── empty_state_widget.dart   # Centred icon + message placeholder
    ├── skeleton_widget.dart      # Pulsing loading placeholder
    ├── segmented_control_widget.dart  # Pill-style segment selector
    ├── reader_controls.dart      # Animated top/bottom overlay in reader
    └── reader_settings_sheet.dart  # Appearance bottom sheet content
```

## Key packages

| Package | Purpose |
|---|---|
| [`go_router`](https://pub.dev/packages/go_router) | Declarative navigation with `StatefulShellRoute` for tabs |
| [`provider`](https://pub.dev/packages/provider) | State management (`ChangeNotifier`) |
| [`http`](https://pub.dev/packages/http) | Gutendex API requests |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) | Persistent key-value storage |
| [`path_provider`](https://pub.dev/packages/path_provider) | Device documents directory for offline book files |
| [`cached_network_image`](https://pub.dev/packages/cached_network_image) | Book cover caching |
| [`google_fonts`](https://pub.dev/packages/google_fonts) | Lora + Inter fonts |

## CI / GitHub Actions

| Trigger | Job | Artifact |
|---|---|---|
| Push or PR → `main` | `analyze` — `flutter analyze` + `flutter test` | — |
| Push or PR → `main` | `build-android` — `flutter build apk --release` | `release-apk` |
| `workflow_dispatch` → ios | `build-ios` — `flutter build ipa --no-codesign` | `ios-ipa` |

## License

App code: MIT.  
Book content sourced from [Project Gutenberg](https://gutenberg.org) (public domain).
