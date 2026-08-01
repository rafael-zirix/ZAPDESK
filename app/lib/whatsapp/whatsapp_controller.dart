import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/embedded_signup.dart';
import '../models/whatsapp_number.dart';

/// Área do CLIENTE: a empresa conecta e desconecta os seus números de WhatsApp.
class WhatsAppController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<WhatsAppNumber> numbers = [];
  bool loading = false;
  String? error;

  // Embedded Signup (onboarding via popup da Meta). Desligado até a plataforma
  // configurar o App ID/config_id (aí a opção "Conectar com a Meta" aparece).
  bool embeddedEnabled = false;
  String _esAppId = '', _esConfigId = '', _esGraph = 'v20.0';

  /// Carrega a config do Embedded Signup (para saber se mostra a opção da Meta).
  Future<void> loadEmbeddedConfig() async {
    final r = await _api.get('/settings/embedded/config');
    if (r.ok && r.data is Map) {
      final m = r.data as Map;
      embeddedEnabled = (m['enabled'] ?? false) as bool;
      _esAppId = (m['app_id'] ?? '').toString();
      _esConfigId = (m['config_id'] ?? '').toString();
      _esGraph = (m['graph_version'] ?? 'v20.0').toString();
      notifyListeners();
    }
  }

  /// Abre o popup da Meta e conecta o número retornado. Retorna null em sucesso,
  /// 'cancelado' se o usuário fechou, ou a mensagem de erro.
  Future<String?> connectEmbedded() async {
    final res = await runEmbeddedSignup(appId: _esAppId, configId: _esConfigId, graphVersion: _esGraph);
    if (res == null) return 'cancelado';
    final r = await _api.post('/settings/embedded/connect', {
      'code': res.code,
      'waba_id': res.wabaId,
      'phone_number_id': res.phoneNumberId,
    });
    if (r.ok) {
      _guardaResultado(r.data);
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível conectar pela Meta';
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/settings/whatsapp');
    loading = false;
    if (r.ok && r.data is List) {
      numbers = (r.data as List).map((e) => WhatsAppNumber.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar os números';
    }
    notifyListeners();
  }

  /// Conecta um número. Retorna null em sucesso, ou a mensagem de erro.
  Future<String?> connect(Map<String, String> v) async {
    final body = <String, dynamic>{
      'waba_id': v['waba_id'],
      'phone_number_id': v['phone_number_id'],
      'access_token': v['access_token'],
    };
    for (final k in ['app_secret', 'verify_token', 'display_phone', 'verified_name', 'pin']) {
      if ((v[k] ?? '').isNotEmpty) body[k] = v[k];
    }
    final r = await _api.post('/settings/whatsapp', body);
    if (r.ok) {
      _guardaResultado(r.data);
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível conectar o número';
  }

  /// PIN devolvido pelo último registro na Cloud API — quando o backend sorteia
  /// um, é a única vez que ele aparece, então a tela precisa mostrá-lo.
  String? ultimoPin;

  /// Se o webhook daquele número ficou apontado para cá. Sem ele o número ENVIA
  /// mas NÃO RECEBE, e o cliente precisa saber disso na hora — não quando o
  /// primeiro cliente final escrever e ninguém vir a mensagem.
  bool ultimoWebhookOk = false;
  String? ultimoWebhookMotivo;
  String? ultimoCallbackUrl;
  String? ultimoVerifyToken;

  void _guardaResultado(dynamic data) {
    if (data is! Map) return;
    ultimoPin = data['pin'] as String?;
    ultimoWebhookOk = data['webhook_ok'] == true;
    ultimoWebhookMotivo = data['webhook_motivo'] as String?;
    ultimoCallbackUrl = data['callback_url'] as String?;
    ultimoVerifyToken = data['verify_token'] as String?;
  }

  /// Registra na Cloud API um número já conectado.
  ///
  /// Número conectado antes de o registro existir no zapdesk mostra tudo certo
  /// na tela e recusa cada envio com "(#133010) Account not registered". Este é
  /// o conserto, sem desconectar e reconectar.
  Future<String?> registrar(String id, {String? pin}) async {
    final r = await _api.post('/settings/whatsapp/$id/register',
        {if ((pin ?? '').isNotEmpty) 'pin': pin});
    if (r.ok) {
      _guardaResultado(r.data);
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível registrar o número na Meta';
  }

  /// Grava o App Secret do app próprio do cliente num número já conectado (para o
  /// webhook validar a assinatura das mensagens recebidas). Retorna null em
  /// sucesso, ou a mensagem de erro.
  Future<String?> definirAppSecret(String id, String appSecret) async {
    if (appSecret.isEmpty) return 'Informe o App Secret';
    final r = await _api.put('/settings/whatsapp/$id/app-secret', {'app_secret': appSecret});
    if (r.ok) return null;
    return r.message ?? 'Não foi possível salvar o App Secret';
  }

  Future<String?> disconnect(String id) async {
    final r = await _api.delete('/settings/whatsapp/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível desconectar';
  }

  /// Envia a foto (avatar) do número. Retorna null em sucesso, ou o erro.
  Future<String?> uploadPhoto(String id, {required List<int> bytes, required String filename, String? contentType}) async {
    final r = await _api.uploadFile('/settings/whatsapp/$id/photo',
        bytes: bytes, filename: filename, contentType: contentType);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível salvar a foto';
  }
}
