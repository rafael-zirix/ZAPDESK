import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../core/theme.dart';
import '../inbox/inbox_screen.dart';
import '../models/app_user.dart';

/// Layout principal do painel: rail lateral + conteúdo.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final me = auth.me;

    final items = <_NavItem>[
      _NavItem(Icons.forum_outlined, Icons.forum, 'Atendimento'),
      _NavItem(Icons.settings_outlined, Icons.settings, 'Configurações'),
      if (me?.isSuperAdmin ?? false) _NavItem(Icons.apartment_outlined, Icons.apartment, 'Empresas'),
    ];
    if (_index >= items.length) _index = 0;

    final pages = <Widget>[
      const InboxScreen(),
      const _Placeholder(
        icon: Icons.settings_outlined,
        title: 'Configurações',
        subtitle: 'Aqui você vai conectar o número de WhatsApp, gerir usuários e o seu perfil.',
      ),
      if (me?.isSuperAdmin ?? false)
        const _Placeholder(
          icon: Icons.apartment_outlined,
          title: 'Empresas',
          subtitle: 'Cadastro das empresas clientes da plataforma (super-admin).',
        ),
    ];

    return Scaffold(
      body: Row(
        children: [
          _rail(items, me),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }

  Widget _rail(List<_NavItem> items, AppUser? me) {
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
          for (var i = 0; i < items.length; i++) _railButton(items[i], i),
          const Spacer(),
          if (me != null) _userMenu(me),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _railButton(_NavItem item, int i) {
    final sel = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Tooltip(
        message: item.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _index = i),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: sel ? Colors.white.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(sel ? item.activeIcon : item.icon, color: sel ? Colors.white : Colors.white70, size: 24),
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

class _NavItem {
  _NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: 360,
              child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
            ),
            const SizedBox(height: 16),
            const Chip(label: Text('Em breve'), visualDensity: VisualDensity.compact),
          ],
        ),
      ),
    );
  }
}
