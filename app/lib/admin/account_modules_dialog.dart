import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/app_module.dart';

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
  String? salvando; // chave do módulo em gravação

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.get('/admin/accounts/${widget.accountId}/modules');
    if (!mounted) return;
    setState(() {
      loading = false;
      modulos = r.ok && r.data is List
          ? (r.data as List).map((e) => AppModule.fromJson(e as Map<String, dynamic>)).toList()
          : [];
    });
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
