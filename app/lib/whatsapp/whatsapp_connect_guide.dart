import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import 'whatsapp_controller.dart';

/// Passo a passo guiado para conectar o número pela Meta (Embedded Signup): o
/// cliente entra com o Facebook da empresa, escolhe o número e confirma por SMS
/// — o resto (token, webhook, registro na Cloud API) é automático. Reusado no
/// onboarding e no empty-state da tela WhatsApp.
class WhatsAppConnectGuide extends StatefulWidget {
  const WhatsAppConnectGuide({super.key, this.onManual, this.onConnected, this.showHandle = false});

  /// "Prefiro inserir manualmente" — no onboarding leva à aba WhatsApp; na tela
  /// WhatsApp abre o formulário.
  final VoidCallback? onManual;

  /// Chamado após conectar com sucesso (ex.: fechar o sheet e recarregar).
  final VoidCallback? onConnected;

  /// Mostra a alcinha do bottom-sheet no topo.
  final bool showHandle;

  @override
  State<WhatsAppConnectGuide> createState() => _WhatsAppConnectGuideState();
}

class _WhatsAppConnectGuideState extends State<WhatsAppConnectGuide> {
  bool _connecting = false;

  Future<void> _meta() async {
    final c = context.read<WhatsAppController>();
    setState(() => _connecting = true);
    final err = await c.connectEmbedded();
    if (!mounted) return;
    setState(() => _connecting = false);
    if (err == 'cancelado') return; // usuário fechou o popup
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await showConnectResultDialog(context, c);
    widget.onConnected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<WhatsAppController>();
    final embedded = c.embeddedEnabled;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showHandle)
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.chat, color: AppTheme.seed),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Conecte seu WhatsApp', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(
          embedded
              ? 'Você entra com o Facebook da sua empresa e pronto — a gente configura o token e o recebimento sozinho, sem você copiar nada.'
              : 'Informe os dados do número do WhatsApp Business (Meta). A conexão automática pela Meta ainda não foi liberada pela plataforma.',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (embedded) ...[
          _passo(1, Icons.facebook, 'Entre com o Facebook da empresa', 'A conta Meta Business dona do número.'),
          _passo(2, Icons.dialpad, 'Escolha ou cadastre o número', 'Um número novo, ou um que você já usa.'),
          _passo(3, Icons.sms_outlined, 'Confirme o código por SMS', 'A Meta envia um código pra provar que o número é seu.'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.auto_awesome, size: 18, color: AppTheme.seed),
              SizedBox(width: 8),
              Expanded(child: Text('O resto é automático: token, webhook e registro na Meta. Você não copia nada.',
                  style: TextStyle(fontSize: 12.5, height: 1.3))),
            ]),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _connecting ? null : _meta,
            icon: _connecting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.verified_outlined, size: 20),
            label: Text(_connecting ? 'Abrindo a Meta…' : 'Conectar com a Meta'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.seed,
              minimumSize: const Size(0, 50),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.onManual != null) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _connecting ? null : widget.onManual,
                child: Text('Prefiro inserir os dados manualmente', style: TextStyle(color: Colors.grey.shade600)),
              ),
            ),
          ],
        ] else ...[
          FilledButton.icon(
            onPressed: widget.onManual,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Inserir os dados do número'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 50)),
          ),
        ],
      ]),
    );
  }

  Widget _passo(int n, IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30, height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppTheme.seed, shape: BoxShape.circle),
          child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 1),
            Text(sub, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.3)),
          ]),
        ),
        const SizedBox(width: 8),
        Icon(icon, color: AppTheme.seed.withValues(alpha: 0.5), size: 20),
      ]),
    );
  }
}

/// Conta como ficaram as DUAS metades — enviar (registro na Cloud API) e receber
/// (webhook apontado para cá) — logo após conectar um número. O PIN sorteado só
/// aparece aqui, uma vez. Compartilhado entre a tela WhatsApp e o guia.
Future<void> showConnectResultDialog(BuildContext context, WhatsAppController c) async {
  final ok = c.ultimoWebhookOk;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(ok ? 'Pronto para enviar e receber' : 'Conectado — falta configurar o recebimento'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded, color: ok ? AppTheme.seed : Colors.orange, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ok
                  ? 'O webhook deste número foi apontado para cá automaticamente — não precisa configurar nada no painel da Meta.'
                  : 'O envio está liberado, mas o RECEBIMENTO não foi configurado sozinho. Sem ele, as mensagens que chegarem NÃO aparecem aqui até você configurar.'),
            ),
          ]),
          if (!ok) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Configure o webhook na Meta', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('WhatsApp › Configuração da API › Webhooks › Editar. Cole os dados abaixo e assine o campo "messages".',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                _campoCopiavel(context, 'Callback URL', c.ultimoCallbackUrl ?? '${Config.apiBaseUrl}/webhook/meta'),
                const SizedBox(height: 8),
                _campoCopiavel(context, 'Verify Token', c.ultimoVerifyToken ?? '(peça o META_VERIFY_TOKEN à plataforma)'),
                if ((c.ultimoWebhookMotivo ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Por que não foi automático: ${c.ultimoWebhookMotivo}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('PIN da verificação em duas etapas: ${c.ultimoPin ?? "—"}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Guarde este PIN — a Meta o pede para migrar o número de provedor.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
    ),
  );
}

// Campo com valor selecionável + botão de copiar (para colar no painel da Meta).
Widget _campoCopiavel(BuildContext context, String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
      const SizedBox(height: 2),
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(6)),
            child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copiar',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado')));
          },
        ),
      ]),
    ],
  );
}
