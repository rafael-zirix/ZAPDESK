import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';

/// Conexão da conta do Instagram (Direct + Lead Ads). O Direct e os formulários
/// caem na MESMA caixa de entrada do WhatsApp, com os mesmos setores, etiquetas
/// e IA — o canal fica marcado na conversa.
class InstagramScreen extends StatefulWidget {
  const InstagramScreen({super.key});

  @override
  State<InstagramScreen> createState() => _InstagramScreenState();
}

class _InstagramScreenState extends State<InstagramScreen> {
  final _api = ApiClient.instance;
  List<Map<String, dynamic>> contas = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final r = await _api.get('/settings/instagram');
    if (!mounted) return;
    setState(() {
      loading = false;
      contas = r.ok && r.data is List ? (r.data as List).cast<Map<String, dynamic>>() : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Instagram', actionLabel: 'Conectar conta', onAction: _connect),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _aviso(),
                      if (contas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma conta conectada ainda.'),
                        ),
                      for (final c in contas) _tile(c),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // O que o cliente precisa saber ANTES de tentar: o canal depende de aprovação
  // da Meta e tem regras diferentes das do WhatsApp.
  Widget _aviso() => Container(
        margin: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF79009).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF79009).withValues(alpha: 0.4)),
        ),
        child: const Text(
          'Para o Instagram funcionar são necessários: conta profissional ligada a uma Página do Facebook, '
          'mensagens de terceiros liberadas nas configurações do Instagram, e as permissões do app aprovadas '
          'pela Meta. No Instagram NÃO existe modelo aprovado: só dá para responder dentro de 24h desde a '
          'última mensagem do cliente.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF93370D)),
        ),
      );

  Widget _tile(Map<String, dynamic> c) {
    final user = (c['username'] ?? '').toString();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFE1306C),
        child: Icon(Icons.camera_alt_outlined, color: Colors.white),
      ),
      title: Text(user.isEmpty ? c['ig_user_id'].toString() : '@$user',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Conta ${c['ig_user_id']} · Página ${c['page_id']} · ${c['status']}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.link_off, color: Colors.red),
        tooltip: 'Desconectar',
        onPressed: () => _disconnect(c),
      ),
    );
  }

  Future<void> _connect() async {
    final ig = TextEditingController();
    final page = TextEditingController();
    final user = TextEditingController();
    final token = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conectar Instagram'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ig, decoration: const InputDecoration(labelText: 'ID da conta profissional (IG User ID)')),
              const SizedBox(height: 8),
              TextField(controller: page, decoration: const InputDecoration(labelText: 'ID da Página do Facebook')),
              const SizedBox(height: 8),
              TextField(controller: user, decoration: const InputDecoration(labelText: '@ do perfil (opcional)')),
              const SizedBox(height: 8),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token da Página',
                  helperText: 'Guardado cifrado. Nunca é exibido de volta.',
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.post('/settings/instagram', {
      'ig_user_id': ig.text.trim(),
      'page_id': page.text.trim(),
      'username': user.text.trim(),
      'token': token.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Instagram conectado' : (r.message ?? 'Não foi possível conectar'))));
    if (r.ok) await _load();
  }

  Future<void> _disconnect(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desconectar Instagram'),
        content: const Text('As conversas já recebidas continuam no histórico, mas nada novo chega nem sai por este canal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/settings/instagram/${c['id']}');
    if (!mounted) return;
    if (r.ok) await _load();
  }
}
