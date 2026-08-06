import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';
import '../models/campaign.dart';
import '../models/contact.dart';
import '../models/message_template.dart';
import '../models/support.dart';
import 'campaign_detail.dart';

/// Campanhas de WhatsApp (admin): dispara um modelo aprovado para uma audiência,
/// com ritmo controlado. Autocontida (estado local + polling do funil).
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final _api = ApiClient.instance;

  List<Campaign> campaigns = [];
  bool loading = false;
  String? error;
  Timer? _poll;

  /// Campanha aberta na tela de detalhe (null = lista).
  Campaign? selected;

  @override
  void initState() {
    super.initState();
    _load();
    // O funil muda enquanto o worker envia — atualiza sozinho.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    final r = await _api.get('/campaigns');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (r.ok && r.data is List) {
        campaigns = (r.data as List).map((e) => Campaign.fromJson(e as Map<String, dynamic>)).toList();
      } else if (!silent) {
        error = r.message ?? 'Erro ao carregar campanhas';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    if (sel != null) {
      return CampaignDetailScreen(
        campaign: sel,
        onBack: () => setState(() => selected = null),
        onCopy: (c) {
          setState(() => selected = null);
          _openWizard(copyOf: c);
        },
        onChanged: ({bool deleted = false}) {
          if (deleted) setState(() => selected = null);
          _load(silent: true);
        },
      );
    }
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Campanhas', actionLabel: 'Nova campanha', onAction: _openWizard),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (loading && campaigns.isEmpty) return const Center(child: CircularProgressIndicator());
    if (error != null) return _empty(Icons.error_outline, error!, retry: _load);
    if (campaigns.isEmpty) {
      return _empty(Icons.campaign_outlined,
          'Nenhuma campanha ainda.\nDispare um modelo aprovado para os seus contatos —\npromoções, avisos, reativação de clientes…');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: campaigns.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 24),
      itemBuilder: (_, i) => _tile(campaigns[i]),
    );
  }

  Color _statusColor(Campaign c) => switch (c.status) {
        'scheduled' => const Color(0xFFCA8A04),
        'running' => const Color(0xFF2563EB),
        'paused' => const Color(0xFF7C3AED),
        'done' => const Color(0xFF1F9D57),
        _ => Colors.grey,
      };

  Widget _tile(Campaign c) {
    final f = c.funnel;
    final progress = f.total == 0 ? 0.0 : f.done / f.total;
    return InkWell(
      onTap: () => setState(() => selected = c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: _statusColor(c).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Text(c.statusLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(c))),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  onSelected: (a) => _action(c, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'open',
                        child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Abrir'), dense: true)),
                    const PopupMenuItem(
                        value: 'copy',
                        child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Copiar campanha'), dense: true)),
                    if (c.isActive) const PopupMenuDivider(),
                    if (c.isActive && c.status != 'paused')
                      const PopupMenuItem(
                          value: 'pause',
                          child: ListTile(leading: Icon(Icons.pause), title: Text('Pausar'), dense: true)),
                    if (c.status == 'paused')
                      const PopupMenuItem(
                          value: 'resume',
                          child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Retomar'), dense: true)),
                    if (c.isActive)
                      const PopupMenuItem(
                          value: 'cancel',
                          child: ListTile(leading: Icon(Icons.stop), title: Text('Cancelar'), dense: true)),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Excluir', style: TextStyle(color: Colors.red)),
                            dense: true)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Modelo ${c.templateName} · ${c.ratePerMin}/min · ${DateFormat('dd/MM HH:mm').format(c.scheduledAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                color: _statusColor(c),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${f.total} destinatários · ${f.reachedSent} enviadas · ${f.reachedDelivered} entregues · '
              '${f.reachedRead} lidas · ${f.replied} responderam'
              '${f.failed > 0 ? ' · ${f.failed} falhas' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(Campaign c, String action) async {
    if (action == 'open') {
      setState(() => selected = c);
      return;
    }
    if (action == 'copy') {
      await _openWizard(copyOf: c);
      return;
    }
    if (action == 'delete') {
      await _confirmDelete(c);
      return;
    }
    final r = await _api.post('/campaigns/${c.id}/action', {'action': action});
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível')));
    }
    await _load(silent: true);
  }

  /// Confirma e exclui a campanha (o histórico de envios vai junto).
  Future<void> _confirmDelete(Campaign c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir campanha'),
        content: Text('Excluir "${c.name}"? O histórico de envios dela também é apagado. '
            'As conversas com os contatos permanecem.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/campaigns/${c.id}');
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível excluir')));
    }
    await _load();
  }

  // ---------- Nova campanha ----------
  Future<void> _openWizard({Campaign? copyOf}) async {
    // Carrega modelos aprovados, grupos, etiquetas e contatos antes de abrir.
    final rt = await _api.get('/support/templates');
    final rg = await _api.get('/support/tags');
    final rc = await _api.get('/contacts');
    final rgs = await _api.get('/contact-groups');
    if (!mounted) return;
    final templates = (rt.ok && rt.data is List)
        ? (rt.data as List)
            .map((e) => MessageTemplate.fromJson(e as Map<String, dynamic>))
            .where((t) => t.isApproved)
            .toList()
        : <MessageTemplate>[];
    final tags = (rg.ok && rg.data is List)
        ? (rg.data as List).map((e) => TicketTag.fromJson(e as Map<String, dynamic>)).toList()
        : <TicketTag>[];
    final contacts = (rc.ok && rc.data is List)
        ? (rc.data as List).map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList()
        : <Contact>[];
    final groups = (rgs.ok && rgs.data is List)
        ? (rgs.data as List).map((e) => ContactGroup.fromJson(e as Map<String, dynamic>)).toList()
        : <ContactGroup>[];
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum modelo aprovado na Meta ainda — crie um na aba Modelos.')));
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CampaignWizard(
          templates: templates, tags: tags, contacts: contacts, groups: groups, copyOf: copyOf),
    );
    if (created == true) await _load();
  }

  Widget _empty(IconData icon, String text, {Future<void> Function()? retry}) {
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
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Tentar de novo')),
          ],
        ],
      ),
    );
  }
}

