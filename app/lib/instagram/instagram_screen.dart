import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../core/api_client.dart';
import '../core/embedded_signup.dart';
import '../core/entity_form.dart';
import '../core/theme.dart';

/// Conexão da conta do Instagram (Direct + Lead Ads). O Direct e os formulários
/// caem na MESMA caixa de entrada do WhatsApp, com os mesmos setores, etiquetas
/// e IA — o canal fica marcado na conversa.
class InstagramScreen extends StatefulWidget {
  const InstagramScreen({super.key});

  @override
  State<InstagramScreen> createState() => _InstagramScreenState();
}

class _InstagramScreenState extends State<InstagramScreen> {
  final _api = ApiClient.instance;
  List<Map<String, dynamic>> contas = [];
  bool loading = true;

  // Roteiro do PRIMEIRO atendimento de lead (vale para o Direct e para o
  // WhatsApp de anúncio — o lead entra pelos dois e o filtro é o mesmo).
  final _roteiro = TextEditingController();
  final _criterio = TextEditingController();
  bool salvando = false;

  // Conexão pelo popup da Meta. Desligada até a plataforma cadastrar o
  // config_id do Facebook Login — aí o botão aparece e o manual vira alternativa.
  bool loginMeta = false;
  String _fbAppId = '', _fbConfigId = '', _fbGraph = 'v20.0';
  bool conectando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final r = await _api.get('/settings/instagram');
    final q = await _api.get('/support/lead-qualification');
    final cfg = await _api.get('/settings/instagram/login/config');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (cfg.ok && cfg.data is Map) {
        final m = cfg.data as Map;
        loginMeta = (m['enabled'] ?? false) == true;
        _fbAppId = (m['app_id'] ?? '').toString();
        _fbConfigId = (m['config_id'] ?? '').toString();
        _fbGraph = (m['graph_version'] ?? 'v20.0').toString();
      }
      contas = r.ok && r.data is List ? (r.data as List).cast<Map<String, dynamic>>() : [];
      if (q.ok && q.data is Map) {
        _roteiro.text = ((q.data as Map)['lead_script'] ?? '').toString();
        _criterio.text = ((q.data as Map)['lead_criteria'] ?? '').toString();
      }
    });
  }

  Future<void> _salvarRoteiro() async {
    setState(() => salvando = true);
    final r = await _api.put('/support/lead-qualification', {
      'lead_script': _roteiro.text.trim(),
      'lead_criteria': _criterio.text.trim(),
    });
    if (!mounted) return;
    setState(() => salvando = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Roteiro salvo' : (r.message ?? 'Não foi possível salvar'))));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          ListHeader(
            title: 'Instagram',
            actionLabel: loginMeta ? 'Conectar com Facebook' : 'Conectar conta',
            onAction: conectando ? null : (loginMeta ? _connectViaMeta : _connect),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _aviso(),
                      if (contas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma conta conectada ainda.'),
                        ),
                      for (final c in contas) _tile(c),
                      if (loginMeta)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: conectando ? null : _connect,
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: const Text('Preencher manualmente (IDs e token)'),
                            ),
                          ),
                        ),
                      _roteiroCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // O que o cliente precisa saber ANTES de tentar: o canal depende de aprovação
  // da Meta e tem regras diferentes das do WhatsApp.
  Widget _aviso() => Container(
        margin: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF79009).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF79009).withValues(alpha: 0.4)),
        ),
        child: const Text(
          'Para o Instagram funcionar são necessários: conta profissional ligada a uma Página do Facebook, '
          'mensagens de terceiros liberadas nas configurações do Instagram, e as permissões do app aprovadas '
          'pela Meta. No Instagram NÃO existe modelo aprovado: só dá para responder dentro de 24h desde a '
          'última mensagem do cliente.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF93370D)),
        ),
      );

  // O filtro do primeiro atendimento: a IA pergunta o que a empresa mandar e
  // classifica pelo critério dela. Quem descarta continua sendo gente.
  Widget _roteiroCard() {
    final temIA = context.watch<AuthController>().has('ia');
    return Container(
        margin: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Primeiro atendimento dos leads',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
                'Vale para quem chega pelo Direct E pelo WhatsApp de anúncio. A IA faz as perguntas, '
                'entrega o resumo ao vendedor e etiqueta a conversa como Prospect ou Não é prospect. '
                'Ninguém é descartado automaticamente.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
            if (!temIA)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.seed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Quem executa o roteiro é o Atendente IA. Contrate o módulo de IA para ativar o filtro '
                  '— sem ele o texto fica salvo, mas ninguém pergunta nada.',
                  style: TextStyle(fontSize: 12, color: AppTheme.seed, height: 1.35),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              enabled: temIA,
              controller: _roteiro,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'O que a IA deve descobrir',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                hintText: 'Ex.: 1) quantos veículos · 2) cidade · 3) já tem rastreador hoje? · '
                    '4) para quando precisa · 5) peça o WhatsApp se veio pelo Direct',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: temIA,
              controller: _criterio,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'O que é um prospect para a sua empresa',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                hintText: 'Ex.: prospect = 2+ veículos OU precisa em até 15 dias, e cidade atendida. '
                    'Não é prospect = fora da área ou só pesquisando preço.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                onPressed: (salvando || !temIA) ? null : _salvarRoteiro,
                icon: salvando
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Salvar roteiro'),
              ),
            ),
          ],
        ),
      );
  }

  Widget _tile(Map<String, dynamic> c) {
    final user = (c['username'] ?? '').toString();
    final ligada = (c['status'] ?? '').toString() == 'connected';
    return ListTile(
      enabled: ligada,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: ligada ? const Color(0xFFE1306C) : Colors.grey.shade400,
        child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
      ),
      title: Text(user.isEmpty ? c['ig_user_id'].toString() : '@$user',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          'Conta ${c['ig_user_id']} · Página ${c['page_id']} · '
          '${ligada ? 'conectada' : 'DESCONECTADA — não recebe nem envia'}',
          style: TextStyle(
              color: ligada ? Colors.grey.shade600 : Colors.red.shade700, fontSize: 12)),
      trailing: ligada
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.autorenew),
                  tooltip: 'Reassinar webhooks (não está recebendo mensagens)',
                  onPressed: _resubscribe,
                ),
                IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  tooltip: 'Desconectar',
                  onPressed: () => _disconnect(c),
                ),
              ],
            )
          // Ícone, não botão com texto: no CanvasKit, texto em espaço de largura
          // mínima (o trailing do ListTile) quebra letra por letra.
          : IconButton(
              icon: const Icon(Icons.power_settings_new, color: Color(0xFF12B76A)),
              tooltip: 'Reativar (reusa o token guardado)',
              onPressed: () => _reactivate(c),
            ),
    );
  }

  Future<void> _connect() async {
    final ig = TextEditingController();
    final page = TextEditingController();
    final user = TextEditingController();
    final token = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conectar Instagram'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ig, decoration: const InputDecoration(labelText: 'ID da conta profissional (IG User ID)')),
              const SizedBox(height: 8),
              TextField(controller: page, decoration: const InputDecoration(labelText: 'ID da Página do Facebook')),
              const SizedBox(height: 8),
              TextField(controller: user, decoration: const InputDecoration(labelText: '@ do perfil (opcional)')),
              const SizedBox(height: 8),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token da Página',
                  helperText: 'Guardado cifrado. Nunca é exibido de volta.',
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.post('/settings/instagram', {
      'ig_user_id': ig.text.trim(),
      'page_id': page.text.trim(),
      'username': user.text.trim(),
      'token': token.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Instagram conectado' : (r.message ?? 'Não foi possível conectar'))));
    if (r.ok) await _load();
  }

  /// Conecta pelo popup da Meta: o usuário se autentica no domínio da Meta e o
  /// servidor descobre a Página, a conta do Instagram e o token. Só pergunta algo
  /// quando a conta administra mais de uma Página com Instagram vinculado.
  Future<void> _connectViaMeta() async {
    setState(() => conectando = true);
    try {
      final code = await runFacebookLogin(
          appId: _fbAppId, configId: _fbConfigId, graphVersion: _fbGraph);
      if (!mounted) return;
      if (code == null) return; // cancelou ou o SDK não carregou
      final r = await _api.post('/settings/instagram/login', {'code': code});
      if (!mounted) return;
      if (r.ok && r.data is Map && (r.data as Map)['escolher'] == true) {
        await _escolherConta(r.data as Map);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.ok ? 'Instagram conectado' : (r.message ?? 'Não foi possível conectar'))));
      if (r.ok) await _load();
    } finally {
      if (mounted) setState(() => conectando = false);
    }
  }

  /// Pergunta qual conta conectar quando o login trouxe mais de uma Página.
  Future<void> _escolherConta(Map dados) async {
    final sessao = (dados['sessao'] ?? '').toString();
    final opcoes = ((dados['contas'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final escolhido = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Qual conta conectar?'),
        children: [
          for (final c in opcoes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (c['page_id'] ?? '').toString()),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('@${c['username'] ?? ''}'),
                subtitle: Text((c['page_name'] ?? '').toString()),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (escolhido == null || escolhido.isEmpty || !mounted) return;
    final r = await _api.post('/settings/instagram/login/escolher',
        {'sessao': sessao, 'page_id': escolhido});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? 'Instagram conectado' : (r.message ?? 'Não foi possível conectar'))));
    if (r.ok) await _load();
  }

  /// Reassina a Página nos webhooks da Meta. É o que faz a Meta ENTREGAR o Direct
  /// e os leads — conta conectada sem isso aparece normal e não recebe nada.
  Future<void> _resubscribe() async {
    final r = await _api.post('/settings/instagram/reassinar', {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? 'Webhooks reassinados' : (r.message ?? 'Não foi possível reassinar'))));
  }

  /// Religa a conta reusando o token já guardado — sem precisar de token novo.
  Future<void> _reactivate(Map<String, dynamic> c) async {
    final r = await _api.post('/settings/instagram/${c['id']}/reativar', {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? 'Instagram reativado' : (r.message ?? 'Não foi possível reativar'))));
    if (r.ok) await _load();
  }

  Future<void> _disconnect(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desconectar Instagram'),
        content: const Text('As conversas já recebidas continuam no histórico, mas nada novo chega nem sai por este canal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/settings/instagram/${c['id']}');
    if (!mounted) return;
    if (r.ok) await _load();
  }
}
