import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../core/url_open.dart';

/// Loja de créditos do cliente (admin da empresa): saldo, planos (pacotes de
/// tokens), pagamento por PIX (QR) ou cartão (Checkout Pro), recarga automática
/// (assinatura) e extrato.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  int _balance = 0;
  double _per1k = 0;
  List<double> _packages = [];
  Map<String, dynamic>? _sub;
  List<Map<String, dynamic>> _ledger = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _api.get('/ai/config');
    final plans = await _api.get('/ai/plans');
    final sub = await _api.get('/ai/subscription');
    final led = await _api.get('/ai/ledger');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (cfg.ok && cfg.data is Map) {
        _balance = (((cfg.data as Map)['token_balance'] ?? 0) as num).toInt();
      }
      if (plans.ok && plans.data is Map) {
        final m = plans.data as Map;
        _per1k = ((m['price_1k_tokens'] ?? 0) as num).toDouble();
        _packages = ((m['packages'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList();
      }
      _sub = (sub.ok && sub.data is Map) ? (sub.data as Map).cast<String, dynamic>() : null;
      _ledger = led.ok && led.data is List ? (led.data as List).cast<Map<String, dynamic>>() : [];
    });
  }

  int _tokensFor(double amount) => _per1k > 0 ? (amount / _per1k * 1000).round() : 0;
  String _fmtTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(children: [
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
          child: Row(children: [
            const Text('Planos e créditos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: _loading ? null : _load, tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [
                  _balanceCard(),
                  const SizedBox(height: 18),
                  _plansSection(),
                  const SizedBox(height: 18),
                  _autoRechargeCard(),
                  const SizedBox(height: 18),
                  _ledgerCard(),
                ]),
        ),
      ]),
    );
  }

  Widget _balanceCard() {
    final low = _balance <= 2000;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.token, color: low ? const Color(0xFFEF4444) : AppTheme.seed, size: 34),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saldo de créditos de IA', style: TextStyle(fontSize: 13, color: Colors.grey)),
          Text('$_balance tokens',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: low ? const Color(0xFFEF4444) : null)),
        ]),
        const Spacer(),
        if (low) const Text('acabando', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _plansSection() {
    final pkgs = _packages.isNotEmpty ? _packages : <double>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Escolha um plano', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_per1k > 0
          ? 'Créditos pré-pagos de IA. Pague por PIX (na hora) ou cartão. R\$ ${_num(_per1k)} por 1.000 tokens.'
          : 'A plataforma ainda não definiu o preço dos tokens.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      const SizedBox(height: 14),
      if (pkgs.isEmpty)
        _freeAmountCard()
      else
        Wrap(spacing: 14, runSpacing: 14, children: [for (final a in pkgs) _planCard(a)]),
    ]);
  }

  Widget _planCard(double amount) {
    final tokens = _tokensFor(amount);
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('R\$ ${_num(amount)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('≈ ${_fmtTokens(tokens)} tokens', style: TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
        Text('~ ${_fmtTokens((tokens / 2).round())} respostas', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy || _per1k <= 0 ? null : () => _payPix(amount),
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text('PIX'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy || _per1k <= 0 ? null : () => _payCard(amount),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              icon: const Icon(Icons.credit_card, size: 18),
              label: const Text('Cartão'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _freeAmountCard() {
    final ctrl = TextEditingController(text: '50');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        SizedBox(
          width: 160,
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _payPix(double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
          icon: const Icon(Icons.qr_code, size: 18), label: const Text('PIX')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _payCard(double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          icon: const Icon(Icons.credit_card, size: 18), label: const Text('Cartão')),
      ]),
    );
  }

  // ---- Pagamento: PIX (QR in-app) ----
  Future<void> _payPix(double amount) async {
    if (amount <= 0) return;
    final nome = TextEditingController();
    final cpf = TextEditingController();
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Pagar R\$ ${_num(amount)} via PIX'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
          TextField(controller: cpf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CPF do pagador')),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gerar PIX')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await _api.post('/ai/recharge/checkout', {
      'amount_brl': amount,
      'first_name': nome.text.trim(),
      'last_name': '',
      'document': cpf.text.trim(),
      'email': email.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok && r.data is Map) {
      await _showPix(r.data as Map);
    } else {
      _toast(r.message ?? 'Não foi possível gerar o PIX');
    }
  }

  Future<void> _showPix(Map res) async {
    final ref = (res['reference_id'] ?? '').toString();
    final qr = (res['pix_qr'] ?? '').toString();
    final b64 = (res['pix_qr_base64'] ?? '').toString();
    var bytes = _b64(b64);
    Timer? poll;
    var pago = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setLocal) {
        poll ??= Timer.periodic(const Duration(seconds: 4), (t) async {
          final s = await _api.get('/ai/recharge/order/$ref');
          if (s.ok && s.data is Map && ((s.data as Map)['credited'] == true)) {
            t.cancel();
            pago = true;
            setLocal(() {});
          }
        });
        return AlertDialog(
          title: Text(pago ? 'Pagamento confirmado' : 'Pague com PIX'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (pago) ...[
                const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 56),
                const SizedBox(height: 8),
                const Text('Tokens creditados no seu saldo.'),
              ] else ...[
                if (bytes != null) Image.memory(bytes, width: 200, height: 200, gaplessPlayback: true),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(qr, maxLines: 3, style: const TextStyle(fontSize: 11.5)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: qr));
                      _toast('Código copiado');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar código'),
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Aguardando pagamento…', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                ]),
              ],
            ]),
          ),
          actions: [
            pago
                ? FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Concluir'))
                : TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Fechar')),
          ],
        );
      }),
    );
    poll?.cancel();
    if (pago && mounted) _load();
  }

  // ---- Pagamento: cartão (Checkout Pro) ----
  Future<void> _payCard(double amount) async {
    if (amount <= 0) return;
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Pagar R\$ ${_num(amount)} com cartão'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Você vai para a página segura do Mercado Pago para pagar com cartão (ou PIX). '
              'Os tokens entram após a aprovação.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await _api.post('/ai/recharge/preference', {'amount_brl': amount, 'email': email.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    final url = (r.ok && r.data is Map) ? (r.data as Map)['init_point']?.toString() ?? '' : '';
    if (url.isNotEmpty) {
      openUrl(url);
      _toast('Abrindo o checkout… os tokens entram após o pagamento.');
    } else {
      _toast(r.message ?? 'Não foi possível abrir o checkout');
    }
  }

  // ---- Recarga automática (assinatura) ----
  Widget _autoRechargeCard() {
    final sub = _sub;
    final ativa = (sub?['status'] ?? '') == 'authorized';
    final valor = ((sub?['amount_brl'] ?? 0) as num).toDouble();
    final tokens = ((sub?['tokens'] ?? 0) as num).toInt();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.autorenew, size: 20, color: AppTheme.seed),
          SizedBox(width: 8),
          Text('Recarga automática', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        if (ativa)
          Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Ativa — R\$ ${_num(valor)}/mês · +$tokens tokens')),
            TextButton(onPressed: _busy ? null : _cancelAuto, child: const Text('Cancelar')),
          ])
        else
          Row(children: [
            Expanded(
              child: Text('Ative para o crédito entrar sozinho todo mês (cartão autorizado uma vez no Mercado Pago).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _busy ? null : _startAuto,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              child: const Text('Ativar'),
            ),
          ]),
      ]),
    );
  }

  Future<void> _startAuto() async {
    final valor = TextEditingController(text: '50');
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recarga automática (mensal)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: valor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor por mês', prefixText: 'R\$ ')),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail do pagador')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ativar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await _api.post('/ai/subscription', {
      'amount_brl': double.tryParse(valor.text.replaceAll(',', '.')) ?? 0,
      'email': email.text.trim(),
      'frequency': 1,
      'frequency_type': 'months',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok && r.data is Map) {
      final init = (r.data as Map)['init_point']?.toString() ?? '';
      if (init.isNotEmpty) openUrl(init);
      _toast('Autorize o cartão no Mercado Pago para ativar.');
      await _load();
    } else {
      _toast(r.message ?? 'Não foi possível ativar');
    }
  }

  Future<void> _cancelAuto() async {
    setState(() => _busy = true);
    final r = await _api.delete('/ai/subscription');
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.ok ? 'Recarga automática cancelada' : (r.message ?? 'Não foi possível cancelar'));
    await _load();
  }

  // ---- Extrato ----
  Widget _ledgerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.receipt_long_outlined, size: 20, color: AppTheme.seed),
          SizedBox(width: 8),
          Text('Extrato', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        if (_ledger.isEmpty)
          Text('Sem movimentações ainda.', style: TextStyle(color: Colors.grey.shade500))
        else
          for (final e in _ledger.take(15)) _ledgerRow(e),
      ]),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> e) {
    final delta = ((e['delta'] ?? 0) as num).toInt();
    final pos = delta >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(pos ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 16, color: pos ? const Color(0xFF15803D) : Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(_kind(e['kind']?.toString() ?? ''), style: const TextStyle(fontSize: 13.5))),
        Text('${pos ? '+' : ''}$delta', style: TextStyle(fontWeight: FontWeight.w700, color: pos ? const Color(0xFF15803D) : null)),
      ]),
    );
  }

  String _kind(String k) => switch (k) {
        'purchase' => 'Compra de tokens',
        'autorecharge' => 'Recarga automática',
        'recharge' => 'Recarga',
        'consumption' => 'Uso da IA',
        _ => k,
      };

  Uint8List? _b64(String s) {
    if (s.isEmpty) return null;
    try {
      return base64Decode(s.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
