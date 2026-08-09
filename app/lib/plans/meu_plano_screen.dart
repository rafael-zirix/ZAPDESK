import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/package.dart';

/// "Meu plano" (admin da empresa): o pacote contratado, a IA em uso com o saldo,
/// e a troca de IA respeitando a regra do saldo. Espelha o protótipo aprovado.
class MeuPlanoScreen extends StatefulWidget {
  const MeuPlanoScreen({super.key});
  @override
  State<MeuPlanoScreen> createState() => _MeuPlanoScreenState();
}

class _MeuPlanoScreenState extends State<MeuPlanoScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  AppPackage? _current;
  List<AppPackage> _packages = [];
  List<Map<String, dynamic>> _offered = [];
  String _aiCurrent = '';
  String _aiPending = '';
  int _aiBalance = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/plan');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is Map) {
        final m = r.data as Map;
        _current = m['current'] is Map ? AppPackage.fromJson((m['current'] as Map).cast<String, dynamic>()) : null;
        _packages = (m['packages'] as List? ?? [])
            .map((e) => AppPackage.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _offered = (m['ai_offered'] as List? ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _aiCurrent = (m['ai_current'] ?? '').toString();
        _aiPending = (m['ai_pending'] ?? '').toString();
        _aiBalance = (m['ai_balance'] ?? 0) as int;
      }
    });
  }

  Map<String, dynamic>? _model(String id) {
    for (final m in _offered) {
      if ((m['model'] ?? '').toString().toLowerCase() == id.toLowerCase()) return m;
    }
    return null;
  }

  String _label(String id) {
    final m = _model(id);
    if (m == null) return id.isEmpty ? 'Padrão' : id;
    final l = (m['label'] ?? '').toString();
    return l.isEmpty ? (m['provider'] ?? id).toString() : l;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(children: [
        const ListHeader(title: 'Meu plano'),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _packageCard(),
                      const SizedBox(height: 18),
                      _aiCard(),
                      const SizedBox(height: 18),
                      _vitrine(),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  // ---- pacote atual ----
  Widget _packageCard() {
    final p = _current;
    if (p == null) {
      return _card([
        Row(children: [
          Icon(Icons.inventory_2_outlined, color: AppTheme.seed),
          const SizedBox(width: 10),
          const Expanded(child: Text('Sem pacote contratado ainda', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        const SizedBox(height: 6),
        Text('Fale com a gente para escolher o pacote da sua empresa.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ]);
    }
    Widget inc(String t, bool on) => Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(on ? Icons.check_circle : Icons.remove_circle_outline,
                size: 18, color: on ? AppTheme.seed : Colors.grey.shade400),
            const SizedBox(width: 9),
            Expanded(child: Opacity(opacity: on ? 1 : .45, child: Text(t, style: const TextStyle(fontSize: 13.5)))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.seed, const Color(0xFF0B7268)])),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SEU PACOTE',
            style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('R\$ ', style: TextStyle(color: Colors.white, fontSize: 15)),
          Text(reaisFromCents(p.priceMonthCents),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1)),
          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('/mês', style: TextStyle(color: Colors.white70))),
        ]),
        const SizedBox(height: 6),
        inc('${p.incLines} linha${p.incLines > 1 ? 's' : ''} de WhatsApp', true),
        inc('${p.incAgents} atendentes', true),
        inc('Atendente de IA 24/7', p.incIA),
        inc('Instagram — Direct e Lead Ads', p.incInstagram),
        inc('Campanhas em massa', p.incCampanhas),
        inc('Métricas e relatórios', p.incMetricas),
        if (p.incIA && p.franchiseCents > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
            child: Text('Franquia de IA: R\$ ${reaisFromCents(p.franchiseCents)}/mês inclusos',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }

  // ---- IA em uso ----
  Widget _aiCard() {
    return _card([
      Row(children: [
        Icon(Icons.smart_toy_outlined, color: AppTheme.seed),
        const SizedBox(width: 10),
        const Text('IA em uso', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const Spacer(),
        if (_model(_aiCurrent)?['logo'] != null) ...[
          aiLogo((_model(_aiCurrent)!['logo']).toString(), size: 26),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
          child: Text(_label(_aiCurrent),
              style: TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SALDO', style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .8)),
            const SizedBox(height: 4),
            Text('${milhar(_aiBalance)} tokens', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        OutlinedButton.icon(
          onPressed: _openSwitch,
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.seed, side: BorderSide(color: AppTheme.seed)),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Trocar de IA'),
        ),
      ]),
      if (_aiPending.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: const Color(0xFFB45309).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB45309).withValues(alpha: .3))),
          child: Row(children: [
            const Icon(Icons.schedule, size: 18, color: Color(0xFFB45309)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Troca agendada para ${_label(_aiPending)} assim que o saldo atual zerar.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
            ),
            TextButton(onPressed: () => _confirmSwitch(_aiCurrent, false, cancelPending: true), child: const Text('Cancelar')),
          ]),
        ),
      ],
    ]);
  }

  void _openSwitch() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true, // senão a folha fica presa em ~metade e corta a lista
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _SwitchSheet(
        offered: _offered,
        current: _aiCurrent,
        onPick: (id) {
          Navigator.pop(context);
          if (id.toLowerCase() != _aiCurrent.toLowerCase()) _chooseHow(id);
        },
        labelOf: _label,
      ),
    );
  }

  // escolha: usar saldo e trocar depois OU trocar agora perdendo o saldo
  void _chooseHow(String targetId) {
    final temSaldo = _aiBalance > 0;
    // dialogCtx é o contexto do PRÓPRIO diálogo: fechá-lo por aqui evita mexer no
    // navigator da tela (era o que apagava o "Meu plano" ao confirmar a troca).
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Trocar para ${_label(targetId)}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!temSaldo)
            const Text('Sem saldo na IA atual — a troca é imediata, nada se perde.')
          else ...[
            _howOpt(Icons.check_circle_outline, AppTheme.seed, 'Usar o saldo e trocar depois',
                'A troca fica agendada. Quando os ${milhar(_aiBalance)} tokens zerarem, a IA passa para ${_label(targetId)}. Nada se perde.',
                () {
              Navigator.pop(dialogCtx);
              _confirmSwitch(targetId, false);
            }),
            const SizedBox(height: 10),
            _howOpt(Icons.warning_amber_rounded, const Color(0xFFB45309), 'Trocar agora',
                'A IA muda na hora. O saldo atual é encerrado: você perde ${milhar(_aiBalance)} tokens.', () {
              Navigator.pop(dialogCtx);
              _confirmSwitch(targetId, true);
            }),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Voltar')),
          if (!temSaldo)
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _confirmSwitch(targetId, false);
                },
                child: const Text('Trocar')),
        ],
      ),
    );
  }

  Widget _howOpt(IconData ic, Color color, String t, String d, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text(d, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            ])),
          ]),
        ),
      );

  // Faz a troca. NÃO mexe em navegação — quem abriu um diálogo o fecha antes de
  // chamar aqui. O caminho do "Cancelar" (banner de troca agendada) não tem
  // diálogo aberto, então também não há nada a fechar.
  Future<void> _confirmSwitch(String model, bool forfeit, {bool cancelPending = false}) async {
    final r = await _api.put('/plan/ai-model', {'model': cancelPending ? _aiCurrent : model, 'forfeit': forfeit});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok
            ? (cancelPending
                ? 'Troca agendada cancelada'
                : forfeit
                    ? 'IA trocada para ${_label(model)}'
                    : 'Troca agendada para ${_label(model)}')
            : (r.message ?? 'Não foi possível trocar'))));
    if (r.ok) await _load();
  }

  // ---- vitrine de pacotes ----
  Widget _vitrine() {
    if (_packages.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text('Outros pacotes',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textOnSurface)),
      ),
      ..._packages.where((p) => p.id != _current?.id).map(_vitrineCard),
      const SizedBox(height: 8),
      Center(
        child: Text('Para trocar de pacote, fale com a gente.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
      ),
    ]);
  }

  Widget _vitrineCard(AppPackage p) {
    final bits = <String>[];
    if (p.incIA) bits.add('IA');
    if (p.incInstagram) bits.add('Instagram');
    if (p.incCampanhas) bits.add('Campanhas');
    if (p.incMetricas) bits.add('Métricas');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 3),
            Text('${p.incLines} linha${p.incLines > 1 ? 's' : ''} · ${p.incAgents} atendentes'
                '${bits.isEmpty ? '' : ' · ${bits.join(' · ')}'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('R\$ ${reaisFromCents(p.priceMonthCents)}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.seed)),
          Text('/mês', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
        ]),
      ]),
    );
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

