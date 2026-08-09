import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart' show ListHeader;
import '../core/theme.dart';

/// Configurações → Perfis: o admin cria perfis de acesso e marca, numa árvore
/// que espelha o menu, o que cada perfil pode VER e GRAVAR. Plano/cobrança e
/// este editor não aparecem na árvore — são sempre do admin.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _Profile {
  _Profile({required this.id, required this.name, required this.perms, required this.users});
  final String id;
  String name;
  Map<String, Map<String, bool>> perms; // key -> {view, write}
  List<String> users;

  factory _Profile.fromJson(Map<String, dynamic> j) => _Profile(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        perms: {
          for (final e in ((j['perms'] ?? {}) as Map).entries)
            e.key as String: {
              'view': (e.value['view'] ?? false) as bool,
              'write': (e.value['write'] ?? false) as bool,
            },
        },
        users: [for (final u in (j['user_ids'] as List? ?? [])) u as String],
      );
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_Profile> _profiles = [];
  List<dynamic> _catalog = []; // [{label, items:[{key,label,has_write}]}]

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cat = await _api.get('/settings/profiles/catalog');
    final list = await _api.get('/settings/profiles');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!cat.ok || !list.ok) {
        _error = cat.message ?? list.message ?? 'Erro ao carregar os perfis';
        return;
      }
      _catalog = cat.data as List? ?? [];
      _profiles = [for (final p in list.data as List? ?? []) _Profile.fromJson(p)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListHeader(
            title: 'Perfis de acesso',
            actionLabel: 'Novo perfil',
            onAction: () => _editor(),
          ),
          const SizedBox(height: 6),
          Text(
            'Cada perfil define o que o usuário VÊ e GRAVA no sistema. Usuário sem perfil segue o '
            'comportamento do papel (Atendente/Vendedor). Plano e cobrança são sempre do administrador.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Center(
              child: Column(children: [
                Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                    onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Tentar de novo')),
              ]),
            )
          else ...[
            // Perfis de SISTEMA: fixos, sempre presentes — são a base.
            _systemRow('Administrador', 'Tudo, inclusive plano, cobrança e este editor. A âncora da empresa.',
                Icons.verified_user_outlined, AppTheme.seed),
            _systemRow('Atendente', 'Atendimento, contatos e CRM (os leads dele + fila).',
                Icons.support_agent_outlined, Colors.blueGrey),
            _systemRow('Vendedor (CRM)', 'Funil do CRM e atendimento dos próprios leads.',
                Icons.storefront_outlined, const Color(0xFFF79009)),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('SEUS PERFIS PERSONALIZADOS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade500)),
            ),
            if (_profiles.isEmpty) _empty() else for (final p in _profiles) _profileRow(p),
          ],
        ],
      ),
    );
  }

  /// Linha de perfil de SISTEMA: fixo, sem editar/excluir — só informa.
  Widget _systemRow(String name, String desc, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Row(children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(99)),
            child: Text('SISTEMA',
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6)),
          ),
        ]),
        subtitle: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Tooltip(
          message: 'Perfil de sistema — fixo (garante que a empresa nunca fica sem administrador)',
          child: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: [
        Icon(Icons.admin_panel_settings_outlined, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 10),
        const Text('Nenhum perfil ainda', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SizedBox(
          width: 420,
          child: Text(
            'Crie perfis como "Gerente de vendas" ou "Supervisor" e delegue fatias das suas funções, '
            'no clique. Depois atribua o perfil na tela de Usuários.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      ]),
    );
  }

  Widget _profileRow(_Profile p) {
    final granted = p.perms.entries.where((e) => e.value['view'] == true).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: const Icon(Icons.badge_outlined, color: AppTheme.seed),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          '$granted função${granted == 1 ? '' : 's'} liberada${granted == 1 ? '' : 's'} · '
          '${p.users.length} usuário${p.users.length == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar permissões',
              onPressed: () => _editor(edit: p)),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir (quem usa volta ao papel)',
              onPressed: () => _confirmDelete(p)),
        ]),
        onTap: () => _editor(edit: p),
      ),
    );
  }

  Future<void> _confirmDelete(_Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${p.name}"?'),
        content: Text(p.users.isEmpty
            ? 'O perfil será removido.'
            : '${p.users.length} usuário(s) usam este perfil e voltarão ao comportamento do papel.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/settings/profiles/${p.id}');
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Erro ao excluir')));
      return;
    }
    _load();
  }

  /// Editor do perfil: nome + a ÁRVORE de funções com Ver/Gravar.
  Future<void> _editor({_Profile? edit}) async {
    final name = TextEditingController(text: edit?.name ?? '');
    // Cópia mutável das permissões.
    final perms = <String, Map<String, bool>>{
      for (final e in (edit?.perms ?? {}).entries)
        e.key: {'view': e.value['view'] ?? false, 'write': e.value['write'] ?? false},
    };
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Map<String, bool> permOf(String key) =>
              perms.putIfAbsent(key, () => {'view': false, 'write': false});
          void setView(String key, bool v) {
            final p = permOf(key);
            p['view'] = v;
            if (!v) p['write'] = false; // sem ver não há gravar
          }

          void setWrite(String key, bool v) {
            final p = permOf(key);
            p['write'] = v;
            if (v) p['view'] = true; // gravar implica ver
          }

          return AlertDialog(
            title: Text(edit == null ? 'Novo perfil' : 'Editar perfil'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome do perfil (ex.: Gerente de vendas)'),
                  ),
                  const SizedBox(height: 12),
                  // Cabeçalho das colunas de checkbox.
                  Row(children: [
                    const SizedBox(width: 330),
                    SizedBox(
                        width: 70,
                        child: Text('Ver',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade600))),
                    SizedBox(
                        width: 70,
                        child: Text('Gravar',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade600))),
                  ]),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 380,
                    child: ListView(children: [
                      for (final g in _catalog) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 0, 4),
                          child: Text((g['label'] as String).toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: Colors.grey.shade500)),
                        ),
                        for (final it in (g['items'] as List)) _permRow(it, permOf, setView, setWrite, setState),
                      ],
                    ]),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty) {
                          setState(() => error = 'Dê um nome ao perfil.');
                          return;
                        }
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        final body = {
                          'name': name.text.trim(),
                          'perms': {
                            for (final e in perms.entries)
                              if (e.value['view'] == true)
                                e.key: {'view': e.value['view'], 'write': e.value['write']},
                          },
                        };
                        final r = edit == null
                            ? await _api.post('/settings/profiles', body)
                            : await _api.put('/settings/profiles/${edit.id}', body);
                        if (!ctx.mounted) return;
                        if (!r.ok) {
                          setState(() {
                            busy = false;
                            error = r.message ?? 'Erro ao salvar o perfil';
                          });
                          return;
                        }
                        Navigator.of(ctx).pop();
                        _load();
                      },
                child: Text(busy ? 'Salvando…' : 'Salvar perfil'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _permRow(dynamic it, Map<String, bool> Function(String) permOf,
      void Function(String, bool) setView, void Function(String, bool) setWrite, StateSetter setState) {
    final key = it['key'] as String;
    final hasWrite = (it['has_write'] ?? false) as bool;
    final p = permOf(key);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(children: [
        SizedBox(
          width: 324,
          child: Text(it['label'] as String,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
        ),
        SizedBox(
          width: 70,
          child: Checkbox(
            value: p['view'],
            onChanged: (v) => setState(() => setView(key, v ?? false)),
          ),
        ),
        SizedBox(
          width: 70,
          child: hasWrite
              ? Checkbox(
                  value: p['write'],
                  onChanged: (v) => setState(() => setWrite(key, v ?? false)),
                )
              : Tooltip(
                  message: 'Função somente de leitura',
                  child: Icon(Icons.remove, size: 16, color: Colors.grey.shade400),
                ),
        ),
      ]),
    );
  }
}
