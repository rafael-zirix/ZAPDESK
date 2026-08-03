import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';

enum AuthStatus { loading, loggedOut, awaitingCode, loggedIn }

/// Estado de autenticação (login OTP em duas etapas).
class AuthController extends ChangeNotifier {
  final _api = ApiClient.instance;

  AuthStatus status = AuthStatus.loading;
  AppUser? me;
  String? pendingIdentifier;
  String? error;
  bool busy = false;

  /// No boot: se há token salvo, tenta restaurar a sessão via /auth/me.
  Future<void> bootstrap() async {
    await _api.load();
    if (!_api.isLogged) {
      _set(AuthStatus.loggedOut);
      return;
    }
    final r = await _api.get('/auth/me');
    if (r.ok && r.data != null) {
      me = AppUser.fromJson(r.data as Map<String, dynamic>);
      _set(AuthStatus.loggedIn);
    } else {
      await _api.clear();
      _set(AuthStatus.loggedOut);
    }
  }

  /// Etapa 1: pede o código para o e-mail.
  Future<void> requestCode(String identifier) async {
    _busy(true);
    error = null;
    final r = await _api.post('/auth/login', {'identifier': identifier.trim()});
    _busy(false);
    if (r.ok) {
      pendingIdentifier = identifier.trim();
      _set(AuthStatus.awaitingCode);
    } else {
      error = r.message ?? 'Não foi possível enviar o código';
      notifyListeners();
    }
  }

  /// Auto-cadastro: cria a empresa + o admin e cai no fluxo de código (OTP no
  /// WhatsApp) — o mesmo verifyCode conclui o login e leva ao onboarding.
  Future<void> signup(String company, String name, String email, String phone) async {
    _busy(true);
    error = null;
    final r = await _api.post('/auth/signup', {
      'company_name': company.trim(),
      'admin_name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
    });
    _busy(false);
    if (r.ok) {
      // O código vai pelo e-mail (canal confiável) quando informado; o
      // verifyCode usa o mesmo identificador.
      pendingIdentifier = email.trim().isNotEmpty ? email.trim() : phone.trim();
      _set(AuthStatus.awaitingCode);
    } else {
      error = r.message ?? 'Não foi possível criar a conta';
      notifyListeners();
    }
  }

  /// Etapa 2: valida o código e entra.
  Future<void> verifyCode(String code) async {
    if (pendingIdentifier == null) return;
    _busy(true);
    error = null;
    final r = await _api.post('/auth/verify', {
      'identifier': pendingIdentifier,
      'code': code.trim(),
    });
    if (r.ok && r.data != null) {
      final data = r.data as Map<String, dynamic>;
      await _api.setTokens(data['access_token'], data['refresh_token']);
      me = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      _busy(false);
      _set(AuthStatus.loggedIn);
    } else {
      _busy(false);
      error = r.message ?? 'Código inválido';
      notifyListeners();
    }
  }

  void backToEmail() {
    pendingIdentifier = null;
    error = null;
    _set(AuthStatus.loggedOut);
  }

  Future<void> logout() async {
    await _api.clear();
    me = null;
    pendingIdentifier = null;
    _set(AuthStatus.loggedOut);
  }

  void _busy(bool v) {
    busy = v;
    notifyListeners();
  }

  void _set(AuthStatus s) {
    status = s;
    notifyListeners();
  }
}
