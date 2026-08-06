import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/usage.dart';

class UsageController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<CompanyUsage> companies = [];
  Pricing pricing = Pricing(conversation: 0, per1kTokens: 0, packages: const []);
  bool loading = false;
  bool savingPricing = false;
  String? error;

  /// Período selecionado: month | lastMonth | 7d | 30d.
  String period = '30d';
  String fromLabel = '';
  String toLabel = '';

  Future<void> load([String? p]) async {
    if (p != null) period = p;
    loading = true;
    error = null;
    notifyListeners();
    final (from, to) = _range(period);
    final r = await _api.get('/admin/usage?from=$from&to=$to');
    loading = false;
    if (r.ok && r.data is Map) {
      final data = r.data as Map<String, dynamic>;
      fromLabel = data['from'] ?? from;
      toLabel = data['to'] ?? to;
      pricing = Pricing.fromJson(data['pricing'] as Map<String, dynamic>?);
      companies = ((data['companies'] as List?) ?? [])
          .map((e) => CompanyUsage.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      error = r.message ?? 'Erro ao carregar o consumo';
    }
    notifyListeners();
    loadMetaPricing(); // tabela de custo da Meta (referência do dono)
    loadAICosts(); // custo dos modelos de IA
  }

  /// Salva os preços da plataforma e recarrega (recalcula os valores). Retorna erro.
  /// Tabela de custo da META (referência do dono; nunca vai ao cliente).
  MetaPricingTable metaPricing = MetaPricingTable();
  bool refreshingMeta = false;

  /// Custos dos modelos de IA (o que pagamos ao provedor).
  AICostTable aiCosts = AICostTable();

  Future<void> loadAICosts() async {
    final r = await _api.get('/admin/ai-costs');
    if (r.ok && r.data is Map) {
      aiCosts = AICostTable.fromJson((r.data as Map).cast<String, dynamic>());
      notifyListeners();
    }
  }

  /// Salva a tabela de custos de IA (lista de modelos).
  Future<String?> saveAICosts(List<AIModelCost> models) async {
    final r = await _api.put('/admin/ai-costs', {'models': models.map((m) => m.toJson()).toList()});
    if (r.ok && r.data is Map) {
      aiCosts = AICostTable.fromJson((r.data as Map).cast<String, dynamic>());
      notifyListeners();
      return null;
    }
    return r.message ?? 'Não foi possível salvar os custos de IA';
  }

  /// Tokens de IA consumidos por todas as empresas no período.
  int get totalAITokens => companies.fold<int>(0, (a, u) => a + u.aiTokens);

  Future<void> loadMetaPricing() async {
    final r = await _api.get('/admin/meta-pricing');
    if (r.ok && r.data is Map) {
      metaPricing = MetaPricingTable.fromJson((r.data as Map).cast<String, dynamic>());
      notifyListeners();
    }
  }

  /// Consulta a Meta agora (a atualização também roda sozinha, 1x por dia).
  Future<String?> refreshMetaPricing() async {
    refreshingMeta = true;
    notifyListeners();
    final r = await _api.post('/admin/meta-pricing/refresh');
    refreshingMeta = false;
    if (r.ok && r.data is Map) {
      metaPricing = MetaPricingTable.fromJson((r.data as Map).cast<String, dynamic>());
      notifyListeners();
      return null;
    }
    notifyListeners();
    return r.message ?? 'Não foi possível consultar a Meta';
  }

  Future<String?> savePricing(
    double conversation,
    double per1kTokens,
    List<double> packages, {
    double marketing = 0,
    double utility = 0,
    double authentication = 0,
  }) async {
    savingPricing = true;
    notifyListeners();
    final r = await _api.put('/admin/pricing', {
      'price_conversation': conversation,
      'price_1k_tokens': per1kTokens,
      'price_marketing': marketing,
      'price_utility': utility,
      'price_authentication': authentication,
      'packages': packages,
    });
    savingPricing = false;
    if (!r.ok) {
      notifyListeners();
      return r.message ?? 'Não foi possível salvar os preços';
    }
    await load(); // recarrega com os valores recalculados
    return null;
  }

  (String, String) _range(String p) {
    final now = DateTime.now();
    late DateTime from;
    late DateTime to;
    switch (p) {
      case 'lastMonth':
        from = DateTime(now.year, now.month - 1, 1);
        to = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
      case '7d':
        to = now;
        from = now.subtract(const Duration(days: 7));
      case '30d':
        to = now;
        from = now.subtract(const Duration(days: 30));
      default: // month
        from = DateTime(now.year, now.month, 1);
        to = now;
    }
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (fmt(from), fmt(to));
  }
}
