import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/contacts_import.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';
import '../models/contact.dart';
import 'contacts_controller.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<ContactsController>();
      c.load();
      c.loadGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ContactsController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(
            title: 'Contatos',
            actionLabel: 'Novo contato',
            onAction: () => _openForm(c),
            secondary: OutlinedButton.icon(
              onPressed: () => _import(c),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Importar'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ),
          _groupsBar(c),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  // Barra de grupos: filtro por grupo + gestão (criar/renomear/excluir).
  Widget _groupsBar(ContactsController c) {
    Widget chip(String label, String? value, {int? count}) {
      final sel = c.groupFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(count == null ? label : '$label ($count)',
              style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          selected: sel,
          onSelected: (_) => c.setGroupFilter(value),
          selectedColor: AppTheme.seed.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('Todos', null),
            for (final g in c.groups) chip(g.name, g.id, count: g.members),
            TextButton.icon(
              onPressed: () => _manageGroups(c),
              icon: const Icon(Icons.group_add_outlined, size: 17),
              label: Text(c.groups.isEmpty ? 'Criar grupos' : 'Grupos'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ContactsController c) {
    if (c.loading && c.contacts.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) {
      return _empty(Icons.error_outline, c.error!, retry: c.load);
    }
    if (c.contacts.isEmpty) {
      return _empty(Icons.people_outline, 'Nenhum contato ainda.\nCadastre o primeiro no botão acima.');
    }
    final list = c.filtered;
    if (list.isEmpty) {
      return _empty(Icons.filter_alt_outlined, 'Nenhum contato neste grupo.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) => _tile(c, list[i]),
    );
  }

  Widget _tile(ContactsController c, Contact ct) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
        child: Text(ct.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
      ),
      title: Text(ct.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        ct.groups.isEmpty ? ct.prettyPhone : '${ct.prettyPhone} · ${ct.groups.map((g) => g.name).join(', ')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              icon: Icon(Icons.label_outline, color: ct.groups.isEmpty ? null : AppTheme.seed),
              tooltip: 'Grupos do contato',
              onPressed: () => _contactGroupsDialog(c, ct)),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openForm(c, edit: ct)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(c, ct)),
        ],
      ),
    );
  }

  /// Marca/desmarca os grupos de UM contato (com criação rápida de grupo).
  Future<void> _contactGroupsDialog(ContactsController c, Contact ct) async {
    final selected = {for (final g in ct.groups) g.id};
    final newGroup = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text('Grupos — ${ct.displayName}'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Nenhum grupo ainda — crie o primeiro abaixo.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final g in c.groups)
                            FilterChip(
                              label: Text(g.name, style: const TextStyle(fontSize: 12)),
                              selected: selected.contains(g.id),
                              selectedColor: AppTheme.seed.withValues(alpha: 0.2),
                              onSelected: (v) => setLocal(() {
                                if (v) {
                                  selected.add(g.id);
                                } else {
                                  selected.remove(g.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: newGroup,
                  decoration: InputDecoration(
                    labelText: 'Novo grupo',
                    hintText: 'Ex.: Clientes VIP, Leads frios…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final name = newGroup.text.trim();
                        if (name.isEmpty) return;
                        final err = await c.saveGroup(name: name);
                        if (err == null) {
                          newGroup.clear();
                          setLocal(() {});
                        }
                      },
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await c.setContactGroups(ct, selected.toList());
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// Gestão dos grupos: criar, renomear e excluir.
  Future<void> _manageGroups(ContactsController c) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          Future<void> edit({ContactGroup? g}) async {
            final name = TextEditingController(text: g?.name ?? '');
            final ok = await showDialog<bool>(
              context: dialogCtx,
              builder: (c2) => AlertDialog(
                title: Text(g == null ? 'Novo grupo' : 'Renomear grupo'),
                content: TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome do grupo', border: OutlineInputBorder()),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancelar')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                    onPressed: () => Navigator.pop(c2, true),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            );
            if (ok == true && name.text.trim().isNotEmpty) {
              final err = await c.saveGroup(id: g?.id, name: name.text.trim());
              if (err != null && dialogCtx.mounted) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text(err)));
              }
              setLocal(() {});
            }
          }

          return AlertDialog(
            title: const Text('Grupos de contatos'),
            content: SizedBox(
              width: 380,
              child: c.groups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nenhum grupo ainda.\nGrupos organizam os contatos para o marketing —\na campanha pode mirar um ou vários grupos.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: c.groups.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final g = c.groups[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.group_outlined, size: 20),
                          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${g.members} contato${g.members == 1 ? '' : 's'}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => edit(g: g)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  await c.removeGroup(g.id);
                                  setLocal(() {});
                                }),
                          ]),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo grupo'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(ContactsController c, Contact ct) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir contato'),
        content: Text('Excluir "${ct.displayName}"? As conversas dele também serão removidas.'),
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
      final err = await c.remove(ct.id);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  Future<void> _openForm(ContactsController c, {Contact? edit}) async {
    await showEntityForm(
      context,
      title: edit == null ? 'Novo contato' : 'Editar contato',
      submitLabel: edit == null ? 'Cadastrar' : 'Salvar',
      fields: [
        FieldSpec(key: 'name', label: 'Nome', initial: edit?.name ?? ''),
        FieldSpec(
          key: 'phone',
          label: 'Telefone (com DDD)',
          initial: edit?.phone ?? '',
          keyboard: TextInputType.phone,
          hint: '55 21 99999-9999',
        ),
      ],
      onSubmit: (v) => c.save(id: edit?.id, name: v['name']!, phone: v['phone']!),
    );
  }

  /// Importa contatos de um arquivo padrão (.vcf/vCard ou .csv).
  Future<void> _import(ContactsController c) async {
    final f = await pickFile(accept: '.vcf,.csv,text/csv,text/vcard,text/x-vcard');
    if (f == null) return;
    final content = utf8.decode(f.bytes, allowMalformed: true);
    final parsed = parseContactsFile(f.name, content);
    if (!mounted) return;
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum contato encontrado. Use um arquivo .vcf (vCard) ou .csv com nome e telefone.')));
      return;
    }
    // Confirmação + escolha do GRUPO de destino (fecha o ciclo importar →
    // grupo → campanha). "novo" cria um grupo na hora.
    String? groupChoice; // null = sem grupo | id | 'novo'
    final newGroup = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: const Text('Importar contatos'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Foram encontrados ${parsed.length} contatos no arquivo.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: groupChoice,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Adicionar a um grupo (opcional)', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— sem grupo —')),
                    for (final g in c.groups)
                      DropdownMenuItem(value: g.id, child: Text('${g.name} (${g.members})', overflow: TextOverflow.ellipsis)),
                    const DropdownMenuItem(value: 'novo', child: Text('+ Criar grupo novo…')),
                  ],
                  onChanged: (v) => setLocal(() => groupChoice = v),
                ),
                if (groupChoice == 'novo') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: newGroup,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Nome do grupo novo',
                        hintText: 'Ex.: Feira de agosto',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              child: const Text('Importar'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    // Grupo "novo": cria primeiro (se o nome ficou vazio, importa sem grupo).
    String? groupId = groupChoice == 'novo' ? null : groupChoice;
    if (groupChoice == 'novo' && newGroup.text.trim().isNotEmpty) {
      final err = await c.saveGroup(name: newGroup.text.trim());
      if (err == null) {
        groupId = c.groups.firstWhere((g) => g.name.toLowerCase() == newGroup.text.trim().toLowerCase()).id;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err — importando sem grupo.')));
      }
    }
    final (ok, skipped) = await c.importContacts(parsed, groupId: groupId);
    if (!mounted) return;
    final gName = groupId == null ? '' : ' no grupo "${c.groups.firstWhere((g) => g.id == groupId).name}"';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$ok contato(s) importado(s)$gName'
            '${skipped > 0 ? ' · $skipped ignorado(s)/duplicado(s)' : ''}.')));
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
