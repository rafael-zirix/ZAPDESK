import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/account.dart';
import '../models/app_user.dart';

/// Usuários de UMA empresa, gerenciados pelo super-admin (via /admin/accounts/:id/users).
class AccountUsersController extends ChangeNotifier {
  AccountUsersController(this.accountId);
  final String accountId;
  final _api = ApiClient.instance;

  List<AppUser> users = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final r = await _api.get('/admin/accounts/$accountId/users');
    loading = false;
    if (r.ok && r.data is List) {
      users = (r.data as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      error = r.message ?? 'Erro ao carregar usuários';
    }
    notifyListeners();
  }

  Future<String?> save({String? id, required String fullName, required String email, required String role}) async {
    final body = {'full_name': fullName, 'email': email, 'role': role};
    final r = id == null
        ? await _api.post('/admin/accounts/$accountId/users', body)
        : await _api.put('/admin/accounts/$accountId/users/$id', body);
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível salvar o usuário';
  }

  Future<String?> remove(String id) async {
    final r = await _api.delete('/admin/accounts/$accountId/users/$id');
    if (r.ok) {
      await load();
      return null;
    }
    return r.message ?? 'Não foi possível excluir';
  }
}

/// Detalhe da empresa: ficha + usuários (perfis) gerenciados pelo super-admin.
class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AccountUsersController(account.id)..load(),
      child: _Body(account: account),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountUsersController>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _fichaCard(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Usuários', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openUserForm(context, c),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Novo usuário'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 42)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _usersBody(context, c),
        ],
      ),
    );
  }

  Widget _fichaCard() {
    Widget line(IconData ic, String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ic, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 10),
            SizedBox(width: 90, child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if ((account.tradeName ?? '').isNotEmpty)
            Text(account.tradeName!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          line(Icons.badge_outlined, account.personType == 'pf' ? 'CPF' : 'CNPJ', account.document),
          line(Icons.person_outline, 'Tipo', account.personType == null ? null : account.personTypeLabel),
          line(Icons.mail_outline, 'E-mail', account.email),
          line(Icons.phone_outlined, 'Telefone', account.phone),
          line(Icons.location_on_outlined, 'Endereço', account.hasAddress ? account.addressLine : null),
          if ((account.zipCode ?? '').isNotEmpty) line(Icons.markunread_mailbox_outlined, 'CEP', account.zipCode),
        ],
      ),
    );
  }

  Widget _usersBody(BuildContext context, AccountUsersController c) {
    if (c.loading && c.users.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (c.error != null) return _msg(c.error!);
    if (c.users.isEmpty) return _msg('Nenhum usuário nesta empresa ainda.');
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE7EAEC))),
      child: Column(
        children: [
          for (var i = 0; i < c.users.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            _userTile(context, c, c.users[i]),
          ],
        ],
      ),
    );
  }

  Widget _userTile(BuildContext context, AccountUsersController c, AppUser u) {
    final admin = u.role == 'admin';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
        child: Text(u.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
      ),
      title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(u.email, style: TextStyle(color: Colors.grey.shade600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: (admin ? AppTheme.seed : Colors.blueGrey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(admin ? 'Administrador' : 'Atendente',
                style: TextStyle(color: admin ? AppTheme.seed : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar perfil', onPressed: () => _openUserForm(context, c, edit: u)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDeleteUser(context, c, u)),
        ],
      ),
    );
  }

  Future<void> _openUserForm(BuildContext context, AccountUsersController c, {AppUser? edit}) async {
    await showEntityForm(
      context,
      title: edit == null ? 'Novo usuário' : 'Editar usuário',
      submitLabel: edit == null ? 'Adicionar' : 'Salvar',
      fields: [
        FieldSpec(key: 'full_name', label: 'Nome completo', initial: edit?.fullName ?? ''),
        FieldSpec(key: 'email', label: 'E-mail', initial: edit?.email ?? '', keyboard: TextInputType.emailAddress),
        FieldSpec(key: 'role', label: 'Perfil', initial: edit?.role ?? 'agent', options: const [('agent', 'Atendente'), ('admin', 'Administrador')]),
      ],
      onSubmit: (v) => c.save(id: edit?.id, fullName: v['full_name']!, email: v['email']!, role: v['role']!),
    );
  }

  Future<void> _confirmDeleteUser(BuildContext context, AccountUsersController c, AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir usuário'),
        content: Text('Remover "${u.fullName}" desta empresa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      final err = await c.remove(u.id);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  Widget _msg(String text) => Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );
}
