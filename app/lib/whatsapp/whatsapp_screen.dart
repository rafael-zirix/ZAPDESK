import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<WhatsAppController>();
      c.load();
      c.loadEmbeddedConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<WhatsAppController>();
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'WhatsApp', actionLabel: 'Conectar número', onAction: () => _openConnect(c)),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _avatar(c, n),
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
            icon: const Icon(Icons.cell_tower),
            tooltip: 'Registrar na Meta (as mensagens não saem?)',
            onPressed: () => _registrar(c, n),
          ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'App Secret (número sob app próprio — não recebe mensagens?)',
            onPressed: () => _definirAppSecret(c, n),
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

  /// Avatar do número (foto se houver, senão ícone). Toca para trocar a foto.
  Widget _avatar(WhatsAppController c, WhatsAppNumber n) {
    final url = (n.photoUrl != null && n.photoUrl!.isNotEmpty) ? Config.apiBaseUrl + n.photoUrl! : null;
    return InkWell(
      onTap: () => _pickPhoto(c, n),
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.seed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
            ),
            child: url == null ? const Icon(Icons.chat, color: AppTheme.seed) : null,
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.seed,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.surface, width: 1.5),
              ),
              child: const Icon(Icons.photo_camera, color: Colors.white, size: 11),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(WhatsAppController c, WhatsAppNumber n) async {
    final f = await pickFile(accept: 'image/*');
    if (f == null) return;
    final err = await c.uploadPhoto(n.id, bytes: f.bytes, filename: f.name, contentType: f.mimeType);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
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
              onPressed: () => _openConnect(c),
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

  /// Abre a conexão de número: se o Embedded Signup estiver ligado, oferece
  /// "Conectar com a Meta" (popup) ou "Inserir manualmente"; senão, vai direto
  /// para o formulário manual.
  Future<void> _openConnect(WhatsAppController c) async {
    if (!c.embeddedEnabled) {
      await _openForm(c);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conectar número'),
        content: const Text(
            'Conecte pelo login da Meta (recomendado — sem copiar tokens) ou insira os dados manualmente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'manual'), child: const Text('Inserir manualmente')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'meta'),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: const Text('Conectar com a Meta'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'manual') {
      await _openForm(c);
    } else if (choice == 'meta') {
      await _doEmbedded(c);
    }
  }

  Future<void> _doEmbedded(WhatsAppController c) async {
    final err = await c.connectEmbedded();
    if (!mounted || err == 'cancelado') return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _mostrarResultado(c); // mostra envio/recebimento (webhook) + passos manuais se faltar
  }

  Future<void> _openForm(WhatsAppController c) async {
    final conectou = await showEntityForm(
      context,
      title: 'Conectar número',
      submitLabel: 'Conectar',
      fields: [
        FieldSpec(key: 'verified_name', label: 'Nome da empresa (exibido)', required: false),
        FieldSpec(key: 'display_phone', label: 'Telefone (ex.: +55 21 99999-9999)', required: false, keyboard: TextInputType.phone),
        FieldSpec(key: 'waba_id', label: 'WABA ID'),
        FieldSpec(key: 'phone_number_id', label: 'ID do número (phone_number_id)'),
        FieldSpec(key: 'access_token', label: 'Token de acesso'),
        // A Meta exige um PIN para LIGAR o número na Cloud API. Em branco, o
        // sistema sorteia um — o cliente precisa guardá-lo para um dia migrar o
        // número de provedor.
        FieldSpec(
            key: 'pin',
            label: 'PIN de 6 dígitos (em branco, geramos um)',
            required: false,
            keyboard: TextInputType.number),
      ],
      onSubmit: (v) => c.connect(v),
    );
    // conta como ficou envio e recebimento, e mostra o PIN (que pode ter sido
    // sorteado no backend e não aparece de novo)
    if (conectou && mounted) await _mostrarResultado(c);
  }

  /// Registra na Cloud API um número já conectado — o passo que falta quando o
  /// número conecta normalmente mas as mensagens não saem ("(#133010) Account
  /// not registered").
  Future<void> _registrar(WhatsAppController c, WhatsAppNumber n) async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Registrar na Meta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Liga "${n.title}" na Cloud API. É o que falta quando o número '
              'conecta certo mas as mensagens não saem.'),
          const SizedBox(height: 12),
          TextField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN de 6 dígitos',
              helperText: 'Em branco, geramos um. Se o número já tem PIN, informe o atual.',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await c.registrar(n.id, pin: pinCtrl.text.trim());
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _mostrarResultado(c);
  }

  /// Define o App Secret do app PRÓPRIO do cliente. Necessário quando o número
  /// está sob o app da empresa (não o da plataforma): sem o secret dele, a Meta
  /// assina o webhook com uma chave que não conferimos e as mensagens recebidas
  /// são descartadas — o número envia, mas não recebe.
  Future<void> _definirAppSecret(WhatsAppController c, WhatsAppNumber n) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App Secret do número'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Cole o App Secret do app da Meta dono de "${n.title}". É o que '
              'valida as mensagens recebidas quando o número está sob o app '
              'próprio da empresa (não o da plataforma).'),
          const SizedBox(height: 6),
          const Text('Meta for Developers › seu app › Configurações › Básico › Chave Secreta do App.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'App Secret',
              helperText: 'Guardado cifrado. Nunca volta na tela.',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await c.definirAppSecret(n.id, ctrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'App Secret salvo — o recebimento passa a validar com ele.')));
  }

  /// Conta como ficaram as DUAS metades: enviar (registro na Cloud API) e receber
  /// (webhook apontado para cá). O PIN sorteado só aparece nesta tela, uma vez.
  Future<void> _mostrarResultado(WhatsAppController c) async {
    final ok = c.ultimoWebhookOk;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ok ? 'Pronto para enviar e receber' : 'Conectado — falta configurar o recebimento'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: ok ? AppTheme.seed : Colors.orange, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(ok
                  ? 'O webhook deste número foi apontado para cá automaticamente — '
                      'não precisa configurar nada no painel da Meta.'
                  : 'O envio está liberado, mas o RECEBIMENTO não foi configurado sozinho. '
                      'Sem ele, as mensagens que chegarem NÃO aparecem aqui até você configurar.')),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Configure o webhook na Meta', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('WhatsApp › Configuração da API › Webhooks › Editar. Cole os dados abaixo e assine o campo "messages".',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    _campoCopiavel('Callback URL', c.ultimoCallbackUrl ?? '${Config.apiBaseUrl}/webhook/meta'),
                    const SizedBox(height: 8),
                    _campoCopiavel('Verify Token', c.ultimoVerifyToken ?? '(peça o META_VERIFY_TOKEN à plataforma)'),
                    if ((c.ultimoWebhookMotivo ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Por que não foi automático: ${c.ultimoWebhookMotivo}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('PIN da verificação em duas etapas: ${c.ultimoPin ?? "—"}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
  Widget _campoCopiavel(String label, String value) {
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
