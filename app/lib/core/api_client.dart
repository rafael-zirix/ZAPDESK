import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Resultado padronizado de uma chamada à API (envelope success/message/data).
class ApiResult {
  ApiResult({required this.ok, this.data, this.message, this.errorCode, this.status});
  final bool ok;
  final dynamic data;
  final String? message;
  final String? errorCode;
  final int? status;
}

/// Cliente HTTP do Zapdesk: injeta o token, entende o envelope da API e
/// renova o access token automaticamente em caso de 401.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  bool get isLogged => _accessToken != null;

  static const _kAccess = 'zap_access';
  static const _kRefresh = 'zap_refresh';

  /// Carrega tokens salvos (chamado no boot).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _accessToken = p.getString(_kAccess);
    _refreshToken = p.getString(_kRefresh);
  }

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccess, access);
    await p.setString(_kRefresh, refresh);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
  }

  Uri _u(String path) => Uri.parse('${Config.apiBaseUrl}$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<ApiResult> get(String path) => _send('GET', path);
  Future<ApiResult> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  Future<ApiResult> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body);
  Future<ApiResult> delete(String path) => _send('DELETE', path);

  Future<ApiResult> _send(String method, String path, [Map<String, dynamic>? body, bool retry = true]) async {
    try {
      final res = await _raw(method, path, body);
      if (res.statusCode == 401 && retry && _refreshToken != null) {
        if (await _tryRefresh()) return _send(method, path, body, false);
      }
      return _parse(res);
    } catch (e) {
      return ApiResult(ok: false, message: 'Falha de conexão: $e');
    }
  }

  Future<http.Response> _raw(String method, String path, Map<String, dynamic>? body) {
    final u = _u(path);
    final b = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        return http.post(u, headers: _headers, body: b);
      case 'PUT':
        return http.put(u, headers: _headers, body: b);
      case 'DELETE':
        return http.delete(u, headers: _headers);
      default:
        return http.get(u, headers: _headers);
    }
  }

  ApiResult _parse(http.Response res) {
    Map<String, dynamic> j = {};
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final ok = j['success'] == true;
    return ApiResult(
      ok: ok,
      data: j['data'],
      message: j['message'] as String?,
      errorCode: ok ? null : (j['error']?['code'] as String?),
      status: res.statusCode,
    );
  }

  Future<bool> _tryRefresh() async {
    try {
      final res = await http.post(_u('/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': _refreshToken}));
      if (res.statusCode != 200) return false;
      final data = (jsonDecode(res.body)['data']) as Map<String, dynamic>?;
      if (data == null) return false;
      await setTokens(data['access_token'], data['refresh_token']);
      return true;
    } catch (_) {
      return false;
    }
  }
}
