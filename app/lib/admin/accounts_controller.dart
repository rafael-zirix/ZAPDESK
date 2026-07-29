import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/account.dart';

class AccountsController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<Account> accounts = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/admin/accounts');
    loading = false;
    if (r.ok && r.data is List) {
      accounts = (r.data as List).map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar empresas';
    }
    notifyListeners();
  }

  /// Cria empresa + primeiro admin. Retorna null em sucesso, ou o erro.
  /// Campos da ficha (endereço/documento/contato) — só os preenchidos, para
  /// não falhar validação (ex.: e-mail vazio) nem sobrescrever com vazio.
  static const _detailKeys = [
    'person_type', 'document', 'trade_name', 'email', 'phone',
    'zip_code', 'street', 'number', 'complement', 'district', 'city', 'state',
  ];
  Map<String, dynamic> _details(Map<String, String> v) {
    final m = <String, dynamic>{};
    for (final k in _detailKeys) {
      final x = (v[k] ?? '').trim();
      if (x.isNotEmpty) m[k] = x;
    }
    return m;
  }

  /// Cria empresa + primeiro admin (com a ficha). Retorna null em sucesso.
  Future<String?> create(Map<String, String> v) async {
    final body = {
      'name': v['name'],
      'admin_name': v['admin_name'],
      'admin_email': v['admin_email'],
      ..._details(v),
    };
    final r = await _api.post('/admin/accounts', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível criar a empresa';
  }

  /// Edita situação + ficha da empresa. Retorna null em sucesso, ou o erro.
  Future<String?> update(String id, Map<String, String> v) async {
    final body = {'name': v['name'], 'status': v['status'], ..._details(v)};
    final r = await _api.put('/admin/accounts/$id', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível salvar a empresa';
  }

  /// Exclui a empresa. Retorna null em sucesso, ou o erro.
  Future<String?> remove(String id) async {
    final r = await _api.delete('/admin/accounts/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível excluir a empresa';
  }
}
