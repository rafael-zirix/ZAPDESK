import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/contact.dart';
import '../models/message_template.dart';
import '../models/support.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<InboxController>().loadTickets());
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
      color: Colors.white,
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
    final slots = <Widget>[
      for (var i = 0; i < inbox.paneCount; i++)
        i < inbox.open.length
            ? _ConversationPane(conv: inbox.open[i], onClose: () => inbox.closePane(inbox.open[i]), templates: inbox.templates)
            : _emptySlot(),
    ];
    return Container(color: AppTheme.bg, child: _grid(slots, inbox.paneCount));
  }

  Widget _grid(List<Widget> slots, int count) {
    Widget col(Widget w) => Expanded(child: w);
    switch (count) {
      case 1:
        return slots[0];
      case 2:
        return Row(children: [col(slots[0]), const VerticalDivider(width: 1), col(slots[1])]);
      case 3:
        return Row(children: [
          col(slots[0]),
          const VerticalDivider(width: 1),
          col(slots[1]),
          const VerticalDivider(width: 1),
          col(slots[2]),
        ]);
      default: // 4 → 2x2
        return Column(children: [
          Expanded(child: Row(children: [col(slots[0]), const VerticalDivider(width: 1), col(slots[1])])),
          const Divider(height: 1),
          Expanded(child: Row(children: [col(slots[2]), const VerticalDivider(width: 1), col(slots[3])])),
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
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                const Text('Conversas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton.filled(
                  onPressed: () => _newConversation(inbox),
                  tooltip: 'Nova conversa',
                  style: IconButton.styleFrom(backgroundColor: AppTheme.seed),
                  icon: const Icon(Icons.add_comment_outlined, color: Colors.white, size: 20),
                ),
              ],
            ),
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
    final sel = inbox.isOpen(t.id);
    return InkWell(
      onTap: () => inbox.openTicket(t),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                      if (sel)
                        const Icon(Icons.check_circle, size: 16, color: AppTheme.seed)
                      else if (t.status == 'open')
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
  const _ConversationPane({required this.conv, required this.onClose, this.templates = const [], this.showBack = false});

  final ConversationController conv;
  final VoidCallback onClose;
  final List<MessageTemplate> templates;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
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
    );
  }

  // Barra de modelos aprovados, acima do compositor.
  Widget _templatesBar(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: conv.sending ? null : () => _pickTemplate(context),
          icon: const Icon(Icons.article_outlined, size: 18),
          label: const Text('Modelos aprovados'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
        ),
      ),
    );
  }

  Future<void> _pickTemplate(BuildContext context) async {
    final picked = await showModalBottomSheet<MessageTemplate>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TemplateSheet(templates: templates),
    );
    if (picked == null || !context.mounted) return;
    final sent = await conv.sendTemplate(picked.name, picked.language);
    if (!sent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar o modelo')));
    }
  }

  Widget _header(BuildContext context) {
    final t = conv.ticket;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (showBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onClose),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.seed.withValues(alpha: 0.15),
            child: Text(t.initials, style: const TextStyle(color: AppTheme.seed, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(t.contactPhone, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
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
        itemBuilder: (_, i) => _bubble(conv.messages[conv.messages.length - 1 - i]),
      ),
    );
  }

  Widget _bubble(Message m) {
    final out = m.isOutbound;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
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
            Text(m.content ?? '', style: const TextStyle(fontSize: 14, height: 1.3)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat('HH:mm').format(m.createdAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                if (out) ...[
                  const SizedBox(width: 4),
                  switch (m.status) {
                    'failed' => const Icon(Icons.error_outline, size: 13, color: Colors.red),
                    'pending' => Icon(Icons.schedule, size: 12, color: Colors.grey.shade500),
                    _ => const Icon(Icons.done_all, size: 13, color: AppTheme.seed),
                  },
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    Future<void> doSend() async {
      final ok = await conv.send();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar a mensagem')));
      }
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: conv.composer,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => doSend(),
              decoration: InputDecoration(
                hintText: 'Mensagem…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: conv.sending ? null : doSend,
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
              color: active ? Colors.white : Colors.transparent,
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
  const _ContactPickerDialog({required this.contacts});
  final List<Contact> contacts;

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
                  const Text('Nova conversa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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

/// Folha de seleção dos modelos aprovados. Toca no modelo (ou em "Enviar") para
/// devolvê-lo a quem abriu — que dispara o envio.
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.templates});
  final List<MessageTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Modelos aprovados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: templates.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final t = templates[i];
                return ListTile(
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    t.bodyText ?? '(sem prévia)',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, height: 1.3),
                  ),
                  trailing: FilledButton(
                    onPressed: () => Navigator.pop(context, t),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
                    child: const Text('Enviar'),
                  ),
                  onTap: () => Navigator.pop(context, t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
