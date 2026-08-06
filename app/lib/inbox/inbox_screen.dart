import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../core/config.dart';
import '../core/file_pick.dart';
import '../core/geolocation.dart';
import '../core/theme.dart';
import '../core/theme_controller.dart';
import '../core/url_open.dart';
import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/message_template.dart';
import '../models/support.dart';
import 'audio_view.dart';
import 'conversation_controller.dart';
import 'inbox_controller.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inbox = context.read<InboxController>();
      inbox.myUserId = context.read<AuthController>().me?.id; // p/ o filtro "Minhas"
      inbox.loadTickets();
      inbox.startPolling();
    });
  }

  Future<void> _newConversation(InboxController inbox) async {
    await inbox.loadContacts();
    if (!mounted) return;
    final picked = await showDialog<Contact>(
      context: context,
      builder: (_) => _ContactPickerDialog(contacts: inbox.contacts),
    );
    if (picked != null) {
      final err = await inbox.startWith(picked);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 720;
    final inbox = context.watch<InboxController>();

    if (narrow) {
      // Mobile: uma coluna por vez (sempre 1 painel).
      return inbox.open.isEmpty
          ? _list(inbox)
          : _ConversationPane(
              conv: inbox.open.first,
              onClose: inbox.closeAll,
              templates: inbox.templates,
              showBack: true,
              inbox: inbox,
            );
    }

    return Row(
      children: [
        SizedBox(width: 340, child: _list(inbox)),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: Column(
            children: [
              _topBar(inbox),
              const Divider(height: 1),
              Expanded(child: _panesArea(inbox)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Barra do topo com o seletor de layout ----------
  Widget _topBar(InboxController inbox) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          const Text('Atendimento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('Conversas lado a lado', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(width: 10),
          _LayoutPicker(
            count: inbox.paneCount,
            onPick: inbox.setPaneCount,
          ),
          const SizedBox(width: 6),
          // Alterna tema dia/noite — depois do seletor de janelas.
          Consumer<ThemeController>(
            builder: (context, tc, _) => IconButton(
              tooltip: tc.isDark ? 'Tema claro (dia)' : 'Tema escuro (noite)',
              onPressed: tc.toggle,
              icon: Icon(tc.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Área de painéis (grid conforme paneCount) ----------
  Widget _panesArea(InboxController inbox) {
    if (inbox.open.isEmpty) {
      return Container(
        color: AppTheme.bg,
        child: _center(Icons.chat_bubble_outline,
            'Selecione uma conversa para começar.\nEscolha o layout no alto para atender até 4 ao mesmo tempo.'),
      );
    }
    final multi = inbox.paneCount > 1;
    final slots = [for (var i = 0; i < inbox.paneCount; i++) _slot(inbox, i, multi)];
    return Container(
      color: multi ? AppTheme.gutter : AppTheme.bg,
      padding: multi ? const EdgeInsets.all(2) : EdgeInsets.zero,
      child: _grid(slots, inbox.paneCount),
    );
  }

  // Cor por painel (modo multi): cada conversa aberta ganha uma identidade de cor
  // no cabeçalho, pra não confundir qual é qual. Azul, amarelo, vermelho e o teal
  // da marca (a cor de seleção que já existe).
  static final _paneColors = <Color>[
    const Color(0xFF2563EB), // azul
    const Color(0xFFCA8A04), // amarelo (dourado, legível)
    const Color(0xFFEF4444), // vermelho
    AppTheme.seed, // teal
  ];

  // Um slot do grid. Em modo multi vira um CARTÃO com espaço e borda; a conversa
  // em foco ganha borda verde + sombra, para não confundir qual é qual.
  Widget _slot(InboxController inbox, int i, bool multi) {
    final selected = multi && inbox.selectedPane == i;
    final pane = i < inbox.open.length
        ? _ConversationPane(
            conv: inbox.open[i],
            onClose: () => inbox.closePane(inbox.open[i]),
            templates: inbox.templates,
            selected: selected,
            onSelect: multi ? () => inbox.selectPane(i) : null,
            aiEnabled: inbox.aiEnabled,
            accent: multi ? _paneColors[i % _paneColors.length] : null,
            inbox: inbox,
          )
        : _emptySlot();
    if (!multi) return pane;
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppTheme.seed : AppTheme.border,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? AppTheme.seed.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.06),
            blurRadius: selected ? 14 : 6,
            spreadRadius: selected ? 1 : 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: pane,
    );
  }

  Widget _grid(List<Widget> slots, int count) {
    Widget col(Widget w) => Expanded(child: w);
    switch (count) {
      case 1:
        return slots[0];
      case 2:
        return Row(children: [col(slots[0]), col(slots[1])]);
      case 3:
        return Row(children: [col(slots[0]), col(slots[1]), col(slots[2])]);
      default: // 4 → 2x2
        return Column(children: [
          Expanded(child: Row(children: [col(slots[0]), col(slots[1])])),
          Expanded(child: Row(children: [col(slots[2]), col(slots[3])])),
        ]);
    }
  }

  Widget _emptySlot() {
    return Container(
      color: AppTheme.bg,
      child: _center(Icons.add_comment_outlined, 'Escolha uma conversa\nna lista ao lado'),
    );
  }

  // ---------- Lista de conversas ----------
  Widget _list(InboxController inbox) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                const Text('Conversas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    final err = await inbox.claimNext();
                    if (err != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                  tooltip: 'Pegar o próximo da fila (sem atendente)',
                  icon: const Icon(Icons.playlist_add_check_circle_outlined, color: AppTheme.seed, size: 24),
                ),
                IconButton.filled(
                  onPressed: () => _newConversation(inbox),
                  tooltip: 'Nova conversa',
                  style: IconButton.styleFrom(backgroundColor: AppTheme.seed),
                  icon: const Icon(Icons.add_comment_outlined, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          _filtersBar(inbox),
          const Divider(height: 1),
          Expanded(child: _listBody(inbox)),
        ],
      ),
    );
  }

  // Filtros da lista: status (chips) + setor (menu). "Fechadas" só aparecem
  // escolhendo o filtro delas.
  Widget _filtersBar(InboxController inbox) {
    Widget chip(String label, String value) {
      final sel = inbox.statusFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          selected: sel,
          onSelected: (_) => inbox.setStatusFilter(value),
          selectedColor: AppTheme.seed.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final sector = inbox.sectors.where((s) => s.id == inbox.sectorFilter).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('Todas', 'all'),
            chip('Minhas', 'mine'),
            chip('Novas/abertas', 'open'),
            chip('Aguardando', 'pending'),
            chip('Resolvidas', 'resolved'),
            chip('Fechadas', 'closed'),
            if (inbox.sectors.isNotEmpty)
              PopupMenuButton<String?>(
                tooltip: 'Filtrar por setor',
                onSelected: (v) => inbox.setSectorFilter(v == '' ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('Todos os setores')),
                  for (final s in inbox.sectors) PopupMenuItem(value: s.id, child: Text(s.name)),
                ],
                child: Chip(
                  avatar: Icon(Icons.workspaces_outline, size: 15,
                      color: inbox.sectorFilter != null ? AppTheme.seed : Colors.grey.shade600),
                  label: Text(sector.isEmpty ? 'Setor' : sector.first.name,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: inbox.sectorFilter != null ? FontWeight.w700 : FontWeight.w500,
                          color: inbox.sectorFilter != null ? AppTheme.seed : null)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _listBody(InboxController inbox) {
    if (inbox.loadingTickets && inbox.tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (inbox.ticketsError != null) {
      return _center(Icons.error_outline, inbox.ticketsError!, onRetry: inbox.loadTickets);
    }
    if (inbox.tickets.isEmpty) {
      return _center(Icons.forum_outlined, 'Nenhuma conversa ainda.\nQuando um cliente mandar mensagem, ela aparece aqui.');
    }
    final list = inbox.filteredTickets;
    if (list.isEmpty) {
      return _center(Icons.filter_alt_outlined, 'Nenhuma conversa neste filtro.');
    }
    return RefreshIndicator(
      onRefresh: inbox.loadTickets,
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (_, i) => _ticketTile(inbox, list[i]),
      ),
    );
  }

  // Chip compacto de etiqueta na lista (cor da etiqueta + nome curto).
  Widget _tagDot(TicketTag tag) {
    final color = _hexColor(tag.color);
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(tag.name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  static Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v != null ? Color(v) : AppTheme.seed;
  }

  // Cor do status no chip da lista/painel.
  static Color statusColor(TicketListItem t) => switch (t.status) {
        'open' => t.assignedUserId == null ? const Color(0xFFCA8A04) : const Color(0xFF2563EB),
        'pending' => const Color(0xFF7C3AED),
        'resolved' => const Color(0xFF1F9D57),
        'closed' => Colors.grey,
        _ => Colors.grey,
      };

  Widget _ticketTile(InboxController inbox, TicketListItem t) {
    // Se a conversa está aberta num painel, o contato na lista ganha a MESMA cor
    // da janela dela (azul/amarelo/vermelho/teal), pra casar visualmente.
    final paneIdx = inbox.open.indexWhere((c) => c.ticket.id == t.id);
    final sel = paneIdx >= 0;
    final multi = inbox.paneCount > 1;
    final paneColor = (sel && multi) ? _paneColors[paneIdx % _paneColors.length] : (sel ? AppTheme.seed : null);
    final focused = sel && multi && inbox.selectedPane == paneIdx;
    // Não lida = PENDENTE de abertura (mesmo com a IA já tendo respondido) →
    // destaca em âmbar. Some quando a conversa é aberta (markRead zera o contador).
    final pending = t.unreadCount > 0 && !sel;
    return InkWell(
      onTap: () => inbox.openTicket(t),
      child: Container(
        color: paneColor != null
            ? paneColor.withValues(alpha: focused ? 0.22 : 0.13)
            : (pending ? Colors.amber.withValues(alpha: 0.13) : null),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: (paneColor ?? AppTheme.seed).withValues(alpha: 0.15),
              child: Text(t.initials, style: TextStyle(color: paneColor ?? AppTheme.seed, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: t.unreadCount > 0 ? FontWeight.w800 : FontWeight.w600, fontSize: 15)),
                      ),
                      Text(_time(t.lastMessageAt),
                          style: TextStyle(
                              fontSize: 12,
                              color: t.unreadCount > 0 ? const Color(0xFF25D366) : Colors.grey.shade500,
                              fontWeight: t.unreadCount > 0 ? FontWeight.w700 : FontWeight.normal)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.prettyPhone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                      if (sel)
                        Icon(Icons.check_circle, size: 16, color: paneColor ?? AppTheme.seed)
                      else if (t.unreadCount > 0)
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(10)),
                          child: Text(t.unreadCount > 99 ? '99+' : '${t.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: statusColor(t).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(t.statusLabel,
                              style: TextStyle(fontSize: 11, color: statusColor(t), fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  if (t.assignedUserName != null || t.sectorName != null || t.tags.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(t.assignedUserName != null ? Icons.headset_mic_outlined : Icons.workspaces_outline,
                            size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            [
                              if (t.assignedUserName != null) t.assignedUserName!,
                              if (t.sectorName != null) t.sectorName!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                        for (final tag in t.tags.take(3)) _tagDot(tag),
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

  // ---------- helpers ----------
  Widget _center(IconData icon, String text, {Future<void> Function()? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ],
      ),
    );
  }

  String _time(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }
}

/// Um painel de conversa: escuta o seu [ConversationController] e se atualiza
/// sozinho (independente dos outros painéis abertos).
class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.conv,
    required this.onClose,
    this.templates = const [],
    this.showBack = false,
    this.selected = false,
    this.onSelect,
    this.aiEnabled = false,
    this.accent,
    this.inbox,
  });

  final ConversationController conv;
  final VoidCallback onClose;
  final List<MessageTemplate> templates;
  final bool showBack;
  final bool selected;
  final VoidCallback? onSelect;
  final bool aiEnabled; // Atendente IA ligado na empresa → mostra o toggle no header
  final Color? accent; // cor-identidade do painel (multi) — tinge o cabeçalho e o avatar
  final InboxController? inbox; // setores/equipe p/ transferir + espelhar updates na lista

  @override
  Widget build(BuildContext context) {
    // Clicar em qualquer lugar do painel o "seleciona" (foco) — sem consumir o
    // evento, para os botões/campo internos seguirem funcionando.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: onSelect == null ? null : (_) => onSelect!(),
      child: ListenableBuilder(
        listenable: conv,
        builder: (context, _) {
          return Column(
            children: [
              _header(context),
              const Divider(height: 1),
              Expanded(child: _thread()),
              _templatesBar(context),
              _composer(context),
            ],
          );
        },
      ),
    );
  }

  // Barra de modelos aprovados, acima do compositor.
  Widget _templatesBar(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Builder(
          builder: (btnCtx) => TextButton.icon(
            onPressed: conv.sending ? null : () => _pickTemplate(btnCtx),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Mensagens prontas'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
          ),
        ),
      ),
    );
  }

  // Abre as mensagens prontas num popup compacto ACIMA do botão. Devolve o modelo
  // escolhido (ou null).
  Future<MessageTemplate?> _chooseTemplate(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox;
    final overlayBox = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlayBox),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlayBox),
      ),
      Offset.zero & overlayBox.size,
    );
    return showMenu<MessageTemplate>(
      context: btnCtx,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        PopupMenuItem<MessageTemplate>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TemplateSheet(templates: templates),
        ),
      ],
    );
  }

  // Janela ABERTA: prepara o modelo no campo (o atendente revisa e envia).
  // Janela FECHADA: envia o modelo DIRETO (é o único que a Meta entrega fora das 24h),
  // com uma confirmação — não faz sentido "preparar" num campo bloqueado.
  Future<void> _pickTemplate(BuildContext btnCtx) async {
    final picked = await _chooseTemplate(btnCtx);
    if (picked == null || !btnCtx.mounted) return;
    if (conv.windowOpen) {
      conv.stageTemplate(picked);
      return;
    }
    final go = await showDialog<bool>(
      context: btnCtx,
      builder: (_) => AlertDialog(
        title: const Text('Enviar modelo'),
        content: Text(picked.bodyText?.isNotEmpty == true ? picked.bodyText! : picked.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(btnCtx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(btnCtx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (go != true) return;
    final ok = await conv.sendTemplate(picked.name, picked.language, picked.bodyText ?? '');
    if (!ok && btnCtx.mounted) {
      ScaffoldMessenger.of(btnCtx).showSnackBar(const SnackBar(content: Text('Não foi possível enviar o modelo')));
    }
  }

  Widget _header(BuildContext context) {
    final t = conv.ticket;
    final a = accent; // cor-identidade do painel (multi)
    return Container(
      decoration: BoxDecoration(
        color: a != null
            ? a.withValues(alpha: selected ? 0.22 : 0.14) // cabeçalho colorido por painel (mais forte se em foco)
            : (selected ? AppTheme.sidebarSel : AppTheme.surface),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (showBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onClose),
          CircleAvatar(
            radius: 18,
            backgroundColor: (a ?? AppTheme.seed).withValues(alpha: 0.2),
            child: Text(t.initials, style: TextStyle(color: a ?? AppTheme.seed, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  [
                    t.contactPhone,
                    if (t.assignedUserName != null) t.assignedUserName!,
                    if (t.sectorName != null) t.sectorName!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          _statusChip(),
          if (aiEnabled) _aiToggle(),
          _windowChip(),
          _actionsMenu(context),
          if (!showBack)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Fechar painel',
              onPressed: onClose,
            ),
        ],
      ),
    );
  }

  /// Chip com o status atual da conversa (Novo / Em atendimento / Aguardando…).
  Widget _statusChip() {
    final t = conv.ticket;
    final color = _InboxScreenState.statusColor(t);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(t.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  /// Menu de ações da Fase 1: assumir, transferir, mudar status e histórico.
  Widget _actionsMenu(BuildContext context) {
    final t = conv.ticket;
    final closed = t.status == 'closed';
    return PopupMenuButton<String>(
      tooltip: 'Ações da conversa',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) => _runAction(context, v),
      itemBuilder: (_) => [
        if (!closed) ...[
          const PopupMenuItem(
              value: 'claim',
              child: ListTile(leading: Icon(Icons.pan_tool_alt_outlined), title: Text('Assumir conversa'), dense: true)),
          const PopupMenuItem(
              value: 'transfer',
              child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('Transferir…'), dense: true)),
          const PopupMenuDivider(),
          if (t.status != 'pending')
            const PopupMenuItem(
                value: 'pending',
                child: ListTile(leading: Icon(Icons.hourglass_empty), title: Text('Aguardando cliente'), dense: true)),
          if (t.status != 'resolved')
            const PopupMenuItem(
                value: 'resolved',
                child: ListTile(leading: Icon(Icons.task_alt), title: Text('Marcar como resolvida'), dense: true)),
          const PopupMenuItem(
              value: 'closed',
              child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Fechar conversa'), dense: true)),
        ] else
          const PopupMenuItem(
              value: 'open',
              child: ListTile(leading: Icon(Icons.lock_open_outlined), title: Text('Reabrir conversa'), dense: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'tags',
            child: ListTile(leading: Icon(Icons.label_outline), title: Text('Etiquetas…'), dense: true)),
        const PopupMenuItem(
            value: 'events',
            child: ListTile(leading: Icon(Icons.history), title: Text('Histórico da conversa'), dense: true)),
      ],
    );
  }

  Future<void> _runAction(BuildContext context, String action) async {
    TicketListItem? updated;
    switch (action) {
      case 'claim':
        updated = await conv.claim();
      case 'transfer':
        await _transferDialog(context);
        return;
      case 'pending':
      case 'resolved':
      case 'open':
      case 'closed':
        updated = await conv.setStatus(action);
      case 'tags':
        await _tagsDialog(context);
        return;
      case 'events':
        await _showEvents(context);
        return;
    }
    if (updated != null) {
      inbox?.applyTicketUpdate(updated);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível concluir a ação')));
    }
  }

  Future<void> _transferDialog(BuildContext context) async {
    final result = await showDialog<({String? userId, String? sectorId, String note})>(
      context: context,
      builder: (_) => _TransferDialog(
        team: inbox?.team ?? const [],
        sectors: inbox?.sectors ?? const [],
        currentUserId: conv.ticket.assignedUserId,
        currentSectorId: conv.ticket.sectorId,
      ),
    );
    if (result == null) return;
    final updated = await conv.transfer(userId: result.userId, sectorId: result.sectorId, note: result.note);
    if (updated != null) {
      inbox?.applyTicketUpdate(updated);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível transferir')));
    }
  }

  Future<void> _showEvents(BuildContext context) async {
    final events = await conv.loadEvents();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Histórico — ${conv.ticket.protocol}'),
        content: SizedBox(
          width: 420,
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Nenhum evento ainda.\nTransferências e mudanças de status aparecem aqui.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        switch (e.kind) {
                          'assigned' => Icons.pan_tool_alt_outlined,
                          'transferred' => Icons.swap_horiz,
                          'status_changed' => Icons.flag_outlined,
                          'reopened' => Icons.replay,
                          _ => Icons.notes,
                        },
                        size: 18,
                      ),
                      title: Text(e.describe, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        [
                          DateFormat('dd/MM HH:mm').format(e.createdAt),
                          if (e.note != null && e.note!.isNotEmpty) '“${e.note!}”',
                        ].join(' — '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }

  /// Chip que liga/pausa o Atendente IA nesta conversa (verde = respondendo,
  /// cinza = pausada). O atendente pausa quando quiser assumir; ao reativar, a
  /// IA volta a responder o cliente.
  Widget _aiToggle() {
    final active = !conv.ticket.aiPaused;
    final color = active ? const Color(0xFF1F9D57) : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: active ? 'IA respondendo — toque para pausar' : 'IA pausada — toque para reativar',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: conv.togglingAI ? null : () => conv.toggleAI(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active ? Icons.smart_toy : Icons.smart_toy_outlined, size: 15, color: color),
              const SizedBox(width: 5),
              Text(active ? 'IA ativa' : 'IA off',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ),
    );
  }

  // Chip compacto no header (à direita do "IA ativa") com o status da janela de
  // 24h da Meta: cadeado + "24h", verde = aberta, vermelho = fechada. Não ocupa
  // linha própria (economiza espaço na conversa). Detalhe/tempo restante no tooltip.
  Widget _windowChip() {
    final open = conv.windowOpen;
    final color = open ? const Color(0xFF1F9D57) : const Color(0xFFEF4444);
    final left = conv.windowLeft;
    final tip = open
        ? (left.inHours > 0
            ? 'Janela de 24h aberta · faltam ${left.inHours}h — pode enviar texto livre'
            : 'Janela de 24h aberta · faltam ${left.inMinutes}min — pode enviar texto livre')
        : 'Janela de 24h fechada — só modelo aprovado é entregue';
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: tip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(open ? Icons.lock_open_outlined : Icons.lock_clock_outlined, size: 15, color: color),
            const SizedBox(width: 5),
            Text('24h', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _thread() {
    if (conv.loading && conv.messages.isEmpty) return const Center(child: CircularProgressIndicator());
    if (conv.messages.isEmpty) {
      return Container(
        color: AppTheme.bg,
        alignment: Alignment.center,
        child: Text('Sem mensagens ainda.', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return Container(
      color: AppTheme.bg,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: conv.messages.length,
        itemBuilder: (ctx, i) => _bubble(ctx, conv.messages[conv.messages.length - 1 - i]),
      ),
    );
  }

  Widget _bubble(BuildContext context, Message m) {
    if (m.internal) return _noteBubble(m);
    final out = m.isOutbound;
    // Localização: guardamos o link do mapa no conteúdo — vira um card clicável.
    final mapUrl = _mapUrl(m.content);
    final text = mapUrl != null ? m.content!.replaceAll(mapUrl, '').trim() : (m.content ?? '');
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPressStart: (d) => _msgMenu(context, m, d.globalPosition),
        onSecondaryTapDown: (d) => _msgMenu(context, m, d.globalPosition),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: out ? AppTheme.bubbleOut : AppTheme.bubbleIn,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(out ? 10 : 2),
              bottomRight: Radius.circular(out ? 2 : 10),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 1, offset: const Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.hasMedia) _media(m),
              if (mapUrl != null) _locationCard(mapUrl),
              // Texto e, "ao lado" dele, a hora + os tracinhos de envio — alinhados
              // à direita (estilo WhatsApp). Em texto curto ficam na mesma linha;
              // em texto longo, a hora desce para a direita da última linha.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(text, style: const TextStyle(fontSize: 14, height: 1.3)),
                    ),
                  _meta(m, out),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bolha de NOTA INTERNA: amarela, com autor — só a equipe vê (nada foi ao cliente).
  Widget _noteBubble(Message m) {
    final amber = const Color(0xFFB45309);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.push_pin, size: 13, color: amber),
              const SizedBox(width: 4),
              Text('Nota interna${m.senderName != null ? ' — ${m.senderName}' : ''}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: amber)),
            ]),
            const SizedBox(height: 3),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(m.content ?? '', style: const TextStyle(fontSize: 14, height: 1.3)),
                ),
                Text(DateFormat('HH:mm').format(m.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Extrai o link do Google Maps de uma mensagem de localização (ou null).
  String? _mapUrl(String? content) {
    if (content == null) return null;
    return RegExp(r'https://www\.google\.com/maps\?q=[-0-9.]+,[-0-9.]+').firstMatch(content)?.group(0);
  }

  /// Card de localização (abre o mapa no navegador ao tocar).
  Widget _locationCard(String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => openUrl(url),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 220,
          decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 84,
                decoration: const BoxDecoration(
                  color: Color(0xFFD9E7F8),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Center(child: Icon(Icons.location_on, color: Color(0xFF2F80ED), size: 38)),
              ),
              const Padding(
                padding: EdgeInsets.all(9),
                child: Row(children: [
                  Icon(Icons.map_outlined, size: 16, color: Color(0xFF2F80ED)),
                  SizedBox(width: 6),
                  Text('Ver no mapa', style: TextStyle(color: Color(0xFF2F80ED), fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu de contexto da mensagem (long-press / clique direito): Encaminhar.
  Future<void> _msgMenu(BuildContext ctx, Message m, Offset at) async {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, overlay.size.height - at.dy),
      items: const [
        PopupMenuItem<String>(
          value: 'forward',
          height: 44,
          child: Row(children: [Icon(Icons.forward, size: 18), SizedBox(width: 10), Text('Encaminhar')]),
        ),
      ],
    );
    if (choice == 'forward' && ctx.mounted) await _forwardFlow(ctx, m);
  }

  /// Escolhe o contato de destino e encaminha a mensagem.
  Future<void> _forwardFlow(BuildContext ctx, Message m) async {
    final inbox = ctx.read<InboxController>();
    await inbox.loadContacts();
    if (!ctx.mounted) return;
    final picked = await showDialog<Contact>(
      context: ctx,
      builder: (_) => _ContactPickerDialog(contacts: inbox.contacts, title: 'Encaminhar para'),
    );
    if (picked == null || !ctx.mounted) return;
    final ok = await conv.forward(m.id, picked.id);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(ok ? 'Mensagem encaminhada para ${picked.displayName}' : 'Não foi possível encaminhar')));
  }

  /// Item do menu de anexos (círculo colorido + label).
  PopupMenuItem<String> _attachItem(String value, IconData icon, Color color, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  /// Hora + tracinhos de envio, no canto inferior direito da bolha. Quando a
  /// mensagem falhou, mostra "Reenviar" (toca para tentar de novo).
  Widget _meta(Message m, bool out) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('HH:mm').format(m.createdAt),
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          if (out) ...[
            const SizedBox(width: 3),
            if (m.status == 'failed')
              InkWell(
                onTap: () => conv.retry(m),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline, size: 14, color: Colors.red),
                    SizedBox(width: 2),
                    Text('Reenviar', style: TextStyle(fontSize: 10.5, color: Colors.red, fontWeight: FontWeight.w700)),
                  ]),
                ),
              )
            else
              _statusIcon(m.status),
          ],
        ],
      ),
    );
  }

  /// Tracinhos de envio (estilo WhatsApp): relógio (pendente), ✓✓ (enviado/
  /// entregue), ✓✓ azul (lido) e alerta (falhou).
  Widget _statusIcon(String status) {
    switch (status) {
      case 'failed':
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
      case 'pending':
        return Icon(Icons.access_time, size: 12.5, color: Colors.grey.shade600);
      case 'read':
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF34B7F1));
      default: // sent | delivered | outros
        return Icon(Icons.done_all, size: 15, color: Colors.grey.shade600);
    }
  }

  Widget _media(Message m) {
    final url = Config.apiBaseUrl + m.mediaUrl!;
    if (m.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fileCard(m),
            loadingBuilder: (c, w, p) => p == null
                ? w
                : Container(height: 140, width: 200, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }
    if (m.isAudio) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: audioView(url),
      );
    }
    return _fileCard(m);
  }

  Widget _fileCard(Message m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, color: AppTheme.seed),
          const SizedBox(width: 8),
          Flexible(
            child: Text(m.fileName ?? 'arquivo',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    Future<void> doSend() async {
      // Modo NOTA: grava a nota interna (nunca vai à Meta/cliente).
      final ok = conv.noteMode ? await conv.sendNote() : await conv.send();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(conv.noteMode ? 'Não foi possível salvar a nota' : 'Não foi possível enviar a mensagem')));
      }
    }

    // Popup de respostas rápidas ACIMA do botão ⚡: toque insere o texto no campo.
    Future<void> openQuickReplies(BuildContext btnCtx) async {
      final replies = inbox?.quickReplies ?? const <QuickReply>[];
      final box = btnCtx.findRenderObject() as RenderBox;
      final overlayBox = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlayBox),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlayBox),
        ),
        Offset.zero & overlayBox.size,
      );
      final choice = await showMenu<String>(
        context: btnCtx,
        position: position,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        items: [
          if (replies.isEmpty)
            const PopupMenuItem<String>(
                enabled: false, child: Text('Nenhum atalho ainda.\nCrie em "Gerenciar atalhos".')),
          for (final q in replies)
            PopupMenuItem<String>(
              value: 'use:${q.id}',
              height: 44,
              child: SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('/${q.shortcut}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.seed)),
                    Text(q.content, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'manage',
            height: 40,
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 16),
              SizedBox(width: 8),
              Text('Gerenciar atalhos', style: TextStyle(fontSize: 13)),
            ]),
          ),
        ],
      );
      if (choice == null || !btnCtx.mounted) return;
      if (choice == 'manage') {
        await _manageQuickReplies(btnCtx);
        return;
      }
      final q = replies.firstWhere((x) => 'use:${x.id}' == choice);
      final t = conv.composer;
      t.text = t.text.isEmpty ? q.content : '${t.text} ${q.content}';
      t.selection = TextSelection.collapsed(offset: t.text.length);
    }

    Future<void> pickAndSend(String? accept) async {
      final f = await pickFile(accept: accept);
      if (f == null) return;
      final ok = await conv.sendMedia(
        bytes: f.bytes,
        filename: f.name,
        mimeType: f.mimeType,
        caption: conv.composer.text.trim(),
      );
      if (ok) {
        conv.composer.clear();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar o anexo')));
      }
    }

    Future<void> doSendLocation(BuildContext ctx) async {
      final pos = await currentPosition();
      if (pos == null) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Não foi possível obter a localização. Verifique a permissão do navegador.')));
        }
        return;
      }
      if (!ctx.mounted) return;
      final go = await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Enviar localização'),
          content: const Text('Enviar a sua localização atual para este contato?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (go != true || !ctx.mounted) return;
      final ok = await conv.sendLocation(lat: pos.$1, lng: pos.$2);
      if (!ok && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Não foi possível enviar a localização')));
      }
    }

    Future<void> doSendContact(BuildContext ctx) async {
      final inbox = ctx.read<InboxController>();
      await inbox.loadContacts();
      if (!ctx.mounted) return;
      final picked = await showDialog<Contact>(
        context: ctx,
        builder: (_) => _ContactPickerDialog(contacts: inbox.contacts, title: 'Enviar contato'),
      );
      if (picked == null || !ctx.mounted) return;
      final ok = await conv.sendContact(name: picked.displayName, phone: picked.phone);
      if (!ok && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Não foi possível enviar o contato')));
      }
    }

    Future<void> doSendButtons(BuildContext ctx) async {
      final res = await showDialog<({String body, List<String> buttons})>(
        context: ctx,
        builder: (_) => const _ButtonsBuilderDialog(),
      );
      if (res == null || !ctx.mounted) return;
      final ok = await conv.sendButtons(res.body, res.buttons);
      if (!ok && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar. Botões só funcionam se o cliente te escreveu nas últimas 24h.')));
      }
    }

    Future<void> doSendList(BuildContext ctx) async {
      final res = await showDialog<
          ({String body, String buttonLabel, String sectionTitle, List<({String title, String description})> rows})>(
        context: ctx,
        builder: (_) => const _ListBuilderDialog(),
      );
      if (res == null || !ctx.mounted) return;
      final ok = await conv.sendList(res.body, res.buttonLabel, res.sectionTitle, res.rows);
      if (!ok && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar. O menu só funciona se o cliente te escreveu nas últimas 24h.')));
      }
    }

    // Menu de anexos como popup compacto ACIMA do botão (não tampa o campo).
    Future<void> openAttachMenu(BuildContext btnCtx) async {
      final box = btnCtx.findRenderObject() as RenderBox;
      final overlayBox = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlayBox),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlayBox),
        ),
        Offset.zero & overlayBox.size,
      );
      final choice = await showMenu<String>(
        context: btnCtx,
        position: position,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        items: [
          _attachItem('photos', Icons.photo_library_outlined, const Color(0xFF7B4DFF), 'Fotos e vídeos'),
          _attachItem('file', Icons.insert_drive_file_outlined, const Color(0xFF2F80ED), 'Arquivo'),
          _attachItem('buttons', Icons.smart_button_outlined, const Color(0xFF00A884), 'Botões'),
          _attachItem('list', Icons.list_alt_outlined, const Color(0xFF6941C6), 'Lista / Menu'),
          _attachItem('location', Icons.location_on_outlined, const Color(0xFF12B76A), 'Localização'),
          _attachItem('contact', Icons.person_outline, const Color(0xFFF79009), 'Contato'),
        ],
      );
      if (!btnCtx.mounted) return;
      switch (choice) {
        case 'photos':
          await pickAndSend('image/*,video/*');
        case 'file':
          await pickAndSend(null);
        case 'buttons':
          await doSendButtons(btnCtx);
        case 'list':
          await doSendList(btnCtx);
        case 'location':
          await doSendLocation(btnCtx);
        case 'contact':
          await doSendContact(btnCtx);
      }
    }

    Future<void> startRec() async {
      final ok = await conv.startRecording();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível acessar o microfone. Verifique a permissão do navegador.')),
        );
      }
    }

    void insertEmoji(String emoji) {
      final t = conv.composer;
      final sel = t.selection;
      if (sel.isValid) {
        t.text = t.text.replaceRange(sel.start, sel.end, emoji);
        t.selection = TextSelection.collapsed(offset: sel.start + emoji.length);
      } else {
        t.text = t.text + emoji;
      }
    }

    // Emoji num popup compacto ACIMA do botão (igual ao menu +).
    void openEmoji(BuildContext btnCtx) {
      final box = btnCtx.findRenderObject() as RenderBox;
      final overlayBox = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlayBox),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlayBox),
        ),
        Offset.zero & overlayBox.size,
      );
      showMenu<void>(
        context: btnCtx,
        position: position,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        items: [
          PopupMenuItem<void>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _EmojiGrid(onPick: insertEmoji),
          ),
        ],
      );
    }

    // Durante a gravação, o compositor vira a barra de gravação.
    if (conv.recording) return _recordingBar(context);

    // Fora da janela de 24h a Meta só entrega MODELO aprovado → bloqueia o texto
    // livre e direciona para os modelos. NOTA interna pode sempre (não vai à Meta).
    if (!conv.windowOpen && !conv.noteMode) return _closedWindowComposer(context);

    return Container(
      color: conv.noteMode ? Colors.amber.withValues(alpha: 0.12) : AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          // "+" abre o menu de anexos (popup acima), como o WhatsApp.
          if (!conv.noteMode)
            Builder(
              builder: (btnCtx) => IconButton(
                onPressed: conv.sending ? null : () => openAttachMenu(btnCtx),
                tooltip: 'Anexar',
                icon: Icon(Icons.add, color: Colors.grey.shade700),
              ),
            ),
          // ⚡ respostas rápidas (atalhos de texto da empresa).
          if (!conv.noteMode)
            Builder(
              builder: (btnCtx) => IconButton(
                onPressed: conv.sending ? null : () => openQuickReplies(btnCtx),
                tooltip: 'Respostas rápidas',
                icon: Icon(Icons.bolt_outlined, color: Colors.grey.shade700),
              ),
            ),
          // 📌 alterna o modo NOTA INTERNA (amarelo = ligado).
          IconButton(
            onPressed: conv.sending ? null : conv.toggleNoteMode,
            tooltip: conv.noteMode ? 'Voltar a responder o cliente' : 'Nota interna (só a equipe vê)',
            icon: Icon(conv.noteMode ? Icons.push_pin : Icons.push_pin_outlined,
                color: conv.noteMode ? const Color(0xFFB45309) : Colors.grey.shade700),
          ),
          Expanded(
            child: TextField(
              controller: conv.composer,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => doSend(),
              decoration: InputDecoration(
                hintText: conv.noteMode ? 'Nota interna — o cliente NÃO vê…' : 'Mensagem…',
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                // Emoji DENTRO do campo, à direita (como o WhatsApp).
                suffixIcon: Builder(
                  builder: (emojiCtx) => IconButton(
                    onPressed: () => openEmoji(emojiCtx),
                    tooltip: 'Emoji',
                    icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey.shade600, size: 22),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Botão à direita: microfone (campo vazio) ↔ seta enviar (com texto).
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: conv.composer,
            builder: (_, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              final note = conv.noteMode;
              return IconButton.filled(
                onPressed: conv.sending ? null : (hasText ? doSend : (note ? null : startRec)),
                tooltip: note ? 'Salvar nota interna' : (hasText ? 'Enviar' : 'Gravar áudio'),
                style: IconButton.styleFrom(backgroundColor: note ? const Color(0xFFB45309) : AppTheme.seed),
                icon: conv.sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(note ? Icons.push_pin : (hasText ? Icons.send : Icons.mic), color: Colors.white, size: 20),
              );
            },
          ),
        ],
      ),
    );
  }

  // Compositor bloqueado quando a janela de 24h está fechada: sem texto livre,
  // só o botão de escolher um modelo (que é enviado direto, pois é o único que a
  // Meta entrega fora das 24h).
  Widget _closedWindowComposer(BuildContext context) {
    final noTemplates = templates.isEmpty;
    // Column empilhada (sem Expanded-em-Row, que colapsa no CanvasKit): texto na
    // largura toda com quebra natural + botão embaixo.
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.lock_clock_outlined, size: 16, color: Colors.grey.shade600),
              ),
              const TextSpan(text: '  '),
              TextSpan(
                text: noTemplates
                    ? 'Janela de 24h fechada. Fora dela só um modelo aprovado é entregue — crie um na aba Modelos.'
                    : 'Janela de 24h fechada. Envie um modelo aprovado (o único que a Meta entrega agora).',
              ),
            ]),
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          if (!noTemplates) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (btnCtx) => FilledButton.icon(
                onPressed: conv.sending ? null : () => _pickTemplate(btnCtx),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Enviar modelo'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Nota interna funciona mesmo com a janela fechada (não vai à Meta).
          OutlinedButton.icon(
            onPressed: conv.toggleNoteMode,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB45309),
              side: BorderSide(color: Colors.amber.withValues(alpha: 0.7)),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.push_pin_outlined, size: 17),
            label: const Text('Escrever nota interna'),
          ),
        ],
      ),
    );
  }

  /// Diálogo de gestão das respostas rápidas (criar/editar/excluir atalhos).
  Future<void> _manageQuickReplies(BuildContext context) async {
    final ib = inbox;
    if (ib == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          Future<void> edit({QuickReply? q}) async {
            final shortcut = TextEditingController(text: q?.shortcut ?? '');
            final content = TextEditingController(text: q?.content ?? '');
            final ok = await showDialog<bool>(
              context: dialogCtx,
              builder: (c2) => AlertDialog(
                title: Text(q == null ? 'Novo atalho' : 'Editar atalho'),
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: shortcut,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: 'Atalho (sem espaços)', prefixText: '/', hintText: 'boleto',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: content,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            labelText: 'Texto da resposta', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancelar')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                    onPressed: () => Navigator.pop(c2, true),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            );
            if (ok == true && shortcut.text.trim().isNotEmpty && content.text.trim().isNotEmpty) {
              final err = await ib.saveQuickReply(id: q?.id, shortcut: shortcut.text.trim(), content: content.text.trim());
              if (err != null && dialogCtx.mounted) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text(err)));
              }
              setLocal(() {});
            }
          }

          return AlertDialog(
            title: const Text('Respostas rápidas'),
            content: SizedBox(
              width: 420,
              child: ib.quickReplies.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nenhum atalho ainda.\nCrie textos prontos como /boleto, /horario, /pix…'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: ib.quickReplies.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final q = ib.quickReplies[i];
                        return ListTile(
                          dense: true,
                          title: Text('/${q.shortcut}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.seed)),
                          subtitle: Text(q.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => edit(q: q)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  await ib.deleteQuickReply(q.id);
                                  setLocal(() {});
                                }),
                          ]),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo atalho'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }

  /// Diálogo de etiquetas: marca/desmarca as da conversa e cria novas na hora.
  Future<void> _tagsDialog(BuildContext context) async {
    final ib = inbox;
    if (ib == null) return;
    final selected = {for (final t in conv.ticket.tags) t.id};
    final newTag = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: const Text('Etiquetas da conversa'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ib.tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Nenhuma etiqueta ainda — crie a primeira abaixo.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in ib.tags)
                            FilterChip(
                              label: Text(t.name, style: const TextStyle(fontSize: 12)),
                              selected: selected.contains(t.id),
                              selectedColor: AppTheme.seed.withValues(alpha: 0.2),
                              onSelected: (v) => setLocal(() {
                                if (v) {
                                  selected.add(t.id);
                                } else {
                                  selected.remove(t.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: newTag,
                  decoration: InputDecoration(
                    labelText: 'Nova etiqueta',
                    hintText: 'Ex.: VIP, orçamento, urgente',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final name = newTag.text.trim();
                        if (name.isEmpty) return;
                        final t = await ib.createTag(name);
                        if (t != null) {
                          newTag.clear();
                          setLocal(() => selected.add(t.id));
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final updated = await conv.setTags(selected.toList());
    if (updated != null) {
      inbox?.applyTicketUpdate(updated);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível salvar as etiquetas')));
    }
  }

  // Barra que substitui o compositor durante a gravação de áudio.
  Widget _recordingBar(BuildContext context) {
    Future<void> sendRec() async {
      final ok = await conv.stopAndSendRecording();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar o áudio')));
      }
    }

    final s = conv.recordSeconds;
    final mmss = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: conv.sending ? null : conv.cancelRecording,
            tooltip: 'Cancelar',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          const _RecordingDot(),
          const SizedBox(width: 10),
          Text('Gravando…  $mmss', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton.filled(
            onPressed: conv.sending ? null : sendRec,
            tooltip: 'Enviar áudio',
            style: IconButton.styleFrom(backgroundColor: AppTheme.seed),
            icon: conv.sending
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Seletor de layout no topo (1 a 4 painéis), com mini-prévias como o
/// "Preencher e Organizar" do sistema.
class _LayoutPicker extends StatelessWidget {
  const _LayoutPicker({required this.count, required this.onPick});

  final int count;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3E6E8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var n = 1; n <= 4; n++) _button(n)],
      ),
    );
  }

  Widget _button(int n) {
    final active = count == n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: n == 1 ? '1 conversa' : '$n conversas',
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => onPick(n),
          child: Container(
            width: 34,
            height: 28,
            decoration: BoxDecoration(
              color: active ? AppTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: active ? AppTheme.seed : Colors.transparent, width: 1.4),
              boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)] : null,
            ),
            child: Center(child: _preview(n, active)),
          ),
        ),
      ),
    );
  }

  /// Desenha o mini-layout (barrinhas) representando N painéis.
  Widget _preview(int n, bool active) {
    final color = active ? AppTheme.seed : Colors.grey.shade500;
    Widget cell() => Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5)),
        );
    const gap = SizedBox(width: 2, height: 2);
    switch (n) {
      case 1:
        return SizedBox(width: 16, height: 12, child: cell());
      case 2:
        return SizedBox(width: 16, height: 12, child: Row(children: [Expanded(child: cell()), gap, Expanded(child: cell())]));
      case 3:
        return SizedBox(
            width: 16,
            height: 12,
            child: Row(children: [Expanded(child: cell()), gap, Expanded(child: cell()), gap, Expanded(child: cell())]));
      default:
        return SizedBox(
          width: 16,
          height: 12,
          child: Column(
            children: [
              Expanded(child: Row(children: [Expanded(child: cell()), gap, Expanded(child: cell())])),
              gap,
              Expanded(child: Row(children: [Expanded(child: cell()), gap, Expanded(child: cell())])),
            ],
          ),
        );
    }
  }
}

