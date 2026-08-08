import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/app_module.dart';
import '../models/package.dart';

/// Tabela de MÓDULOS de uma empresa (super-admin): é onde a venda acontece —
/// liga, desliga, dá teste por N dias e negocia preço fora da tabela.
class AccountModulesDialog extends StatefulWidget {
  const AccountModulesDialog({super.key, required this.accountId, required this.accountName});

  final String accountId;
  final String accountName;

  @override
  State<AccountModulesDialog> createState() => _AccountModulesDialogState();
}

class _AccountModulesDialogState extends State<AccountModulesDialog> {
  final _api = ApiClient.instance;
  List<AppModule> modulos = [];
  bool loading = true;

  // Régua do plano: o que o Free limita e o pago solta.
  final _assentos = TextEditingController();
  final _numeros = TextEditingController();
  final _historico = TextEditingController();
  bool salvandoPlano = false;
  String? salvando; // chave do módulo em gravação

  // Pacote aplicado à empresa: aplicá-lo já liga os módulos e ajusta os limites.
  List<AppPackage> pacotes = [];
  String? pacoteId;
  bool aplicandoPacote = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/admin/accounts/${widget.accountId}/modules');
    final p = await _api.get('/admin/accounts/${widget.accountId}/plan');
    final lp = await _api.get('/admin/packages');
    final cp = await _api.get('/admin/accounts/${widget.accountId}/package');
    if (!mounted) return;
    if (p.ok && p.data is Map) {
      final m = p.data as Map;
      _assentos.text = '${m['max_users'] ?? 2}';
      _numeros.text = '${m['max_numbers'] ?? 1}';
      _historico.text = '${m['history_days'] ?? 0}';
    }
    setState(() {
      loading = false;
      modulos = r.ok && r.data is List
          ? (r.data as List).map((e) => AppModule.fromJson(e as Map<String, dynamic>)).toList()
          : [];
      pacotes = lp.ok && lp.data is List
          ? (lp.data as List).map((e) => AppPackage.fromJson((e as Map).cast<String, dynamic>())).toList()
          : [];
      pacoteId = (cp.ok && cp.data is Map) ? (cp.data as Map)['id']?.toString() : null;
    });
  }

  Future<void> _aplicarPacote() async {
    if (pacoteId == null) return;
    setState(() => aplicandoPacote = true);
    final r = await _api.put('/admin/accounts/${widget.accountId}/package', {'package_id': pacoteId});
    if (!mounted) return;
    setState(() => aplicandoPacote = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? 'Pacote aplicado — módulos e limites ajustados' : (r.message ?? 'Não foi possível aplicar'))));
    if (r.ok) await _load();
  }

  Widget _pacoteCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.seed.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.seed.withValues(alpha: .3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: AppTheme.seed),
          const SizedBox(width: 8),
          const Text('Pacote da empresa', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 4),
        Text('Aplicar um pacote liga os módulos que ele inclui e ajusta linhas/atendentes de uma vez.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: pacoteId,
              isExpanded: true,
              decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              hint: const Text('Escolha um pacote'),
              items: pacotes
                  .map((p) => DropdownMenuItem(
                      value: p.id, child: Text('${p.name} — R\$ ${reaisFromCents(p.priceMonthCents)}/mês')))
                  .toList(),
              onChanged: (v) => setState(() => pacoteId = v),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: (pacoteId == null || aplicandoPacote) ? null : _aplicarPacote,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: aplicandoPacote
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Aplicar'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _salvar(AppModule m, {required bool enabled, int? priceCents, int trialDays = 0}) async {
    setState(() => salvando = m.key);
    final r = await _api.put('/admin/accounts/${widget.accountId}/modules', {
      'module': m.key,
      'enabled': enabled,
      'price_cents': ?priceCents,
      if (trialDays > 0) 'trial_days': trialDays,
    });
    if (!mounted) return;
    setState(() => salvando = null);
    if (r.ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível salvar')));
    }
  }

  Future<void> _salvarPlano() async {
    setState(() => salvandoPlano = true);
    final r = await _api.put('/admin/accounts/${widget.accountId}/plan', {
      'max_users': int.tryParse(_assentos.text.trim()) ?? 2,
      'max_numbers': int.tryParse(_numeros.text.trim()) ?? 1,
      'history_days': int.tryParse(_historico.text.trim()) ?? 0,
    });
    if (!mounted) return;
    setState(() => salvandoPlano = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Plano atualizado' : (r.message ?? 'Não foi possível salvar'))));
  }

  // Limites do plano. O Free nasce 2 usuários / 1 número / 90 dias; o pago solta.
  Widget _planoCard() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plano (limites do núcleo)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _assentos,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Usuários', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _numeros,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Números', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _historico,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Histórico (dias)', helperText: '0 = ilimitado', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                onPressed: salvandoPlano ? null : _salvarPlano,
                child: const Text('Salvar'),
              ),
            ]),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Módulos — ${widget.accountName}'),
      content: SizedBox(
        width: 640,
        child: loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('O núcleo (Atendimento) vem sempre. Os demais são a venda: ligue o que a empresa '
                        'contratou, use o teste para deixar experimentar, e o preço só quando for diferente '
                        'da tabela.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
                    const SizedBox(height: 12),
                    _pacoteCard(),
                    const SizedBox(height: 10),
                    _planoCard(),
                    for (final m in modulos) _linha(m),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }

  Widget _linha(AppModule m) {
    final gravando = salvando == m.key;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 330,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(width: 8),
                  if (m.core) _selo('núcleo', Colors.grey),
                  if (m.comingSoon) _selo('em breve', AppTheme.seed),
                  if (m.inTrial) _selo('teste: ${m.trialDaysLeft}d', const Color(0xFFF79009)),
                ]),
                const SizedBox(height: 2),
                Text(m.description,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 90, child: Text(m.priceLabel, style: const TextStyle(fontSize: 12.5))),
          SizedBox(
            width: 130,
            child: m.core
                ? Text('sempre ativo', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
                : Row(
                    children: [
                      gravando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Switch(
                              value: m.enabled,
                              activeThumbColor: AppTheme.seed,
                              onChanged: (v) => _salvar(m, enabled: v),
                            ),
                      IconButton(
                        icon: const Icon(Icons.tune, size: 18),
                        tooltip: 'Preço e teste',
                        onPressed: () => _ajustar(m),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _selo(String txt, Color cor) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(txt, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cor)),
      );

  /// Preço combinado com ESTA empresa e teste por N dias. Preço vazio volta a
  /// valer a tabela.
  Future<void> _ajustar(AppModule m) async {
    final preco = TextEditingController(text: m.priceCents > 0 ? (m.priceCents / 100).toStringAsFixed(2) : '');
    final dias = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(m.name),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: preco,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Preço mensal desta empresa (R\$)',
                helperText: 'Em branco = preço de tabela',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dias,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Ligar como TESTE por (dias)',
                helperText: 'Em branco = contratado, sem prazo',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final valor = double.tryParse(preco.text.trim().replaceAll(',', '.'));
    await _salvar(
      m,
      enabled: true,
      priceCents: valor == null ? null : (valor * 100).round(),
      trialDays: int.tryParse(dias.text.trim()) ?? 0,
    );
  }
}
