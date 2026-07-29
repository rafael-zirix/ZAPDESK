import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin/accounts_screen.dart';
import '../auth/auth_controller.dart';
import '../contacts/contacts_screen.dart';
import '../core/theme.dart';
import '../inbox/inbox_screen.dart';
import '../models/app_user.dart';
import '../users/users_screen.dart';
import '../whatsapp/whatsapp_screen.dart';

/// Layout principal do painel: rail lateral + conteúdo, montado conforme o papel.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<_NavDest> _destinations(AppUser me) {
    // Super-admin é o dono da plataforma: só gerencia empresas.
    if (me.isSuperAdmin) {
      return const [_NavDest(Icons.apartment_outlined, Icons.apartment, 'Empresas', AccountsScreen())];
    }
    final items = <_NavDest>[
      const _NavDest(Icons.forum_outlined, Icons.forum, 'Atendimento', InboxScreen()),
      const _NavDest(Icons.people_outline, Icons.people, 'Contatos', ContactsScreen()),
    ];
    if (me.isAdmin) {
      items.add(const _NavDest(Icons.badge_outlined, Icons.badge, 'Usuários', UsersScreen()));
      items.add(const _NavDest(Icons.chat_outlined, Icons.chat, 'WhatsApp', WhatsAppScreen()));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthController>().me;
    if (me == null) return const SizedBox.shrink();

    final dests = _destinations(me);
    if (_index >= dests.length) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          _rail(dests, me),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: dests[_index].page),
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
          for (var i = 0; i < dests.length; i++) _railButton(dests[i], i),
          const Spacer(),
          _userMenu(me),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _railButton(_NavDest dest, int i) {
    final sel = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Tooltip(
        message: dest.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _index = i),
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
