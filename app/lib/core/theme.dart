import 'package:flutter/material.dart';

/// Tema do Zapdesk — teal de atendimento, Material 3, com modo claro (dia) e
/// escuro (noite). As cores "semânticas" (bg, surface, bolhas…) são getters que
/// seguem [isDark], setado pelo ThemeController antes de construir a árvore.
class AppTheme {
  static const seed = Color(0xFF0E9384); // teal (marca — não muda no dark)

  /// Modo escuro ativo. O ThemeController mantém isto sincronizado com o
  /// themeMode do MaterialApp antes de cada build.
  static bool isDark = false;

  // ---- Cores semânticas (dia / noite) ----
  static Color get bg => isDark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5);
  // Vão ENTRE os cartões de conversa (modo multi): um tom mais escuro que os
  // cartões brancos, para eles se destacarem. No dark = mesmo [bg].
  static Color get gutter => isDark ? const Color(0xFF0B141A) : const Color(0xFFD5DCE2);
  static Color get surface => isDark ? const Color(0xFF1F2C34) : Colors.white;
  static Color get bubbleIn => isDark ? const Color(0xFF1F2C34) : Colors.white;
  static Color get bubbleOut => isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3);
  static Color get sidebarSel => isDark ? const Color(0xFF2A3942) : const Color(0xFFE7F5F3);
  static Color get border => isDark ? const Color(0xFF384A50) : const Color(0xFFE7EAEC);
  static Color get textOnSurface => isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111B21);

  // Criados uma única vez (ColorScheme.fromSeed é caro) — não recriar a cada
  // rebuild do MaterialApp na troca de tema.
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final surface = dark ? const Color(0xFF1F2C34) : Colors.white;
    final bg = dark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5);
    final line = dark ? const Color(0xFF2A3942) : const Color(0xFFE3E6E8);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      dividerTheme: DividerThemeData(color: dark ? const Color(0xFF384A50) : const Color(0xFFE7EAEC)),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: dark ? const Color(0xFFE9EDF0) : const Color(0xFF111B21),
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
