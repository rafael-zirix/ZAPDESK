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
  Future<String?> create({required String name, required String adminName, required String adminEmail}) async {
    final r = await _api.post('/admin/accounts', {
      'name': name,
      'admin_name': adminName,
      'admin_email': adminEmail,
    });
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível criar a empresa';
  }

  /// Edita nome e situação da empresa. Retorna null em sucesso, ou o erro.
  Future<String?> update({required String id, required String name, required String status}) async {
    final r = await _api.put('/admin/accounts/$id', {'name': name, 'status': status});
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