/// Formulário da nova campanha: nome + modelo + audiência + ritmo + agendamento.
class _CampaignWizard extends StatefulWidget {
  const _CampaignWizard({
    required this.templates,
    required this.tags,
    required this.contacts,
    required this.groups,
    this.copyOf,
  });

  final List<MessageTemplate> templates;
  final List<TicketTag> tags;
  final List<Contact> contacts;
  final List<ContactGroup> groups;

  /// Campanha de origem ao COPIAR: o formulário abre já preenchido.
  final Campaign? copyOf;

  @override
  State<_CampaignWizard> createState() => _CampaignWizardState();
}

class _CampaignWizardState extends State<_CampaignWizard> {
  final _api = ApiClient.instance;
  final name = TextEditingController();

  MessageTemplate? template;
  String audience = 'all'; // all | groups | tag | manual
  String? tagId;
  final selectedGroups = <String>{};
  final selectedContacts = <String>{};
  double rate = 12;
  DateTime? scheduledAt; // null = agora
  bool saving = false;

  // Variáveis do modelo ({{1}}, {{2}}…): um campo por variável.
  final paramCtrls = <TextEditingController>[];

  // Foto (modelos com CABEÇALHO de imagem): sobe agora, envia a URL na criação.
  String? imageUrl;
  String? imageName;
  bool uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final src = widget.copyOf;
    // Copiar: repete modelo, textos, público, foto e ritmo — só o agendamento
    // volta para "agora" (a cópia é um novo disparo).
    template = widget.templates.firstWhere(
      (t) => src != null && t.name == src.templateName,
      orElse: () => widget.templates.first,
    );
    _syncParams();
    if (src != null) {
      name.text = '${src.name} (cópia)';
      audience = src.audience ?? 'all';
      selectedGroups.addAll(src.groupIds);
      tagId = src.tagId;
      selectedContacts.addAll(src.contactIds);
      rate = src.ratePerMin.toDouble().clamp(1, 60);
      imageUrl = src.imageUrl;
      imageName = src.imageUrl != null ? 'foto da campanha copiada' : null;
      for (var i = 0; i < paramCtrls.length && i < src.params.length; i++) {
        paramCtrls[i].text = src.params[i];
      }
    }
  }

  /// Quantas variáveis {{n}} o corpo do modelo tem (maior índice).
  int _varCount(MessageTemplate? t) {
    final body = t?.bodyText ?? '';
    var max = 0;
    for (final m in RegExp(r'\{\{(\d+)\}\}').allMatches(body)) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  void _syncParams() {
    final n = _varCount(template);
    while (paramCtrls.length < n) {
      paramCtrls.add(TextEditingController());
    }
    while (paramCtrls.length > n) {
      paramCtrls.removeLast().dispose();
    }
  }

  Future<void> _pickImage() async {
    final f = await pickFile(accept: 'image/png,image/jpeg');
    if (f == null) return;
    setState(() => uploadingImage = true);
    final r = await _api.uploadFile('/campaigns/media',
        bytes: f.bytes, filename: f.name, contentType: f.mimeType);
    if (!mounted) return;
    setState(() {
      uploadingImage = false;
      if (r.ok && r.data is Map) {
        imageUrl = (r.data as Map)['url'] as String?;
        imageName = f.name;
      }
    });
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível enviar a foto')));
    }
  }

  @override
  void dispose() {
    name.dispose();
    for (final c in paramCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  int get audienceCount => switch (audience) {
        'manual' => selectedContacts.length,
        _ => -1, // desconhecido até criar (o backend resolve)
      };

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() => scheduledAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _create() async {
    if (name.text.trim().length < 2 || template == null) return;
    if (audience == 'groups' && selectedGroups.isEmpty) return;
    if (audience == 'tag' && tagId == null) return;
    if (audience == 'manual' && selectedContacts.isEmpty) return;
    // Modelo com variáveis: todas precisam de valor (a Meta rejeita sem — #132000).
    if (paramCtrls.any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preencha o valor de todas as variáveis do modelo')));
      return;
    }
    setState(() => saving = true);
    final r = await _api.post('/campaigns', {
      'name': name.text.trim(),
      'template_name': template!.name,
      'template_lang': template!.language,
      'body_text': template!.bodyText ?? '',
      'audience': audience,
      'tag_id': ?tagId,
      if (audience == 'groups') 'group_ids': selectedGroups.toList(),
      if (audience == 'manual') 'contact_ids': selectedContacts.toList(),
      if (scheduledAt != null) 'scheduled_at': scheduledAt!.toUtc().toIso8601String(),
      'rate_per_min': rate.round(),
      if (paramCtrls.isNotEmpty) 'params': [for (final c in paramCtrls) c.text.trim()],
      'image_url': ?imageUrl,
    });
    if (!mounted) return;
    setState(() => saving = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível criar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.copyOf == null ? 'Nova campanha' : 'Copiar campanha'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nome da campanha', hintText: 'Ex.: Promoção de agosto', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<MessageTemplate>(
                initialValue: template,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Modelo aprovado (Meta)', border: OutlineInputBorder()),
                items: [
                  for (final t in widget.templates)
                    DropdownMenuItem(value: t, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  template = v;
                  _syncParams();
                }),
              ),
              if (template?.bodyText != null && template!.bodyText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(template!.bodyText!, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                ),
              ],
              // Variáveis do modelo: um campo por {{n}} (obrigatórios).
              if (paramCtrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Valores das variáveis', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Dica: use {nome} para inserir o nome de cada contato automaticamente.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                for (var i = 0; i < paramCtrls.length; i++) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: paramCtrls[i],
                    decoration: InputDecoration(
                      labelText: 'Valor de {{${i + 1}}}',
                      hintText: i == 0 ? 'Ex.: {nome} ou Central Zirix' : 'Texto que substitui {{${i + 1}}}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
              // Foto: só p/ modelos com CABEÇALHO de imagem aprovado na Meta.
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (saving || uploadingImage) ? null : _pickImage,
                    icon: uploadingImage
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined, size: 18),
                    label: Text(imageUrl == null ? 'Adicionar foto' : 'Trocar foto'),
                  ),
                  const SizedBox(width: 8),
                  if (imageUrl != null)
                    SizedBox(
                      width: 150,
                      child: Row(children: [
                        const Icon(Icons.check_circle, size: 16, color: Color(0xFF1F9D57)),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 110,
                          child: Text(imageName ?? 'foto', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        InkWell(
                          onTap: () => setState(() {
                            imageUrl = null;
                            imageName = null;
                          }),
                          child: const Icon(Icons.close, size: 15),
                        ),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('A foto só é entregue se o modelo tiver CABEÇALHO de imagem aprovado na Meta.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 14),
              const Text('Audiência', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioGroup<String>(
                groupValue: audience,
                onChanged: (v) => setState(() => audience = v ?? 'all'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: 'all',
                      title: Text('Todos os contatos (${widget.contacts.length})'),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: 'groups',
                      enabled: widget.groups.isNotEmpty,
                      title: Text(widget.groups.isEmpty
                          ? 'Por grupos (crie grupos na aba Contatos)'
                          : 'Grupos de contatos${selectedGroups.isEmpty ? '' : ' (${selectedGroups.length})'}'),
                    ),
                    if (audience == 'groups')
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final g in widget.groups)
                                FilterChip(
                                  label: Text('${g.name} (${g.members})', style: const TextStyle(fontSize: 12)),
                                  selected: selectedGroups.contains(g.id),
                                  selectedColor: AppTheme.seed.withValues(alpha: 0.2),
                                  onSelected: (v) => setState(() {
                                    if (v) {
                                      selectedGroups.add(g.id);
                                    } else {
                                      selectedGroups.remove(g.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: 'tag',
                      enabled: widget.tags.isNotEmpty,
                      title: Text(widget.tags.isEmpty
                          ? 'Por etiqueta (marque etiquetas nos contatos)'
                          : 'Contatos com uma etiqueta'),
                    ),
                    if (audience == 'tag')
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
                        child: DropdownButtonFormField<String>(
                          initialValue: tagId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Etiqueta', border: OutlineInputBorder(), isDense: true),
                          items: [
                            for (final t in widget.tags) DropdownMenuItem(value: t.id, child: Text(t.name)),
                          ],
                          onChanged: (v) => setState(() => tagId = v),
                        ),
                      ),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: 'manual',
                      title: Text('Escolher contatos${selectedContacts.isEmpty ? '' : ' (${selectedContacts.length})'}'),
                    ),
                  ],
                ),
              ),
              if (audience == 'manual')
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final ct in widget.contacts)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 8),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(ct.displayName, overflow: TextOverflow.ellipsis),
                          value: selectedContacts.contains(ct.id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              selectedContacts.add(ct.id);
                            } else {
                              selectedContacts.remove(ct.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text('Quem pediu para sair (SAIR) é excluído automaticamente.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 14),
              Text('Ritmo de envio: ${rate.round()} mensagens/min', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: rate,
                min: 1,
                max: 60,
                divisions: 59,
                activeColor: AppTheme.seed,
                label: '${rate.round()}/min',
                onChanged: (v) => setState(() => rate = v),
              ),
              Text('Ritmo baixo protege a qualidade do seu número na Meta.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 8),
                  Text(scheduledAt == null
                      ? 'Começa: agora'
                      : 'Começa: ${DateFormat('dd/MM/yyyy HH:mm').format(scheduledAt!)}'),
                  const Spacer(),
                  TextButton(onPressed: _pickSchedule, child: const Text('Agendar')),
                  if (scheduledAt != null)
                    IconButton(
                        tooltip: 'Voltar para "agora"',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => scheduledAt = null)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          onPressed: saving ? null : _create,
          icon: saving
              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.campaign_outlined, size: 18),
          label: Text(scheduledAt == null ? 'Disparar' : 'Agendar'),
        ),
      ],
    );
  }
}
