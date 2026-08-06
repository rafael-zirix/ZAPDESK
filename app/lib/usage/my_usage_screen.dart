import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/usage.dart';

/// Consumo da PRÓPRIA empresa (admin da empresa): uso + valores cobrados pela
/// plataforma no período. Read-only.
class MyUsageScreen extends StatefulWidget {
  const MyUsageScreen({super.key});

  @override
  State<MyUsageScreen> createState() => _MyUsageScreenState();
}

class _MyUsageScreenState extends State<MyUsageScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  CompanyUsage? _u;
  Pricing _pricing = Pricing(conversation: 0, per1kTokens: 0);
  String _fromLabel = '';
  String _toLabel = '';
  String _period = '30d';

  static const _periods = [
    ('month', 'Este mês'),
    ('lastMonth', 'Mês passado'),
    ('7d', 'Últimos 7 dias'),
    ('30d', 'Últimos 30 dias'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? p]) async {
    if (p != null) _period = p;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _range(_period);
    final r = await _api.get('/support/usage?from=$from&to=$to');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is Map) {
        final d = r.data as Map<String, dynamic>;
        _fromLabel = d['from'] ?? from;
        _toLabel = d['to'] ?? to;
        _pricing = Pricing.fromJson(d['pricing'] as Map<String, dynamic>?);
        _u = d['usage'] is Map ? CompanyUsage.fromJson(d['usage'] as Map<String, dynamic>) : null;
      } else {
        _error = r.message ?? 'Erro ao carregar o consumo';
      }
    });
  }

  (String, String) _range(String p) {
    final now = DateTime.now();
    late DateTime from;
    late DateTime to;
    switch (p) {
      case 'lastMonth':
        from = DateTime(now.year, now.month - 1, 1);
        to = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
      case '7d':
        to = now;
        from = now.subtract(const Duration(days: 7));
      case '30d':
        to = now;
        from = now.subtract(const Duration(days: 30));
      default:
        from = DateTime(now.year, now.month, 1);
        to = now;
    }
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (fmt(from), fmt(to));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Consumo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (_fromLabel.isNotEmpty)
              Text('$_fromLabel → $_toLabel', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const Spacer(),
            IconButton(onPressed: _loading ? null : () => _load(), tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (key, label) in _periods)
                ChoiceChip(
                  label: Text(label),
                  selected: _period == key,
                  onSelected: _loading ? null : (_) => _load(key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _u == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _center(Icons.error_outline, _error!, retry: () => _load());
    }
    final u = _u;
    if (u == null) return _center(Icons.query_stats, 'Sem dados no período.');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _usageCard(u),
        _valuesCard(u),
      ],
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _usageCard(CompanyUsage u) => _card([
        const Text('Uso no período', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _stat('Conversas', u.conversations, Icons.forum_outlined, AppTheme.seed),
            _stat('Enviadas', u.messagesOut, Icons.north_east, const Color(0xFF2F80ED)),
            _stat('Recebidas', u.messagesIn, Icons.south_west, const Color(0xFF12B76A)),
            _stat('Modelos', u.templates, Icons.article_outlined, const Color(0xFF7B4DFF)),
            _stat('Mídia', u.media, Icons.attach_file, const Color(0xFFF79009)),
            _stat('Tokens IA', u.aiTokens, Icons.smart_toy_outlined, const Color(0xFFB54708)),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 14),
        const Text('Cobrado pela Meta (mensagens entregues)',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _stat('Marketing', u.marketing, Icons.campaign_outlined, const Color(0xFFD92D20)),
            _stat('Utilidade', u.utility, Icons.receipt_long_outlined, const Color(0xFF2F80ED)),
            _stat('Autenticação', u.authentication, Icons.lock_outline, const Color(0xFF7B4DFF)),
            _stat('Atendimento (grátis)', u.serviceFree, Icons.support_agent, const Color(0xFF12B76A)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'A Meta cobra por mensagem de modelo ENTREGUE, com preço por categoria. '
          'Conversas iniciadas pelo cliente (atendimento) são gratuitas.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
        ),
      ]);

  Widget _valuesCard(CompanyUsage u) => _card([
        const Text('Valores', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          'Preços por mensagem entregue: marketing R\$ ${_pricing.marketing.toStringAsFixed(2)} · '
          'utilidade R\$ ${_pricing.utility.toStringAsFixed(2)} · '
          'autenticação R\$ ${_pricing.authentication.toStringAsFixed(2)}. '
          'IA: R\$ ${_pricing.per1kTokens.toStringAsFixed(2)} por 1.000 tokens.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.35),
        ),
        const SizedBox(height: 14),
        if (u.marketing > 0 || u.utility > 0 || u.authentication > 0) ...[
          if (u.marketing > 0) _valueLine('Marketing (${u.marketing} mensagens)', u.valueMarketing),
          if (u.utility > 0) ...[
            if (u.marketing > 0) const Divider(height: 18),
            _valueLine('Utilidade (${u.utility} mensagens)', u.valueUtility),
          ],
          if (u.authentication > 0) ...[
            const Divider(height: 18),
            _valueLine('Autenticação (${u.authentication} mensagens)', u.valueAuthentication),
          ],
          const Divider(height: 18),
          _valueLine('Atendimento (${u.serviceFree} conversas)', 0),
        ] else
          _valueLine('WhatsApp (${u.conversations} conversas)', u.valueWhatsApp),
        const Divider(height: 18),
        _valueLine('IA (${u.aiTokens} tokens)', u.valueAI),
        const Divider(height: 18),
        _valueLine('Total', u.valueTotal, big: true),
      ]);

  Widget _valueLine(String label, double v, {bool big = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: big ? 15 : 13.5, fontWeight: big ? FontWeight.w700 : FontWeight.w500)),
        ),
        Text(v == 0 && !big ? 'grátis' : 'R\$ ${v.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: big ? 20 : 15,
                fontWeight: FontWeight.w800,
                color: big ? AppTheme.seed : (v == 0 ? const Color(0xFF12B76A) : null))),
      ],
    );
  }

  // Stat compacto INLINE (ícone + número + rótulo numa linha só). mainAxisSize.min
  // p/ o item medir pelo conteúdo e o Wrap fluir vários por linha (não 1 por linha).
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
