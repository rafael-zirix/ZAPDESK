import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin/accounts_screen.dart';
import '../ai/ai_screen.dart';
import '../auth/auth_controller.dart';
import '../core/api_client.dart';
import '../contacts/contacts_screen.dart';
import '../core/theme.dart';
import '../inbox/inbox_screen.dart';
import '../models/app_user.dart';
import '../plans/plans_screen.dart';
import '../settings/settings_screen.dart';
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
  Timer? _tokenPoll;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final label = p.getString(_navKey);
      if (label != null && mounted) setState(() => _savedLabel = label);
    });
    _loadTokens();
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
    final items = <_NavDest>[
      const _NavDest(Icons.forum_outlined, Icons.forum, 'Atendimento', InboxScreen()),
      const _NavDest(Icons.people_outline, Icons.people, 'Contatos', ContactsScreen()),
    ];
    if (me.isAdmin) {
      items.add(const _NavDest(Icons.badge_outlined, Icons.badge, 'Usuários', UsersScreen()));
      items.add(const _NavDest(Icons.chat_outlined, Icons.chat, 'WhatsApp', WhatsAppScreen()));
      items.add(const _NavDest(Icons.article_outlined, Icons.article, 'Modelos', TemplatesScreen()));
      items.add(const _NavDest(Icons.smart_toy_outlined, Icons.smart_toy, 'Atendente IA', AIScreen()));
      items.add(const _NavDest(Icons.credit_card_outlined, Icons.credit_card, 'Planos', PlansScreen()));
      items.add(const _NavDest(Icons.bar_chart_outlined, Icons.bar_chart, 'Consumo', MyUsageScreen()));
      items.add(const _NavDest(Icons.settings_outlined, Icons.settings, 'Configurações', SettingsScreen()));
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
          for (var i = 0; i < dests.length; i++) _railButton(dests, i),
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

  Widget _userMenu(AppUser me) {
    return PopupMenuButton<String>(
      tooltip: me.fullName,
      onSelected: (v) {
        if (v == 'logout') context.read<AuthController>().logout();
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
        const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Sair')])),
      ],
      child: CircleAvatar(
        radius: 20,
        backgroundColor: AppTheme.seed,
        child: Text(me.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
