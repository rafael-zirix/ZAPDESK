import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/usage.dart';
import 'usage_controller.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<UsageController>().load());
  }

  static const _periods = [
    ('month', 'Este mês'),
    ('lastMonth', 'Mês passado'),
    ('7d', 'Últimos 7 dias'),
    ('30d', 'Últimos 30 dias'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<UsageController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          _header(c),
          const Divider(height: 1),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _header(UsageController c) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Consumo por empresa', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              if (c.fromLabel.isNotEmpty)
                Text('${c.fromLabel} → ${c.toLabel}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              IconButton(onPressed: c.loading ? null : () => c.load(), tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (key, label) in _periods)
                ChoiceChip(
                  label: Text(label),
                  selected: c.period == key,
                  onSelected: c.loading ? null : (_) => c.load(key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(UsageController c) {
    if (c.loading && c.companies.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.error != null) {
      return _center(Icons.error_outline, c.error!, retry: () => c.load());
    }
    if (c.companies.isEmpty) {
      return _center(Icons.query_stats, 'Nenhuma empresa com dados no período.');
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PricingCard(c),
        for (final co in c.companies) _companyCard(co, c.pricing),
      ],
    );
  }

  Widget _companyCard(CompanyUsage co, Pricing pricing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(co.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Text('${co.messagesTotal} msgs', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _stat('Enviadas', co.messagesOut, Icons.north_east, const Color(0xFF2F80ED)),
              _stat('Recebidas', co.messagesIn, Icons.south_west, const Color(0xFF12B76A)),
              _stat('Conversas', co.conversations, Icons.forum_outlined, AppTheme.seed),
              _stat('Modelos', co.templates, Icons.article_outlined, const Color(0xFF7B4DFF)),
              _stat('Mídia', co.media, Icons.attach_file, const Color(0xFFF79009)),
              _stat('Tokens IA', co.aiTokens, Icons.smart_toy_outlined, const Color(0xFFB54708)),
            ],
          ),
          const SizedBox(height: 14),
          _billingBreakdown(co, pricing),
          if (co.numbers.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            for (final n in co.numbers) _numberRow(n),
          ],
        ],
      ),
    );
  }

  // Stat compacto INLINE (ícone + número + rótulo numa linha). mainAxisSize.min p/ o
  // Wrap fluir vários por linha em vez de 1 por linha.
  Widget _stat(String label, int value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      ],
    );
  }

  // Detalhamento a cobrar por tipo de uso (fatura do mês): quantidade × preço = valor.
  Widget _billingBreakdown(CompanyUsage co, Pricing p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Detalhamento a cobrar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        _billLine('Conversas (WhatsApp)', '${co.conversations} × R\$ ${_price(p.conversation)}/conversa', co.valueWhatsApp),
        const SizedBox(height: 8),
        _billLine('Tokens de IA', '${_int(co.aiTokens)} × R\$ ${_price(p.per1kTokens)}/1k', co.valueAI),
        const Padding(padding: EdgeInsets.symmetric(vertical: 9), child: Divider(height: 1)),
        Row(children: [
          const Expanded(child: Text('Total a cobrar', style: TextStyle(fontWeight: FontWeight.w800))),
          Text(_reais(co.valueTotal), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.seed)),
        ]),
      ]),
    );
  }

  Widget _billLine(String label, String detail, double value) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          Text(detail, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
      ),
      Text(_reais(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }

  // R$ no formato pt-BR (vírgula decimal).
  String _reais(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  String _price(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');
  // Inteiro com separador de milhar (25133 -> 25.133).
  String _int(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _numberRow(NumberUsage n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.chat_outlined, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(child: Text(n.displayPhone.isEmpty ? n.wabaId : n.displayPhone, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (n.costAvailable)
            Text('${n.metaConversations} conversas · custo Meta ${n.metaCost.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))
          else
            Text('custo Meta indisponível', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _center(IconData icon, String text, {VoidCallback? retry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.grey.shade400),
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

/// Card de preços da plataforma (super-admin): R$ por conversa e por 1k tokens.
class _PricingCard extends StatefulWidget {
  const _PricingCard(this.c);
  final UsageController c;

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  late final TextEditingController _conv = TextEditingController(text: _init(widget.c.pricing.conversation));
  late final TextEditingController _tok = TextEditingController(text: _init(widget.c.pricing.per1kTokens));
  late final TextEditingController _pkgs = TextEditingController(
      text: widget.c.pricing.packages.map(_num).join(', '));

  String _init(double v) => v == 0 ? '' : _num(v);
  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _conv.dispose();
    _tok.dispose();
    _pkgs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final conv = double.tryParse(_conv.text.trim().replaceAll(',', '.')) ?? 0;
    final tok = double.tryParse(_tok.text.trim().replaceAll(',', '.')) ?? 0;
    final pkgs = _pkgs.text
        .split(',')
        .map((s) => double.tryParse(s.trim().replaceAll(',', '.')) ?? 0)
        .where((v) => v > 0)
        .toList();
    final err = await widget.c.savePricing(conv, tok, pkgs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Preços e planos salvos')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.sell_outlined, size: 20, color: AppTheme.seed),
            const SizedBox(width: 8),
            const Text('Preços da plataforma', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Text('O que você cobra de cada empresa pelo uso. Ao salvar, os valores abaixo recalculam.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: TextField(
                  controller: _conv,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'por conversa WhatsApp', prefixText: 'R\$ '),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _tok,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'por 1.000 tokens de IA', prefixText: 'R\$ '),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _pkgs,
                  decoration: const InputDecoration(
                    labelText: 'planos de recarga (R\$, vírgula)',
                    hintText: '25, 50, 100, 200',
                  ),
                ),
              ),
              FilledButton(
                onPressed: widget.c.savingPricing ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 52)),
                child: widget.c.savingPricing
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar preços'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
