import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/crm.dart';
import 'contact_ficha_editor.dart';
import 'crm_controller.dart';
import 'crm_format.dart';
import 'deal_editor.dart';
import 'stage_editor.dart';

/// Quadro Kanban do CRM: colunas por etapa, arrastar-e-soltar move o negócio.
/// Larguras fixas em todo Row (CanvasKit web colapsa Expanded-em-Row).
class CrmBoardView extends StatefulWidget {
  const CrmBoardView({super.key, required this.crm});
  final CrmController crm;

  @override
  State<CrmBoardView> createState() => _CrmBoardViewState();
}

class _CrmBoardViewState extends State<CrmBoardView> {
  CrmController get crm => widget.crm;

  static const _colWidth = 300.0;
  static const _cardWidth = _colWidth - 20; // padding interno da coluna

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: crm,
      builder: (context, _) {
        if (crm.loading && crm.stages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (crm.error != null && crm.stages.isEmpty) {
          return _errorState();
        }
        final stages = [...crm.stages]..sort((a, b) => a.ordinal.compareTo(b.ordinal));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in stages) ...[
                    _column(s),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 10),
        Text(crm.error!, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: crm.load,
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.refresh, size: 18),
            SizedBox(width: 8),
            Text('Tentar de novo'),
          ]),
        ),
      ]),
    );
  }

  Widget _toolbar() {
    final open = crm.deals.where((d) => d.status == 'open').toList();
    final total = open.fold(0, (s, d) => s + d.valueCents);
    return Row(children: [
      // GOTCHA CanvasKit: FilledButton não pinta neste contexto (sonda A/B) —
      // botão custom via crmButton (InkWell+Container, sempre pinta).
      crmButton(
        onTap: () => showDealEditor(context, crm),
        icon: Icons.add,
        label: 'Novo lead',
      ),
      const SizedBox(width: 8),
      if (crm.isAdmin)
        crmButton(
          onTap: () => showStageEditor(context, crm),
          icon: Icons.view_week_outlined,
          label: 'Etapas',
          filled: false,
        ),
      const SizedBox(width: 8),
      if (crm.isAdmin && crm.sellers.isNotEmpty) _sellerFilter(),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Atualizar',
        onPressed: crm.load,
        icon: const Icon(Icons.refresh, size: 20),
      ),
      const SizedBox(width: 4),
      _alertBell(),
      const SizedBox(width: 12),
      Text('${open.length} em aberto · ${moneyFromCents(total)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
    ]);
  }

  /// Campainha com balão: retornos de HOJE e ATRASADOS. Clicou num alerta,
  /// abre o lead na hora.
  Widget _alertBell() {
    final alerts = crm.deals
        .where((d) =>
            d.status == 'open' &&
            d.nextFollowUpAt != null &&
            followUpState(d.nextFollowUpAt!) > 0)
        .toList()
      // Atrasados primeiro, depois os de hoje.
      ..sort((a, b) => followUpState(b.nextFollowUpAt!)
          .compareTo(followUpState(a.nextFollowUpAt!)));
    final hasLate = alerts.any((d) => followUpState(d.nextFollowUpAt!) == 2);
    final color = alerts.isEmpty
        ? Colors.grey.shade500
        : (hasLate ? const Color(0xFFEF4444) : const Color(0xFFF79009));
    final bell = Stack(clipBehavior: Clip.none, children: [
      Icon(alerts.isEmpty ? Icons.notifications_none : Icons.notifications_active,
          size: 22, color: color),
      if (alerts.isNotEmpty)
        Positioned(
          right: -7,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            child: Text('${alerts.length}',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
    if (alerts.isEmpty) {
      return Tooltip(
          message: 'Nenhum retorno pendente 🎉',
          child: Padding(padding: const EdgeInsets.all(8), child: bell));
    }
    const maxShow = 12;
    return PopupMenuButton<String>(
      tooltip: 'Retornos de hoje e atrasados',
      onSelected: (id) {
        final deal = crm.deals.where((d) => d.id == id).firstOrNull;
        if (deal != null) showDealEditor(context, crm, deal: deal);
      },
      itemBuilder: (_) => [
        for (final d in alerts.take(maxShow))
          PopupMenuItem(
            value: d.id,
            height: 42,
            child: Row(children: [
              Icon(
                  followUpState(d.nextFollowUpAt!) == 2
                      ? Icons.notifications_active
                      : Icons.notifications_active_outlined,
                  size: 16,
                  color: followUpState(d.nextFollowUpAt!) == 2
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFF79009)),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                child: Text(d.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                    followUpState(d.nextFollowUpAt!) == 1
                        ? 'hoje'
                        : followUpLabel(d.nextFollowUpAt!),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: followUpState(d.nextFollowUpAt!) == 2
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFF79009))),
              ),
            ]),
          ),
        if (alerts.length > maxShow)
          PopupMenuItem(
            enabled: false,
            height: 34,
            child: Text('… e mais ${alerts.length - maxShow}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
      ],
      child: Padding(padding: const EdgeInsets.all(8), child: bell),
    );
  }

  Widget _sellerFilter() {
    final sel = crm.ownerFilter;
    final name = sel == null
        ? 'Todos os vendedores'
        : crm.sellers.where((s) => s.id == sel).map((s) => s.name).firstOrNull ?? 'Vendedor';
    return PopupMenuButton<String>(
      tooltip: 'Filtrar por vendedor',
      onSelected: (v) => crm.setOwnerFilter(v == '' ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('Todos os vendedores')),
        for (final s in crm.sellers) PopupMenuItem(value: s.id, child: Text(s.name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_outline, size: 17, color: sel == null ? Colors.grey.shade600 : AppTheme.seed),
          const SizedBox(width: 6),
          Text(name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel == null ? Colors.grey.shade700 : AppTheme.seed)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade600),
        ]),
      ),
    );
  }

  Widget _column(CrmStage stage) {
    final deals = crm.dealsOf(stage.id);
    final value = crm.valueOf(stage.id);
    return DragTarget<CrmDeal>(
      onWillAcceptWithDetails: (d) => d.data.stageId != stage.id,
      onAcceptWithDetails: (d) async {
        final err = await crm.moveDeal(d.data, stage.id);
        if (err != null) _snack(err);
      },
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        // No tema CLARO a coluna precisa se destacar do fundo da página (que é
        // quase igual): preenchimento um tom abaixo + borda mais firme. No
        // escuro o contraste natural já resolve.
        final colFill = AppTheme.isDark ? AppTheme.bg : const Color(0xFFE7EAEF);
        final colBorder = AppTheme.isDark ? AppTheme.border : const Color(0xFFCBD2DA);
        return Container(
          width: _colWidth,
          decoration: BoxDecoration(
            color: hover ? AppTheme.seed.withValues(alpha: 0.06) : colFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hover ? AppTheme.seed : colBorder,
                width: hover ? 1.6 : 1),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 8, 8),
              child: Row(children: [
                // Admin: clica no nome e edita a etapa ali mesmo.
                Tooltip(
                  message: crm.isAdmin ? 'Clique para editar a etapa' : '',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: crm.isAdmin ? () => _editStageDialog(stage) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: hexColor(stage.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 146,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                              child: Text(stage.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            ),
                            if (stage.isWon)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text('🏆', style: TextStyle(fontSize: 13)),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 66,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${deals.length}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
                    Text(moneyFromCents(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                ),
                // Abre um lead JÁ nesta etapa — o caminho mais curto do quadro.
                IconButton(
                  tooltip: 'Abrir lead em "${stage.name}"',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showDealEditor(context, crm, stageId: stage.id),
                  icon: const Icon(Icons.add_circle_outline, size: 19, color: AppTheme.seed),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: deals.isEmpty
                  ? Center(
                      child: hover
                          ? Text('Solte aqui',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 13))
                          : TextButton(
                              onPressed: () =>
                                  showDealEditor(context, crm, stageId: stage.id),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey.shade500),
                              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                Icon(Icons.add, size: 16),
                                SizedBox(width: 6),
                                Text('Abrir lead'),
                              ]),
                            ))
                  : ListView(
                      padding: const EdgeInsets.all(10),
                      children: [for (final d in deals) _draggableCard(d)],
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _draggableCard(CrmDeal deal) {
    final card = _dealCard(deal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Draggable<CrmDeal>(
        data: deal,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: _cardWidth, child: Opacity(opacity: 0.92, child: card)),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      ),
    );
  }

  Widget _dealCard(CrmDeal deal) {
    final won = deal.status == 'won';
    const innerWidth = _cardWidth - 24.0; // padding horizontal do card
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _cardMenu(deal),
      child: Container(
        width: _cardWidth,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: won ? const Color(0xFF16A34A) : AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(deal.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          if (deal.contactName != null &&
              deal.contactName!.isNotEmpty &&
              deal.displayName != deal.contactName) ...[
            const SizedBox(height: 2),
            Text(deal.contactName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              width: innerWidth - 92,
              child: Text(deal.valueCents > 0 ? moneyFromCents(deal.valueCents) : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.seed)),
            ),
            SizedBox(
              width: 92,
              child: deal.nextFollowUpAt == null
                  ? const SizedBox.shrink()
                  : Align(alignment: Alignment.centerRight, child: _followUpChip(deal)),
            ),
          ]),
          if (deal.source != null && deal.source!.isNotEmpty || deal.ownerName != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              if (deal.source != null && deal.source!.isNotEmpty) ...[
                Icon(sourceIcon(deal.source), size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                SizedBox(
                  width: 110,
                  child: Text(sourceLabel(deal.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                ),
              ] else
                const SizedBox(width: 127),
              SizedBox(
                width: innerWidth - 127 - 24,
                child: deal.ownerName == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: deal.ownerName!,
                          child: Text(deal.ownerName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600)),
                        ),
                      ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _followUpChip(CrmDeal deal) {
    // 3 estados: agendado (cinza) · é HOJE (laranja, "hoje") · atrasado
    // (vermelho, ícone ativo) — o vendedor bate o olho e sabe quem cobrar.
    final state = followUpState(deal.nextFollowUpAt!);
    final (color, bg, icon, label) = switch (state) {
      2 => (
          const Color(0xFFEF4444),
          const Color(0xFFEF4444).withValues(alpha: 0.10),
          Icons.notifications_active,
          followUpLabel(deal.nextFollowUpAt!),
        ),
      1 => (
          const Color(0xFFF79009),
          const Color(0xFFF79009).withValues(alpha: 0.12),
          Icons.notifications_active_outlined,
          'hoje',
        ),
      _ => (
          Color(0xFF757575),
          AppTheme.bg,
          Icons.notifications_none,
          followUpLabel(deal.nextFollowUpAt!),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  /// Edição rápida da etapa direto do quadro (admin): nome, cor e exclusão.
  Future<void> _editStageDialog(CrmStage stage) async {
    final name = TextEditingController(text: stage.name);
    var color = stage.color;
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Editar etapa'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome da etapa'),
                ),
                const SizedBox(height: 14),
                Text('Cor',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in kStagePalette)
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => setState(() => color = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: hexColor(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: color == c ? Colors.black87 : AppTheme.border,
                              width: color == c ? 2.5 : 1),
                        ),
                      ),
                    ),
                ]),
                if (stage.isSystem) ...[
                  const SizedBox(height: 12),
                  Text(
                    stage.isWon
                        ? 'Etapa de ganho: pode renomear e mudar a cor; não pode ser excluída.'
                        : 'Etapa de entrada (os leads caem aqui): pode renomear e mudar a cor; não pode ser excluída.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            if (!stage.isSystem)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        final err = await crm.deleteStage(stage.id);
                        if (!ctx.mounted) return;
                        if (err != null) {
                          setState(() {
                            busy = false;
                            error = err;
                          });
                          return;
                        }
                        Navigator.of(ctx).pop();
                      },
                child: const Text('Excluir',
                    style: TextStyle(color: Color(0xFFEF4444))),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final err = await crm.updateStage(stage.id,
                          {'name': name.text.trim(), 'color': color});
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setState(() {
                          busy = false;
                          error = err;
                        });
                        return;
                      }
                      Navigator.of(ctx).pop();
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Menu do card: editar, marcar perdido, excluir.
  Future<void> _cardMenu(CrmDeal deal) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 420),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar negócio'),
            onTap: () => Navigator.of(ctx).pop('edit'),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: AppTheme.seed),
            title: const Text('Ficha do contato'),
            subtitle: const Text('Empresa, CPF/CNPJ, endereço', style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.of(ctx).pop('ficha'),
          ),
          if (deal.status != 'lost')
            ListTile(
              leading: const Icon(Icons.trending_down, color: Color(0xFFEF4444)),
              title: const Text('Marcar como perdido'),
              onTap: () => Navigator.of(ctx).pop('lose'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Excluir'),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await showDealEditor(context, crm, deal: deal);
      case 'ficha':
        await showContactFicha(context, deal.contactId);
        await crm.load(); // nome/empresa podem ter mudado no card
      case 'lose':
        await showLoseDialog(context, crm, deal);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Excluir "${deal.displayName}"?'),
            content: const Text('O histórico do negócio some do funil. Para registrar um não-fechamento, prefira "Marcar como perdido".'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        );
        if (ok == true) {
          final err = await crm.deleteDeal(deal.id);
          if (err != null) _snack(err);
        }
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
