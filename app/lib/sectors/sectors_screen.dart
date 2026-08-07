import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/app_user.dart';
import '../models/support.dart';

/// Setores (filas de atendimento) da empresa: CRUD + membros de cada setor.
/// Estado local (sem Provider): a tela é simples e autocontida.
class SectorsScreen extends StatefulWidget {
  const SectorsScreen({super.key});

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends State<SectorsScreen> {
  final _api = ApiClient.instance;

  List<Sector> sectors = [];
  List<AppUser> team = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final rs = await _api.get('/support/sectors');
    final ru = await _api.get('/users');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (rs.ok && rs.data is List) {
        sectors = (rs.data as List).map((e) => Sector.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        error = rs.message ?? 'Erro ao carregar setores';
      }
      if (ru.ok && ru.data is List) {
        team = (ru.data as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Setores', actionLabel: 'Novo setor', onAction: () => _openForm()),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (loading && sectors.isEmpty) return const Center(child: CircularProgressIndicator());
    if (error != null) return _empty(Icons.error_outline, error!, retry: _load);
    if (sectors.isEmpty) {
      return _empty(Icons.workspaces_outline,
          'Nenhum setor ainda.\nCrie filas como Comercial, Suporte e Financeiro\npara organizar e transferir as conversas.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sectors.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) => _tile(sectors[i]),
    );
  }

  String _memberNames(Sector s) {
    final names = [
      for (final id in s.members)
        for (final u in team)
          if (u.id == id) u.fullName,
    ];
    if (names.isEmpty) return 'Sem atendentes vinculados';
    return names.join(', ');
  }

  Widget _tile(Sector s) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
        child: const Icon(Icons.workspaces_outline, color: AppTheme.seed),
      ),
      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(_memberNames(s), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey.shade600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppTheme.seed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text('${s.members.length} atendente${s.members.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppTheme.seed, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          // 📣 setor que recebe os leads de anúncio (Click-to-WhatsApp).
          IconButton(
            icon: Icon(s.adDefault ? Icons.campaign : Icons.campaign_outlined,
                color: s.adDefault ? const Color(0xFFF79009) : null),
            tooltip: s.adDefault
                ? 'Recebe os leads de anúncio — clique para desmarcar'
                : 'Marcar como o setor que recebe os leads de anúncio',
            onPressed: () => _toggleAd(s),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openForm(edit: s)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(s)),
        ],
      ),
    );
  }

  /// Marca/desmarca o setor que recebe os leads de anúncio. É exclusivo: marcar
  /// um desmarca o anterior (o backend garante isso).
  Future<void> _toggleAd(Sector s) async {
    final r = await _api.put('/support/sectors/${s.id}/ad', {'ad_default': !s.adDefault});
    if (!mounted) return;
    if (r.ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.adDefault
              ? 'Leads de anúncio voltam a cair na triagem normal'
              : '“${s.name}” passa a receber os leads de anúncio')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.message ?? 'Não foi possível salvar')));
    }
  }

  Future<void> _openForm({Sector? edit}) async {
    final name = TextEditingController(text: edit?.name ?? '');
    final selected = {...(edit?.members ?? const <String>[])};
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text(edit == null ? 'Novo setor' : 'Editar setor'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome do setor',
                    hintText: 'Ex.: Comercial, Suporte, Financeiro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Atendentes deste setor', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (team.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Nenhum usuário na equipe ainda.', style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final u in team)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(u.fullName, overflow: TextOverflow.ellipsis),
                              value: selected.contains(u.id),
                              onChanged: (v) => setLocal(() {
                                if (v == true) {
                                  selected.add(u.id);
                                } else {
                                  selected.remove(u.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(edit == null ? 'Criar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final n = name.text.trim();
    if (n.isEmpty) return;
    final body = {'name': n, 'members': selected.toList()};
    final r = edit == null
        ? await _api.post('/support/sectors', body)
        : await _api.put('/support/sectors/${edit.id}', body);
    if (r.ok) {
      await _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível salvar o setor')));
    }
  }

  Future<void> _confirmDelete(Sector s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir setor'),
        content: Text('Remover "${s.name}"? As conversas dele ficam sem setor (nada é apagado).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final r = await _api.delete('/support/sectors/${s.id}');
      if (r.ok) {
        await _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível excluir')));
      }
    }
  }

  Widget _empty(IconData icon, String text, {Future<void> Function()? retry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
          ),
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Tentar de novo')),
          ],
        ],
      ),
    );
  }
}
