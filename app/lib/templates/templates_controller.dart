import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/message_template.dart';

class TemplatesController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<MessageTemplate> templates = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/support/templates');
    loading = false;
    if (r.ok && r.data is List) {
      templates = (r.data as List).map((e) => MessageTemplate.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar os modelos';
    }
    notifyListeners();
  }

  /// Cria um modelo (vai para aprovação da Meta). `title` vira o nome técnico
  /// (slug). Retorna null em sucesso, ou a mensagem de erro.
  Future<String?> create({
    required String title,
    required String body,
    required String category,
    String language = 'pt_BR',
  }) async {
    final name = _slug(title);
    if (name.isEmpty) return 'Dê um nome ao modelo';
    final r = await _api.post('/support/templates', {
      'name': name,
      'body': body,
      'category': category,
      'language': language,
    });
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível criar o modelo';
  }

  /// Liga/desliga um modelo na barra de mensagens prontas da conversa. Atualiza
  /// na hora (otimista) e persiste; reverte se o backend recusar.
  Future<void> setEnabled(String name, bool enabled) async {
    final i = templates.indexWhere((t) => t.name == name);
    if (i < 0) return;
    final prev = templates[i];
    templates[i] = MessageTemplate(
      name: prev.name,
      language: prev.language,
      bodyText: prev.bodyText,
      category: prev.category,
      status: prev.status,
      enabled: enabled,
    );
    notifyListeners();
    final r = await _api.put('/support/templates/$name/enabled', {'enabled': enabled});
    if (!r.ok) {
      templates[i] = prev; // reverte
      notifyListeners();
    }
  }

  /// Nome técnico da Meta: minúsculas, sem acento, só [a-z0-9_].
  static String _slug(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var out = s.toLowerCase().trim();
    final b = StringBuffer();
    for (final ch in out.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    out = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return out;
  }
}
