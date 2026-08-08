import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../inbox/inbox_controller.dart';
import '../models/support.dart';
import 'chat_screen.dart';
import 'push.dart';
import 'sheets.dart';
import 'theme_mobile.dart';
import 'widgets.dart';

/// Lista de conversas — a tela inicial do app, no formato do WhatsApp: avatar,
/// nome, prévia da última mensagem, hora e o balãozinho de não lidas.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Depois do primeiro frame: precisa do context para ler o AuthController.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inbox = context.read<InboxController>();
      inbox.myUserId = context.read<AuthController>().me?.id;
      inbox.loadTickets();
      inbox.startPolling();
    });
    Push.instance.abrirTicket.addListener(_onPush);
  }

  @override
  void dispose() {
    Push.instance.abrirTicket.removeListener(_onPush);
    _search.dispose();
    super.dispose();
  }

  /// Tocou na notificação: abre aquela conversa. Se ela ainda não está na lista
  /// (chegou com o app fechado), recarrega antes de desistir.
  Future<void> _onPush() async {
    final id = Push.instance.abrirTicket.value;
    if (id == null || !mounted) return;
    Push.instance.abrirTicket.value = null; // consome, para não reabrir depois
    final inbox = context.read<InboxController>();
    var i = inbox.tickets.indexWhere((t) => t.id == id);
    if (i < 0) {
      await inbox.loadTickets();
      if (!mounted) return;
      i = inbox.tickets.indexWhere((t) => t.id == id);
    }
    if (i < 0) return;
    // Empilhar duas conversas confundiria o "voltar": fecha a que estiver aberta.
    Navigator.of(context).popUntil((r) => r.isFirst);
    _open(inbox.tickets[i]);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<InboxController>();
    final auth = context.watch<AuthController>();
    final chats = inbox.filteredTickets;

    return Scaffold(
      backgroundColor: MobileTheme.listBg,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 17),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Buscar nome ou telefone',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
                  border: InputBorder.none,
                ),
                onChanged: inbox.setSearch,
              )
            : const Text('HotZap'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Fechar busca' : 'Buscar',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                inbox.setSearch('');
              }
            },
          ),
          _menu(context, inbox, auth),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _Filters(inbox: inbox),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova conversa',
        onPressed: () => _startNew(inbox),
        child: const Icon(Icons.chat),
      ),
      body: RefreshIndicator(
        onRefresh: inbox.loadTickets,
        child: _body(inbox, chats),
      ),
    );
  }

  Widget _body(InboxController inbox, List<TicketListItem> chats) {
    if (inbox.loadingTickets && inbox.tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (inbox.ticketsError != null && inbox.tickets.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Não foi possível carregar',
        detail: inbox.ticketsError!,
        action: FilledButton.tonal(onPressed: inbox.loadTickets, child: const Text('Tentar de novo')),
      );
    }
    if (chats.isEmpty) {
      final queue = inbox.statusFilter == 'queue';
      return _Empty(
        icon: queue ? Icons.inbox : Icons.chat_bubble_outline,
        title: queue ? 'Nenhuma conversa na fila' : 'Nenhuma conversa aqui',
        detail: inbox.searchQuery.trim().isNotEmpty
            ? 'Nada encontrado para "${inbox.searchQuery.trim()}".'
            : queue
                ? 'Tudo que chegou já tem responsável.'
                : 'Quando um cliente mandar mensagem, ela aparece aqui.',
      );
    }
    return ListView.separated(
      // Sempre rolável, senão o "puxar para atualizar" não funciona com lista curta.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: chats.length,
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(left: 84),
        child: Divider(height: 0.5, color: MobileTheme.border),
      ),
      itemBuilder: (context, i) => _ChatTile(ticket: chats[i], onTap: () => _open(chats[i])),
    );
  }

  Future<void> _open(TicketListItem t) async {
    t.unreadCount = 0; // zera na hora (o backend marca lida ao abrir)
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(ticket: t)));
    if (!mounted) return;
    setState(() {}); // reflete status/dono alterados dentro da conversa
  }

  /// Nova conversa: escolhe um contato e abre a conversa dele.
  Future<void> _startNew(InboxController inbox) async {
    final ticket = await pickContactAndStart(context, inbox);
    if (ticket != null && mounted) _open(ticket);
  }

  Widget _menu(BuildContext context, InboxController inbox, AuthController auth) {
    final away = auth.me?.isAway ?? false;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'queue':
            final ticket = await claimNextTicket(inbox);
            if (!context.mounted) return;
            if (ticket == null) {
              toast(context, 'Nenhuma conversa esperando na fila');
            } else {
              _open(ticket);
            }
          case 'presence':
            await auth.setPresence(!away);
          case 'theme':
            await context.read<MobileThemeController>().toggle();
          case 'logout':
            final ok = await confirm(context, title: 'Sair do app?', action: 'Sair');
            if (!ok) return;
            // Descadastra o aparelho ANTES de perder o token de acesso, senão o
            // atendente continuaria recebendo notificações da empresa.
            await Push.instance.desligar();
            if (context.mounted) await auth.logout();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'queue',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_for_offline_outlined),
            title: Text('Pegar próximo da fila'),
          ),
        ),
        PopupMenuItem(
          value: 'presence',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(away ? Icons.do_not_disturb_on : Icons.check_circle,
                color: away ? Colors.orange : const Color(0xFF25D366)),
            title: Text(away ? 'Ficar disponível' : 'Ficar ausente'),
          ),
        ),
        const PopupMenuItem(
          value: 'theme',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.brightness_6_outlined),
            title: Text('Tema claro/escuro'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sair'),
          ),
        ),
      ],
    );
  }
}

