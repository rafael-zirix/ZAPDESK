import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'force_present.dart';
import 'theme.dart';

/// Guarda a preferência de tema (dia/noite) e a persiste.
class ThemeController extends ChangeNotifier {
  static const _key = 'zap_theme_dark';
  bool _dark = false;

  ThemeController() {
    _load();
  }

  bool get isDark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _dark = p.getBool(_key) ?? false;
    AppTheme.isDark = _dark;
    notifyListeners();
  }

  Future<void> toggle() async {
    _dark = !_dark;
    AppTheme.isDark = _dark;
    // Persiste ANTES de recarregar: no boot o app lê esta preferência e já pinta
    // no tema certo. A troca ao vivo trava no "stale frame" do CanvasKit/Skia
    // Graphite (fica congelada até um input); recarregar aplica na hora, de forma
    // 100% confiável (confirmado no ambiente do usuário).
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, _dark);
    reloadApp();
  }
}
