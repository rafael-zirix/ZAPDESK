import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/file_pick.dart';
import '../core/geolocation.dart';
import '../inbox/conversation_controller.dart';
import '../inbox/inbox_controller.dart';
import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/support.dart';
import 'theme_mobile.dart';
import 'widgets.dart';

/// Envelope comum: bottom sheet arrastável, com altura limitada à tela.
Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Deixa espaço para o teclado quando o sheet tem campo de texto.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: builder(ctx),
      ),
    ),
  );
}

// --- Fila -------------------------------------------------------------------

/// Pega o próximo da fila. Devolve a conversa puxada, ou null se a fila está vazia.
Future<TicketListItem?> claimNextTicket(InboxController inbox) async {
  final (ticket, _) = await inbox.claimNextTicket();
  return ticket;
}

// --- Nova conversa ----------------------------------------------------------

/// Escolhe um contato da agenda. Usado para iniciar conversa, encaminhar
/// mensagem e enviar cartão de contato — daí o título ser parametrizável.
Future<Contact?> pickContact(
  BuildContext context,
  InboxController inbox, {
  String title = 'Nova conversa',
}) {
  return _sheet<Contact>(context, (ctx) => _ContactPicker(inbox: inbox, title: title));
}

/// Escolhe um contato e abre (ou reabre) a conversa dele. Devolve o ticket.
Future<TicketListItem?> pickContactAndStart(BuildContext context, InboxController inbox) async {
  final contact = await _sheet<Contact>(context, (ctx) => _ContactPicker(inbox: inbox));
  if (contact == null || !context.mounted) return null;
  final (ticket, erro) = await inbox.startConversation(contact);
  if (ticket == null && context.mounted) {
    toast(context, erro ?? 'Não foi possível iniciar a conversa', isError: true);
  }
  return ticket;
}

class _ContactPicker extends StatefulWidget {
  const _ContactPicker({required this.inbox, this.title = 'Nova conversa'});
  final InboxController inbox;
  final String title;

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.inbox.loadContacts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = widget.inbox.contacts;
    final list = q.isEmpty
        ? all
        : all.where((c) => '${c.name ?? ''} ${c.phone}'.toLowerCase().contains(q)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(widget.title),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: MobileTheme.text),
            decoration: InputDecoration(
              hintText: 'Buscar contato',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: MobileTheme.composerField,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (widget.inbox.loadingContacts && all.isEmpty)
          const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 34),
            child: Text(
              all.isEmpty ? 'Nenhum contato cadastrado ainda.' : 'Nada encontrado.',
              style: TextStyle(color: MobileTheme.textFaint),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: Avatar(name: c.displayName, size: 42),
                  title: Text(c.displayName, style: TextStyle(color: MobileTheme.text)),
                  subtitle: Text(c.prettyPhone, style: TextStyle(color: MobileTheme.textFaint)),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// --- Anexos -----------------------------------------------------------------

/// Menu de anexo (o "+" do compositor): documento, câmera, galeria, localização
/// e cartão de contato.
Future<void> attachSheet(BuildContext context, ConversationController conv, InboxController inbox) async {
  final acao = await _sheet<String>(
    context,
    (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Anexar'),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
          child: Wrap(
            alignment: WrapAlignment.start,
            children: [
              _AttachOption(
                  icon: Icons.insert_drive_file, color: const Color(0xFF7B4DD8), label: 'Documento', value: 'doc'),
              _AttachOption(
                  icon: Icons.photo_camera, color: const Color(0xFFE0447C), label: 'Câmera', value: 'camera'),
              _AttachOption(
                  icon: Icons.photo_library, color: const Color(0xFFC13584), label: 'Galeria', value: 'galeria'),
              _AttachOption(
                  icon: Icons.location_on, color: const Color(0xFF25A45B), label: 'Localização', value: 'local'),
              _AttachOption(
                  icon: Icons.person, color: const Color(0xFF2C7BE5), label: 'Contato', value: 'contato'),
            ],
          ),
        ),
      ],
    ),
  );
  if (acao == null || !context.mounted) return;

