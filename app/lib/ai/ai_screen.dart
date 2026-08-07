import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';

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

  // Config
  bool _enabled = false;
  bool _providerReady = false;
  final _instructions = TextEditingController();

  // Modelos que a plataforma oferece (o cliente compra token conosco e escolhe
  // qual IA usar; modelo mais forte consome mais do saldo).
  List<Map<String, dynamic>> _modelos = [];
  String _modeloAtual = '';
  int _balance = 0;
  int _kbLimit = 4000; // teto de caracteres da base de conhecimento (vem do backend)

  List<Map<String, dynamic>> _contexts = [];
  List<Map<String, dynamic>> _actions = []; // Ações da IA (buscas externas)

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
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await _api.get('/ai/config');
    final ctx = await _api.get('/ai/context');
    final act = await _api.get('/ai/actions');
    final mods = await _api.get('/ai/models');
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
      }
      _contexts = ctx.ok && ctx.data is List ? (ctx.data as List).cast<Map<String, dynamic>>() : [];
      _actions = act.ok && act.data is List ? (act.data as List).cast<Map<String, dynamic>>() : [];
      if (mods.ok && mods.data is Map) {
        final m = mods.data as Map;
        _modelos = ((m['models'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _modeloAtual = (m['current'] ?? '').toString();
      }
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _savingCfg = true);
    final r = await _api.put('/ai/config', {'enabled': _enabled, 'instructions': _instructions.text.trim()});
    if (!mounted) return;
    setState(() => _savingCfg = false);
    _toast(r.ok ? 'Atendente IA salvo' : (r.message ?? 'Não foi possível salvar'));
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
                            if (_modelos.isNotEmpty) ...[
                              _modeloCard(),
                              const SizedBox(height: 16),
                            ],
                            _knowledgeCard(),
                            const SizedBox(height: 16),
                            _actionsCard(),
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
        Text('A IA consome tokens a cada resposta; ao zerar, ela pausa e as conversas caem no atendimento humano. Compre créditos na aba Planos.',
            style: TextStyle(color: Colors.grey.shade600, height: 1.35)),
      ]);

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

  // ---- Ações da IA (buscas externas / function-calling) ----
  /// Escolha da IA. Uma linha por modelo, com o quanto ele consome do saldo —
  /// é a informação que evita o cliente escolher o mais forte e se assustar com
  /// o consumo depois.
  Widget _modeloCard() => _card([
        const Text('Escolha a sua IA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        Text('A IA escolhida vale para TUDO: o atendimento automático, a sugestão de resposta e o que '
            'vier depois. Todas são cobradas do seu saldo de tokens — as mais fortes consomem mais por '
            'mensagem. Compare e escolha; dá para trocar quando quiser.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final m in _modelos) _modeloOpcao(m)]),
      ]);

  /// Cartão comparativo de um modelo. Largura fixa (nada de Expanded em Row —
  /// colapsa no CanvasKit) e os números que decidem: contexto, inteligência,
  /// velocidade e quanto consome.
  Widget _modeloOpcao(Map<String, dynamic> m) {
    final id = (m['model'] ?? '').toString();
    final atual = id == _modeloAtual;
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: atual ? AppTheme.seed.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: atual ? AppTheme.seed : Colors.grey.withValues(alpha: 0.3),
            width: atual ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((m['label'] ?? id).toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text((m['provider'] ?? '').toString(),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            if ((m['best_for'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(m['best_for'].toString(),
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ],
            const SizedBox(height: 10),
            if ((m['context'] ?? '').toString().isNotEmpty)
              _linhaSpec('Contexto', m['context'].toString()),
            _barra('Inteligência', (m['intelligence'] ?? 0) as int),
            _barra('Velocidade', (m['speed'] ?? 0) as int),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.token, size: 15, color: Color(0xFFF79009)),
              const SizedBox(width: 5),
              Text('consome ${_fator(m)}× por mensagem',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB54708))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: atual
                  ? Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppTheme.seed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Em uso',
                          style: TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700, fontSize: 13)),
                    )
                  : OutlinedButton(onPressed: () => _salvarModelo(id), child: const Text('Usar esta')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaSpec(String label, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))),
          Text(valor, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  // Nota comparativa em barra: dá a noção sem prometer precisão de benchmark.
  Widget _barra(String label, int nota) {
    final v = (nota.clamp(0, 100)) / 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))),
        SizedBox(
          width: 90,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(AppTheme.seed),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$nota%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  String _fator(Map<String, dynamic> m) {
    final f = (m['factor'] ?? 1) as num;
    return f == f.roundToDouble() ? f.toInt().toString() : f.toStringAsFixed(1);
  }

  Future<void> _salvarModelo(String model) async {
    final anterior = _modeloAtual;
    setState(() => _modeloAtual = model);
    final r = await _api.put('/ai/models', {'model': model});
    if (!mounted) return;
    if (r.ok) {
      _toast('IA atualizada');
    } else {
      setState(() => _modeloAtual = anterior);
      _toast(r.message ?? 'Não foi possível trocar o modelo');
    }
  }

  Widget _actionsCard() => _card([
        _cardTitle(Icons.bolt_outlined, 'Ações da IA — buscas externas'),
        Text('A IA usa estas buscas sozinha quando o cliente precisar (ex.: 2ª via de boleto). '
            'Ela pergunta o dado, consulta a API que você configurar e responde com o resultado.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const SizedBox(height: 12),
        if (_actions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Nenhuma ação ainda.', style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          for (final a in _actions) _actionRow(a),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _editAction(null),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nova ação'),
          ),
        ),
      ]);

  Widget _actionRow(Map<String, dynamic> a) {
    final enabled = (a['enabled'] ?? true) == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.bolt, size: 18, color: enabled ? AppTheme.seed : Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((a['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                a['kind'] == 'text'
                    ? 'Texto fixo · ${(a['content'] ?? '').toString().replaceAll('\n', ' ')}'
                    : '${a['method'] ?? 'GET'} · pergunta: ${a['param_desc'] ?? a['param_name'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
        ),
        Switch(value: enabled, activeThumbColor: AppTheme.seed, onChanged: (v) => _toggleAction(a, v)),
        IconButton(onPressed: () => _editAction(a), icon: const Icon(Icons.edit_outlined, size: 18), tooltip: 'Editar'),
        IconButton(onPressed: () => _deleteAction(a), icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Excluir'),
      ]),
    );
  }

  Future<void> _toggleAction(Map<String, dynamic> a, bool v) async {
    setState(() => a['enabled'] = v);
    final r = await _api.put('/ai/actions/${a['id']}/enabled', {'enabled': v});
    if (!r.ok && mounted) {
      setState(() => a['enabled'] = !v);
      _toast(r.message ?? 'Não foi possível alterar');
    }
  }

  Future<void> _deleteAction(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir ação'),
        content: Text('Excluir "${a['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/ai/actions/${a['id']}');
    if (!mounted) return;
    if (r.ok) {
      _toast('Ação excluída');
      await _load();
    } else {
      _toast(r.message ?? 'Não foi possível excluir');
    }
  }

  Future<void> _editAction(Map<String, dynamic>? existing) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final trigger = TextEditingController(text: existing?['trigger_desc']?.toString() ?? '');
    final paramDesc = TextEditingController(text: existing?['param_desc']?.toString() ?? '');
    final paramName = TextEditingController(text: existing?['param_name']?.toString() ?? 'cpf_cnpj');
    final url = TextEditingController(text: existing?['url']?.toString() ?? '');
    final body = TextEditingController(text: existing?['body_template']?.toString() ?? '');
    final auth = TextEditingController();
    final loginUrl = TextEditingController(text: existing?['login_url']?.toString() ?? '');
    final loginBody = TextEditingController();
    final tokenField = TextEditingController(text: existing?['token_field']?.toString() ?? 'token');
    final content = TextEditingController(text: existing?['content']?.toString() ?? '');
    var kind = (existing?['kind']?.toString() ?? 'http'); // http = consulta API; text = conteúdo escrito
    var method = (existing?['method']?.toString() ?? 'GET').toUpperCase();
    final hasAuth = existing?['has_auth'] == true;
    final hasLogin = existing?['has_login'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Nova ação' : 'Editar ação'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (ex.: 2ª via de boleto)')),
                const SizedBox(height: 10),
                // Como a ação responde. O texto fixo é para quem não tem API:
                // a IA consulta esse conteúdo SÓ quando o assunto aparece.
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'http', icon: Icon(Icons.cloud_outlined, size: 16), label: Text('Consulta em API')),
                    ButtonSegment(value: 'text', icon: Icon(Icons.notes_outlined, size: 16), label: Text('Texto fixo')),
                  ],
                  selected: {kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setLocal(() => kind = v.first),
                ),
                const SizedBox(height: 8),
                TextField(controller: trigger, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Quando a IA deve usar', hintText: 'Ex.: cliente pede 2ª via, boleto, fatura em aberto', alignLabelWithHint: true)),
                if (kind == 'text') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: content,
                    minLines: 6,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Conteúdo que a IA deve usar',
                      alignLabelWithHint: true,
                      hintText: 'Ex.: tabela de preços por cidade, prazos de instalação, o que está na garantia…',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Vale para quem não tem integração. Diferente da base de conhecimento, este texto '
                          'não entra em toda mensagem — a IA busca aqui só quando o assunto aparece, o que sai '
                          'mais barato e mais preciso para tabelas e listas.',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                    ),
                  ),
                ],
                if (kind != 'text') ...[
                const SizedBox(height: 8),
                TextField(controller: paramDesc, decoration: const InputDecoration(labelText: 'O que perguntar ao cliente', hintText: 'Ex.: CPF ou CNPJ (só números)')),
                const SizedBox(height: 8),
                TextField(controller: paramName, decoration: const InputDecoration(labelText: 'Nome da variável (use entre {} na URL)', hintText: 'cpf_cnpj')),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(labelText: 'Método'),
                      items: const [DropdownMenuItem(value: 'GET', child: Text('GET')), DropdownMenuItem(value: 'POST', child: Text('POST'))],
                      onChanged: (v) => setLocal(() => method = v ?? 'GET'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: url, decoration: const InputDecoration(labelText: 'URL da API', hintText: 'https://.../consulta?doc={cpf_cnpj}'))),
                ]),
                if (method == 'POST') ...[
                  const SizedBox(height: 8),
                  TextField(controller: body, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Corpo JSON (pode usar {cpf_cnpj})', alignLabelWithHint: true)),
                ],
                const SizedBox(height: 8),
                TextField(controller: auth, decoration: InputDecoration(labelText: 'Autenticação por header (opcional)', hintText: hasAuth ? 'salvo — deixe em branco p/ manter' : 'Authorization: Bearer xxxxx')),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Login (token → JWT) — opcional', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Para APIs que exigem logar antes (ex.: RODAR). O sistema faz o login e usa o token nas chamadas.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                ),
                const SizedBox(height: 6),
                TextField(controller: loginUrl, decoration: const InputDecoration(labelText: 'URL de login', hintText: 'https://.../login')),
                const SizedBox(height: 8),
                TextField(controller: loginBody, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: 'Corpo do login (com o token)', hintText: hasLogin ? 'salvo — deixe em branco p/ manter' : '{"token":"SEU_TOKEN"}')),
                const SizedBox(height: 8),
                TextField(controller: tokenField, decoration: const InputDecoration(labelText: 'Campo do token na resposta', hintText: 'token')),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.seed), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'kind': kind,
      'content': content.text.trim(),
      'trigger_desc': trigger.text.trim(),
      'param_desc': paramDesc.text.trim(),
      'param_name': paramName.text.trim(),
      'method': method,
      'url': url.text.trim(),
      'body_template': body.text,
      if (auth.text.trim().isNotEmpty) 'auth_header': auth.text.trim(),
      'login_url': loginUrl.text.trim(),
      if (loginBody.text.trim().isNotEmpty) 'login_body': loginBody.text.trim(),
      'token_field': tokenField.text.trim(),
    };
    final r = existing == null
        ? await _api.post('/ai/actions', payload)
        : await _api.put('/ai/actions/${existing['id']}', payload);
    if (!mounted) return;
    if (r.ok) {
      _toast('Ação salva');
      await _load();
    } else {
      _toast(r.message ?? 'Não foi possível salvar');
    }
  }
}
