import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/crm.dart';

/// Estado do CRM: quadro (etapas + negócios), vendedores e motivos de perda.
/// Convenção do painel: ações devolvem `null` no sucesso e a mensagem de erro
/// pronta para SnackBar quando falham.
class CrmController extends ChangeNotifier {
  final _api = ApiClient.instance;

  bool loading = false;
  String? error;
  List<CrmStage> stages = [];
  List<CrmDeal> deals = [];
  List<CrmSeller> sellers = [];
  List<CrmLossReason> lossReasons = [];

  /// Papel de quem usa (vem da tela, via AuthController).
  bool isAdmin = false;
  String myUserId = '';

  /// Filtro por vendedor (admin). null = todos; '' não é usado aqui.
  String? ownerFilter;

  void configure({required bool admin, required String userId}) {
    isAdmin = admin;
    myUserId = userId;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final q = (isAdmin && ownerFilter != null) ? '?owner_id=$ownerFilter' : '';
    final r = await _api.get('/crm/board$q');
    if (!r.ok) {
      error = r.message ?? 'Erro ao carregar o quadro';
      loading = false;
      notifyListeners();
      return;
    }
    final data = r.data as Map;
    stages = [for (final s in (data['stages'] as List? ?? [])) CrmStage.fromJson(s)];
    deals = [for (final d in (data['deals'] as List? ?? [])) CrmDeal.fromJson(d)];
    loading = false;
    notifyListeners();
    // Vendedores: alimentam o filtro (admin) e o dropdown de dono do editor.
    if (isAdmin && sellers.isEmpty) {
      final rs = await _api.get('/crm/sellers');
      if (rs.ok && rs.data is List) {
        sellers = [for (final s in rs.data as List) CrmSeller.fromJson(s)];
        notifyListeners();
      }
    }
  }

  Future<void> setOwnerFilter(String? ownerId) async {
    ownerFilter = ownerId;
    await load();
    if (report != null) await loadReport();
  }

  // --- Relatório (Funil / Métricas / Perdidos) ---

  CrmReport? report;
  bool reportLoading = false;
  String? reportError;

  /// Recorte de período em dias (0 = todo o período).
  int periodDays = 30;

  Future<void> setPeriod(int days) async {
    periodDays = days;
    await loadReport();
  }

  Future<void> loadReport() async {
    reportLoading = true;
    reportError = null;
    notifyListeners();
    final params = <String>[];
    if (isAdmin && ownerFilter != null) params.add('owner_id=$ownerFilter');
    if (periodDays > 0) {
      // Dia local (UTC-3): hoje inclusive, N dias para trás.
      final today = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final from = today.subtract(Duration(days: periodDays - 1));
      String d(DateTime t) =>
          '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      params.add('from=${d(from)}');
      params.add('to=${d(today)}');
    }
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    final r = await _api.get('/crm/reports$q');
    if (!r.ok) {
      reportError = r.message ?? 'Erro ao carregar o relatório';
      reportLoading = false;
      notifyListeners();
      return;
    }
    report = CrmReport.fromJson(r.data as Map<String, dynamic>);
    reportLoading = false;
    notifyListeners();
  }

  /// Negócios de uma coluna, ORDEM CRONOLÓGICA pelo retorno: quem tem retorno
  /// agendado vem primeiro, do mais atrasado/próximo (topo) ao mais distante;
  /// quem não tem retorno cai no fim, na ordem manual do quadro.
  List<CrmDeal> dealsOf(String stageId) {
    final list = deals.where((d) => d.stageId == stageId).toList();
    list.sort((a, b) {
      final af = a.nextFollowUpAt;
      final bf = b.nextFollowUpAt;
      if (af != null && bf != null) {
        final c = af.compareTo(bf); // cronológico: atrasado/hoje no topo
        if (c != 0) return c;
      } else if (af != null) {
        return -1; // com retorno vem antes de sem retorno
      } else if (bf != null) {
        return 1;
      }
      if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
      return a.id.compareTo(b.id);
    });
    return list;
  }

