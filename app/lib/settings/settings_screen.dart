import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';

/// Configurações da própria empresa (admin). Por ora: canais de OTP de login —
/// por onde a equipe recebe o código de acesso (WhatsApp e/ou e-mail).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  bool _saving = false;
  bool _whats = true;
  bool _email = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/settings/otp');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is Map) {
        final m = r.data as Map;
        _whats = (m['whatsapp_enabled'] ?? true) as bool;
        _email = (m['email_enabled'] ?? true) as bool;
      } else {
        _error = r.message ?? 'Erro ao carregar as configurações';
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _api.put('/settings/otp', {'whatsapp_enabled': _whats, 'email_enabled': _email});
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.ok ? 'Configurações salvas' : (r.message ?? 'Não foi possível salvar'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          const ListHeader(title: 'Tipo de login'),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: _otpCard())],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _otpCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: AppTheme.seed),
                SizedBox(width: 10),
                Expanded(child: Text('Login por código (OTP)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 4, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Escolha por onde a sua equipe recebe o código de acesso.',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
          ),
          SwitchListTile(
            value: _whats,
            onChanged: _saving ? null : (v) => setState(() => _whats = v),
            secondary: const Icon(Icons.chat_outlined),
            title: const Text('Código por WhatsApp'),
            subtitle: const Text('Chega no WhatsApp do celular cadastrado no usuário.'),
          ),
          SwitchListTile(
            value: _email,
            onChanged: _saving ? null : (v) => setState(() => _email = v),
            secondary: const Icon(Icons.mail_outline),
            title: const Text('Código por e-mail'),
            subtitle: const Text('Chega no e-mail do usuário.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
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
