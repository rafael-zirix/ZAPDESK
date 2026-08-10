// Página de DESENVOLVIMENTO: preview do funil estilizado com dados de
// exemplo (os números da referência do usuário). NÃO entra no deploy.
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'crm/crm_funnel_chart.dart';
import 'models/crm.dart';

void main() {
  final rows = [
    CrmFunnelRow(stageId: '1', name: 'Lead', color: '#64748B', ordinal: 0, isWon: false, dealCount: 117, valueCents: 189032021),
    CrmFunnelRow(stageId: '2', name: 'Contato', color: '#7C3AED', ordinal: 1, isWon: false, dealCount: 72, valueCents: 89011411),
    CrmFunnelRow(stageId: '3', name: 'Proposta', color: '#F59E0B', ordinal: 2, isWon: false, dealCount: 24, valueCents: 54124400),
    CrmFunnelRow(stageId: '4', name: 'Negociação', color: '#F97316', ordinal: 3, isWon: false, dealCount: 11, valueCents: 30173150),
    CrmFunnelRow(stageId: '5', name: 'Fechado', color: '#16A34A', ordinal: 4, isWon: true, dealCount: 5, valueCents: 164760),
  ];
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppTheme.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Funil de conversão',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            CrmFunnelChart(rows: rows),
          ]),
        ),
      ),
    ),
  ));
}
