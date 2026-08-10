// Página de DESENVOLVIMENTO: renderiza o quadro do CRM com dados falsos,
// sem login — para depurar visualmente o painel no CanvasKit (foi assim que
// se descobriu que o FilledButton não pinta fora de diálogo; ver crmButton).
// NÃO entra no deploy (main.dart/main_mobile.dart são os entrypoints reais).
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'crm/crm_board.dart';
import 'crm/crm_controller.dart';
import 'models/crm.dart';

void main() {
  final crm = CrmController();
  crm.configure(admin: true, userId: 'u1');
  crm.loading = false;
  crm.stages = [
    CrmStage(id: 's1', name: 'Lead', color: '#64748B', ordinal: 0, isWon: false, isSystem: true),
    CrmStage(id: 's2', name: 'Contato', color: '#7C3AED', ordinal: 1, isWon: false, isSystem: false),
    CrmStage(id: 's3', name: 'Fechado', color: '#16A34A', ordinal: 2, isWon: true, isSystem: true),
  ];
  crm.deals = [
    CrmDeal(
      id: 'd1',
      contactId: 'c1',
      stageId: 's1',
      valueCents: 111111,
      status: 'open',
      sortOrder: 0,
      contactName: 'Bruno Barbeito',
      ownerName: 'Rafael Campos',
      nextFollowUpAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
    ),
    CrmDeal(
      id: 'd2',
      contactId: 'c2',
      stageId: 's1',
      valueCents: 250000,
      status: 'open',
      sortOrder: 1,
      contactName: 'Maria Silva',
      nextFollowUpAt: DateTime.now().toUtc(),
    ),
  ];
  crm.sellers = [CrmSeller(id: 'u1', name: 'Rafael Campos', role: 'admin')];
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppTheme.bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: CrmBoardView(crm: crm),
      ),
    ),
  ));
}
