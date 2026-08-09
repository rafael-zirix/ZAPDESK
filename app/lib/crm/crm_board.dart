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
        OutlinedButton.icon(
          onPressed: crm.load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Tentar de novo'),
        ),
      ]),
    );
  }

  Widget _toolbar() {
    final open = crm.deals.where((d) => d.status == 'open').toList();
    final total = open.fold(0, (s, d) => s + d.valueCents);
    return Row(children: [
      FilledButton.icon(
        onPressed: () => showDealEditor(context, crm),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Novo lead'),
      ),
      const SizedBox(width: 8),
      if (crm.isAdmin)
        OutlinedButton.icon(
          onPressed: () => showStageEditor(context, crm),
          icon: const Icon(Icons.view_week_outlined, size: 18),
          label: const Text('Etapas'),
        ),
      const SizedBox(width: 8),
      if (crm.isAdmin && crm.sellers.isNotEmpty) _sellerFilter(),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Atualizar',
        onPressed: crm.load,
        icon: const Icon(Icons.refresh, size: 20),
      ),
      const SizedBox(width: 16),
      Text('${open.length} em aberto · ${moneyFromCents(total)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
    ]);
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
        return Container(
          width: _colWidth,
          decoration: BoxDecoration(
            color: hover ? AppTheme.seed.withValues(alpha: 0.06) : AppTheme.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hover ? AppTheme.seed : AppTheme.border,
                width: hover ? 1.6 : 1),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: hexColor(stage.color), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 148,
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
                          : TextButton.icon(
                              onPressed: () =>
                                  showDealEditor(context, crm, stageId: stage.id),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Abrir lead'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey.shade500),
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
    final overdue = followUpOverdue(deal.nextFollowUpAt!);
    final color = overdue ? const Color(0xFFEF4444) : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overdue ? const Color(0xFFEF4444).withValues(alpha: 0.08) : AppTheme.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_none, size: 12, color: color),
        const SizedBox(width: 3),
        Text(followUpLabel(deal.nextFollowUpAt!),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
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
