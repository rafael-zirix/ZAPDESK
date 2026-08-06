import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/theme.dart';

/// Dashboard de métricas de atendimento (admin): TME, TMA, produção por
/// atendente/setor e picos por dia/hora. Fonte: eventos das fases 1–3.
class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  final _api = ApiClient.instance;

  Map<String, dynamic>? data;
  bool loading = false;
  String? error;
  int periodDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final now = DateTime.now();
    final from = now.subtract(Duration(days: periodDays - 1));
    final fmt = DateFormat('yyyy-MM-dd');
    final r = await _api.get('/support/metrics?from=${fmt.format(from)}&to=${fmt.format(now)}');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (r.ok && r.data is Map) {
        data = (r.data as Map).cast<String, dynamic>();
      } else {
        error = r.message ?? 'Erro ao carregar métricas';
      }
    });
  }

  // ---------- formatação ----------
  String _dur(num? seconds) {
    if (seconds == null) return '—';
    final s = seconds.round();
    if (s < 60) return '${s}s';
    if (s < 3600) return '${(s / 60).round()}min';
    if (s < 86400) {
      final h = s ~/ 3600;
      final m = (s % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}min' : '${h}h';
    }
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    return h > 0 ? '${d}d ${h}h' : '${d}d';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
            child: Row(
              children: [
                const Text('Métricas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 dias')),
                    ButtonSegment(value: 30, label: Text('30 dias')),
                    ButtonSegment(value: 90, label: Text('90 dias')),
                  ],
                  selected: {periodDays},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => periodDays = s.first);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _load, tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (loading && data == null) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
        ]),
      );
    }
    final d = data;
    if (d == null) return const SizedBox.shrink();

    final created = (d['tickets_created'] as num?)?.toInt() ?? 0;
    final resolved = (d['tickets_resolved'] as num?)?.toInt() ?? 0;
    final aiResolved = (d['ai_resolved'] as num?)?.toInt() ?? 0;
    final aiPct = resolved > 0 ? (aiResolved * 100 / resolved).round() : 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _card('Conversas criadas', '$created', Icons.forum_outlined, const Color(0xFF2563EB)),
            _card('Resolvidas', '$resolved', Icons.task_alt, const Color(0xFF1F9D57)),
            _card('Em aberto agora', '${d['open_now'] ?? 0}', Icons.inbox_outlined, const Color(0xFFCA8A04)),
            _card('Na fila (sem atendente)', '${d['queue_now'] ?? 0}', Icons.hourglass_empty, const Color(0xFFEF4444)),
            _card('1ª resposta (média)', _dur(d['avg_first_response_sec'] as num?), Icons.bolt_outlined, const Color(0xFF7C3AED)),
            _card('Tempo de resolução', _dur(d['avg_resolution_sec'] as num?), Icons.timer_outlined, const Color(0xFF0E9384)),
            _card('Resolvidas sem humano', '$aiResolved ($aiPct%)', Icons.smart_toy_outlined, const Color(0xFF6941C6)),
            _card('Transferências', '${d['transfers'] ?? 0}', Icons.swap_horiz, const Color(0xFFF79009)),
          ],
        ),
        const SizedBox(height: 20),
        _section('Conversas por dia', _byDayChart((d['by_day'] as List?) ?? const [])),
        const SizedBox(height: 16),
        _section('Distribuição por hora do dia', _byHourChart((d['by_hour'] as List?) ?? const [])),
        const SizedBox(height: 16),
        _section('Por atendente', _attendantTable((d['per_attendant'] as List?) ?? const [])),
        const SizedBox(height: 16),
        _section('Por setor', _sectorTable((d['per_sector'] as List?) ?? const [])),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            SizedBox(
              width: 165,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // Barras por dia (altura proporcional; rola na horizontal se precisar).
  Widget _byDayChart(List days) {
    if (days.isEmpty) return Text('Sem conversas no período.', style: TextStyle(color: Colors.grey.shade600));
    final max = days.fold<int>(1, (acc, e) => ((e['count'] as num).toInt() > acc) ? (e['count'] as num).toInt() : acc);
    return SizedBox(
      height: 140,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final e in days)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${e['count']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Container(
                      width: 26,
                      height: 90.0 * (e['count'] as num).toInt() / max,
                      decoration: BoxDecoration(
                        color: AppTheme.seed.withValues(alpha: 0.75),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text((e['day'] as String).substring(5).split('-').reversed.join('/'),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Distribuição por hora (0–23) — mostra onde estão os picos.
  Widget _byHourChart(List hours) {
    if (hours.isEmpty) return Text('Sem conversas no período.', style: TextStyle(color: Colors.grey.shade600));
    final byHour = {for (final e in hours) (e['hour'] as num).toInt(): (e['count'] as num).toInt()};
    final max = byHour.values.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 110,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var h = 0; h < 24; h++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 18,
                      height: 4 + 66.0 * (byHour[h] ?? 0) / max,
                      decoration: BoxDecoration(
                        color: (byHour[h] ?? 0) == 0
                            ? Colors.grey.withValues(alpha: 0.18)
                            : const Color(0xFF2563EB).withValues(alpha: 0.35 + 0.6 * (byHour[h] ?? 0) / max),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$h', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attendantTable(List rows) {
    if (rows.isEmpty) return Text('Sem atividade de atendentes no período.', style: TextStyle(color: Colors.grey.shade600));
    return _table(
      const ['Atendente', 'Resolvidas', 'Respostas', 'Em atendimento'],
      [
        for (final r in rows)
          [r['name'] ?? '', '${r['resolved'] ?? 0}', '${r['messages_sent'] ?? 0}', '${r['open_assigned'] ?? 0}'],
      ],
    );
  }

  Widget _sectorTable(List rows) {
    if (rows.isEmpty) return Text('Nenhum setor criado ainda.', style: TextStyle(color: Colors.grey.shade600));
    return _table(
      const ['Setor', 'Criadas', 'Resolvidas', 'Abertas agora'],
      [
        for (final r in rows)
          [r['name'] ?? '', '${r['created'] ?? 0}', '${r['resolved'] ?? 0}', '${r['open_now'] ?? 0}'],
      ],
    );
  }

  Widget _table(List<String> headers, List<List<String>> rows) {
    TextStyle head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Table(
      columnWidths: const {0: FlexColumnWidth(2.2)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [for (final h in headers) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(h, style: head))]),
        for (final r in rows)
          TableRow(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
            children: [
              for (var i = 0; i < r.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(r[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500)),
                ),
            ],
          ),
      ],
    );
  }
}
