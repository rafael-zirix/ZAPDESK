import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/whatsapp_number.dart';

/// Área do CLIENTE: a empresa conecta e desconecta os seus números de WhatsApp.
class WhatsAppController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<WhatsAppNumber> numbers = [];
  bool loading = false;
  String? error;

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
    for (final k in ['app_secret', 'verify_token', 'display_phone', 'verified_name']) {
      if ((v[k] ?? '').isNotEmpty) body[k] = v[k];
    }
    final r = await _api.post('/settings/whatsapp', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível conectar o número';
  }

  Future<String?> disconnect(String id) async {
    final r = await _api.delete('/settings/whatsapp/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível desconectar';
  }
}
