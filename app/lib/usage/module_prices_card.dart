import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/app_module.dart';

/// TABELA de preços dos módulos (super-admin). É o preço que aparece na vitrine
/// de quem ainda não negociou nada; preço por empresa continua no diálogo de
/// módulos daquela conta e ganha desta tabela.
class ModulePricesCard extends StatefulWidget {
  const ModulePricesCard({super.key});

  @override
  State<ModulePricesCard> createState() => _ModulePricesCardState();
}

class _ModulePricesCardState extends State<ModulePricesCard> {
  final _api = ApiClient.instance;
  final Map<String, TextEditingController> campos = {};
  List<AppModule> catalogo = [];
  bool loading = true;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // O catálogo vem de /modules (a conta do super-admin passa direto no gate).
    final cat = await _api.get('/modules');
    final pre = await _api.get('/admin/module-prices');
    if (!mounted) return;
    final precos = pre.ok && pre.data is Map ? Map<String, dynamic>.from(pre.data as Map) : {};
    setState(() {
      loading = false;
      catalogo = cat.ok && cat.data is List
          ? (cat.data as List)
              .map((e) => AppModule.fromJson(e as Map<String, dynamic>))
              .where((m) => !m.core)
              .toList()
          : [];
      for (final m in catalogo) {
        final v = (precos[m.key] ?? 0) as int;
        campos[m.key] = TextEditingController(text: v > 0 ? (v / 100).toStringAsFixed(2) : '');
      }
    });
  }

  Future<void> _salvar() async {
    setState(() => salvando = true);
    final body = <String, int>{};
    campos.forEach((k, c) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) body[k] = (v * 100).round();
    });
    final r = await _api.put('/admin/module-prices', body);
    if (!mounted) return;
    setState(() => salvando = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Tabela de preços salva' : (r.message ?? 'Não foi possível salvar'))));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preços dos módulos (tabela)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Mensalidade padrão de cada módulo. Em branco = "sob consulta". Empresa com preço '
              'negociado ignora esta tabela.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
          const SizedBox(height: 12),
          if (loading)
            const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in catalogo)
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: campos[m.key],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: m.name,
                        prefixText: 'R\$ ',
                        isDense: true,
                        helperText: m.comingSoon ? 'em breve' : null,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
              onPressed: (loading || salvando) ? null : _salvar,
              icon: salvando
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Salvar tabela'),
            ),
          ),
        ],
      ),
    );
  }
}
