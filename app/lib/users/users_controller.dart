import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';

class UsersController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<AppUser> users = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/users');
    loading = false;
    if (r.ok && r.data is List) {
      users = (r.data as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar usuários';
    }
    notifyListeners();
  }

  /// Cria (POST) ou edita (PUT). Retorna null em sucesso, ou o erro.
  Future<String?> save({String? id, required String fullName, required String email, String? phone, required String role}) async {
    final body = {'full_name': fullName, 'email': email, 'role': role, 'phone': phone ?? ''};
    final r = id == null ? await _api.post('/users', body) : await _api.put('/users/$id', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível salvar o usuário';
  }

  Future<String?> remove(String id) async {
    final r = await _api.delete('/users/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível excluir';
  }
}