  int valueOf(String stageId) =>
      dealsOf(stageId).fold(0, (sum, d) => sum + d.valueCents);

  /// Move otimista: o card troca de coluna na hora; erro desfaz recarregando.
  Future<String?> moveDeal(CrmDeal deal, String stageId) async {
    final fromStage = deal.stageId;
    if (fromStage == stageId) return null;
    final order = dealsOf(stageId).isEmpty
        ? 0
        : dealsOf(stageId).map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    deal.stageId = stageId;
    deal.sortOrder = order;
    notifyListeners();
    final r = await _api.patch('/crm/deals/${deal.id}/move',
        {'stage_id': stageId, 'sort_order': order});
    if (!r.ok) {
      await load(); // desfaz: a verdade é do servidor
      return r.message ?? 'Erro ao mover o negócio';
    }
    await load(); // status (ganho/reaberto) e agregados vêm do servidor
    return null;
  }

  Future<String?> createDeal(Map<String, dynamic> body) async {
    final r = await _api.post('/crm/deals', body);
    if (!r.ok) return r.message ?? 'Erro ao criar o negócio';
    await load();
    return null;
  }

  Future<String?> updateDeal(String id, Map<String, dynamic> body) async {
    final r = await _api.put('/crm/deals/$id', body);
    if (!r.ok) return r.message ?? 'Erro ao salvar o negócio';
    await load();
    return null;
  }

  Future<String?> loseDeal(String id, String? reasonId, String? notes) async {
    final r = await _api.post('/crm/deals/$id/lose', {
      if (reasonId != null && reasonId.isNotEmpty) 'lost_reason_id': reasonId,
      if (notes != null && notes.isNotEmpty) 'lost_notes': notes,
    });
    if (!r.ok) return r.message ?? 'Erro ao marcar a perda';
    await load();
    return null;
  }

  Future<String?> deleteDeal(String id) async {
    final r = await _api.delete('/crm/deals/$id');
    if (!r.ok) return r.message ?? 'Erro ao excluir o negócio';
    await load();
    return null;
  }

  Future<void> loadLossReasons() async {
    if (lossReasons.isNotEmpty) return;
    final r = await _api.get('/crm/loss-reasons');
    if (r.ok && r.data is List) {
      lossReasons = [for (final m in r.data as List) CrmLossReason.fromJson(m)];
      notifyListeners();
    }
  }

  // --- Etapas (admin) ---

  Future<String?> createStage(String name, String color) async {
    final ordinal = stages.isEmpty ? 0 : stages.map((s) => s.ordinal).reduce((a, b) => a > b ? a : b) + 1;
    final r = await _api.post('/crm/stages',
        {'name': name, 'color': color, 'ordinal': ordinal});
    if (!r.ok) return r.message ?? 'Erro ao criar a etapa';
    await load();
    return null;
  }

  Future<String?> updateStage(String id, Map<String, dynamic> body) async {
    final r = await _api.put('/crm/stages/$id', body);
    if (!r.ok) return r.message ?? 'Erro ao salvar a etapa';
    await load();
    return null;
  }

  Future<String?> deleteStage(String id) async {
    final r = await _api.delete('/crm/stages/$id');
    if (!r.ok) return r.message ?? 'Erro ao excluir a etapa';
    await load();
    return null;
  }

  /// Sobe/desce a etapa trocando os ordinais com a vizinha.
  Future<String?> reorderStage(CrmStage stage, int delta) async {
    final sorted = [...stages]..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final i = sorted.indexWhere((s) => s.id == stage.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= sorted.length) return null;
    final other = sorted[j];
    final e1 = await updateStage(stage.id, {'ordinal': other.ordinal});
    if (e1 != null) return e1;
    return updateStage(other.id, {'ordinal': stage.ordinal});
  }
}
