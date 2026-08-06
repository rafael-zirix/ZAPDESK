import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/contact.dart';
import '../models/support.dart';

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

  /// Importa vários contatos (nome/telefone), criando um a um. Duplicados e
  /// falhas são apenas ignorados. Com [groupId], vincula TODOS os telefones do
  /// arquivo ao grupo (criados e já existentes). Retorna (importados, ignorados).
  Future<(int, int)> importContacts(List<({String name, String phone})> items, {String? groupId}) async {
    var ok = 0, skipped = 0;
    final phones = <String>[];
    for (final it in items) {
      if (it.phone.trim().isEmpty) {
        skipped++;
        continue;
      }
      phones.add(it.phone);
      final r = await _api.post('/contacts', {'name': it.name, 'phone': it.phone});
      if (r.ok) {
        ok++;
      } else {
        skipped++;
      }
    }
    if (groupId != null && phones.isNotEmpty) {
      await _api.post('/contact-groups/$groupId/members', {'phones': phones});
      await loadGroups();
    }
    await load();
    return (ok, skipped);
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

  // --- Grupos de contatos (listas de marketing) ---

  List<ContactGroup> groups = [];
  String? groupFilter; // id do grupo (null = todos)
  List<TicketTag> tags = []; // etiquetas da empresa (mesmas das conversas)
  String? tagFilter; // id da etiqueta (null = todas)

  /// Contatos após os filtros de grupo e etiqueta.
  List<Contact> get filtered => contacts.where((c) {
        if (groupFilter != null && !c.groups.any((g) => g.id == groupFilter)) return false;
        if (tagFilter != null && !c.tags.any((t) => t.id == tagFilter)) return false;
        return true;
      }).toList();

  void setGroupFilter(String? id) {
    groupFilter = id;
    notifyListeners();
  }

  void setTagFilter(String? id) {
    tagFilter = id;
    notifyListeners();
  }

  Future<void> loadTags() async {
    final r = await _api.get('/support/tags');
    if (r.ok && r.data is List) {
      tags = (r.data as List).map((e) => TicketTag.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// Cria uma etiqueta (mesma lista usada nas conversas).
  Future<TicketTag?> createTag(String name) async {
    final r = await _api.post('/support/tags', {'name': name});
    if (r.ok && r.data is Map) {
      final t = TicketTag.fromJson((r.data as Map).cast<String, dynamic>());
      tags = [...tags, t];
      notifyListeners();
      return t;
    }
    return null;
  }

  /// Substitui as etiquetas de um contato.
  Future<String?> setContactTags(Contact ct, List<String> tagIds) async {
    final r = await _api.put('/contacts/${ct.id}/tags', {'tag_ids': tagIds});
    if (r.ok && r.data is Map) {
      ct.tags = Contact.fromJson(r.data as Map<String, dynamic>).tags;
      notifyListeners();
      return null;
    }
    return r.message ?? 'Não foi possível salvar as etiquetas';
  }

  Future<void> loadGroups() async {
    final r = await _api.get('/contact-groups');
    if (r.ok && r.data is List) {
      groups = (r.data as List).map((e) => ContactGroup.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// Cria/renomeia/exclui grupo. Null em sucesso, ou o erro.
  Future<String?> saveGroup({String? id, required String name}) async {
    final r = id == null
        ? await _api.post('/contact-groups', {'name': name})
        : await _api.put('/contact-groups/$id', {'name': name});
    if (r.ok) {
      await loadGroups();
      return null;
    }
    return r.message ?? 'Não foi possível salvar o grupo';
  }

  Future<String?> removeGroup(String id) async {
    final r = await _api.delete('/contact-groups/$id');
    if (r.ok) {
      if (groupFilter == id) groupFilter = null;
      await loadGroups();
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível excluir o grupo';
  }

  /// Substitui os grupos de um contato. Null em sucesso, ou o erro.
  Future<String?> setContactGroups(Contact ct, List<String> groupIds) async {
    final r = await _api.put('/contacts/${ct.id}/groups', {'group_ids': groupIds});
    if (r.ok && r.data is Map) {
      final updated = Contact.fromJson(r.data as Map<String, dynamic>);
      ct.groups = updated.groups;
      notifyListeners();
      loadGroups(); // atualiza as contagens
      return null;
    }
    return r.message ?? 'Não foi possível salvar';
  }
}
