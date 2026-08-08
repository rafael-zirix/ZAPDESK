import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../inbox/conversation_controller.dart';
import '../inbox/inbox_controller.dart';
import '../models/support.dart';
import 'bubbles.dart';
import 'composer.dart';
import 'sheets.dart';
import 'theme_mobile.dart';
import 'widgets.dart';

/// A conversa. Reusa o [ConversationController] do painel web (mesmas regras de
/// envio, janela de 24h, handoff da IA e polling), só troca a apresentação.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.ticket});
  final TicketListItem ticket;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ConversationController _conv;
  final _scroll = ScrollController();
  Timer? _clock;
  int _lastCount = 0;

  /// Uma chave por mensagem: é o que permite rolar até a citada ao tocar no
  /// bloco de citação.
  final _keys = <String, GlobalKey>{};

  /// Mensagem destacada por um instante depois do "ir até a citada".
  String? _highlightId;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _conv = ConversationController(
      widget.ticket,
      myUserId: auth.me?.id,
      iAmAdmin: auth.me?.isAdmin ?? false,
    );
    _conv.addListener(_onChange);
    // O contador da janela de 24h anda sozinho: sem este relógio ele só
    // atualizaria quando chegasse mensagem nova.
    _clock = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    // Mensagem nova → rola para o fim, como todo app de conversa.
    if (_conv.messages.length != _lastCount) {
      _lastCount = _conv.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(max, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(max);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _conv.removeListener(_onChange);
    _conv.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<InboxController>();
    final me = context.read<AuthController>().me;

    return ChangeNotifierProvider.value(
      value: _conv,
      child: Consumer<ConversationController>(
        builder: (context, conv, _) {
          final t = conv.ticket;
          final semDono = t.assignedUserId == null;
          final minha = t.assignedUserId != null && t.assignedUserId == me?.id;

          return Scaffold(
            backgroundColor: MobileTheme.chatBg,
            appBar: _appBar(context, conv, inbox, t),
            body: Column(
              children: [
                // Assumir é a ação número 1 de quem abre uma conversa nova: fica
                // como faixa, não escondida no menu.
                if (semDono) _FaixaAssumir(conv: conv, inbox: inbox),
                if (!semDono && !minha && t.assignedUserName != null)
                  _Faixa(
                    icone: Icons.info_outline,
                    cor: const Color(0xFF8A6D00),
                    fundo: const Color(0xFFFFF4CC),
                    texto: 'Em atendimento com ${t.assignedUserName}',
                    // Só o administrador toma a conversa de outro (o servidor
                    // recusa para o atendente comum). Oferecer o botão a todos
                    // seria prometer o que a regra não permite.
                    acao: conv.iAmAdmin
                        ? TextButton(
                            onPressed: () => _assumir(conv, inbox, roubando: true),
                            child: const Text('Assumir'),
                          )
                        : null,
                  ),
                if (!conv.windowOpen && !t.isInstagram && conv.messages.isNotEmpty)
                  _Faixa(
                    icone: Icons.schedule,
                    cor: const Color(0xFFB42318),
                    fundo: const Color(0xFFFDE8E8),
                    texto: 'Janela de 24h fechada — só modelo aprovado chega ao cliente.',
                    acao: TextButton(
                      onPressed: () => quickRepliesSheet(context, conv, inbox),
                      child: const Text('Modelos'),
                    ),
                  ),
                Expanded(child: _thread(conv)),
                Composer(conv: conv, inbox: inbox, onSent: _toBottom),
              ],
            ),
          );
        },
      ),
    );
  }

  AppBar _appBar(
    BuildContext context,
    ConversationController conv,
    InboxController inbox,
    TicketListItem t,
  ) {
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: () => contactSheet(context, t),
        child: Row(
          children: [
            Avatar(name: t.displayName, channel: t.channel, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    t.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  Text(
                    _subtitulo(conv, t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Liga/pausa a IA nesta conversa — só quando a empresa tem IA ligada.
        if (inbox.aiEnabled)
          IconButton(
            tooltip: conv.aiPaused ? 'Ativar a IA nesta conversa' : 'Pausar a IA nesta conversa',
            onPressed: conv.togglingAI ? null : conv.toggleAI,
            icon: Icon(
              conv.aiPaused ? Icons.smart_toy_outlined : Icons.smart_toy,
              color: conv.aiPaused ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF7CF5B0),
            ),
          ),
        _menu(context, conv, inbox, t),
      ],
    );
  }

  /// Linha sob o nome: a "tag 24h" (tempo restante da janela) ou a situação.
  String _subtitulo(ConversationController conv, TicketListItem t) {
    if (t.isInstagram) return 'Instagram Direct · ${t.statusLabel}';
    if (conv.messages.isEmpty) return t.statusLabel;
    if (!conv.windowOpen) return 'Janela fechada · ${t.statusLabel}';
    final falta = conv.windowLeft;
    final h = falta.inHours;
    final m = falta.inMinutes.remainder(60);
    return 'Janela: ${h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}min'} · ${t.statusLabel}';
  }

  Widget _menu(
    BuildContext context,
    ConversationController conv,
    InboxController inbox,
    TicketListItem t,
  ) {
    final resolvida = t.status == 'resolved' || t.status == 'closed';
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'assumir':
            await _assumir(conv, inbox);
          case 'transferir':
            final ok = await transferSheet(context, conv, inbox);
            if (ok && context.mounted) toast(context, 'Conversa transferida');
          case 'etiquetas':
            await tagsSheet(context, conv, inbox);
          case 'nota':
            conv.toggleNoteMode();
          case 'resolver':
            await _mudarStatus(conv, inbox, resolvida ? 'open' : 'resolved');
          case 'aguardando':
            await _mudarStatus(conv, inbox, 'pending');
          case 'historico':
            await eventsSheet(context, conv);
          case 'contato':
            await contactSheet(context, t);
        }
      },
      itemBuilder: (_) => [
        if (t.assignedUserId == null)
          const PopupMenuItem(
            value: 'assumir',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_add),
                title: Text('Assumir conversa')),
        ),
        const PopupMenuItem(
          value: 'transferir',
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.swap_horiz),
              title: Text('Transferir')),
        ),
        const PopupMenuItem(
          value: 'etiquetas',
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sell_outlined),
              title: Text('Etiquetas')),
        ),
        PopupMenuItem(
          value: 'nota',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(conv.noteMode ? 'Sair da nota interna' : 'Nota interna'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'resolver',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(resolvida ? Icons.refresh : Icons.check_circle_outline),
            title: Text(resolvida ? 'Reabrir conversa' : 'Marcar como resolvida'),
          ),
        ),
        const PopupMenuItem(
          value: 'aguardando',
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.hourglass_empty),
              title: Text('Aguardando cliente')),
        ),
        const PopupMenuItem(
          value: 'historico',
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history),
              title: Text('Histórico')),
        ),
        const PopupMenuItem(
          value: 'contato',
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.badge_outlined),
              title: Text('Dados da conversa')),
        ),
      ],
    );
  }

  Future<void> _assumir(ConversationController conv, InboxController inbox, {bool roubando = false}) async {
    if (roubando) {
      final ok = await confirm(
        context,
        title: 'Assumir esta conversa?',
        detail: 'Ela está com ${conv.ticket.assignedUserName}. Você passa a ser o responsável.',
        action: 'Assumir',
      );
      if (!ok) return;
    }
    final r = await conv.claim();
    if (!mounted) return;
    if (r == null) {
      toast(context, 'Não foi possível assumir a conversa', isError: true);
      return;
    }
    inbox.applyTicketUpdate(r);
    toast(context, 'Você assumiu a conversa');
  }

  Future<void> _mudarStatus(ConversationController conv, InboxController inbox, String status) async {
    final r = await conv.setStatus(status);
    if (!mounted) return;
    if (r == null) {
      toast(context, 'Não foi possível mudar a situação', isError: true);
      return;
    }
    inbox.applyTicketUpdate(r);
    toast(
      context,
      switch (status) {
        'resolved' => 'Conversa resolvida',
        'pending' => 'Marcada como aguardando cliente',
        'open' => 'Conversa reaberta',
        _ => 'Situação atualizada',
      },
    );
  }

  Widget _thread(ConversationController conv) {
    if (conv.loading && conv.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (conv.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.waving_hand_outlined, size: 46, color: MobileTheme.textFaint.withValues(alpha: 0.6)),
              const SizedBox(height: 14),
              Text(
                'Nenhuma mensagem ainda.\nComece com um modelo aprovado — sem mensagem do cliente, a janela está fechada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MobileTheme.textFaint, height: 1.45),
              ),
            ],
          ),
        ),
      );
    }

    final itens = _comSeparadores(conv.messages);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: itens.length,
      itemBuilder: (context, i) {
        final item = itens[i];
        if (item is DateTime) return SystemNote(_rotuloDia(item));
        final m = item as Message;
        final key = _keys.putIfAbsent(m.id, () => GlobalKey());
        final bolha = Bubble(
          key: key,
          message: m,
          onRetry: m.status == 'failed'
              ? () async {
                  final ok = await conv.retry(m);
                  if (context.mounted && !ok) toast(context, 'Não saiu desta vez', isError: true);
                }
              : null,
          // Sem "Responder" quando a conversa é de outro: o envio voltaria 403.
          onReply: conv.lockedByOther
              ? null
              : () {
                  conv.setReply(m);
                  setState(() {});
                },
          onForward: () => _encaminhar(m),
          onQuoteTap: _irAteMensagem,
        );
        if (_highlightId != m.id) return bolha;
        // Destaque temporário: sem ele, a rolagem até a citada deixa o atendente
        // sem saber qual das bolhas era.
        return ColoredBox(color: MobileTheme.brand.withValues(alpha: 0.12), child: bolha);
      },
    );
  }

  /// Rola até a mensagem citada e a destaca por um instante.
  Future<void> _irAteMensagem(String messageId) async {
    final key = _keys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      // Fora da área construída (ou já expurgada do histórico): avisa em vez de
      // deixar o toque sem resposta nenhuma.
      toast(context, 'A mensagem citada não está nesta parte da conversa');
      return;
    }
    await Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _highlightId = messageId);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _highlightId = null);
  }

  /// Encaminha a mensagem para a conversa de outro contato.
  Future<void> _encaminhar(Message m) async {
    final inbox = context.read<InboxController>();
    final contato = await pickContact(context, inbox, title: 'Encaminhar para');
    if (contato == null || !mounted) return;
    final erro = await _conv.forward(m.id, contato.id);
    if (!mounted) return;
    toast(
      context,
      erro ?? 'Encaminhada para ${contato.displayName}',
      isError: erro != null,
    );
  }

  /// Intercala a data entre as mensagens de dias diferentes.
  List<Object> _comSeparadores(List<Message> msgs) {
    final out = <Object>[];
    DateTime? dia;
    for (final m in msgs) {
      final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (dia == null || d != dia) {
        out.add(d);
        dia = d;
      }
      out.add(m);
    }
    return out;
  }

  String _rotuloDia(DateTime d) {
    final hoje = DateTime.now();
    final dif = DateTime(hoje.year, hoje.month, hoje.day).difference(d).inDays;
    if (dif == 0) return 'Hoje';
    if (dif == 1) return 'Ontem';
    return DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(d);
  }
}

