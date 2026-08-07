import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/message_template.dart';
import 'template_editor.dart';
import 'templates_controller.dart';

class TemplatesScreen extends StatefulWidget {
  /// [usage] filtra a lista: 'chat' (mensagens do atendimento) ou 'campaign'
  /// (disparo). Null mostra todos.
  const TemplatesScreen({super.key, this.usage});

  final String? usage;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<TemplatesController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TemplatesController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(
              title: switch (widget.usage) {
                'campaign' => 'Modelos de campanha',
                'chat' => 'Modelos de conversa',
                _ => 'Modelos de mensagem',
              },
              actionLabel: 'Novo modelo',
              onAction: () => _openForm(c)),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(TemplatesController c) {
    if (c.loading && c.templates.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) return _empty(Icons.error_outline, c.error!, retry: c.load);
    if (c.templates.isEmpty) {
      return _empty(Icons.article_outlined,
          'Nenhum modelo ainda.\nCrie modelos aprovados pela Meta para iniciar conversas fora da janela de 24h.');
    }
    final list = widget.usage == null
        ? c.templates
        : c.templates.where((t) => t.usage == widget.usage).toList();
    if (list.isEmpty) {
      return _empty(
          Icons.article_outlined,
          widget.usage == 'campaign'
              ? 'Nenhum modelo de campanha.\nCrie um aqui, ou mude o uso de um modelo existente para "Campanha".'
              : 'Nenhum modelo de conversa.\nCrie um aqui para usar como mensagem pronta no atendimento.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (_, i) => _tile(c, list[i]),
    );
  }

  Widget _tile(TemplatesController c, MessageTemplate t) {
    // Só os aprovados podem ser ligados/desligados na barra de mensagens prontas.
    final canToggle = t.isApproved;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      title: Row(
        children: [
          Flexible(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          const SizedBox(width: 10),
          _statusChip(t.status),
          const SizedBox(width: 6),
          // Categoria da META (define o preço por mensagem) — diferente do uso
          // interno abaixo, que só diz onde o modelo aparece aqui no sistema.
          _categoryChip(t.category),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t.bodyText ?? '(sem corpo)', style: TextStyle(color: Colors.grey.shade600, height: 1.3)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.language, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(width: 10),
          // Para que o modelo serve: campanha não aparece nas conversas.
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'chat', icon: Icon(Icons.forum_outlined, size: 16), tooltip: 'Usar nas conversas'),
              ButtonSegment(value: 'campaign', icon: Icon(Icons.campaign_outlined, size: 16), tooltip: 'Usar em campanhas'),
            ],
            selected: {t.usage},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (sel) => c.setUsage(t.name, sel.first),
          ),
          const SizedBox(width: 10),
          // Chave: aparecer ou não na conversa. Desabilitada p/ modelos não aprovados.
          Tooltip(
            message: canToggle
                ? (t.enabled ? 'Aparece nas mensagens prontas' : 'Oculto nas mensagens prontas')
                : 'Disponível quando a Meta aprovar',
            child: Switch(
              value: canToggle && t.enabled,
              onChanged: canToggle ? (v) => c.setEnabled(t.name, v) : null,
              activeThumbColor: AppTheme.seed,
            ),
          ),
        ],
      ),
    );
  }

  /// Categoria na Meta: é ela que define quanto custa cada mensagem entregue
  /// (marketing é a faixa mais cara) e ela pode mudar isso na revisão.
  Widget _categoryChip(String? category) {
    final c = (category ?? '').toUpperCase();
    if (c.isEmpty) return const SizedBox.shrink();
    final (Color color, String label, String help) = switch (c) {
      'MARKETING' => (
          const Color(0xFFB54708),
          'Marketing',
          'Categoria na Meta: marketing (abordagem, oferta). Faixa mais cara e sujeita ao limite por pessoa.'
        ),
      'UTILITY' => (
          const Color(0xFF175CD3),
          'Utilidade',
          'Categoria na Meta: utilidade (aviso sobre algo que o cliente já tem). Faixa mais barata.'
        ),
      'AUTHENTICATION' => (const Color(0xFF6941C6), 'Autenticação', 'Categoria na Meta: código de acesso.'),
      _ => (Colors.grey, category!, 'Categoria na Meta.'),
    };
    return Tooltip(
      message: help,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _statusChip(String? status) {
    final s = (status ?? '').toUpperCase();
    final (Color color, String label) = switch (s) {
      'APPROVED' => (const Color(0xFF1F9D57), 'Aprovado'),
      'REJECTED' => (Colors.red, 'Rejeitado'),
      'PENDING' => (const Color(0xFFB88109), 'Em análise'),
      _ => (Colors.grey, s.isEmpty ? '—' : s),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  /// Editor completo: cabeçalho (texto/foto), variáveis com exemplos, rodapé e
  /// botões — tudo enviado para a aprovação da Meta sem sair do sistema.
  Future<void> _openForm(TemplatesController c) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const TemplateEditor(),
    );
    if (created == true && mounted) {
      await c.load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Modelo enviado. A Meta revisa em minutos a algumas horas — acompanhe o status aqui.')));
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
