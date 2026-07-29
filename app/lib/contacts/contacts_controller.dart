import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/contact.dart';

class ContactsController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<Contact> contacts = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/contacts');
    loading = false;
    if (r.ok && r.data is List) {
      contacts = (r.data as List).map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar contatos';
    }
    notifyListeners();
  }

  /// Cria (POST) ou edita (PUT). Retorna null em sucesso, ou a mensagem de erro.
  Future<String?> save({String? id, required String name, required String phone}) async {
    final body = {'name': name, 'phone': phone};
    final r = id == null ? await _api.post('/contacts', body) : await _api.put('/contacts/$id', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível salvar o contato';
  }

  /// Exclui o contato. Retorna null em sucesso, ou o erro.
  Future<String?> remove(String id) async {
    final r = await _api.delete('/contacts/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível excluir o contato';
  }
}
