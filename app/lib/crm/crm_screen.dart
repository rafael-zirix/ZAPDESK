import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../core/theme.dart';
import 'crm_board.dart';
import 'crm_controller.dart';
import 'crm_report_view.dart';

/// CRM — funil de vendas ligado às conversas.
///
/// Abas: Kanban (quadro real), Funil, Métricas e Perdidos (chegam na F5).
class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  String _tab = 'kanban';
  final _crm = CrmController();

  static const _tabs = [
    (key: 'kanban', label: 'Kanban', icon: Icons.view_kanban_outlined),
    (key: 'funil', label: 'Funil', icon: Icons.filter_alt_outlined),
    (key: 'metricas', label: 'Métricas', icon: Icons.query_stats_outlined),
    (key: 'perdidos', label: 'Perdidos', icon: Icons.trending_down_outlined),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = context.read<AuthController>().me;
      _crm.configure(admin: me?.isAdmin ?? false, userId: me?.id ?? '');
      _crm.load();
    });
  }

  @override
  void dispose() {
    _crm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('CRM',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 20),
                SegmentedButton<String>(
                  segments: [
                    for (final t in _tabs)
                      ButtonSegment(
                          value: t.key,
                          label: Text(t.label),
                          icon: Icon(t.icon, size: 18)),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _tab == 'kanban'
                  ? CrmBoardView(crm: _crm)
                  : CrmReportView(crm: _crm, mode: _tab),
            ),
          ],
        ),
      ),
    );
  }
}
