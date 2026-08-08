import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Cores e tema do app de celular. Segue a linguagem visual do WhatsApp (barra
/// colorida, fundo bege no chat, bolha verde-clara nossa) usando o teal da marca
/// HotZap no lugar do verde. Lê [AppTheme.isDark] — a mesma chave do painel.
class MobileTheme {
  static const brand = AppTheme.seed; // teal #0E9384

  static bool get _dark => AppTheme.isDark;

  /// Barra superior: colorida no claro (como o WhatsApp), grafite no escuro.
  static Color get appBar => _dark ? const Color(0xFF1F2C34) : brand;
  static Color get onAppBar => Colors.white;

  /// Fundo da conversa: o bege clássico do WhatsApp.
  static Color get chatBg => _dark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);

  static Color get bubbleOut => _dark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3);
  static Color get bubbleIn => _dark ? const Color(0xFF1F2C34) : Colors.white;

  /// Nota interna: amarelo de recado — precisa ser IMPOSSÍVEL confundir com uma
  /// mensagem que foi ao cliente, senão alguém escreve algo sigiloso achando que
  /// é nota e manda para fora.
  static Color get noteBg => _dark ? const Color(0xFF3B3524) : const Color(0xFFFFF4CC);
  static Color get noteBorder => _dark ? const Color(0xFF6B5D2E) : const Color(0xFFE6CF6A);

  /// Chip central de evento ("assumiu a conversa") — o "aviso de sistema".
  static Color get systemChip => _dark ? const Color(0xFF182229) : const Color(0xFFE7F3EF);
  static Color get systemText => _dark ? const Color(0xFF8FA6AE) : const Color(0xFF5A7A72);

  static Color get surface => _dark ? const Color(0xFF1F2C34) : Colors.white;
  static Color get listBg => _dark ? const Color(0xFF111B21) : Colors.white;
  static Color get border => _dark ? const Color(0xFF2A3942) : const Color(0xFFE7EAEC);
  static Color get text => _dark ? const Color(0xFFE9EDF0) : const Color(0xFF111B21);
  static Color get textFaint => _dark ? const Color(0xFF8696A0) : const Color(0xFF667781);

  /// Barra do compositor.
  static Color get composerBg => _dark ? const Color(0xFF1F2C34) : Colors.white;
  static Color get composerField => _dark ? const Color(0xFF2A3942) : const Color(0xFFF0F2F5);

  /// Cor do avatar derivada do nome — dá variedade à lista sem guardar nada.
  static Color avatarColor(String seed) {
    const palette = [
      Color(0xFF0E9384), Color(0xFF6C6BCE), Color(0xFFC2557A), Color(0xFF3B82C4),
      Color(0xFFB4762B), Color(0xFF4A9E5C), Color(0xFF9B59B6), Color(0xFFCC5C3F),
    ];
    if (seed.isEmpty) return palette.first;
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  static ThemeData build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF111B21) : Colors.white,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF1F2C34) : brand,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF1F2C34) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? const Color(0xFF21C063) : brand,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(
        color: dark ? const Color(0xFF2A3942) : const Color(0xFFE7EAEC),
        space: 0,
        thickness: 0.5,
      ),
    );
  }
}

/// Tema dia/noite do app. Diferente do painel web, aqui a troca é instantânea
/// (o bug de "stale frame" do CanvasKit que obriga o web a recarregar não existe
/// no celular).
class MobileThemeController extends ChangeNotifier {
  static const _key = 'zap_theme_dark'; // mesma chave do painel

  bool _dark = false;
  bool get isDark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  MobileThemeController() {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _dark = p.getBool(_key) ?? false;
    AppTheme.isDark = _dark;
    notifyListeners();
  }

  Future<void> toggle() async {
    _dark = !_dark;
    AppTheme.isDark = _dark;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, _dark);
  }
}
