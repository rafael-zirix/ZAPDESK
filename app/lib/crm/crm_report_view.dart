import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/crm.dart';
import 'crm_controller.dart';
import 'crm_format.dart';
import 'crm_funnel_chart.dart';

/// Abas de relatório do CRM: Funil, Métricas e Perdidos. Toolbar comum
/// (período + vendedor); larguras fixas em Row (gotcha do CanvasKit).
class CrmReportView extends StatefulWidget {
  const CrmReportView({super.key, required this.crm, required this.mode});
  final CrmController crm;
  final String mode; // funil | metricas | perdidos

  @override
  State<CrmReportView> createState() => _CrmReportViewState();
}

class _CrmReportViewState extends State<CrmReportView> {
  CrmController get crm => widget.crm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (crm.report == null && !crm.reportLoading) crm.loadReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: crm,
      builder: (context, _) {
        final rep = crm.report;
        return ListView(children: [
          _toolbar(),
          const SizedBox(height: 16),
          if (crm.reportLoading && rep == null)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (crm.reportError != null && rep == null)
            _error()
          else if (rep != null) ...[
            switch (widget.mode) {
              'funil' => _funnel3d(rep),
              'metricas' => _metrics(rep),
              _ => _lost(rep),
            },
          ],
        ]);
      },
    );
  }

  Widget _error() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(children: [
          Text(crm.reportError!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: crm.loadReport,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tentar de novo'),
          ),
        ]),
      ),
    );
  }

  // --- Toolbar: período + vendedor ---

  Widget _toolbar() {
    return Row(children: [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7 dias')),
          ButtonSegment(value: 30, label: Text('30 dias')),
          ButtonSegment(value: 90, label: Text('90 dias')),
          ButtonSegment(value: 0, label: Text('Tudo')),
        ],
        selected: {crm.periodDays},
        showSelectedIcon: false,
        onSelectionChanged: (s) => crm.setPeriod(s.first),
      ),
      const SizedBox(width: 10),
      if (crm.isAdmin && crm.sellers.isNotEmpty) _sellerFilter(),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Atualizar',
        onPressed: crm.loadReport,
        icon: const Icon(Icons.refresh, size: 20),
      ),
    ]);
  }

  Widget _sellerFilter() {
    final sel = crm.ownerFilter;
    var name = 'Todos os vendedores';
    if (sel != null) {
      for (final s in crm.sellers) {
        if (s.id == sel) name = s.name;
      }
    }
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

  // --- Funil estilizado (aba Funil): o cone 3D nas cores das etapas ---
  Widget _funnel3d(CrmReport rep) {
    return _card(
      title: 'Funil de conversão',
      // Largura cheia + alinhamento central: dentro da Column do card um
      // Center puro encolheria e o funil ficaria à esquerda.
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal, // janela estreita rola, não corta
          child: SizedBox(width: 720, child: CrmFunnelChart(rows: rep.funnel)),
        ),
      ),
    );
  }

  // --- Funil compacto em barras (usado na aba Métricas) ---

  Widget _funnel(CrmReport rep) {
    final rows = rep.funnel;
    final maxCount = rows.fold(0, (m, r) => r.dealCount > m ? r.dealCount : m);
    final first = rows.isEmpty ? 0 : rows.first.dealCount;
    return _card(
      title: 'Funil de conversão',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < rows.length; i++) ...[
          _funnelRow(rows[i], maxCount, i == 0 ? null : rows[i - 1].dealCount),
          if (i < rows.length - 1) const SizedBox(height: 10),
        ],
        if (rows.isNotEmpty && first > 0) ...[
          const Divider(height: 24),
          Text(
            'Conversão do funil: ${(rows.last.dealCount * 100 / first).toStringAsFixed(1)}% '
            '(${rows.last.dealCount} de $first leads)',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    );
  }

  Widget _funnelRow(CrmFunnelRow row, int maxCount, int? prevCount) {
    const barMax = 420.0;
    final w = maxCount == 0 ? 0.0 : (row.dealCount / maxCount) * barMax;
    final pct = prevCount == null || prevCount == 0
        ? null
        : row.dealCount * 100 / prevCount;
    return Row(children: [
      SizedBox(
        width: 130,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: hexColor(row.color), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          if (row.isWon) const Text(' 🏆', style: TextStyle(fontSize: 11)),
        ]),
      ),
      SizedBox(
        width: barMax,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: w < 4 && row.dealCount > 0 ? 4 : w,
            height: 22,
            decoration: BoxDecoration(
              color: hexColor(row.color).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 110,
        child: Text(
          pct == null ? '${row.dealCount}' : '${row.dealCount}  (${pct.toStringAsFixed(0)}%)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      SizedBox(
        width: 130,
        child: Text(moneyFromCents(row.valueCents),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      ),
    ]);
  }

  // --- Métricas ---

  Widget _metrics(CrmReport rep) {
    final s = rep.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kpi(Icons.work_outline, const Color(0xFF2563EB), 'Em aberto',
            '${s.openCount}', moneyFromCents(s.openValue)),
        _kpi(Icons.emoji_events_outlined, const Color(0xFF16A34A), 'Ganhos',
            '${s.wonCount}', moneyFromCents(s.wonValue)),
        _kpi(Icons.trending_down, const Color(0xFFEF4444), 'Perdidos',
            '${s.lostCount}', moneyFromCents(s.lostValue)),
        _kpi(Icons.percent, AppTheme.seed, 'Conversão',
            '${s.conversionPct.toStringAsFixed(1)}%', 'ganhos ÷ total de leads'),
        _kpi(Icons.timer_outlined, const Color(0xFFF59E0B), 'Tempo até fechar',
            s.avgDaysToWin <= 0 ? '—' : '${s.avgDaysToWin.toStringAsFixed(1)} d',
            s.avgDaysToWin <= 0 ? 'sem ganhos no período' : 'média dos ganhos'),
      ]),
      const SizedBox(height: 16),
      _funnel(rep),
    ]);
  }

  Widget _kpi(IconData icon, Color color, String label, String big, String sub) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: 150,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(big, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
      ]),
    );
  }

  // --- Perdidos ---

  Widget _lost(CrmReport rep) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(
        title: 'Perdas por motivo',
        child: rep.losses.isEmpty
            ? Text('Nenhum negócio perdido no período. 🎉',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
            : Column(children: [
                for (final l in rep.losses)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(
                        width: 240,
                        child: Text(l.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('${l.count}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(moneyFromCents(l.valueCents),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                      ),
                    ]),
                  ),
              ]),
      ),
      const SizedBox(height: 14),
      _card(
        title: 'Negócios perdidos (${rep.lostDeals.length})',
        child: rep.lostDeals.isEmpty
            ? Text('Nada por aqui.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
            : Column(children: [
                for (final d in rep.lostDeals)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 250,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          if (d.lostNotes != null && d.lostNotes!.isNotEmpty)
                            Text(d.lostNotes!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                        ]),
                      ),
                      SizedBox(
                        width: 150,
                        child: Text(d.lostReasonName ?? 'Sem motivo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: const Color(0xFFEF4444).withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(d.valueCents > 0 ? moneyFromCents(d.valueCents) : '—',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(d.lostAt == null ? '' : fmt.format(d.lostAt!.add(const Duration(hours: -3))),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(d.ownerName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}