/// Faixa de aviso entre o cabeçalho e a conversa.
class _Faixa extends StatelessWidget {
  const _Faixa({
    required this.icone,
    required this.cor,
    required this.fundo,
    required this.texto,
    this.acao,
  });

  final IconData icone;
  final Color cor;
  final Color fundo;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: fundo,
      padding: EdgeInsets.fromLTRB(14, 8, acao == null ? 14 : 4, 8),
      child: Row(
        children: [
          Icon(icone, size: 17, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 12.5, color: cor, height: 1.3)),
          ),
          ?acao,
        ],
      ),
    );
  }
}

/// Faixa verde de "assumir conversa" — a ação principal de uma conversa sem dono.
class _FaixaAssumir extends StatefulWidget {
  const _FaixaAssumir({required this.conv, required this.inbox});
  final ConversationController conv;
  final InboxController inbox;

  @override
  State<_FaixaAssumir> createState() => _FaixaAssumirState();
}

class _FaixaAssumirState extends State<_FaixaAssumir> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE7F8EE),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.person_add_alt, size: 18, color: Color(0xFF157347)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Ninguém assumiu esta conversa ainda.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF157347), height: 1.3),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _assumir,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: const Color(0xFF157347),
            ),
            child: _busy
                ? const SizedBox(
                    width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('ASSUMIR', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _assumir() async {
    setState(() => _busy = true);
    final r = await widget.conv.claim();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) {
      toast(context, 'Não foi possível assumir a conversa', isError: true);
      return;
    }
    widget.inbox.applyTicketUpdate(r);
    toast(context, 'Você assumiu a conversa');
  }
}
