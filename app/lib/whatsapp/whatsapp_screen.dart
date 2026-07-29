import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/whatsapp_number.dart';
import 'whatsapp_controller.dart';

class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key});

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<WhatsAppController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<WhatsAppController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'WhatsApp', actionLabel: 'Conectar número', onAction: () => _openForm(c)),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(WhatsAppController c) {
    if (c.loading && c.numbers.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) return _errorState(c);
    if (c.numbers.isEmpty) return _emptyState(c);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [for (final n in c.numbers) _card(c, n)],
    );
  }

  Widget _card(WhatsAppController c, WhatsAppNumber n) {
    final connected = n.status == 'connected';
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
            child: const Icon(Icons.chat, color: AppTheme.seed),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('ID do número: ${n.phoneNumberId}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (connected ? AppTheme.seed : Colors.grey).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(connected ? 'conectado' : n.status,
                style: TextStyle(color: connected ? AppTheme.seed : Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Desconectar',
            onPressed: () => _confirmDisconnect(c, n),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(WhatsAppController c) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 56, color: Color(0xFF0E9384)),
            const SizedBox(height: 12),
            const Text('Conecte o WhatsApp da empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Para receber e responder pelo painel, informe os dados do seu número '
              'do WhatsApp Business (Meta). Você pega no painel da Meta, em WhatsApp › '
              'Configuração da API: o WABA ID, o ID do número (phone_number_id) e o token de acesso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openForm(c),
              icon: const Icon(Icons.add),
              label: const Text('Conectar número'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 46)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(WhatsAppController c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(c.error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: c.load, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }

  Future<void> _openForm(WhatsAppController c) async {
    await showEntityForm(
      context,
      title: 'Conectar número',
      submitLabel: 'Conectar',
      fields: [
        FieldSpec(key: 'verified_name', label: 'Nome da empresa (exibido)', required: false),
        FieldSpec(key: 'display_phone', label: 'Telefone (ex.: +55 21 99999-9999)', required: false, keyboard: TextInputType.phone),
        FieldSpec(key: 'waba_id', label: 'WABA ID'),
        FieldSpec(key: 'phone_number_id', label: 'ID do número (phone_number_id)'),
        FieldSpec(key: 'access_token', label: 'Token de acesso'),
      ],
      onSubmit: (v) => c.connect(v),
    );
  }

  Future<void> _confirmDisconnect(WhatsAppController c, WhatsAppNumber n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desconectar número'),
        content: Text('Desconectar "${n.title}"? A empresa deixa de enviar e receber por ele até reconectar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final err = await c.disconnect(n.id);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }
}
