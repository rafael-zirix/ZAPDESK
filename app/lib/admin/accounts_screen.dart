import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/account.dart';
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
      children: [for (final a in c.accounts) _card(a)],
    );
  }

  Widget _card(Account a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EAEC)),
      ),
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
                Text(
                  '${a.numbersCount} ${a.numbersCount == 1 ? 'número conectado' : 'números conectados'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          _statusChip(a.status),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final active = status == 'active';
    final color = active ? AppTheme.seed : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(active ? 'ativa' : status,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _openForm(AccountsController c) async {
    await showEntityForm(
      context,
      title: 'Nova empresa',
      submitLabel: 'Criar',
      fields: [
        FieldSpec(key: 'name', label: 'Nome da empresa'),
        FieldSpec(key: 'admin_name', label: 'Nome do administrador'),
        FieldSpec(key: 'admin_email', label: 'E-mail do administrador', keyboard: TextInputType.emailAddress),
      ],
      onSubmit: (v) => c.create(name: v['name']!, adminName: v['admin_name']!, adminEmail: v['admin_email']!),
    );
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