/// Chips de filtro logo abaixo da barra (Tudo, Minhas, Novos…).
class _Filters extends StatelessWidget {
  const _Filters({required this.inbox});
  final InboxController inbox;

  static const _tabs = [
    ('all', 'Tudo'),
    ('mine', 'Minhas'),
    ('queue', 'Novos'),
    ('pending', 'Aguardando'),
    ('resolved', 'Resolvidas'),
  ];

  @override
  Widget build(BuildContext context) {
    // Quantos esperam na fila: o número que o atendente precisa ver sem abrir nada.
    final queued = inbox.tickets.where((t) => t.status == 'open' && t.assignedUserId == null).length;
    return Container(
      height: 46,
      color: MobileTheme.appBar,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final (key, label) in _tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: _FilterChip(
                label: label,
                count: key == 'queue' && queued > 0 ? queued : null,
                active: inbox.statusFilter == key,
                onTap: () => inbox.setStatusFilter(key),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap, this.count});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: active ? 0.22 : 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: active ? 1 : 0.82),
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('$count',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma linha da lista.
class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.ticket, required this.onTap});
  final TicketListItem ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = ticket.unreadCount;
    final unassigned = ticket.assignedUserId == null && ticket.status == 'open';
    final preview = ticket.preview;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(name: ticket.displayName, channel: ticket.channel, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                            color: MobileTheme.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        shortTime(ticket.lastMessageAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
                          color: unread > 0 ? const Color(0xFF25D366) : MobileTheme.textFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (ticket.previewIsOurs && preview.isNotEmpty) ...[
                        Icon(
                          ticket.lastMessageInternal ? Icons.sticky_note_2 : Icons.done_all,
                          size: 15,
                          color: ticket.lastMessageInternal ? const Color(0xFFCC9A06) : MobileTheme.textFaint,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          preview.isEmpty ? 'Toque para abrir a conversa' : preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: preview.isEmpty ? FontStyle.italic : FontStyle.normal,
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            color: unread > 0 ? MobileTheme.text : MobileTheme.textFaint,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 21),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            borderRadius: BorderRadius.all(Radius.circular(11)),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (unassigned ||
                      ticket.assignedUserName != null ||
                      ticket.sectorName != null ||
                      ticket.tags.isNotEmpty ||
                      ticket.status == 'pending' ||
                      ticket.status == 'resolved') ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        // "Novo" é a informação mais acionável da lista: ninguém assumiu.
                        if (unassigned) const MiniChip(label: 'Novo', color: Color(0xFF25D366), filled: true),
                        if (ticket.status == 'pending')
                          const MiniChip(label: 'Aguardando', color: Color(0xFFCC9A06)),
                        if (ticket.status == 'resolved')
                          const MiniChip(label: 'Resolvido', color: Color(0xFF667781)),
                        if (ticket.assignedUserName != null)
                          MiniChip(
                              label: ticket.assignedUserName!, color: MobileTheme.brand, icon: Icons.person),
                        if (ticket.sectorName != null)
                          MiniChip(
                              label: ticket.sectorName!, color: const Color(0xFF6C6BCE), icon: Icons.groups),
                        for (final tag in ticket.tags) MiniChip(label: tag.name, color: hexColor(tag.color)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.detail, this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // ListView para o "puxar para atualizar" continuar funcionando no vazio.
    return ListView(
      children: [
        const SizedBox(height: 90),
        Icon(icon, size: 58, color: MobileTheme.textFaint.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Center(
          child: Text(title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: MobileTheme.text)),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: MobileTheme.textFaint, height: 1.4)),
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          Center(child: action!),
        ],
      ],
    );
  }
}

/// Hora no formato da lista do WhatsApp: hoje = 14:32, ontem = "Ontem", na
/// semana = "seg", antes = 07/08/26.
String shortTime(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days == 0) return DateFormat('HH:mm').format(t);
  if (days == 1) return 'Ontem';
  if (days < 7) return DateFormat('EEE', 'pt_BR').format(t);
  return DateFormat('dd/MM/yy').format(t);
}