/// Seletor de contato para iniciar uma nova conversa (com busca).
class _ContactPickerDialog extends StatefulWidget {
  const _ContactPickerDialog({required this.contacts, this.title = 'Nova conversa'});
  final List<Contact> contacts;
  final String title;

  @override
  State<_ContactPickerDialog> createState() => _ContactPickerDialogState();
}

class _ContactPickerDialogState extends State<_ContactPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contacts.where((c) {
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return c.displayName.toLowerCase().contains(q) || c.phone.contains(q);
    }).toList();

    return Dialog(
      child: SizedBox(
        width: 400,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(hintText: 'Buscar contato…', prefixIcon: Icon(Icons.search)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.contacts.isEmpty
                  ? _empty('Nenhum contato cadastrado.\nCadastre em Contatos primeiro.')
                  : filtered.isEmpty
                      ? _empty('Nenhum contato encontrado.')
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
                                child: Text(c.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
                              ),
                              title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(c.prettyPhone),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
        ),
      );
}

/// Monta uma mensagem com botões de resposta rápida (1 a 3). Devolve o corpo + os
/// títulos ao fechar em "Enviar".
class _ButtonsBuilderDialog extends StatefulWidget {
  const _ButtonsBuilderDialog();
  @override
  State<_ButtonsBuilderDialog> createState() => _ButtonsBuilderDialogState();
}

