import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/support.dart';
import 'inbox_controller.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _composerCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<InboxController>().loadTickets());
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 720;
    final inbox = context.watch<InboxController>();

    if (narrow) {
      // Mobile: uma coluna por vez.
      return inbox.selected == null ? _list(inbox) : _conversation(inbox, canGoBack: true);
    }
    return Row(
      children: [
        SizedBox(width: 340, child: _list(inbox)),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _conversation(inbox)),
      ],
    );
  }

  // ---------- Lista de conversas ----------
  Widget _list(InboxController inbox) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            alignment: Alignment.centerLeft,
            child: const Text('Conversas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),
          Expanded(child: _listBody(inbox)),
        ],
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
    return RefreshIndicator(
      onRefresh: inbox.loadTickets,
      child: ListView.separated(
        itemCount: inbox.tickets.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (_, i) => _ticketTile(inbox, inbox.tickets[i]),
      ),
    );
  }

  Widget _ticketTile(InboxController inbox, TicketListItem t) {
    final sel = inbox.selected?.id == t.id;
    return InkWell(
      onTap: () => inbox.select(t),
      child: Container(
        color: sel ? AppTheme.sidebarSel : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
              child: Text(t.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
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
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      Text(_time(t.lastMessageAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text('#${t.protocol}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                      if (t.status == 'open')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: const Text('aberta', style: TextStyle(fontSize: 11, color: AppTheme.seed, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Conversa ----------
  Widget _conversation(InboxController inbox, {bool canGoBack = false}) {
    final t = inbox.selected;
    if (t == null) {
      return Container(
        color: AppTheme.bg,
        child: _center(Icons.chat_bubble_outline, 'Selecione uma conversa para começar'),
      );
    }
    return Column(
      children: [
        _convHeader(inbox, t, canGoBack),
        const Divider(height: 1),
        Expanded(child: _thread(inbox)),
        _composer(inbox),
      ],
    );
  }

  Widget _convHeader(InboxController inbox, TicketListItem t, bool canGoBack) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (canGoBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: inbox.deselect),
          if (canGoBack) const SizedBox(width: 4),
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
            child: Text(t.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(t.contactPhone, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thread(InboxController inbox) {
    if (inbox.loadingMessages) return const Center(child: CircularProgressIndicator());
    if (inbox.messages.isEmpty) {
      return Container(color: AppTheme.bg, child: _center(Icons.lock_outline, 'Sem mensagens nesta conversa ainda.'));
    }
    return Container(
      color: AppTheme.bg,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: inbox.messages.length,
        itemBuilder: (_, i) => _bubble(inbox.messages[inbox.messages.length - 1 - i]),
      ),
    );
  }

  Widget _bubble(Message m) {
    final out = m.isOutbound;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
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
            Text(m.content ?? '', style: const TextStyle(fontSize: 15, height: 1.3)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat('HH:mm').format(m.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                if (out) ...[
                  const SizedBox(width: 4),
                  Icon(m.status == 'failed' ? Icons.error_outline : Icons.done_all,
                      size: 14, color: m.status == 'failed' ? Colors.red : AppTheme.seed),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(InboxController inbox) {
    final ctrl = _composerCtrl;
    Future<void> doSend() async {
      final text = ctrl.text;
      if (text.trim().isEmpty) return;
      ctrl.clear();
      final ok = await inbox.send(text);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar a mensagem')));
      }
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => doSend(),
              decoration: InputDecoration(
                hintText: 'Escreva uma mensagem…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: inbox.sending ? null : doSend,
            elevation: 0,
            backgroundColor: AppTheme.seed,
            child: inbox.sending
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ---------- helpers ----------
  Widget _center(IconData icon, String text, {Future<void> Function()? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
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
