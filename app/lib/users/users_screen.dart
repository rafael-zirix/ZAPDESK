import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/app_user.dart';
import 'users_controller.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<UsersController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<UsersController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Usuários', actionLabel: 'Novo usuário', onAction: () => _openForm(c)),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(UsersController c) {
    if (c.loading && c.users.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) return _empty(Icons.error_outline, c.error!, retry: c.load);
    if (c.users.isEmpty) {
      return _empty(Icons.badge_outlined, 'Nenhum usuário ainda.\nAdicione atendentes no botão acima.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: c.users.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) => _tile(c, c.users[i]),
    );
  }

  Widget _tile(UsersController c, AppUser u) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
        child: Text(u.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
      ),
      title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(u.email, style: TextStyle(color: Colors.grey.shade600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleChip(u.role),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _openForm(c, edit: u)),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: () => _confirmDelete(c, u)),
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
    final admin = role == 'admin';
    final color = admin ? AppTheme.seed : Colors.blueGrey;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(admin ? 'Administrador' : 'Atendente',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _openForm(UsersController c, {AppUser? edit}) async {
    await showEntityForm(
      context,
      title: edit == null ? 'Novo usuário' : 'Editar usuário',
      submitLabel: edit == null ? 'Adicionar' : 'Salvar',
      fields: [
        FieldSpec(key: 'full_name', label: 'Nome completo', initial: edit?.fullName ?? ''),
        FieldSpec(key: 'email', label: 'E-mail', initial: edit?.email ?? '', keyboard: TextInputType.emailAddress),
        FieldSpec(
          key: 'phone',
          label: 'Celular (WhatsApp) — para login por código',
          initial: edit?.phone ?? '',
          required: false,
          keyboard: TextInputType.phone,
        ),
        FieldSpec(
          key: 'role',
          label: 'Perfil',
          initial: edit?.role ?? 'agent',
          options: const [('agent', 'Atendente'), ('admin', 'Administrador')],
        ),
      ],
      onSubmit: (v) => c.save(id: edit?.id, fullName: v['full_name']!, email: v['email']!, phone: v['phone'], role: v['role']!),
    );
  }

  Future<void> _confirmDelete(UsersController c, AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir usuário'),
        content: Text('Remover "${u.fullName}"? Essa ação não pode ser desfeita.'),
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
      final err = await c.remove(u.id);
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