class _ButtonsBuilderDialogState extends State<_ButtonsBuilderDialog> {
  final _body = TextEditingController();
  final List<TextEditingController> _buttons = [TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    _body.dispose();
    for (final c in _buttons) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _titles => _buttons.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
  bool get _valid => _body.text.trim().isNotEmpty && _titles.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar botões'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Mensagem', hintText: 'Ex.: Como posso ajudar?'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Botões (até 3)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            for (int i = 0; i < _buttons.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buttons[i],
                        maxLength: 20,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'Botão ${i + 1}',
                          prefixIcon: const Icon(Icons.smart_button_outlined, size: 18),
                        ),
                      ),
                    ),
                    if (_buttons.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () => setState(() => _buttons.removeAt(i).dispose()),
                      ),
                  ],
                ),
              ),
            if (_buttons.length < 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _buttons.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar botão'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, (body: _body.text.trim(), buttons: _titles)) : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

/// Monta um menu de lista (1 a 10 itens, cada um com título e descrição opcional).
class _ListBuilderDialog extends StatefulWidget {
  const _ListBuilderDialog();
  @override
  State<_ListBuilderDialog> createState() => _ListBuilderDialogState();
}

class _ListBuilderDialogState extends State<_ListBuilderDialog> {
  final _body = TextEditingController();
  final _buttonLabel = TextEditingController(text: 'Ver opções');
  final _sectionTitle = TextEditingController(text: 'Opções');
  final List<({TextEditingController title, TextEditingController desc})> _rows = [
    (title: TextEditingController(), desc: TextEditingController()),
    (title: TextEditingController(), desc: TextEditingController()),
  ];

  @override
  void dispose() {
    _body.dispose();
    _buttonLabel.dispose();
    _sectionTitle.dispose();
    for (final r in _rows) {
      r.title.dispose();
      r.desc.dispose();
    }
    super.dispose();
  }

  List<({String title, String description})> get _validRows => [
        for (final r in _rows)
          if (r.title.text.trim().isNotEmpty) (title: r.title.text.trim(), description: r.desc.text.trim()),
      ];
  bool get _valid => _body.text.trim().isNotEmpty && _validRows.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar lista / menu'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _body,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Mensagem', hintText: 'Ex.: Escolha uma opção:'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buttonLabel,
                      maxLength: 20,
                      decoration: const InputDecoration(isDense: true, counterText: '', labelText: 'Botão da lista'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _sectionTitle,
                      maxLength: 24,
                      decoration: const InputDecoration(isDense: true, counterText: '', labelText: 'Título da seção'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Itens (até 10)',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              for (int i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: _rows[i].title,
                              maxLength: 24,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(isDense: true, counterText: '', hintText: 'Item ${i + 1}'),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _rows[i].desc,
                              maxLength: 72,
                              decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'Descrição (opcional)'),
                            ),
                          ],
                        ),
                      ),
                      if (_rows.length > 1)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: () => setState(() {
                            final r = _rows.removeAt(i);
                            r.title.dispose();
                            r.desc.dispose();
                          }),
                        ),
                    ],
                  ),
                ),
              if (_rows.length < 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _rows.add((title: TextEditingController(), desc: TextEditingController()))),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar item'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, (
                    body: _body.text.trim(),
                    buttonLabel: _buttonLabel.text.trim(),
                    sectionTitle: _sectionTitle.text.trim(),
                    rows: _validRows,
                  ))
              : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