  switch (acao) {
    case 'doc':
      final f = await pickFile();
      if (f == null || !context.mounted) return;
      await _enviarArquivo(context, conv, f);
    case 'camera':
    case 'galeria':
      final f = await pickImage(fromCamera: acao == 'camera');
      if (f == null || !context.mounted) return;
      await _enviarArquivo(context, conv, f);
    case 'local':
      final pos = await currentPosition();
      if (!context.mounted) return;
      if (pos == null) {
        toast(context, 'Não foi possível obter a localização. Verifique o GPS e a permissão.', isError: true);
        return;
      }
      final ok = await conv.sendLocation(lat: pos.$1, lng: pos.$2);
      if (context.mounted && !ok) toast(context, 'Falha ao enviar a localização', isError: true);
    case 'contato':
      final c = await _sheet<Contact>(context, (ctx) => _ContactPicker(inbox: inbox));
      if (c == null || !context.mounted) return;
      final ok = await conv.sendContact(name: c.displayName, phone: c.phone);
      if (context.mounted && !ok) toast(context, 'Falha ao enviar o contato', isError: true);
  }
}

Future<void> _enviarArquivo(BuildContext context, ConversationController conv, PickedFile f) async {
  final ok = await conv.sendMedia(bytes: f.bytes, filename: f.name, mimeType: f.mimeType);
  if (context.mounted && !ok) toast(context, 'Falha ao enviar o anexo', isError: true);
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 4 - 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(height: 7),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: MobileTheme.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Mensagens prontas ------------------------------------------------------

/// Respostas rápidas (atalhos da empresa) e modelos aprovados da Meta. O texto
/// vai para o compositor — o atendente confere antes de enviar.
Future<void> quickRepliesSheet(
  BuildContext context,
  ConversationController conv,
  InboxController inbox,
) async {
  final janelaAberta = conv.windowOpen;
  await _sheet<void>(context, (ctx) {
    final replies = inbox.quickReplies;
    final templates = inbox.templates;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Mensagens prontas'),
        if (!janelaAberta && !conv.ticket.isInstagram)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4CC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6CF6A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Color(0xFF8A6D00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Passou de 24h desde a última mensagem do cliente: só MODELO aprovado chega até ele.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8A6D00), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (replies.isNotEmpty) ...[
                _SectionLabel('Respostas rápidas'),
                for (final r in replies)
                  ListTile(
                    leading: const Icon(Icons.bolt, color: Color(0xFFCC9A06)),
                    title: Text('/${r.shortcut}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: MobileTheme.text)),
                    subtitle: Text(r.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MobileTheme.textFaint)),
                    onTap: () {
                      conv.composer.text = r.content;
                      conv.composer.selection =
                          TextSelection.collapsed(offset: conv.composer.text.length);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
              if (templates.isNotEmpty) ...[
                _SectionLabel('Modelos aprovados (furam as 24h)'),
                for (final t in templates)
                  ListTile(
                    leading: const Icon(Icons.verified, color: Color(0xFF25A45B)),
                    title: Text(t.name, style: TextStyle(fontWeight: FontWeight.w600, color: MobileTheme.text)),
                    subtitle: Text(t.bodyText ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MobileTheme.textFaint)),
                    onTap: () {
                      conv.stageTemplate(t);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
              if (replies.isEmpty && templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  child: Text(
                    'Nenhuma mensagem pronta cadastrada. As respostas rápidas e os modelos são criados no painel web.',
                    style: TextStyle(color: MobileTheme.textFaint, height: 1.4),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  });
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: MobileTheme.brand,
        ),
      ),
    );
  }
}

// --- Etiquetas --------------------------------------------------------------

/// Marca/desmarca etiquetas da conversa (e cria uma nova na hora).
Future<void> tagsSheet(BuildContext context, ConversationController conv, InboxController inbox) async {
  await _sheet<void>(context, (ctx) => _TagsSheet(conv: conv, inbox: inbox));
}

class _TagsSheet extends StatefulWidget {
  const _TagsSheet({required this.conv, required this.inbox});
  final ConversationController conv;
  final InboxController inbox;

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  late final Set<String> _selected = widget.conv.ticket.tags.map((t) => t.id).toSet();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final tags = widget.inbox.tags;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          'Etiquetas',
          action: IconButton(
            tooltip: 'Nova etiqueta',
            icon: const Icon(Icons.add),
            onPressed: _saving ? null : _criar,
          ),
        ),
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
            child: Text('Nenhuma etiqueta criada. Toque em + para criar a primeira.',
                style: TextStyle(color: MobileTheme.textFaint)),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in tags)
                  CheckboxListTile(
                    value: _selected.contains(t.id),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(t.id);
                              } else {
                                _selected.remove(t.id);
                              }
                            }),
                    title: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: hexColor(t.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text(t.name, style: TextStyle(color: MobileTheme.text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: FilledButton(
            onPressed: _saving ? null : _salvar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar etiquetas'),
          ),
        ),
      ],
    );
  }

  Future<void> _criar() async {
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Nova etiqueta'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Criar')),
          ],
        );
      },
    );
    if (nome == null || nome.isEmpty) return;
    final t = await widget.inbox.createTag(nome);
    if (!mounted) return;
    if (t == null) {
      toast(context, 'Não foi possível criar a etiqueta', isError: true);
      return;
    }
    // Já marca a recém-criada: quem cria quer aplicar.
    setState(() => _selected.add(t.id));
  }

  Future<void> _salvar() async {
    setState(() => _saving = true);
    final r = await widget.conv.setTags(_selected.toList());
    if (!mounted) return;
    setState(() => _saving = false);
    if (r == null) {
      toast(context, 'Não foi possível salvar as etiquetas', isError: true);
      return;
    }
    widget.inbox.applyTicketUpdate(r);
    Navigator.pop(context);
  }
}

