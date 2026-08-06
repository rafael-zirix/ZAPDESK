import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/support.dart';

/// Cadastro de ETIQUETAS (admin): criar, renomear, escolher cor e excluir.
/// A mesma etiqueta serve para marcar contatos (filtro de campanha) e conversas.
class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  final _api = ApiClient.instance;

  List<TicketTag> tags = [];
  Map<String, (int contatos, int conversas)> uso = {};
  bool loading = false;
  String? error;

  /// Paleta pronta — evita o cliente ter que digitar hexadecimal.
  static const palette = <String>[
    '#0E9384', '#2563EB', '#7C3AED', '#D92D20',
    '#CA8A04', '#12B76A', '#DB2777', '#475467',
  ];

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
    final r = await _api.get('/support/tags');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (r.ok && r.data is List) {
        final list = (r.data as List).cast<Map<String, dynamic>>();
        tags = list.map(TicketTag.fromJson).toList();
        uso = {
          for (final j in list)
            (j['id'] as String): (
              (j['contacts'] as num?)?.toInt() ?? 0,
              (j['tickets'] as num?)?.toInt() ?? 0,
            ),
        };
      } else {
        error = r.message ?? 'Erro ao carregar etiquetas';
      }
    });
  }

  static Color colorOf(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v != null ? Color(v) : AppTheme.seed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Etiquetas', actionLabel: 'Nova etiqueta', onAction: () => _openForm()),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (loading && tags.isEmpty) return const Center(child: CircularProgressIndicator());
    if (error != null) return _empty(Icons.error_outline, error!, retry: _load);
    if (tags.isEmpty) {
      return _empty(Icons.local_offer_outlined,
          'Nenhuma etiqueta ainda.\nEtiquetas marcam contatos e conversas —\ne viram filtro de campanha (ex.: VIP, inadimplente, lead).');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tags.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) => _tile(tags[i]),
    );
  }

  Widget _tile(TicketTag t) {
    final color = colorOf(t.color);
    final (contatos, conversas) = uso[t.id] ?? (0, 0);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.local_offer, color: color, size: 20),
      ),
      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        contatos == 0 && conversas == 0
            ? 'Ainda não usada'
            : '$contatos contato${contatos == 1 ? '' : 's'} · $conversas conversa${conversas == 1 ? '' : 's'}',
        style: TextStyle(color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openForm(edit: t)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(t)),
        ],
      ),
    );
  }

  Future<void> _openForm({TicketTag? edit}) async {
    final nome = TextEditingController(text: edit?.name ?? '');
    var cor = edit?.color ?? palette.first;
    final salvou = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text(edit == null ? 'Nova etiqueta' : 'Editar etiqueta'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nome,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex.: VIP, inadimplente, lead quente',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Cor', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final hex in palette)
                      InkWell(
                        onTap: () => setLocal(() => cor = hex),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorOf(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cor == hex ? Colors.black87 : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: cor == hex ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Prévia igual ao chip que aparece no contato/conversa.
                Row(children: [
                  Text('Fica assim: ', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorOf(cor).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorOf(cor).withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Text(nome.text.trim().isEmpty ? 'etiqueta' : nome.text.trim(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colorOf(cor))),
                  ),
                ]),
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
    if (salvou != true || nome.text.trim().isEmpty) return;
    final body = {'name': nome.text.trim(), 'color': cor};
    final r = edit == null
        ? await _api.post('/support/tags', body)
        : await _api.put('/support/tags/${edit.id}', body);
    if (!mounted) return;
    if (r.ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível salvar')));
    }
  }

  Future<void> _confirmDelete(TicketTag t) async {
    final (contatos, conversas) = uso[t.id] ?? (0, 0);
    final aviso = contatos == 0 && conversas == 0
        ? 'Ela ainda não está em uso.'
        : 'Ela será removida de $contatos contato(s) e $conversas conversa(s) — os registros em si permanecem.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir etiqueta'),
        content: Text('Excluir "${t.name}"? $aviso'),
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
    if (ok != true) return;
    final r = await _api.delete('/support/tags/${t.id}');
    if (!mounted) return;
    if (r.ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível excluir')));
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
