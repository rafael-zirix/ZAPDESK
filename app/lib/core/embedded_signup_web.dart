import 'dart:js_interop';

import 'embedded_result.dart';

@JS('zapEmbeddedSignup')
external JSPromise<JSAny?> _zapEmbeddedSignup(String appId, String configId, String graphVersion);

/// Abre o popup da Meta (Embedded Signup) e devolve o code + IDs do número.
/// Retorna null se o usuário cancelar ou o SDK não carregar.
Future<EmbeddedResult?> runEmbeddedSignup({
  required String appId,
  required String configId,
  required String graphVersion,
}) async {
  try {
    final res = await _zapEmbeddedSignup(appId, configId, graphVersion).toDart;
    final dart = res.dartify();
    if (dart is! Map) return null;
    final m = dart.cast<Object?, Object?>();
    final code = (m['code'] ?? '').toString();
    if (code.isEmpty) return null;
    return EmbeddedResult(
      code: code,
      wabaId: (m['waba_id'] ?? '').toString(),
      phoneNumberId: (m['phone_number_id'] ?? '').toString(),
    );
  } catch (_) {
    return null;
  }
}

@JS('zapFacebookLogin')
external JSPromise<JSAny?> _zapFacebookLogin(String appId, String configId, String graphVersion);

/// Abre o popup da Meta para o Instagram e devolve o `code` + o `redirect_uri`
/// que o diálogo usou — a descoberta da Página e da conta é do servidor.
/// Null se o usuário cancelar ou o SDK falhar.
Future<(String, String)?> runFacebookLogin({
  required String appId,
  required String configId,
  required String graphVersion,
}) async {
  try {
    final res = await _zapFacebookLogin(appId, configId, graphVersion).toDart;
    final dart = res.dartify();
    if (dart is! Map) return null;
    final m = dart.cast<Object?, Object?>();
    final code = (m['code'] ?? '').toString();
    if (code.isEmpty) return null;
    return (code, (m['redirect_uri'] ?? '').toString());
  } catch (_) {
    return null;
  }
}
