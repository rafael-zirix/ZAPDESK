import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/phone.dart';
import '../core/theme.dart';
import '../models/campaign.dart';

/// Tela de uma campanha: funil completo, mensagem enviada e a lista de
/// destinatários com o status de cada um (com filtro e busca).
class CampaignDetailScreen extends StatefulWidget {
  const CampaignDetailScreen({
    super.key,
    required this.campaign,
    required this.onBack,
    required this.onCopy,
    required this.onChanged,
  });

  final Campaign campaign;
  final VoidCallback onBack;

  /// Abrir o formulário já preenchido com esta campanha (copiar).
  final void Function(Campaign) onCopy;

  /// Avisa a lista que algo mudou (status/exclusão) — o segundo parâmetro diz
  /// se a campanha foi excluída (aí a lista volta ao índice).
  final void Function({bool deleted}) onChanged;

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  final _api = ApiClient.instance;

  late Campaign camp = widget.campaign;
  List<CampaignRecipient> recipients = [];
  bool loading = true;
  String filter = 'all';
  String search = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Enquanto está enviando, o funil muda sozinho.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (camp.status == 'running' || camp.status == 'scheduled') _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    final rc = await _api.get('/campaigns/${camp.id}');
    final rr = await _api.get('/campaigns/${camp.id}/recipients?limit=500');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (rc.ok && rc.data is Map) camp = Campaign.fromJson(rc.data as Map<String, dynamic>);
      if (rr.ok && rr.data is List) {
        recipients = (rr.data as List).map((e) => CampaignRecipient.fromJson(e as Map<String, dynamic>)).toList();
      }
    });
  }

  Color get _statusColor => switch (camp.status) {
        'scheduled' => const Color(0xFFCA8A04),
        'running' => const Color(0xFF2563EB),
        'paused' => const Color(0xFF7C3AED),
        'done' => const Color(0xFF1F9D57),
        _ => Colors.grey,
      };

  Future<void> _action(String action) async {
    final r = await _api.post('/campaigns/${camp.id}/action', {'action': action});
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível')));
    }
    await _load(silent: true);
    widget.onChanged();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir campanha'),
        content: Text('Excluir "${camp.name}"? O histórico de envios dela também é apagado. '
            'As conversas com os contatos permanecem.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.delete('/campaigns/${camp.id}');
    if (!mounted) return;
    if (r.ok) {
      widget.onChanged(deleted: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'Não foi possível excluir')));
    }
  }

  List<CampaignRecipient> get _filtered {
    final q = search.trim().toLowerCase();
    return recipients.where((r) {
      if (filter != 'all' && r.status != filter) return false;
      if (q.isEmpty) return true;
      return r.displayName.toLowerCase().contains(q) || r.phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final f = camp.funnel;
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(
            child: loading && recipients.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 360, child: _funnelCard(f)),
                          const SizedBox(width: 16),
                          Expanded(child: _messageCard()),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _recipientsSection(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final running = camp.status == 'running' || camp.status == 'scheduled';
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Voltar às campanhas',
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(camp.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              Text(
                'Modelo ${camp.templateName} · ${camp.ratePerMin}/min · '
                '${DateFormat('dd/MM/yyyy HH:mm').format(camp.scheduledAt)}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(camp.statusLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor)),
          ),
          const Spacer(),
          if (running)
            TextButton.icon(
              onPressed: () => _action('pause'),
              icon: const Icon(Icons.pause, size: 18),
              label: const Text('Pausar'),
            ),
          if (camp.status == 'paused') ...[
            TextButton.icon(
              onPressed: () => _action('resume'),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Retomar'),
            ),
            TextButton.icon(
              onPressed: () => _action('cancel'),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Cancelar'),
            ),
          ],
          if (running)
            TextButton.icon(
              onPressed: () => _action('cancel'),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Cancelar'),
            ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: () => widget.onCopy(camp),
            icon: const Icon(Icons.copy_outlined, size: 17),
            label: const Text('Copiar'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _delete,
            tooltip: 'Excluir campanha',
            icon: const Icon(Icons.delete_outline),
            color: Colors.red.shade400,
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _funnelCard(CampaignFunnel f) {
    return _card(
      title: 'FUNIL',
      child: Column(
        children: [
          _funnelRow('Destinatários', f.total, f.total),
          _funnelRow('Enviadas', f.reachedSent, f.total),
          _funnelRow('Entregues', f.reachedDelivered, f.total),
          _funnelRow('Lidas', f.reachedRead, f.total),
          _funnelRow('Responderam', f.replied, f.total, highlight: true),
          if (f.failed > 0) _funnelRow('Falhas', f.failed, f.total, isError: true),
          if (f.pending > 0) _funnelRow('Na fila', f.pending, f.total),
        ],
      ),
    );
  }

  Widget _funnelRow(String label, int value, int total, {bool highlight = false, bool isError = false}) {
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    final color = isError ? const Color(0xFFEF4444) : (highlight ? AppTheme.seed : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 108, child: Text(label, style: TextStyle(fontSize: 13, color: color))),
          SizedBox(
            width: 130,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : value / total,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                color: color ?? const Color(0xFF2563EB),
              ),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text('  $value ($pct%)',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: highlight ? FontWeight.w700 : FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _messageCard() {
    var text = camp.bodyText ?? '(modelo sem corpo)';
    for (var i = 0; i < camp.params.length; i++) {
      text = text.replaceAll('{{${i + 1}}}', camp.params[i]);
    }
    return _card(
      title: 'MENSAGEM ENVIADA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (camp.imageUrl != null && camp.imageUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                camp.imageUrl!,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  color: Colors.grey.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
            child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
          if (camp.params.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Variáveis: ${camp.params.join(" · ")}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }

  Widget _recipientsSection() {
    final list = _filtered;
    Widget chip(String label, String value, int count) {
      final sel = filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$label ($count)',
              style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          selected: sel,
          onSelected: (_) => setState(() => filter = value),
          selectedColor: AppTheme.seed.withValues(alpha: 0.18),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    int count(String s) => s == 'all' ? recipients.length : recipients.where((r) => r.status == s).length;

    return _card(
      title: 'DESTINATÁRIOS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (v) => setState(() => search = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar nome ou telefone…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      chip('Todos', 'all', count('all')),
                      if (count('pending') > 0) chip('Na fila', 'pending', count('pending')),
                      if (count('sent') > 0) chip('Enviadas', 'sent', count('sent')),
                      if (count('delivered') > 0) chip('Entregues', 'delivered', count('delivered')),
                      if (count('read') > 0) chip('Lidas', 'read', count('read')),
                      if (count('replied') > 0) chip('Responderam', 'replied', count('replied')),
                      if (count('failed') > 0) chip('Falhas', 'failed', count('failed')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Nenhum destinatário neste filtro.', style: TextStyle(color: Colors.grey.shade600)),
            )
          else
            for (final r in list) _recipientRow(r),
        ],
      ),
    );
  }

  Widget _recipientRow(CampaignRecipient r) {
    final (Color color, IconData icon) = switch (r.status) {
      'pending' => (Colors.grey, Icons.schedule),
      'sent' => (const Color(0xFF2563EB), Icons.check),
      'delivered' => (const Color(0xFF2563EB), Icons.done_all),
      'read' => (const Color(0xFF7C3AED), Icons.done_all),
      'replied' => (AppTheme.seed, Icons.reply),
      'failed' => (const Color(0xFFEF4444), Icons.error_outline),
      _ => (Colors.grey, Icons.help_outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            child: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 150,
            child: Text(formatPhone(r.phone), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
          SizedBox(
            width: 110,
            child: Text(r.statusLabel, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          ),
          if (r.error != null && r.error!.isNotEmpty)
            SizedBox(
              width: 420,
              child: Text(r.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFB42318))),
            ),
        ],
      ),
    );
  }
}