/// Folha de seleção dos modelos aprovados. Toca no modelo (ou em "Enviar") para
/// devolvê-lo a quem abriu — que dispara o envio.
// Corpo compacto das "Mensagens prontas" — exibido num popup (showMenu) acima do
// botão. Toca numa mensagem → Navigator.pop devolve o modelo para o showMenu.
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.templates});
  final List<MessageTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text('Mensagens prontas',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.seed)),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: templates.length,
              separatorBuilder: (_, _) => Divider(height: 1, indent: 14, color: AppTheme.border),
              itemBuilder: (_, i) {
                final t = templates[i];
                // Só a mensagem (toca para colocar no campo — o atendente envia).
                return InkWell(
                  onTap: () => Navigator.pop(context, t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(
                      t.bodyText ?? t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Grade de emojis compacta, exibida num popup acima do compositor (igual ao
/// menu +). Toca para inserir no texto; fica aberta para inserir vários.
class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.onPick});
  final void Function(String) onPick;

  static const _emojis = [
    '😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','🙃','😉','😌','😍','🥰',
    '😘','😗','😙','😚','😋','😛','😜','🤪','😎','🤩','🥳','😏','😒','🙄','😔','😟',
    '👍','👎','👌','🙏','💪','👏','🙌','🤝','👋','✌️','🤙','☝️','✋','🫡','🤗','🤔',
    '❤️','🧡','💛','💚','💙','💜','🖤','🔥','⭐','✨','🎉','🎊','✅','❌','⚠️','❗',
    '❓','💬','📞','📅','🗓️','📍','💰','💳','🧾','📄','📎','📷','🚗','🏍️','🚙','🛻',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 336,
      height: 224,
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(6),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final e in _emojis)
            InkWell(
              onTap: () => onPick(e),
              borderRadius: BorderRadius.circular(6),
              child: Center(child: Text(e, style: const TextStyle(fontSize: 21))),
            ),
        ],
      ),
    );
  }
}

