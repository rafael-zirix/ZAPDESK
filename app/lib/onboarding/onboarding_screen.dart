import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../whatsapp/whatsapp_connect_guide.dart';

/// Guia do primeiro acesso: checklist de configuração (com botões que levam à
/// tela certa) + um assistente de IA que tira dúvidas (por conta do HotZap).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onGo, required this.onDone});

  /// Leva o usuário a uma aba do menu pelo rótulo (ex.: 'WhatsApp').
  final void Function(String label) onGo;

  /// Marca o guia como concluído/dispensado (some do menu).
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _api = ApiClient.instance;
  Map<String, dynamic>? _st;
  bool _loading = true;

  final _ask = TextEditingController();
  final List<({bool user, String text})> _chat = [];
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.get('/onboarding/status');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _st = r.ok && r.data is Map ? (r.data as Map).cast<String, dynamic>() : {};
    });
  }

  bool _b(String k) => (_st?[k] ?? false) == true;

  List<({String title, String sub, bool done, bool optional, String go, bool embedded})> get _steps => [
        (title: 'Conecte seu WhatsApp', sub: 'Entre com o Facebook da empresa — a gente configura o resto.', done: _b('has_whatsapp'), optional: false, go: 'WhatsApp', embedded: true),
        (title: 'Ligue o Atendente IA', sub: 'Ative e escreva as instruções (persona e regras).', done: _b('ai_enabled') && _b('has_instructions'), optional: false, go: 'Atendente IA', embedded: false),
        (title: 'Monte a base de conhecimento', sub: 'Horários, contato e o contexto da empresa.', done: _b('has_knowledge'), optional: false, go: 'Atendente IA', embedded: false),
        (title: 'Compre créditos de IA', sub: 'Tokens por PIX ou cartão, na aba Planos.', done: _b('has_credits'), optional: false, go: 'Planos', embedded: false),
        (title: 'Ações da IA (opcional)', sub: 'Buscas na sua API — ex.: 2ª via de boleto.', done: _b('has_actions'), optional: true, go: 'Atendente IA', embedded: false),
        (title: 'Convide a equipe (opcional)', sub: 'Crie logins para os atendentes.', done: ((_st?['team_size'] ?? 1) as num) > 1, optional: true, go: 'Usuários', embedded: false),
      ];

  Future<void> _send() async {
    final q = _ask.text.trim();
    if (q.isEmpty || _asking) return;
    setState(() {
      _chat.add((user: true, text: q));
      _ask.clear();
      _asking = true;
    });
    final r = await _api.post('/onboarding/ask', {'question': q});
    if (!mounted) return;
    final ans = (r.ok && r.data is Map) ? ((r.data as Map)['answer'] ?? '').toString() : (r.message ?? 'Não consegui responder agora.');
    setState(() {
      _chat.add((user: false, text: ans));
      _asking = false;
    });
  }

  /// Abre o guia de conexão do WhatsApp num sheet: o cliente conecta pela Meta
  /// (popup do Facebook) sem sair do onboarding. Ao fechar, recarrega o checklist
  /// para marcar o ✓.
  Future<void> _openConnectGuide() async {
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
            widget.onGo('WhatsApp'); // formulário manual vive na aba WhatsApp
          },
          onConnected: () => Navigator.pop(ctx),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final steps = _steps;
    final doneCount = steps.where((s) => s.done).length;
    return Container(
      color: AppTheme.bg,
      child: LayoutBuilder(
        builder: (context, cons) {
          // Largura FINITA e concreta para o conteúdo: no CanvasKit, um
          // ConstrainedBox(maxWidth) com min 0 deixa os Row/Expanded internos
          // colapsarem a ~0 e o texto renderiza na vertical. SizedBox de largura
          // fixa resolve.
          final w = cons.maxWidth < 720 ? cons.maxWidth - 32 : 720.0;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              Center(
                child: SizedBox(
                  width: w,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: AppTheme.seed, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.rocket_launch, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Bem-vindo(a) ao HotZap', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 4),
                Text('Vamos deixar sua conta pronta em poucos passos — $doneCount de ${steps.length} concluídos.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                _stepsCard(steps),
                const SizedBox(height: 16),
                _assistantCard(),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: widget.onDone,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Concluir o guia'),
                  ),
                ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stepsCard(List<({String title, String sub, bool done, bool optional, String go, bool embedded})> steps) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        for (var i = 0; i < steps.length; i++) _stepRow(steps[i], last: i == steps.length - 1),
      ]),
    );
  }

  Widget _stepRow(({String title, String sub, bool done, bool optional, String go, bool embedded}) s, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0x11000000)))),
      child: Row(children: [
        Icon(s.done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: s.done ? const Color(0xFF1F9D57) : Colors.grey.shade400, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: TextStyle(fontWeight: FontWeight.w600, decoration: s.done ? TextDecoration.lineThrough : null, color: s.done ? Colors.grey : null)),
            Text(s.sub, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ]),
        ),
        const SizedBox(width: 8),
        s.done
            ? const SizedBox.shrink()
            : FilledButton(
                onPressed: s.embedded ? _openConnectGuide : () => widget.onGo(s.go),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
                child: Text(s.embedded ? 'Conectar' : 'Ir'),
              ),
      ]),
    );
  }

  Widget _assistantCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.support_agent, size: 20, color: AppTheme.seed),
          SizedBox(width: 8),
          Text('Assistente de configuração', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        Text('Pergunte qualquer coisa sobre configurar o HotZap — ex.: "como conecto meu número?".',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        for (final m in _chat) _bubble(m),
        if (_asking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Pensando…', style: TextStyle(color: Colors.grey))]),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ask,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Sua dúvida…',
                isDense: true,
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _asking ? null : _send,
            style: IconButton.styleFrom(backgroundColor: AppTheme.seed),
            icon: const Icon(Icons.send, size: 18, color: Colors.white),
          ),
        ]),
      ]),
    );
  }

  Widget _bubble(({bool user, String text}) m) {
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: m.user ? AppTheme.seed.withValues(alpha: 0.12) : AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(m.text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
      ),
    );
  }
}
