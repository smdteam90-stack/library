import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

/// App-wide preferences: theme, language, text scale. Kept as its own
/// service (separate from StorageService, which owns links/folders) so
/// each concern can change independently later.
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.languageCode,
    required this.textScale,
  });

  final AppThemeMode themeMode;
  final String languageCode;
  final double textScale;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    languageCode: 'en',
    textScale: 1.0,
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    double? textScale,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        languageCode: languageCode ?? this.languageCode,
        textScale: textScale ?? this.textScale,
      );
}

class SettingsService {
  static const _themeKey = 'content_library.settings.theme_mode';
  static const _langKey = 'content_library.settings.language';
  static const _scaleKey = 'content_library.settings.text_scale';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_themeKey);
    final mode = AppThemeMode.values.firstWhere(
      (m) => m.name == themeName,
      orElse: () => AppThemeMode.system,
    );
    return AppSettings(
      themeMode: mode,
      languageCode: prefs.getString(_langKey) ?? 'en',
      textScale: prefs.getDouble(_scaleKey) ?? 1.0,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, settings.themeMode.name);
    await prefs.setString(_langKey, settings.languageCode);
    await prefs.setDouble(_scaleKey, settings.textScale);
  }
}
