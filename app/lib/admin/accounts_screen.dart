import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/account.dart';
import 'account_detail_screen.dart';
import 'accounts_controller.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AccountsController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountsController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Empresas', actionLabel: 'Nova empresa', onAction: () => _openForm(c)),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(AccountsController c) {
    if (c.loading && c.accounts.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) return _empty(Icons.error_outline, c.error!, retry: c.load);
    if (c.accounts.isEmpty) {
      return _empty(Icons.apartment_outlined, 'Nenhuma empresa cadastrada.\nCrie a primeira no botão acima.');
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [for (final a in c.accounts) _card(c, a)],
    );
  }

  Widget _card(AccountsController c, Account a) {
    final subtitle = a.document != null
        ? '${a.personType == 'pf' ? 'CPF' : 'CNPJ'} ${a.document}'
        : '${a.numbersCount} ${a.numbersCount == 1 ? 'número conectado' : 'números conectados'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EAEC)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AccountDetailScreen(account: a)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.apartment, color: AppTheme.seed),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              _statusChip(a.status),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openEdit(c, a)),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(c, a)),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final active = status == 'active';
    final color = active ? AppTheme.seed : (status == 'suspended' ? Colors.orange.shade700 : Colors.grey);
    final label = switch (status) {
      'active' => 'ativa',
      'suspended' => 'suspensa',
      'canceled' => 'cancelada',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // Campos da ficha (comuns a criar/editar). `a` nulo = criar.
  List<FieldSpec> _fichaFields(Account? a) => [
        FieldSpec(key: 'person_type', label: 'Tipo', section: 'Dados da empresa', required: false,
            initial: a?.personType ?? 'pj', options: const [('pj', 'Pessoa jurídica'), ('pf', 'Pessoa física')]),
        FieldSpec(key: 'name', label: 'Razão social / Nome', initial: a?.name ?? ''),
        FieldSpec(key: 'trade_name', label: 'Nome fantasia', required: false, initial: a?.tradeName ?? ''),
        FieldSpec(key: 'document', label: 'CPF / CNPJ', required: false, initial: a?.document ?? '', keyboard: TextInputType.number),
        FieldSpec(key: 'email', label: 'E-mail', section: 'Contato', required: false, initial: a?.email ?? '', keyboard: TextInputType.emailAddress),
        FieldSpec(key: 'phone', label: 'Telefone', required: false, initial: a?.phone ?? '', keyboard: TextInputType.phone),
        FieldSpec(key: 'zip_code', label: 'CEP', section: 'Endereço', required: false, initial: a?.zipCode ?? '', keyboard: TextInputType.number),
        FieldSpec(key: 'street', label: 'Logradouro', required: false, initial: a?.street ?? ''),
        FieldSpec(key: 'number', label: 'Número', required: false, initial: a?.number ?? ''),
        FieldSpec(key: 'complement', label: 'Complemento', required: false, initial: a?.complement ?? ''),
        FieldSpec(key: 'district', label: 'Bairro', required: false, initial: a?.district ?? ''),
        FieldSpec(key: 'city', label: 'Cidade', required: false, initial: a?.city ?? ''),
        FieldSpec(key: 'state', label: 'UF', required: false, initial: a?.state ?? ''),
      ];

  Future<void> _openForm(AccountsController c) async {
    await showEntityForm(
      context,
      title: 'Nova empresa',
      submitLabel: 'Criar',
      fields: [
        ..._fichaFields(null),
        FieldSpec(key: 'admin_name', label: 'Nome do administrador', section: 'Administrador (primeiro acesso)'),
        FieldSpec(key: 'admin_email', label: 'E-mail do administrador', keyboard: TextInputType.emailAddress),
      ],
      onSubmit: (v) => c.create(v),
    );
  }

  Future<void> _openEdit(AccountsController c, Account a) async {
    await showEntityForm(
      context,
      title: 'Editar empresa',
      submitLabel: 'Salvar',
      fields: [
        FieldSpec(key: 'status', label: 'Situação', section: 'Situação', initial: a.status,
            options: const [('active', 'Ativa'), ('suspended', 'Suspensa'), ('canceled', 'Cancelada')]),
        ..._fichaFields(a),
      ],
      onSubmit: (v) => c.update(a.id, v),
    );
  }

  Future<void> _confirmDelete(AccountsController c, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir empresa'),
        content: Text(
          'Excluir "${a.name}"? Os usuários dela perdem o acesso. '
          'As conversas e contatos são preservados, mas a empresa some do painel.',
        ),
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
      final err = await c.remove(a.id);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
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
