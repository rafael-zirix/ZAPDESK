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

  Future<String?> save({String? id, required String fullName, required String email, String? phone, required String role}) async {
    final body = {'full_name': fullName, 'email': email, 'role': role, 'phone': phone ?? ''};
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
          const SizedBox(height: 16),
          _OtpAccessCard(account: account),
          const SizedBox(height: 16),
          _AIRechargeCard(account: account),
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
        color: AppTheme.surface,
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
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
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
        FieldSpec(key: 'phone', label: 'Celular (WhatsApp) — login por código', initial: edit?.phone ?? '', required: false, keyboard: TextInputType.phone),
        FieldSpec(key: 'role', label: 'Perfil', initial: edit?.role ?? 'agent', options: const [('agent', 'Atendente'), ('admin', 'Administrador')]),
      ],
      onSubmit: (v) => c.save(id: edit?.id, fullName: v['full_name']!, email: v['email']!, phone: v['phone'], role: v['role']!),
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

/// Card do super-admin para ligar/desligar os canais de OTP de login da empresa.
/// Salva direto na empresa (PUT /admin/accounts/:id).
class _OtpAccessCard extends StatefulWidget {
  const _OtpAccessCard({required this.account});
  final Account account;

  @override
  State<_OtpAccessCard> createState() => _OtpAccessCardState();
}

class _OtpAccessCardState extends State<_OtpAccessCard> {
  final _api = ApiClient.instance;
  late bool _whats = widget.account.otpWhatsAppEnabled;
  late bool _email = widget.account.otpEmailEnabled;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _api.put('/admin/accounts/${widget.account.id}', {
      'otp_whatsapp_enabled': _whats,
      'otp_email_enabled': _email,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.ok ? 'Canais de acesso salvos' : (r.message ?? 'Não foi possível salvar'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EAEC)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Acesso por código (OTP)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          SwitchListTile(
            value: _whats,
            onChanged: _saving ? null : (v) => setState(() => _whats = v),
            secondary: const Icon(Icons.chat_outlined),
            title: const Text('Código por WhatsApp'),
          ),
          SwitchListTile(
            value: _email,
            onChanged: _saving ? null : (v) => setState(() => _email = v),
            secondary: const Icon(Icons.mail_outline),
            title: const Text('Código por e-mail'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card do super-admin: saldo de tokens de IA da empresa + recarga.
class _AIRechargeCard extends StatefulWidget {
  const _AIRechargeCard({required this.account});
  final Account account;

  @override
  State<_AIRechargeCard> createState() => _AIRechargeCardState();
}

class _AIRechargeCardState extends State<_AIRechargeCard> {
  final _api = ApiClient.instance;
  bool _loading = true;
  int _balance = 0;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/admin/accounts/${widget.account.id}/ai');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is Map) {
        final m = r.data as Map;
        _balance = ((m['token_balance'] ?? 0) as num).toInt();
        _enabled = (m['enabled'] ?? false) as bool;
      }
    });
  }

  Future<void> _recharge() async {
    final ctrl = TextEditingController(text: '1000000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recarregar tokens de IA'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantos tokens creditar', suffixText: 'tokens'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Recarregar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final tokens = int.tryParse(ctrl.text.trim()) ?? 0;
    if (tokens <= 0) return;
    final r = await _api.post('/admin/accounts/${widget.account.id}/ai/recharge', {'tokens': tokens});
    if (!mounted) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tokens creditados')));
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível recarregar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Layout em Column (sem Expanded-em-Row, que colapsava no CanvasKit): título,
    // saldo (largura total, quebra natural) e o botão embaixo — igual ao card OTP.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.smart_toy_outlined, color: AppTheme.seed),
            SizedBox(width: 10),
            Text('Atendente IA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            Text('carregando…', style: TextStyle(color: Colors.grey.shade600))
          else
            Text(
              '$_balance tokens (~${(_balance / 2000).round()} respostas) · IA ${_enabled ? "ligada" : "desligada"}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _loading ? null : _recharge,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Recarregar'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            ),
          ),
        ],
      ),
    );
  }
}
