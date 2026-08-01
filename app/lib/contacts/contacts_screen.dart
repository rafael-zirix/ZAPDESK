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
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ContactsController>().load());
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
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: c.contacts.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) => _tile(c, c.contacts[i]),
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
      subtitle: Text(ct.prettyPhone, style: TextStyle(color: Colors.grey.shade600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openForm(c, edit: ct)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(c, ct)),
        ],
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
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar contatos'),
        content: Text('Foram encontrados ${parsed.length} contatos no arquivo. Deseja importar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final (ok, skipped) = await c.importContacts(parsed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$ok contato(s) importado(s)'
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
