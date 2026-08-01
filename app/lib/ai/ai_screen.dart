import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';
import '../core/url_open.dart';

/// Atendente IA da empresa (admin): liga/desliga, instruções, base de
/// conhecimento (contextos), saldo de tokens + extrato e recompra automática.
class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  bool _savingCfg = false;
  bool _savingAuto = false;

  // Config
  bool _enabled = false;
  bool _providerReady = false;
  final _instructions = TextEditingController();
  int _balance = 0;
  int _kbLimit = 4000; // teto de caracteres da base de conhecimento (vem do backend)

  // Recompra automática
  bool _autoEnabled = false;
  bool _hasPayment = false;
  final _autoThreshold = TextEditingController();
  final _autoAmount = TextEditingController();

  List<Map<String, dynamic>> _contexts = [];
  List<Map<String, dynamic>> _ledger = [];

  // ~2.000 tokens por pergunta+resposta (varia com base de conhecimento/conversa).
  int _estReplies(int tokens) => (tokens / 2000).round();

  // Caracteres já usados na base de conhecimento (soma dos contextos).
  int get _kbUsed => _contexts.fold(0, (s, c) => s + (c['content'] ?? '').toString().length);

  // Itens que NÃO são as 3 seções fixas (conteúdo livre adicionado à parte).
  List<Map<String, dynamic>> get _extraItems {
    final fixed = _kbSections.map((s) => s.title).toSet();
    return _contexts.where((c) => !fixed.contains((c['title'] ?? '').toString())).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instructions.dispose();
    _autoThreshold.dispose();
    _autoAmount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await _api.get('/ai/config');
    final ctx = await _api.get('/ai/context');
    final led = await _api.get('/ai/ledger');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (cfg.ok && cfg.data is Map) {
        final m = cfg.data as Map;
        _enabled = (m['enabled'] ?? false) as bool;
        _providerReady = (m['provider_ready'] ?? false) as bool;
        _instructions.text = (m['instructions'] ?? '').toString();
        _balance = ((m['token_balance'] ?? 0) as num).toInt();
        _kbLimit = ((m['kb_limit'] ?? 4000) as num).toInt();
        _autoEnabled = (m['autorecharge_enabled'] ?? false) as bool;
        _hasPayment = (m['has_payment'] ?? false) as bool;
        _autoThreshold.text = ((m['autorecharge_threshold'] ?? 0) as num).toInt().toString();
        _autoAmount.text = ((m['autorecharge_amount'] ?? 0) as num).toInt().toString();
      }
      _contexts = ctx.ok && ctx.data is List ? (ctx.data as List).cast<Map<String, dynamic>>() : [];
      _ledger = led.ok && led.data is List ? (led.data as List).cast<Map<String, dynamic>>() : [];
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _savingCfg = true);
    final r = await _api.put('/ai/config', {'enabled': _enabled, 'instructions': _instructions.text.trim()});
    if (!mounted) return;
    setState(() => _savingCfg = false);
    _toast(r.ok ? 'Atendente IA salvo' : (r.message ?? 'Não foi possível salvar'));
  }

  Future<void> _saveAuto() async {
    setState(() => _savingAuto = true);
    final r = await _api.put('/ai/autorecharge', {
      'enabled': _autoEnabled,
      'threshold': int.tryParse(_autoThreshold.text.trim()) ?? 0,
      'amount': int.tryParse(_autoAmount.text.trim()) ?? 0,
    });
    if (!mounted) return;
    setState(() => _savingAuto = false);
    _toast(r.ok ? 'Recompra automática salva' : (r.message ?? 'Não foi possível salvar'));
  }

  // Seções fixas da base de conhecimento (o "quadro" dividido por tópico).
  static const _kbSections = [
    (title: 'Horários', icon: Icons.schedule_outlined, hint: 'Dias e horas de atendimento.'),
    (title: 'Contato', icon: Icons.call_outlined, hint: 'Telefone, WhatsApp, e-mail.'),
    (title: 'Contexto da empresa', icon: Icons.business_outlined, hint: 'O que a empresa faz, serviços, diferenciais e políticas.'),
  ];

  Map<String, dynamic>? _sectionItem(String title) {
    for (final c in _contexts) {
      if ((c['title'] ?? '').toString() == title) return c;
    }
    return null;
  }

  // Edita o conteúdo de uma seção fixa: cria (POST), atualiza (PUT) ou, se
  // esvaziada, remove (DELETE) — para não deixar item vazio contando no teto.
  Future<void> _editSection(String title) async {
    final item = _sectionItem(title);
    final id = item?['id']?.toString();
    final current = (item?['content'] ?? '').toString();
    final content = TextEditingController(text: current);
    // Livre = teto menos tudo que já existe, exceto esta seção (será substituída).
    final remaining = (_kbLimit - (_kbUsed - current.length)).clamp(0, _kbLimit);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final len = content.text.trim().length;
          final over = len > remaining;
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: content,
                    minLines: 4,
                    maxLines: 12,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(labelText: 'Conteúdo desta seção', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      over
                          ? 'Excede o limite em ${len - remaining} caractere(s)'
                          : 'Usando $len de $remaining caracteres livres',
                      style: TextStyle(fontSize: 12, color: over ? Colors.red : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(
                onPressed: over ? null : () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final text = content.text.trim();
    if (text.isEmpty && id == null) return;
    final r = (text.isEmpty && id != null)
        ? await _api.delete('/ai/context/$id')
        : (id != null)
            ? await _api.put('/ai/context/$id', {'title': title, 'content': text})
            : await _api.post('/ai/context', {'title': title, 'content': text});
    if (r.ok) {
      await _load();
    } else if (mounted) {
      _toast(r.message ?? 'Não foi possível salvar');
    }
  }

  // Conteúdo livre (além das 3 seções): colar um texto avulso.
  Future<void> _addContextDialog() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final remaining = (_kbLimit - _kbUsed).clamp(0, _kbLimit);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final len = content.text.trim().length;
          final over = len > remaining;
          return AlertDialog(
            title: const Text('Adicionar conteúdo'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'Título (ex.: Preços, Formas de pagamento)')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: content,
                    minLines: 4,
                    maxLines: 10,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(labelText: 'Conteúdo', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      over ? 'Excede o limite em ${len - remaining} caractere(s)' : 'Usando $len de $remaining caracteres livres',
                      style: TextStyle(fontSize: 12, color: over ? Colors.red : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(
                onPressed: over ? null : () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                child: const Text('Adicionar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    if (title.text.trim().isEmpty || content.text.trim().isEmpty) return;
    final r = await _api.post('/ai/context', {'title': title.text.trim(), 'content': content.text.trim()});
    if (r.ok) {
      await _load();
    } else if (mounted) {
      _toast(r.message ?? 'Não foi possível adicionar');
    }
  }

  // Conteúdo livre a partir de um arquivo de texto (.txt/.md/.csv).
  Future<void> _uploadContext() async {
    final f = await pickFile(accept: '.txt,.md,.csv,text/plain');
    if (f == null) return;
    final r = await _api.uploadFile('/ai/upload-context', bytes: f.bytes, filename: f.name, contentType: f.mimeType);
    if (r.ok) {
      await _load();
    } else if (mounted) {
      _toast(r.message ?? 'Não foi possível subir o arquivo');
    }
  }

  Future<void> _deleteContext(String id) async {
    final r = await _api.delete('/ai/context/$id');
    if (r.ok) {
      await _load();
    } else if (mounted) {
      _toast(r.message ?? 'Não foi possível excluir');
    }
  }

  // Importa o texto de um site como contexto (o backend busca e extrai o texto).
  Future<void> _importSite() async {
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar site'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cole o endereço do site. A gente extrai o texto e usa como contexto da IA (respeitando o limite da base).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'https://suaempresa.com.br', prefixIcon: Icon(Icons.link)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final u = url.text.trim();
    if (u.isEmpty) return;
    _toast('Importando o site…');
    final r = await _api.post('/ai/import-url', {'url': u});
    if (r.ok) {
      await _load();
      if (mounted) _toast(r.message ?? 'Site importado');
    } else if (mounted) {
      _toast(r.message ?? 'Não foi possível importar o site');
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          const ListHeader(title: 'Atendente IA'),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_providerReady) _providerBanner(),
                            _activationCard(),
                            const SizedBox(height: 16),
                            _balanceCard(),
                            const SizedBox(height: 16),
                            _knowledgeCard(),
                            const SizedBox(height: 16),
                            _autoRechargeCard(),
                            const SizedBox(height: 16),
                            _ledgerCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _cardTitle(IconData ic, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(ic, size: 20, color: AppTheme.seed),
          const SizedBox(width: 10),
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _providerBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFB88109).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFFB88109)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'O motor de IA ainda não foi ligado pela plataforma. Você já pode configurar tudo aqui; '
              'as respostas automáticas começam assim que ligarmos.',
              style: TextStyle(height: 1.35),
            ),
          ),
        ]),
      );

  Widget _activationCard() => _card([
        _cardTitle(Icons.smart_toy_outlined, 'Ativação'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          title: const Text('Responder automaticamente'),
          subtitle: const Text('A IA responde os clientes usando as instruções e a base de conhecimento abaixo.'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _instructions,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Instruções (persona, tom, regras)',
            hintText: 'Ex.: Você é o atendimento da Loja X. Seja cordial, responda em até 3 linhas, não dê descontos.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _savingCfg ? null : _saveConfig,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
            child: _savingCfg
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar'),
          ),
        ),
      ]);

  Widget _balanceCard() => _card([
        _cardTitle(Icons.token_outlined, 'Saldo de IA'),
        Text('$_balance tokens', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text('≈ ${_estReplies(_balance)} respostas', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
        const SizedBox(height: 6),
        Text('A IA consome tokens a cada resposta; ao zerar, ela pausa e as conversas caem no atendimento humano.',
            style: TextStyle(color: Colors.grey.shade600, height: 1.35)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _comprarTokens,
            icon: const Icon(Icons.pix, size: 18),
            label: const Text('Comprar tokens'),
          ),
        ),
      ]);

  /// Abre o checkout de compra de tokens (NuPay): coleta valor + dados do pagador,
  /// cria a cobrança e leva o cliente ao Nubank. Os tokens entram quando o
  /// pagamento confirma (webhook credita o saldo).
  Future<void> _comprarTokens() async {
    final valorCtrl = TextEditingController(text: '50');
    final nomeCtrl = TextEditingController();
    final sobrenomeCtrl = TextEditingController();
    final cpfCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Comprar tokens'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pagamento via PIX (Mercado Pago). Ao gerar, aparece o QR e o '
                'copia e cola; os tokens entram sozinhos assim que o PIX é aprovado.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(controller: valorCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ ')),
            TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: sobrenomeCtrl, decoration: const InputDecoration(labelText: 'Sobrenome')),
            TextField(controller: cpfCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CPF do pagador')),
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gerar PIX')),
        ],
      ),
    );
    if (ok != true) return;
    final valor = double.tryParse(valorCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (valor <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor válido')));
      return;
    }
    final r = await _api.post('/ai/recharge/checkout', {
      'amount_brl': valor,
      'first_name': nomeCtrl.text.trim(),
      'last_name': sobrenomeCtrl.text.trim(),
      'document': cpfCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
    });
    if (!mounted) return;
    if (r.ok && r.data is Map) {
      await _mostrarPix(r.data as Map);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.message ?? 'Não foi possível gerar o PIX')));
    }
  }

  // Decodifica a imagem do QR (base64 do MP, PNG sem prefixo). Null se vier vazio/inválido.
  Uint8List? _qrBytes(String s) {
    if (s.isEmpty) return null;
    try {
      return base64Decode(s.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }

  // Mostra o PIX (QR + copia e cola) e fica consultando o pedido até o pagamento
  // cair — aí credita sozinho e atualiza o saldo. Sem depender de o cliente voltar.
  Future<void> _mostrarPix(Map res) async {
    final ref = (res['reference_id'] ?? '').toString();
    final qr = (res['pix_qr'] ?? '').toString();
    final qrBytes = _qrBytes((res['pix_qr_base64'] ?? '').toString());
    final ticket = (res['ticket_url'] ?? '').toString();
    final tokens = ((res['tokens'] ?? 0) as num).toInt();
    final valor = ((res['amount_brl'] ?? 0) as num).toDouble();
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
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (pago) ...[
                const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 56),
                const SizedBox(height: 10),
                Text('$tokens tokens creditados no seu saldo.', textAlign: TextAlign.center),
              ] else ...[
                Text('R\$ ${valor.toStringAsFixed(2)}  ·  $tokens tokens',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (qrBytes != null)
                  Image.memory(qrBytes, width: 210, height: 210, gaplessPlayback: true)
                else if (ticket.isNotEmpty)
                  TextButton.icon(onPressed: () => openUrl(ticket),
                      icon: const Icon(Icons.open_in_new), label: const Text('Abrir QR no navegador')),
                const SizedBox(height: 12),
                const Text('Ou copie o código PIX:', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                const SizedBox(height: 4),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado')));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar código'),
                  ),
                ),
                const SizedBox(height: 6),
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
    if (pago && mounted) _load(); // atualiza o saldo/extrato
  }

  // Medidor de uso da base: como ela vai inteira no prompt de cada pergunta, há
  // um teto de caracteres (vem do backend) para segurar o custo por resposta.
  Widget _kbMeter() {
    final limit = _kbLimit <= 0 ? 4000 : _kbLimit;
    final used = _kbUsed;
    final frac = (used / limit).clamp(0.0, 1.0);
    final color = frac >= 1.0
        ? Colors.red
        : frac >= 0.8
            ? const Color(0xFFB88109)
            : AppTheme.seed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Uso da base (afeta o custo por resposta)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Spacer(),
            Text('$used / $limit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _knowledgeCard() => _card([
        _cardTitle(Icons.menu_book_outlined, 'Base de conhecimento'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Cada seção é o que a IA usa para responder. Toque em Editar para preencher — mantenha curto e direto.',
              style: TextStyle(color: Colors.grey.shade600)),
        ),
        _kbMeter(),
        const SizedBox(height: 4),
        for (var i = 0; i < _kbSections.length; i++) ...[
          if (i > 0) const Divider(height: 22),
          _sectionRow(_kbSections[i]),
        ],
        const Divider(height: 28),
        Text('Mais conteúdo (opcional)',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700, fontSize: 13)),
        const SizedBox(height: 2),
        Text('Além das 3 seções acima, cole textos ou suba arquivos (.txt/.md/.csv) — ex.: Preços, Formas de pagamento, FAQ.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _addContextDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Colar texto'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
            ),
            OutlinedButton.icon(
              onPressed: _uploadContext,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Subir arquivo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.seed,
                side: BorderSide(color: AppTheme.seed.withValues(alpha: 0.6)),
                minimumSize: const Size(0, 44),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _importSite,
              icon: const Icon(Icons.language, size: 18),
              label: const Text('Importar site'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.seed,
                side: BorderSide(color: AppTheme.seed.withValues(alpha: 0.6)),
                minimumSize: const Size(0, 44),
              ),
            ),
          ],
        ),
        if (_extraItems.isNotEmpty)
          for (final it in _extraItems)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text((it['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text((it['content'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Excluir',
                onPressed: () => _deleteContext((it['id'] ?? '').toString()),
              ),
            ),
      ]);

  // Uma seção fixa do "quadro" da base: ícone + título + conteúdo (ou dica) + Editar.
  Widget _sectionRow(({String title, IconData icon, String hint}) s) {
    final item = _sectionItem(s.title);
    final content = (item?['content'] ?? '').toString();
    final filled = content.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(s.icon, size: 20, color: AppTheme.seed),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                filled ? content : s.hint,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: filled ? null : Colors.grey.shade500,
                  fontStyle: filled ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _editSection(s.title),
          icon: Icon(filled ? Icons.edit_outlined : Icons.add, size: 18),
          label: Text(filled ? 'Editar' : 'Preencher'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.seed),
        ),
      ],
    );
  }

  Widget _autoRechargeCard() => _card([
        _cardTitle(Icons.autorenew, 'Recompra automática'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoEnabled,
          onChanged: (v) => setState(() => _autoEnabled = v),
          title: const Text('Recarregar sozinho quando o saldo ficar baixo'),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _autoThreshold,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quando o saldo cair abaixo de', suffixText: 'tokens'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _autoAmount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Comprar', suffixText: 'tokens'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(_hasPayment ? Icons.credit_card : Icons.credit_card_off_outlined, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hasPayment
                    ? 'Cartão cadastrado. A recompra será cobrada nele.'
                    : 'Requer um cartão cadastrado (em breve). Por ora, a recarga é manual com a plataforma.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _savingAuto ? null : _saveAuto,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
            child: _savingAuto
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar'),
          ),
        ),
      ]);

  Widget _ledgerCard() => _card([
        _cardTitle(Icons.receipt_long_outlined, 'Extrato de tokens'),
        if (_ledger.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Sem movimentações ainda.', style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          for (final e in _ledger)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(_ledgerLabel((e['kind'] ?? '').toString(), (e['note'])?.toString()))),
                Text(
                  '${((e['delta'] ?? 0) as num) >= 0 ? '+' : ''}${(e['delta'] ?? 0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ((e['delta'] ?? 0) as num) >= 0 ? const Color(0xFF1F9D57) : Colors.red,
                  ),
                ),
              ]),
            ),
      ]);

  String _ledgerLabel(String kind, String? note) {
    final base = switch (kind) {
      'recharge' => 'Recarga',
      'autorecharge' => 'Recompra automática',
      'consumption' => 'Consumo (resposta da IA)',
      _ => kind,
    };
    return note != null && note.isNotEmpty ? '$base — $note' : base;
  }
}
