import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/campaign.dart';
import '../models/contact.dart';
import '../models/message_template.dart';
import '../models/support.dart';

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
      onTap: () => _openDetail(c),
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
                if (c.isActive)
                  PopupMenuButton<String>(
                    tooltip: 'Ações',
                    onSelected: (a) => _action(c, a),
                    itemBuilder: (_) => [
                      if (c.status != 'paused')
                        const PopupMenuItem(value: 'pause', child: Text('Pausar')),
                      if (c.status == 'paused')
                        const PopupMenuItem(value: 'resume', child: Text('Retomar')),
                      const PopupMenuItem(value: 'cancel', child: Text('Cancelar campanha')),
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
    final r = await _api.post('/campaigns/${c.id}/action', {'action': action});
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível')));
    }
    await _load(silent: true);
  }

  // ---------- Detalhe ----------
  Future<void> _openDetail(Campaign c) async {
    final r = await _api.get('/campaigns/${c.id}/recipients?limit=200');
    if (!mounted) return;
    final recipients = (r.ok && r.data is List)
        ? (r.data as List).map((e) => CampaignRecipient.fromJson(e as Map<String, dynamic>)).toList()
        : <CampaignRecipient>[];
    final failed = recipients.where((x) => x.status == 'failed').toList();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.bodyText != null && c.bodyText!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(c.bodyText!, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 12),
              ],
              _funnelRow('Destinatários', c.funnel.total, c.funnel.total),
              _funnelRow('Enviadas', c.funnel.reachedSent, c.funnel.total),
              _funnelRow('Entregues', c.funnel.reachedDelivered, c.funnel.total),
              _funnelRow('Lidas', c.funnel.reachedRead, c.funnel.total),
              _funnelRow('Responderam', c.funnel.replied, c.funnel.total, highlight: true),
              if (c.funnel.failed > 0) _funnelRow('Falhas', c.funnel.failed, c.funnel.total, isError: true),
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Falhas:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final x in failed.take(20))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('${x.displayName} — ${x.error ?? 'erro'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }

  Widget _funnelRow(String label, int value, int total, {bool highlight = false, bool isError = false}) {
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    final color = isError ? const Color(0xFFEF4444) : (highlight ? AppTheme.seed : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: color))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : value / total,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                color: color ?? const Color(0xFF2563EB),
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text('  $value ($pct%)',
                style: TextStyle(fontSize: 12.5, fontWeight: highlight ? FontWeight.w700 : FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }

  // ---------- Nova campanha ----------
  Future<void> _openWizard() async {
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
      builder: (_) => _CampaignWizard(templates: templates, tags: tags, contacts: contacts, groups: groups),
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
  const _CampaignWizard({required this.templates, required this.tags, required this.contacts, required this.groups});

  final List<MessageTemplate> templates;
  final List<TicketTag> tags;
  final List<Contact> contacts;
  final List<ContactGroup> groups;

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

  @override
  void initState() {
    super.initState();
    template = widget.templates.first;
  }

  @override
  void dispose() {
    name.dispose();
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
      title: const Text('Nova campanha'),
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
                onChanged: (v) => setState(() => template = v),
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
                          ? 'Por etiqueta (crie etiquetas nas conversas)'
                          : 'Conversas com uma etiqueta'),
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
