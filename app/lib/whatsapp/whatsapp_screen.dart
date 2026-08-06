import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';
import '../models/whatsapp_number.dart';
import 'whatsapp_connect_guide.dart';
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
          // Com número já conectado, o guia continua a um clique — para incluir
          // um número NOVO pelo mesmo passo a passo da Meta.
          ListHeader(
              title: 'WhatsApp',
              actionLabel: c.numbers.isEmpty ? 'Conectar número' : 'Conectar novo número',
              onAction: () => _openConnect(c)),
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
    // Largura FINITA (SizedBox) e não ConstrainedBox: no CanvasKit o segundo
    // deixa os Row/Expanded do guia colapsarem (texto na vertical).
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth < 480 ? cons.maxWidth - 32 : 460.0;
        return Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: w,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                // O guia dá o caminho fácil (Conectar com a Meta) quando o
                // Embedded Signup está ligado, com o manual como alternativa.
                child: WhatsAppConnectGuide(onManual: () => _openForm(c)),
              ),
            ),
          ),
        );
      },
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

  /// Abre a conexão de número num sheet com o guia (passo a passo + "Conectar
  /// com a Meta" + formulário manual). Mesma experiência do onboarding.
  Future<void> _openConnect(WhatsAppController c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: WhatsAppConnectGuide(
          showHandle: true,
          onManual: () {
            Navigator.pop(ctx);
            _openForm(c);
          },
          onConnected: () => Navigator.pop(ctx),
        ),
      ),
    );
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
    if (conectou && mounted) await showConnectResultDialog(context, c);
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
    await showConnectResultDialog(context, c);
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
