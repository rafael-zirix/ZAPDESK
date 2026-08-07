import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../core/url_open.dart';

/// Mensalidade dos MÓDULOS contratados (diferente da compra de tokens de IA,
/// que é consumo). Mostra o que a empresa paga hoje, o estado da cobrança e o
/// botão que abre a autorização do cartão no Mercado Pago.
class SubscriptionCard extends StatefulWidget {
  const SubscriptionCard({super.key});

  @override
  State<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<SubscriptionCard> {
  final _api = ApiClient.instance;
  Map<String, dynamic> dados = {};
  bool loading = true;
  bool assinando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/billing/subscription');
    if (!mounted) return;
    setState(() {
      loading = false;
      dados = r.ok && r.data is Map ? Map<String, dynamic>.from(r.data as Map) : {};
    });
  }

  Future<void> _assinar() async {
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assinar mensalidade'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Você vai para o Mercado Pago autorizar o cartão. A cobrança é mensal e '
                'automática; o cartão fica lá — o HotZap nunca vê os dados.'),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail do responsável pelo pagamento'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => assinando = true);
    final r = await _api.post('/billing/subscription', {'email': email.text.trim()});
    if (!mounted) return;
    setState(() => assinando = false);
    final link = r.ok && r.data is Map ? (r.data as Map)['init_point']?.toString() : null;
    if (link != null && link.isNotEmpty) {
      openUrl(link);
      await _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível criar a assinatura')));
    }
  }

  Future<void> _cancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar mensalidade'),
        content: const Text('A cobrança automática para. Os módulos continuam ligados até o fim do '
            'período contratado — falamos com você antes de desligar qualquer coisa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar assinatura'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/billing/subscription');
    if (!mounted) return;
    if (r.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    final centavos = (dados['amount_cents'] ?? 0) as int;
    final status = (dados['status'] ?? 'none').toString();
    final modulos = ((dados['modules'] as List?) ?? const []).join(' · ');
    final carencia = (dados['grace_days'] ?? 5) as int;
    if (centavos == 0 && status == 'none') return const SizedBox.shrink();

    final (Color cor, String rotulo) = switch (status) {
      'active' => (const Color(0xFF12B76A), 'Assinatura ativa'),
      'past_due' => (const Color(0xFFF79009), 'Pagamento pendente'),
      'pending' => (AppTheme.seed, 'Aguardando autorização do cartão'),
      'canceled' => (Colors.grey, 'Assinatura cancelada'),
      _ => (Colors.grey, 'Sem assinatura'),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Mensalidade dos módulos',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(rotulo, style: TextStyle(color: cor, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('R\$ ${(centavos / 100).toStringAsFixed(2).replaceAll('.', ',')} por mês',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.seed)),
          if (modulos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(modulos, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ),
          if (status == 'past_due')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  'A última cobrança não passou. Atualize o cartão no Mercado Pago — depois de $carencia dias '
                  'os módulos pagos são desligados, mas o atendimento continua funcionando.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF93370D), height: 1.4)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            if (status != 'active' && status != 'pending')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                onPressed: assinando ? null : _assinar,
                icon: assinando
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.credit_card, size: 18),
                label: const Text('Assinar'),
              ),
            if (status == 'pending')
              OutlinedButton.icon(
                onPressed: assinando ? null : _assinar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reabrir autorização'),
              ),
            if (status == 'active' || status == 'past_due') ...[
              const SizedBox(width: 10),
              TextButton(onPressed: _cancelar, child: const Text('Cancelar assinatura')),
            ],
          ]),
        ],
      ),
    );
  }
}