/// Logo da IA: um badge com a cor da marca e um ícone. Ícones do Material (sempre
/// renderizam) em vez de SVG externo — o projeto não tem flutter_svg, e a CSP
/// bloqueia imagem de fora. Reconhecível pela cor; dá para trocar pelos SVGs
/// exatos depois, se valer a dependência.
Widget aiLogo(String slug, {double size = 34}) {
  late final Color bg;
  late final IconData ic;
  switch (slug) {
    case 'claude':
      bg = const Color(0xFFD97757); // clay da Anthropic
      ic = Icons.brightness_7; // sol/raios ≈ o mark da Anthropic
      break;
    case 'gpt':
      bg = const Color(0xFF10A37F); // verde OpenAI
      ic = Icons.hub;
      break;
    case 'deepseek':
      bg = const Color(0xFF4D6BFE); // azul DeepSeek
      ic = Icons.waves; // baleia/oceano
      break;
    case 'gemini':
    default:
      bg = const Color(0xFF4285F4); // azul Google
      ic = Icons.auto_awesome; // a "faísca" do Gemini
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .28)),
    child: Icon(ic, color: Colors.white, size: size * .56),
  );
}

// Sheet de escolha da IA — mostra os modelos ofertados com o comparativo.
class _SwitchSheet extends StatelessWidget {
  const _SwitchSheet({required this.offered, required this.current, required this.onPick, required this.labelOf});
  final List<Map<String, dynamic>> offered;
  final String current;
  final ValueChanged<String> onPick;
  final String Function(String) labelOf;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Teto de 72% da tela: a folha cresce com a lista e rola dentro, em vez de
      // ficar presa numa altura fixa que corta os modelos.
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      child: SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Escolha a IA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: offered.map((m) {
              final id = (m['model'] ?? '').toString();
              final sel = id.toLowerCase() == current.toLowerCase();
              final best = (m['best_for'] ?? '').toString();
              final avail = m['available'] != false; // sem chave = "em breve"
              return Opacity(
                opacity: avail ? 1 : .55,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      border: Border.all(color: sel ? AppTheme.seed : AppTheme.border, width: sel ? 1.6 : 1),
                      borderRadius: BorderRadius.circular(12),
                      color: sel ? AppTheme.seed.withValues(alpha: .06) : null),
                  child: ListTile(
                    onTap: avail ? () => onPick(id) : null,
                    leading: aiLogo((m['logo'] ?? 'gemini').toString()),
                    title: Row(children: [
                      Flexible(child: Text(labelOf(id), style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (sel) ...[
                        const SizedBox(width: 8),
                        Text('em uso', style: TextStyle(color: AppTheme.seed, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ] else if (!avail) ...[
                        const SizedBox(width: 8),
                        Text('em breve', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ]),
                    subtitle: Text(best.isEmpty ? (m['provider'] ?? '').toString() : best,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    trailing: (sel || !avail) ? null : Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
      ),
    );
  }
}