// --- Transferir -------------------------------------------------------------

/// Transfere a conversa para outro atendente ou devolve para a fila de um setor.
Future<bool> transferSheet(BuildContext context, ConversationController conv, InboxController inbox) async {
  final r = await _sheet<bool>(context, (ctx) => _TransferSheet(conv: conv, inbox: inbox));
  return r ?? false;
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.conv, required this.inbox});
  final ConversationController conv;
  final InboxController inbox;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _note = TextEditingController();
  String? _userId;
  String? _sectorId;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.inbox.team.where((u) => !u.isSuperAdmin).toList();
    final sectors = widget.inbox.sectors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Transferir conversa'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              // Radio "na mão" (e não RadioListTile) porque os dois grupos são
              // exclusivos ENTRE SI: escolher um setor limpa o atendente e
              // vice-versa — é setor OU pessoa, nunca os dois.
              if (sectors.isNotEmpty) ...[
                _SectionLabel('Para um setor (volta para a fila)'),
                for (final s in sectors)
                  _PickTile(
                    selected: _sectorId == s.id,
                    leading: const Icon(Icons.groups),
                    title: s.name,
                    onTap: _saving
                        ? null
                        : () => setState(() {
                              _sectorId = s.id;
                              _userId = null;
                            }),
                  ),
              ],
              _SectionLabel('Para um atendente'),
              if (team.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text('Nenhum outro atendente cadastrado.',
                      style: TextStyle(color: MobileTheme.textFaint)),
                ),
              for (final u in team)
                _PickTile(
                  selected: _userId == u.id,
                  leading: Avatar(name: u.fullName, size: 36),
                  title: u.fullName,
                  subtitle: u.isAway ? 'Ausente' : 'Disponível',
                  subtitleColor: u.isAway ? Colors.orange : const Color(0xFF25A45B),
                  onTap: _saving
                      ? null
                      : () => setState(() {
                            _userId = u.id;
                            _sectorId = null;
                          }),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _note,
                  maxLines: 2,
                  style: TextStyle(color: MobileTheme.text),
                  decoration: InputDecoration(
                    labelText: 'Motivo (opcional)',
                    hintText: 'Fica no histórico da conversa',
                    filled: true,
                    fillColor: MobileTheme.composerField,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: MobileTheme.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: FilledButton(
            onPressed: _saving || (_userId == null && _sectorId == null) ? null : _transferir,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Transferir'),
          ),
        ),
      ],
    );
  }

  Future<void> _transferir() async {
    setState(() => _saving = true);
    final r = await widget.conv.transfer(
      userId: _userId,
      sectorId: _sectorId,
      note: _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r == null) {
      toast(context, 'Não foi possível transferir', isError: true);
      return;
    }
    widget.inbox.applyTicketUpdate(r);
    Navigator.pop(context, true);
  }
}

