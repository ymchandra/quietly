enum ThemeName { cream, paper, sepia, slate, midnight }
enum FontFamily { lora, inter }
enum LineHeight { compact, comfortable, airy }

class ReaderSettings {
  final ThemeName theme;
  final FontFamily fontFamily;
  final double fontSize;
  final LineHeight lineHeight;

  const ReaderSettings({
    this.theme = ThemeName.cream,
    this.fontFamily = FontFamily.lora,
    this.fontSize = 18.0,
    this.lineHeight = LineHeight.comfortable,
  });

  double get lineHeightValue {
    switch (lineHeight) {
      case LineHeight.compact:
        return 1.4;
      case LineHeight.comfortable:
        return 1.65;
      case LineHeight.airy:
        return 1.9;
    }
  }

  String get themeName {
    final n = theme.name;
    return n[0].toUpperCase() + n.substring(1);
  }

  ReaderSettings copyWith({
    ThemeName? theme,
    FontFamily? fontFamily,
    double? fontSize,
    LineHeight? lineHeight,
  }) =>
      ReaderSettings(
        theme: theme ?? this.theme,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'fontFamily': fontFamily.name,
        'fontSize': fontSize,
        'lineHeight': lineHeight.name,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
        theme: ThemeName.values.firstWhere(
          (e) => e.name == json['theme'],
          orElse: () => ThemeName.cream,
        ),
        fontFamily: FontFamily.values.firstWhere(
          (e) => e.name == json['fontFamily'],
          orElse: () => FontFamily.lora,
        ),
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
        lineHeight: LineHeight.values.firstWhere(
          (e) => e.name == json['lineHeight'],
          orElse: () => LineHeight.comfortable,
        ),
      );
}

class StoredReaderSettings {
  final ReaderSettings global;
  final Map<int, Map<String, dynamic>> perBook;

  const StoredReaderSettings({
    required this.global,
    this.perBook = const {},
  });

  factory StoredReaderSettings.defaults() =>
      const StoredReaderSettings(global: ReaderSettings());

  ReaderSettings forBook(int bookId) {
    final overrides = perBook[bookId];
    if (overrides == null || overrides.isEmpty) return global;
    final merged = global.toJson()..addAll(overrides);
    return ReaderSettings.fromJson(merged);
  }

  StoredReaderSettings withGlobal(ReaderSettings settings) =>
      StoredReaderSettings(global: settings, perBook: perBook);

  StoredReaderSettings withBookOverride(
          int bookId, Map<String, dynamic> overrides) =>
      StoredReaderSettings(
        global: global,
        perBook: Map.from(perBook)..[bookId] = overrides,
      );

  Map<String, dynamic> toJson() => {
        'global': global.toJson(),
        'perBook': perBook.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory StoredReaderSettings.fromJson(Map<String, dynamic> json) {
    final globalJson = json['global'] as Map<String, dynamic>?;
    final perBookJson = json['perBook'] as Map<String, dynamic>? ?? {};
    return StoredReaderSettings(
      global: globalJson != null
          ? ReaderSettings.fromJson(globalJson)
          : const ReaderSettings(),
      perBook: perBookJson.map(
        (k, v) => MapEntry(
            int.parse(k), Map<String, dynamic>.from(v as Map<dynamic, dynamic>)),
      ),
    );
  }
}