/// Pontinho vermelho pulsante da barra de gravação de áudio.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}

/// Diálogo de transferência: escolhe atendente e/ou setor, com nota opcional.
/// Escolher SÓ o setor devolve a conversa à fila dele (sem dono).
class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    required this.team,
    required this.sectors,
    this.currentUserId,
    this.currentSectorId,
  });

  final List<AppUser> team;
  final List<Sector> sectors;
  final String? currentUserId;
  final String? currentSectorId;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  String? userId;
  String? sectorId;
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    sectorId = widget.currentSectorId;
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = userId != null || (sectorId != null && sectorId != widget.currentSectorId);
    return AlertDialog(
      title: const Text('Transferir conversa'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: userId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Atendente', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('— manter / devolver à fila —')),
                for (final u in widget.team)
                  if (u.id != widget.currentUserId)
                    DropdownMenuItem(
                        value: u.id,
                        child: Text('${u.fullName}${u.isAway ? '  (ausente)' : ''}',
                            overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => userId = v),
            ),
            const SizedBox(height: 12),
            if (widget.sectors.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: sectorId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Setor', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— sem setor —')),
                  for (final s in widget.sectors)
                    DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => sectorId = v),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota para quem recebe (opcional)',
                hintText: 'Ex.: cliente quer falar sobre o boleto',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          onPressed: !canSend
              ? null
              : () => Navigator.pop(context, (
                    userId: userId,
                    sectorId: sectorId != widget.currentSectorId ? sectorId : null,
                    note: note.text.trim(),
                  )),
          child: const Text('Transferir'),
        ),
      ],
    );
  }
}
