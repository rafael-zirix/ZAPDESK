import 'package:flutter/material.dart';

import '../core/ai_logo.dart';
import '../core/api_client.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';
import '../models/package.dart';

/// Construtor de pacotes (super-admin): monta o que se vende. Preço mensal
/// fechado; as peças definem o que o cliente recebe. Espelha o protótipo
/// aprovado — lista à esquerda, editor com prévia ao vivo à direita.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final _api = ApiClient.instance;
  List<AppPackage> _pkgs = [];
  List<Map<String, dynamic>> _models = []; // modelos de IA p/ preço por modelo
  bool _loading = true;
  AppPackage? _edit; // pacote em edição (cópia); null = nada selecionado
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.get('/admin/packages');
    final rm = await _api.get('/admin/ai-costs');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _pkgs = r.ok && r.data is List
          ? (r.data as List).map((e) => AppPackage.fromJson(e as Map<String, dynamic>)).toList()
          : [];
      _models = rm.ok && rm.data is Map && (rm.data as Map)['models'] is List
          ? ((rm.data as Map)['models'] as List).cast<Map<String, dynamic>>()
          : [];
    });
  }

  void _new() => setState(() => _edit = AppPackage(name: 'Novo pacote', priceMonthCents: 14900));
  void _select(AppPackage p) => setState(() => _edit = p.copy());

  Future<void> _save() async {
    final p = _edit;
    if (p == null) return;
    setState(() => _saving = true);
    final r = p.id == null
        ? await _api.post('/admin/packages', p.toJson())
        : await _api.put('/admin/packages/${p.id}', p.toJson());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Pacote salvo' : (r.message ?? 'Não foi possível salvar'))));
    if (r.ok) {
      await _load();
      if (r.data is Map) setState(() => _edit = AppPackage.fromJson(r.data as Map<String, dynamic>));
    }
  }

  Future<void> _delete() async {
    final p = _edit;
    if (p?.id == null) {
      setState(() => _edit = null);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir pacote'),
        content: Text('Excluir "${p!.name}"? Empresas que já usam este pacote ficam sem pacote até você atribuir outro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/admin/packages/${p!.id}');
    if (!mounted) return;
    if (r.ok) {
      setState(() => _edit = null);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(title: 'Pacotes', actionLabel: 'Novo pacote', onAction: _new),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (_, box) {
                    final wide = box.maxWidth >= 900;
                    final list = _listPane();
                    final editor = _edit == null ? _empty() : _editorPane(_edit!);
                    if (!wide) {
                      return _edit == null ? list : editor;
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 330, child: list),
                        VerticalDivider(width: 1, color: AppTheme.border),
                        Expanded(child: editor),
                      ],
                    );
                  }),
          ),
        ],
      ),
    );
  }

  // ---- lista ----
  Widget _listPane() {
    if (_pkgs.isEmpty) {
      return const Center(
          child: Padding(padding: EdgeInsets.all(24), child: Text('Nenhum pacote ainda. Crie o primeiro.')));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _pkgs.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.border),
      itemBuilder: (_, i) {
        final p = _pkgs[i];
        final sel = _edit?.id == p.id && p.id != null;
        return ListTile(
          selected: sel,
          selectedTileColor: AppTheme.sidebarSel,
          leading: CircleAvatar(
            backgroundColor: p.active ? AppTheme.seed : Colors.grey,
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 20),
          ),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('R\$ ${reaisFromCents(p.priceMonthCents)}/mês${p.active ? '' : ' · inativo'}',
              style: TextStyle(color: p.active ? AppTheme.seed : Colors.grey, fontSize: 12.5)),
          onTap: () => _select(p),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.seed.withValues(alpha: .5)),
            const SizedBox(height: 12),
            const Text('Escolha um pacote para editar', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('ou crie um novo.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ]),
        ),
      );

  // ---- editor + prévia ----
  Widget _editorPane(AppPackage p) {
    return LayoutBuilder(builder: (_, box) {
      final wide = box.maxWidth >= 720;
      final form = _form(p);
      final preview = _preview(p);
      final content = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: form),
              const SizedBox(width: 20),
              SizedBox(width: 300, child: preview),
            ])
          : Column(children: [form, const SizedBox(height: 20), preview]);
      return SingleChildScrollView(padding: const EdgeInsets.all(24), child: content);
    });
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _form(AppPackage p) {
    void ch(VoidCallback fn) => setState(fn);
    return _card([
      // nome + preço
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: _field('Nome do pacote',
              child: TextFormField(
                initialValue: p.name,
                key: ValueKey('name-${p.id}'),
                decoration: _dec(),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                onChanged: (v) => ch(() => p.name = v),
              )),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 150,
          child: _field('Preço mensal',
              child: TextFormField(
                initialValue: reaisFromCents(p.priceMonthCents),
                key: ValueKey('price-${p.id}'),
                keyboardType: TextInputType.number,
                decoration: _dec(prefix: 'R\$ ', suffix: '/mês'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                onChanged: (v) => ch(() => p.priceMonthCents = centsFromReais(v)),
              )),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Switch(value: p.active, activeColor: AppTheme.seed, onChanged: (v) => ch(() => p.active = v)),
        const SizedBox(width: 4),
        Text(p.active ? 'Publicado — aparece na vitrine' : 'Rascunho — oculto do cliente',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ]),
      const Divider(height: 28),
      const _Lbl('O que o pacote inclui'),
      const SizedBox(height: 4),
      _stepRow(Icons.chat_bubble_outline, 'Linhas de WhatsApp', 'Números na caixa de entrada', p.incLines, 1, 10,
          (v) => ch(() => p.incLines = v)),
      Padding(
        padding: const EdgeInsets.only(left: 52, bottom: 10),
        child: Row(children: [
          Text('Linha extra:', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: reaisFromCents(p.lineAddonCents),
              key: ValueKey('addon-${p.id}'),
              keyboardType: TextInputType.number,
              decoration: _dec(prefix: 'R\$ ', dense: true),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              onChanged: (v) => ch(() => p.lineAddonCents = centsFromReais(v)),
            ),
          ),
          Text(' /linha·mês', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
        ]),
      ),
      _stepRow(Icons.people_outline, 'Atendentes', 'Acessos ao painel', p.incAgents, 1, 50,
          (v) => ch(() => p.incAgents = v)),
      _toggleRow(Icons.smart_toy_outlined, 'Atendente IA', 'Responde sozinho no tom da empresa', p.incIA,
          (v) => ch(() => p.incIA = v)),
      _toggleRow(Icons.camera_alt_outlined, 'Instagram', 'Direct e Lead Ads na mesma caixa', p.incInstagram,
          (v) => ch(() => p.incInstagram = v)),
      _toggleRow(Icons.campaign_outlined, 'Campanhas', 'Disparos em massa por template', p.incCampanhas,
          (v) => ch(() => p.incCampanhas = v)),
      _toggleRow(Icons.query_stats_outlined, 'Métricas', 'Relatórios de atendimento e IA', p.incMetricas,
          (v) => ch(() => p.incMetricas = v)),
      _toggleRow(Icons.view_kanban_outlined, 'CRM', 'Quadro de leads e funil de vendas', p.incCRM,
          (v) => ch(() => p.incCRM = v)),
      _toggleRow(Icons.filter_alt_outlined, 'Leads & Qualificação', 'Captação e qualificação de leads', p.incLeads,
          (v) => ch(() => p.incLeads = v)),
      // franquia
      const Divider(height: 28),
      Opacity(
        opacity: p.incIA ? 1 : .5,
        child: IgnorePointer(
          ignoring: !p.incIA,
          child: _field('Franquia de IA inclusa (R\$/mês)',
              child: Row(children: [
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    initialValue: reaisFromCents(p.franchiseCents),
                    key: ValueKey('fran-${p.id}-${p.incIA}'),
                    keyboardType: TextInputType.number,
                    decoration: _dec(prefix: 'R\$ '),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    onChanged: (v) => ch(() => p.franchiseCents = centsFromReais(v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      p.incIA
                          ? 'Vira mais ou menos token conforme a IA que o cliente usar. Zerado = só crédito avulso.'
                          : 'Ligue o Atendente IA para incluir franquia.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ),
              ])),
        ),
      ),
      const Divider(height: 28),
      _field('Preço por tipo de mensagem (R\$/msg entregue)',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'A Meta cobra o cliente por modelo entregue, por categoria. Defina o preço deste pacote:',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: reaisFromCents(p.msgMarketingCents),
                  key: ValueKey('mkt-${p.id}'),
                  keyboardType: TextInputType.number,
                  decoration: _dec(prefix: 'R\$ ', dense: true).copyWith(labelText: 'Marketing'),
                  onChanged: (v) => ch(() => p.msgMarketingCents = centsFromReais(v)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: reaisFromCents(p.msgUtilityCents),
                  key: ValueKey('util-${p.id}'),
                  keyboardType: TextInputType.number,
                  decoration: _dec(prefix: 'R\$ ', dense: true).copyWith(labelText: 'Utilidade'),
                  onChanged: (v) => ch(() => p.msgUtilityCents = centsFromReais(v)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: reaisFromCents(p.msgAuthCents),
                  key: ValueKey('auth-${p.id}'),
                  keyboardType: TextInputType.number,
                  decoration: _dec(prefix: 'R\$ ', dense: true).copyWith(labelText: 'Autenticação'),
                  onChanged: (v) => ch(() => p.msgAuthCents = centsFromReais(v)),
                ),
              ),
            ]),
          ])),
      // IA — preço de VENDA por modelo (R$ por 1M tokens), neste pacote.
      const Divider(height: 28),
      _field('Preço de venda da IA por modelo (R\$ por 1M tokens)',
          child: _models.isEmpty
              ? Text('Cadastre modelos de IA em "Custo do provedor" para precificá-los aqui.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'O cliente escolhe o modelo no painel dele e vê o preço deste pacote antes de usar.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  const SizedBox(height: 10),
                  for (final m in _models)
                    Builder(builder: (_) {
                      final mid = (m['model'] ?? '').toString();
                      final cur = p.aiPrices[mid] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: aiLogo((m['logo'] ?? '').toString(), size: 26),
                          ),
                          SizedBox(
                            width: 214,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((m['label'] ?? mid).toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                                Text([
                                  (m['provider'] ?? '').toString(),
                                  mid,
                                ].where((e) => e.toString().isNotEmpty).join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey.shade600)),
                                // Custo do provedor (só super-admin) — referência
                                // para definir o preço de venda com margem.
                                if (((m['per1k'] as num?) ?? 0) > 0)
                                  Text(
                                      'seu custo R\$ ${(m['per1k'] as num).toDouble().toStringAsFixed(2).replaceAll('.', ',')}/1M',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade800,
                                          fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 170,
                            child: TextFormField(
                              initialValue: cur == 0 ? '' : '$cur',
                              key: ValueKey('aip-${p.id}-$mid'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: _dec(prefix: 'R\$ ', dense: true).copyWith(suffixText: '/1M'),
                              onChanged: (v) => ch(() => p.aiPrices = {
                                    ...p.aiPrices,
                                    mid: double.tryParse(v.replaceAll(',', '.')) ?? 0,
                                  }),
                            ),
                          ),
                        ]),
                      );
                    }),
                ])),
      // Recarga avulsa por TAMANHO (tokens). O preço deriva do preço/1M do modelo.
      const Divider(height: 28),
      _field('Pacotes de recarga avulsa (tamanhos em tokens, separados por vírgula)',
          child: SizedBox(
            width: 340,
            child: TextFormField(
              initialValue: p.rechargeSizes.join(', '),
              key: ValueKey('recharge-${p.id}'),
              decoration: _dec(dense: true).copyWith(hintText: 'ex.: 500, 1000, 5000, 10000'),
              onChanged: (v) => ch(() => p.rechargeSizes = v
                  .split(',')
                  .map((e) => int.tryParse(e.trim()) ?? 0)
                  .where((n) => n > 0)
                  .toList()),
            ),
          )),
      // Base de conhecimento: teto de caracteres liberado neste pacote.
      const Divider(height: 28),
      _field('Base de conhecimento — tamanho disponível (caracteres)',
          child: SizedBox(
            width: 220,
            child: TextFormField(
              initialValue: p.kbChars.toString(),
              key: ValueKey('kb-${p.id}'),
              keyboardType: TextInputType.number,
              decoration: _dec(dense: true).copyWith(suffixText: 'caracteres'),
              onChanged: (v) =>
                  ch(() => p.kbChars = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0),
            ),
          )),
      const SizedBox(height: 20),
      Row(children: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 18),
          label: Text(p.id == null ? 'Criar pacote' : 'Salvar'),
        ),
        const SizedBox(width: 10),
        TextButton(onPressed: () => setState(() => _edit = null), child: const Text('Cancelar')),
        const Spacer(),
        if (p.id != null)
          TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: const Text('Excluir', style: TextStyle(color: Colors.red))),
      ]),
    ]);
  }

  // prévia "como o cliente vê"
  Widget _preview(AppPackage p) {
    Widget inc(String t, bool on) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                  color: on ? AppTheme.seed.withValues(alpha: .15) : Colors.grey.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.check, size: 12, color: on ? AppTheme.seed : Colors.grey),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Opacity(
                    opacity: on ? 1 : .4,
                    child: Text(t, style: const TextStyle(fontSize: 13.5)))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 24, offset: const Offset(0, 12))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.seed, const Color(0xFF0B7268)])),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('COMO O CLIENTE VÊ',
                style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            const SizedBox(height: 8),
            Text(p.name.isEmpty ? 'Pacote' : p.name,
                style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Padding(
                  padding: EdgeInsets.only(bottom: 5), child: Text('R\$ ', style: TextStyle(color: Colors.white, fontSize: 15))),
              Text(reaisFromCents(p.priceMonthCents),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
              const Padding(
                  padding: EdgeInsets.only(bottom: 5), child: Text('/mês', style: TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            inc('${p.incLines} linha${p.incLines > 1 ? 's' : ''} de WhatsApp', true),
            inc('${p.incAgents} atendentes', true),
            inc('Atendente de IA 24/7', p.incIA),
            inc('Instagram — Direct e Lead Ads', p.incInstagram),
            inc('Campanhas em massa', p.incCampanhas),
            inc('Métricas e relatórios', p.incMetricas),
            inc('CRM — quadro e funil', p.incCRM),
            inc('Leads & Qualificação', p.incLeads),
            if (p.incIA && p.franchiseCents > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: AppTheme.seed.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppTheme.seed.withValues(alpha: .25))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('FRANQUIA MENSAL DE IA',
                      style: TextStyle(color: AppTheme.seed, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
                  const SizedBox(height: 4),
                  Text('R\$ ${reaisFromCents(p.franchiseCents)}/mês',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('vira token conforme a IA em uso · renova todo mês',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ]),
              ),
            ],
            if (p.lineAddonCents > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Linha extra: R\$ ${reaisFromCents(p.lineAddonCents)}/mês',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
              ),
          ]),
        ),
      ]),
    );
  }

  // ---- widgets utilitários ----
  Widget _field(String label, {required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_Lbl(label), const SizedBox(height: 6), child],
      );

  InputDecoration _dec({String? prefix, String? suffix, bool dense = false}) => InputDecoration(
        isDense: dense,
        prefixText: prefix,
        suffixText: suffix,
        filled: true,
        fillColor: AppTheme.bg,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.seed, width: 1.6)),
      );

  Widget _rowBase(IconData ic, String t, String d, bool on, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: on ? AppTheme.seed.withValues(alpha: .12) : AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? AppTheme.seed.withValues(alpha: .4) : AppTheme.border)),
            child: Icon(ic, size: 19, color: on ? AppTheme.seed : Colors.grey.shade600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              Text(d, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            ]),
          ),
          control,
        ]),
      );

  Widget _toggleRow(IconData ic, String t, String d, bool v, ValueChanged<bool> onCh) =>
      _rowBase(ic, t, d, v, Switch(value: v, activeColor: AppTheme.seed, onChanged: onCh));

  Widget _stepRow(IconData ic, String t, String d, int v, int min, int max, ValueChanged<int> onCh) => _rowBase(
      ic,
      t,
      d,
      true,
      Container(
        decoration: BoxDecoration(border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn('–', () => onCh(v > min ? v - 1 : v)),
          Container(
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border.symmetric(vertical: BorderSide(color: AppTheme.border))),
            child: Text('$v', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          _stepBtn('+', () => onCh(v < max ? v + 1 : v)),
        ]),
      ));

  Widget _stepBtn(String s, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
            width: 32,
            height: 32,
            child: Center(child: Text(s, style: TextStyle(fontSize: 18, color: AppTheme.seed)))),
      );
}

class _Lbl extends StatelessWidget {
  const _Lbl(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: Colors.grey.shade600));
}