/// Linha selecionável com bolinha de rádio à direita.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.leading,
    this.subtitle,
    this.subtitleColor,
  });

  final bool selected;
  final String title;
  final VoidCallback? onTap;
  final Widget? leading;
  final String? subtitle;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(title, style: TextStyle(color: MobileTheme.text)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(fontSize: 12, color: subtitleColor ?? MobileTheme.textFaint)),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? MobileTheme.brand : MobileTheme.textFaint,
      ),
    );
  }
}

// --- Histórico --------------------------------------------------------------

/// Timeline da conversa: quem assumiu, transferências, mudanças de status e notas.
Future<void> eventsSheet(BuildContext context, ConversationController conv) async {
  final eventos = await conv.loadEvents();
  if (!context.mounted) return;
  await _sheet<void>(
    context,
    (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Histórico da conversa'),
        if (eventos.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Text('Nada registrado ainda.', style: TextStyle(color: MobileTheme.textFaint)),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: eventos.length,
              itemBuilder: (_, i) {
                final e = eventos[eventos.length - 1 - i]; // mais recente primeiro
                return ListTile(
                  dense: true,
                  leading: Icon(_iconeEvento(e.kind), size: 20, color: MobileTheme.brand),
                  title: Text(e.describe, style: TextStyle(fontSize: 13.5, color: MobileTheme.text)),
                  subtitle: Text(
                    DateFormat("dd/MM 'às' HH:mm").format(e.createdAt),
                    style: TextStyle(fontSize: 11.5, color: MobileTheme.textFaint),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

IconData _iconeEvento(String kind) => switch (kind) {
      'assigned' => Icons.person_add,
      'transferred' => Icons.swap_horiz,
      'status_changed' => Icons.flag,
      'reopened' => Icons.refresh,
      'note' => Icons.sticky_note_2,
      _ => Icons.circle,
    };

// --- Dados do contato -------------------------------------------------------

/// Ficha do contato: telefone, protocolo, setor, responsável e etiquetas.
Future<void> contactSheet(BuildContext context, TicketListItem t, {AppUser? me}) async {
  await _sheet<void>(
    context,
    (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle('Dados da conversa'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Avatar(name: t.displayName, channel: t.channel, size: 72)),
              const SizedBox(height: 12),
              Center(
                child: Text(t.displayName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MobileTheme.text)),
              ),
              const SizedBox(height: 18),
              _Linha(rotulo: t.isInstagram ? 'Instagram' : 'WhatsApp', valor: t.prettyPhone),
              _Linha(rotulo: 'Protocolo', valor: t.protocol),
              _Linha(rotulo: 'Situação', valor: t.statusLabel),
              if (t.assignedUserName != null) _Linha(rotulo: 'Responsável', valor: t.assignedUserName!),
              if (t.sectorName != null) _Linha(rotulo: 'Setor', valor: t.sectorName!),
              if (t.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final tag in t.tags) MiniChip(label: tag.name, color: hexColor(tag.color))],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Linha extends StatelessWidget {
  const _Linha({required this.rotulo, required this.valor});
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(rotulo, style: TextStyle(fontSize: 13, color: MobileTheme.textFaint)),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: MobileTheme.text)),
          ),
        ],
      ),
    );
  }
}
