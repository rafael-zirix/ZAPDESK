import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/contact.dart';
import '../models/crm.dart';
import 'crm_controller.dart';
import 'crm_format.dart';

/// Origens oferecidas no formulário (a automação usa 'instagram'/'whatsapp').
const _sources = [
  ('', '—'),
  ('instagram', 'Instagram'),
  ('whatsapp', 'WhatsApp'),
  ('site', 'Site'),
  ('indicacao', 'Indicação'),
  ('manual', 'Manual'),
];

/// Abre o editor de lead. `deal` nulo = criar (opcionalmente já numa etapa).
/// Devolve true se salvou.
Future<bool> showDealEditor(BuildContext context, CrmController crm,
    {CrmDeal? deal, String? stageId}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _DealEditorDialog(crm: crm, deal: deal, stageId: stageId),
  );
  return saved == true;
}

class _DealEditorDialog extends StatefulWidget {
  const _DealEditorDialog({required this.crm, this.deal, this.stageId});
  final CrmController crm;
  final CrmDeal? deal;
  final String? stageId; // etapa de destino no criar (veio do "+" da coluna)

  @override
  State<_DealEditorDialog> createState() => _DealEditorDialogState();
}

class _DealEditorDialogState extends State<_DealEditorDialog> {
  bool get isEdit => widget.deal != null;

  // Contato (só no criar): existente (busca) ou novo (nome+telefone).
  bool _newContact = false;
  Contact? _picked;
  final _search = TextEditingController();
  List<Contact> _contacts = [];
  bool _contactsLoading = false;

  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _notes = TextEditingController();
  String _source = '';
  String _ownerId = '';
  DateTime? _followUp; // dia local (UTC-3)
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.deal;
    if (d != null) {
      _title.text = d.title ?? '';
      if (d.valueCents > 0) {
        _value.text = NumberFormat('#,##0.00', 'pt_BR').format(d.valueCents / 100);
      }
      _notes.text = d.notes ?? '';
      _source = d.source ?? '';
      _ownerId = d.ownerUserId ?? '';
      if (d.nextFollowUpAt != null) {
        final l = d.nextFollowUpAt!.add(const Duration(hours: -3));
        _followUp = DateTime(l.year, l.month, l.day);
      }
    } else {
      _loadContacts();
    }
  }

  Future<void> _loadContacts() async {
    setState(() => _contactsLoading = true);
    final r = await ApiClient.instance.get('/contacts');
    if (!mounted) return;
    setState(() {
      _contactsLoading = false;
      if (r.ok && r.data is List) {
        _contacts = [for (final c in r.data as List) Contact.fromJson(c)];
      }
    });
  }

  List<Contact> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts.take(30).toList();
    return _contacts
        .where((c) =>
            (c.name ?? '').toLowerCase().contains(q) || c.phone.contains(q))
        .take(30)
        .toList();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'value_cents': parseMoneyToCents(_value.text),
      'source': _source,
      'notes': _notes.text.trim(),
      'next_follow_up_at': _followUp == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(_followUp!),
      if (widget.crm.isAdmin) 'owner_user_id': _ownerId,
    };
    String? err;
    if (isEdit) {
      err = await widget.crm.updateDeal(widget.deal!.id, body);
    } else {
      if (widget.stageId != null) body['stage_id'] = widget.stageId;
      if (_newContact) {
        body['contact_name'] = _contactName.text.trim();
        body['contact_phone'] = _contactPhone.text.trim();
      } else {
        body['contact_id'] = _picked?.id ?? '';
      }
      if ((body['contact_id'] as String? ?? '').isEmpty &&
          (body['contact_phone'] as String? ?? '').isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Escolha um contato ou informe nome e telefone.';
        });
        return;
      }
      err = await widget.crm.createDeal(body);
    }
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _pickFollowUp() async {
    final nowLocal = DateTime.now().toUtc().add(const Duration(hours: -3));
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? nowLocal,
      firstDate: DateTime(nowLocal.year - 1),
      lastDate: DateTime(nowLocal.year + 2),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'Editar lead' : 'Novo lead'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isEdit) ..._contactSection(),
              _label('Título (opcional — vazio usa o nome do contato)'),
              TextField(controller: _title, decoration: const InputDecoration(hintText: 'Ex.: Rastreamento frota')),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(
                  width: 200,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Valor'),
                    TextField(
                      controller: _value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: const InputDecoration(hintText: '0,00', prefixText: 'R\$ '),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Origem'),
                    DropdownButtonFormField<String>(
                      initialValue: _source,
                      items: [
                        for (final s in _sources)
                          DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                      ],
                      onChanged: (v) => setState(() => _source = v ?? ''),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(
                  width: 200,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Retorno (follow-up)'),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFollowUp,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(_followUp == null
                          ? 'Agendar'
                          : DateFormat('dd/MM/yyyy').format(_followUp!)),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                if (widget.crm.isAdmin)
                  SizedBox(
                    width: 200,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Vendedor'),
                      DropdownButtonFormField<String>(
                        initialValue: _ownerId,
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Sem dono (fila)')),
                          for (final s in widget.crm.sellers)
                            DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _ownerId = v ?? ''),
                      ),
                    ]),
                  ),
              ]),
              const SizedBox(height: 12),
              _label('Observações'),
              TextField(controller: _notes, maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Salvando…' : 'Salvar'),
        ),
      ],
    );
  }

  List<Widget> _contactSection() {
    return [
      Row(children: [
        _label('Contato'),
        const SizedBox(width: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Existente')),
            ButtonSegment(value: true, label: Text('Novo')),
          ],
          selected: {_newContact},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => setState(() => _newContact = s.first),
        ),
      ]),
      const SizedBox(height: 8),
      if (_newContact) ...[
        TextField(controller: _contactName, decoration: const InputDecoration(hintText: 'Nome')),
        const SizedBox(height: 8),
        TextField(
          controller: _contactPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Telefone (55 21 99999-9999)'),
        ),
      ] else ...[
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar por nome ou telefone…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _picked == null
                ? null
                : const Icon(Icons.check_circle, color: AppTheme.seed, size: 20),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _contactsLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    for (final c in _filtered)
                      ListTile(
                        dense: true,
                        selected: _picked?.id == c.id,
                        selectedTileColor: AppTheme.seed.withValues(alpha: 0.08),
                        title: Text(c.name ?? c.prettyPhone,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: c.name == null ? null : Text(c.prettyPhone),
                        onTap: () => setState(() => _picked = c),
                      ),
                  ],
                ),
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600)),
      );
}

/// Diálogo de perda: motivo + observação. Devolve true se marcou.
Future<bool> showLoseDialog(BuildContext context, CrmController crm, CrmDeal deal) async {
  await crm.loadLossReasons();
  if (!context.mounted) return false;
  String reasonId = '';
  final notes = TextEditingController();
  String? error;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Marcar como perdido'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(deal.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: reasonId,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('— sem motivo —')),
                  for (final m in crm.lossReasons)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => setState(() => reasonId = v ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observação (opcional)'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    final err = await crm.loseDeal(deal.id, reasonId, notes.text.trim());
                    if (!ctx.mounted) return;
                    if (err != null) {
                      setState(() {
                        busy = false;
                        error = err;
                      });
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
            child: const Text('Marcar perdido'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}
