import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin/accounts_screen.dart';
import '../ai/ai_screen.dart';
import '../auth/auth_controller.dart';
import '../campaigns/campaigns_screen.dart';
import '../core/api_client.dart';
import '../contacts/contacts_screen.dart';
import '../core/theme.dart';
import '../inbox/inbox_screen.dart';
import '../metrics/metrics_screen.dart';
import '../models/app_user.dart';
import '../onboarding/onboarding_screen.dart';
import '../plans/plans_screen.dart';
import '../sectors/sectors_screen.dart';
import '../settings/settings_screen.dart';
import '../tags/tags_screen.dart';
import '../templates/templates_screen.dart';
import '../usage/my_usage_screen.dart';
import '../usage/usage_screen.dart';
import '../users/users_screen.dart';
import '../whatsapp/whatsapp_screen.dart';

/// Layout principal do painel: rail lateral + conteúdo, montado conforme o papel.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _navKey = 'zap_shell_dest';
  static const _peakKey = 'zap_token_peak'; // maior saldo já visto (referência p/ "acabando")
  int _index = 0;
  String? _savedLabel; // aba salva (restaurada 1x após um reload)
  bool _restored = false;

  final _api = ApiClient.instance;
  int? _tokens; // saldo de tokens de IA (null = ainda não sei / não-admin)
  int _tokenPeak = 0;
  bool _aiOn = false;
  bool _onbDone = true; // guia do 1º acesso concluído? (só admin; true evita piscar)
  Timer? _tokenPoll;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final label = p.getString(_navKey);
      if (label != null && mounted) setState(() => _savedLabel = label);
    });
    _loadTokens();
    _loadOnboarding();
    // Mantém o saldo à vista no topo/logout — sempre avisa o admin (fica vermelho perto de acabar).
    _tokenPoll = Timer.periodic(const Duration(seconds: 45), (_) => _loadTokens());
  }

  @override
  void dispose() {
    _tokenPoll?.cancel();
    super.dispose();
  }

  // Busca o saldo de tokens da empresa (endpoint só de admin; não-admin é ignorado
  // em silêncio). Guarda o maior saldo já visto como referência para o alerta.
  Future<void> _loadTokens() async {
    final r = await _api.get('/ai/config');
    if (!mounted || !r.ok || r.data is! Map) return;
    final m = r.data as Map;
    final bal = ((m['token_balance'] ?? 0) as num).toInt();
    final on = (m['ai_enabled'] ?? false) as bool;
    final p = await SharedPreferences.getInstance();
    var peak = p.getInt(_peakKey) ?? 0;
    if (bal > peak) {
      peak = bal;
      await p.setInt(_peakKey, peak);
    }
    if (!mounted) return;
    setState(() {
      _aiOn = on;
      _tokens = bal;
      _tokenPeak = peak;
    });
  }

  // Guia do 1º acesso: só admins têm o endpoint; para os demais o 403 é ignorado
  // e o guia nunca aparece.
  Future<void> _loadOnboarding() async {
    final r = await _api.get('/onboarding/status');
    if (!mounted || !r.ok || r.data is! Map) return;
    final done = ((r.data as Map)['done'] ?? true) == true;
    if (done != _onbDone) setState(() => _onbDone = done);
  }

  // Leva o usuário a uma aba pelo rótulo (botões do checklist do guia).
  void _goToLabel(String label) {
    final me = context.read<AuthController>().me;
    if (me == null) return;
    final dests = _destinations(me);
    final idx = dests.indexWhere((d) => d.label == label);
    if (idx >= 0) _select(dests, idx);
  }

  // Conclui/dispensa o guia: some do menu e cai no Atendimento.
  Future<void> _finishOnboarding() async {
    await _api.post('/onboarding/done', const <String, dynamic>{});
    if (!mounted) return;
    setState(() {
      _onbDone = true;
      _index = 0;
    });
  }

  // Troca de aba: guarda a escolha para sobreviver a um reload (ex.: troca de tema).
  void _select(List<_NavDest> dests, int i) {
    _restored = true; // uma escolha manual cancela qualquer restauração pendente
    setState(() => _index = i);
    SharedPreferences.getInstance().then((p) => p.setString(_navKey, dests[i].label));
  }

  List<_NavDest> _destinations(AppUser me) {
    // Super-admin é o dono da plataforma: só gerencia empresas.
    if (me.isSuperAdmin) {
      return const [
        _NavDest(Icons.apartment_outlined, Icons.apartment, 'Empresas', AccountsScreen()),
        _NavDest(Icons.bar_chart_outlined, Icons.bar_chart, 'Consumo', UsageScreen()),
      ];
    }
    final items = <_NavDest>[];
    if (me.isAdmin && !_onbDone) {
      items.add(_NavDest(Icons.rocket_launch_outlined, Icons.rocket_launch, 'Início',
          OnboardingScreen(onGo: _goToLabel, onDone: _finishOnboarding)));
    }
    // Ícone sem "caixa" (o balão do forum destoava dos demais, todos em traço).
    items.add(const _NavDest(Icons.support_agent_outlined, Icons.support_agent, 'Atendimento', InboxScreen()));
    items.add(const _NavDest(Icons.people_outline, Icons.people, 'Contatos', ContactsScreen()));
    if (me.isAdmin) {
      items.add(const _NavDest(Icons.badge_outlined, Icons.badge, 'Usuários', UsersScreen()));
      items.add(const _NavDest(Icons.workspaces_outline, Icons.workspaces, 'Setores', SectorsScreen()));
      items.add(const _NavDest(Icons.local_offer_outlined, Icons.local_offer, 'Etiquetas', TagsScreen()));
      items.add(const _NavDest(Icons.smartphone_outlined, Icons.smartphone, 'Telefones', WhatsAppScreen()));
      items.add(const _NavDest(Icons.campaign_outlined, Icons.campaign, 'Campanhas', CampaignsScreen()));
      items.add(const _NavDest(Icons.query_stats_outlined, Icons.query_stats, 'Métricas', MetricsScreen()));
      // Os dois vivem no flyout "Modelos" — o nome curto basta sob o cabeçalho.
      items.add(const _NavDest(Icons.article_outlined, Icons.article, 'Conversa',
          TemplatesScreen(usage: 'chat')));
      items.add(const _NavDest(Icons.mark_email_read_outlined, Icons.mark_email_read, 'Campanha',
          TemplatesScreen(usage: 'campaign')));
      items.add(const _NavDest(Icons.smart_toy_outlined, Icons.smart_toy, 'Atendente IA', AIScreen()));
      items.add(const _NavDest(Icons.credit_card_outlined, Icons.credit_card, 'Planos', PlansScreen()));
      items.add(const _NavDest(Icons.bar_chart_outlined, Icons.bar_chart, 'Consumo', MyUsageScreen()));
      items.add(const _NavDest(Icons.key_outlined, Icons.key, 'Tipo de login', SettingsScreen()));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthController>().me;
    if (me == null) return const SizedBox.shrink();

    final dests = _destinations(me);
    // Restaura a aba salva UMA vez, depois de saber os destinos do papel.
    if (!_restored && _savedLabel != null) {
      final idx = dests.indexWhere((d) => d.label == _savedLabel);
      if (idx >= 0) _index = idx;
      _restored = true;
    }
    if (_index >= dests.length) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          _rail(dests, me),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: RepaintBoundary(child: dests[_index].page)),
        ],
      ),
    );
  }

  Widget _rail(List<_NavDest> dests, AppUser me) {
    return Container(
      width: 76,
      color: const Color(0xFF111B21),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppTheme.seed, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 24),
          ..._railItems(dests),
          const Spacer(),
          if (_tokens != null && (_aiOn || _tokens! > 0)) _tokenChip(dests),
          _userMenu(me),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // Saldo de tokens de IA sempre à vista, junto do logout: verde normal, VERMELHO
  // quando cai a 10% (ou menos) do maior saldo já visto — o aviso de "acabando".
  Widget _tokenChip(List<_NavDest> dests) {
    final n = _tokens ?? 0;
    final low = _tokenPeak > 0 ? n <= _tokenPeak * 0.1 : n <= 2000;
    final color = low ? const Color(0xFFEF4444) : const Color(0xFF25D366);
    final aiIdx = dests.indexWhere((d) => d.label == 'Atendente IA');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tooltip(
        message: '$n tokens de IA${low ? ' — acabando, recarregue!' : ''}',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: aiIdx >= 0 ? () => _select(dests, aiIdx) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Column(
              children: [
                Icon(low ? Icons.warning_amber_rounded : Icons.token, color: color, size: 20),
                const SizedBox(height: 2),
                Text(_fmtTokens(n),
                    style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  /// Grupos do rail (flyout à direita). Um grupo só é montado quando o perfil
  /// tem 2+ das abas dele — senão a aba fica solta (ex.: atendente só com Contatos).
  static const _railGroups = [
    (
      label: 'Cadastros',
      icon: Icons.app_registration_outlined,
      activeIcon: Icons.app_registration,
      members: {'Contatos', 'Usuários', 'Setores', 'Etiquetas'},
    ),
    (
      label: 'Modelos',
      icon: Icons.library_books_outlined,
      activeIcon: Icons.library_books,
      members: {'Conversa', 'Campanha'},
    ),
    (
      label: 'Configurações',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      members: {'Telefones', 'Planos', 'Consumo', 'Tipo de login'},
    ),
  ];

  /// Monta os itens do rail: abas soltas viram botão; as de cada grupo viram UM
  /// item com flyout, na posição da primeira delas.
  List<Widget> _railItems(List<_NavDest> dests) {
    // label da aba → grupo dono (só grupos com 2+ abas presentes).
    final owner = <String, int>{};
    for (var g = 0; g < _railGroups.length; g++) {
      final present = [
        for (final d in dests)
          if (_railGroups[g].members.contains(d.label)) d.label,
      ];
      if (present.length >= 2) {
        for (final l in present) {
          owner[l] = g;
        }
      }
    }
    // Abas soltas primeiro; os GRUPOS vão para o FIM da coluna.
    final out = <Widget>[
      for (var i = 0; i < dests.length; i++)
        if (owner[dests[i].label] == null) _railButton(dests, i),
    ];
    for (var g = 0; g < _railGroups.length; g++) {
      final entries = [
        for (var j = 0; j < dests.length; j++)
          if (owner[dests[j].label] == g) (j, dests[j]),
      ];
      if (entries.isEmpty) continue;
      final spec = _railGroups[g];
      out.add(_RailGroup(
        label: spec.label,
        icon: spec.icon,
        activeIcon: spec.activeIcon,
        entries: entries,
        currentIndex: _index,
        onSelect: (j) => _select(dests, j),
      ));
    }
    return out;
  }

  Widget _railButton(List<_NavDest> dests, int i) {
    final dest = dests[i];
    final sel = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Tooltip(
        message: dest.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _select(dests, i),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: sel ? Colors.white.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(sel ? dest.activeIcon : dest.icon, color: sel ? Colors.white : Colors.white70, size: 24),
          ),
        ),
      ),
    );
  }

  // Presença do atendente (manual): bolinha verde (disponível) / laranja (ausente)
  // no avatar; muda pelo menu. Informativa — aparece na transferência.
  String? _presence;

  Widget _userMenu(AppUser me) {
    final presence = _presence ?? me.presence;
    final away = presence == 'away';
    final dotColor = away ? const Color(0xFFF79009) : const Color(0xFF25D366);
    return PopupMenuButton<String>(
      tooltip: '${me.fullName} — ${away ? 'ausente' : 'disponível'}',
      onSelected: (v) {
        if (v == 'logout') context.read<AuthController>().logout();
        if (v == 'presence') {
          final target = away ? 'available' : 'away';
          setState(() => _presence = target);
          _api.put('/support/presence', {'presence': target});
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me.fullName, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
              Text(me.email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(_roleLabel(me.role), style: const TextStyle(fontSize: 11, color: AppTheme.seed, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'presence',
          child: Row(children: [
            Icon(away ? Icons.check_circle_outline : Icons.schedule, size: 18, color: away ? const Color(0xFF25D366) : const Color(0xFFF79009)),
            const SizedBox(width: 8),
            Text(away ? 'Ficar disponível' : 'Ficar ausente'),
          ]),
        ),
        const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Sair')])),
      ],
      child: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.seed,
            child: Text(me.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF111B21), width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) => switch (role) {
        'superadmin' => 'Super-admin',
        'admin' => 'Administrador',
        _ => 'Atendente',
      };
}

class _NavDest {
  const _NavDest(this.icon, this.activeIcon, this.label, this.page);
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget page;
}

/// Item do rail que agrupa abas num FLYOUT à direita: abre no hover (desktop)
/// e também no clique (touch). Uma tolerância de ~250ms deixa o mouse viajar
/// do botão até o flyout sem ele fechar.
class _RailGroup extends StatefulWidget {
  const _RailGroup({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.entries,
    required this.currentIndex,
    required this.onSelect,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final List<(int, _NavDest)> entries; // (índice na lista de abas, aba)
  final int currentIndex;
  final void Function(int index) onSelect;

  @override
  State<_RailGroup> createState() => _RailGroupState();
}

class _RailGroupState extends State<_RailGroup> {
  final _link = LayerLink();
  final _overlay = OverlayPortalController();
  Timer? _closeTimer;

  /// Só UM flyout aberto por vez: ao abrir um grupo, o anterior fecha NA HORA
  /// (sem esperar o timer) — senão um sobrepõe o outro nos grupos vizinhos.
  static _RailGroupState? _openNow;

  bool get _groupActive => widget.entries.any((e) => e.$1 == widget.currentIndex);

  void _open() {
    _closeTimer?.cancel();
    if (_openNow != null && _openNow != this) _openNow!._hideNow();
    _openNow = this;
    if (!_overlay.isShowing) _overlay.show();
  }

  void _hideNow() {
    _closeTimer?.cancel();
    if (_overlay.isShowing) _overlay.hide();
    if (_openNow == this) _openNow = null;
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _hideNow();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    if (_openNow == this) _openNow = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _groupActive;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(6, -4),
          child: Align(
            alignment: Alignment.topLeft,
            child: MouseRegion(
              onEnter: (_) => _open(),
              onExit: (_) => _scheduleClose(),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.surface,
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                        child: Text(widget.label.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: Colors.grey.shade500)),
                      ),
                      for (final e in widget.entries) _flyItem(e.$1, e.$2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _open(),
          onExit: (_) => _scheduleClose(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            child: Tooltip(
              message: widget.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _overlay.isShowing ? _hideNow() : _open(),
                child: Container(
                  height: 52,
                  // Visual IDÊNTICO ao dos botões comuns do rail (pedido do
                  // usuário) — o flyout é a única diferença.
                  decoration: BoxDecoration(
                    color: sel ? Colors.white.withValues(alpha: 0.12) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(sel ? widget.activeIcon : widget.icon,
                      color: sel ? Colors.white : Colors.white70, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Linha do flyout: ícone + nome, destacando a aba ativa. Larguras fixas
  // (nada de Expanded-em-Row — colapsa no CanvasKit web).
  Widget _flyItem(int index, _NavDest d) {
    final active = index == widget.currentIndex;
    return InkWell(
      onTap: () {
        _hideNow();
        widget.onSelect(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: active ? AppTheme.seed.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            Icon(active ? d.activeIcon : d.icon, size: 19, color: active ? AppTheme.seed : Colors.grey.shade600),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: Text(d.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppTheme.seed : null)),
            ),
          ],
        ),
      ),
    );
  }
}
