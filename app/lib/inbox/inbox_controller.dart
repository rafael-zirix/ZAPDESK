import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';
import '../models/contact.dart';
import '../models/message_template.dart';
import '../models/support.dart';
import 'conversation_controller.dart';

/// Estado do inbox: a lista de conversas (esquerda) e os painéis abertos
/// (direita). Suporta trabalhar com até 4 conversas simultâneas.
class InboxController extends ChangeNotifier {
  final _api = ApiClient.instance;

  static const int maxPanes = 4;
  static const _stateKey = 'zap_inbox_open';

  List<TicketListItem> tickets = [];
  bool loadingTickets = false;
  String? ticketsError;

  // --- Filtros da lista (Fase 1 de atendimento) ---
  /// 'all' | 'mine' | 'open' | 'pending' | 'resolved' | 'closed'
  String statusFilter = 'all';
  String? sectorFilter; // id do setor (null = todos)
  String? myUserId; // preenchido pela tela (p/ o filtro "Minhas")

  void setStatusFilter(String f) {
    statusFilter = f;
    notifyListeners();
  }

  void setSectorFilter(String? id) {
    sectorFilter = id;
    notifyListeners();
  }

  /// Conversas após aplicar os filtros. Fechadas só aparecem no filtro delas.
  List<TicketListItem> get filteredTickets => tickets.where((t) {
        if (sectorFilter != null && t.sectorId != sectorFilter) return false;
        switch (statusFilter) {
          case 'mine':
            return t.assignedUserId == myUserId && t.status != 'closed';
          case 'open':
            return t.status == 'open';
          case 'pending':
            return t.status == 'pending';
          case 'resolved':
            return t.status == 'resolved';
          case 'closed':
            return t.status == 'closed';
          default:
            return t.status != 'closed';
        }
      }).toList();

  // Setores e equipe (para transferir e para o filtro por setor).
  List<Sector> sectors = [];
  List<AppUser> team = [];

  Future<void> loadSectors() async {
    final r = await _api.get('/support/sectors');
    if (r.ok && r.data is List) {
      sectors = (r.data as List).map((e) => Sector.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> loadTeam() async {
    final r = await _api.get('/users');
    if (r.ok && r.data is List) {
      team = (r.data as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  // Respostas rápidas e etiquetas da empresa.
  List<QuickReply> quickReplies = [];
  List<TicketTag> tags = [];

  Future<void> loadQuickReplies() async {
    final r = await _api.get('/support/quick-replies');
    if (r.ok && r.data is List) {
      quickReplies = (r.data as List).map((e) => QuickReply.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> loadTags() async {
    final r = await _api.get('/support/tags');
    if (r.ok && r.data is List) {
      tags = (r.data as List).map((e) => TicketTag.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// Cria uma etiqueta e devolve-a (null em falha).
  Future<TicketTag?> createTag(String name) async {
    final r = await _api.post('/support/tags', {'name': name});
    if (r.ok && r.data is Map) {
      final t = TicketTag.fromJson(r.data as Map<String, dynamic>);
      tags = [...tags, t]..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return t;
    }
    return null;
  }

  /// Cria/edita/apaga resposta rápida. Devolve null em sucesso ou o erro.
  Future<String?> saveQuickReply({String? id, required String shortcut, required String content}) async {
    final body = {'shortcut': shortcut, 'content': content};
    final r = id == null
        ? await _api.post('/support/quick-replies', body)
        : await _api.put('/support/quick-replies/$id', body);
    if (r.ok) {
      await loadQuickReplies();
      return null;
    }
    return r.message ?? 'Não foi possível salvar';
  }

  Future<String?> deleteQuickReply(String id) async {
    final r = await _api.delete('/support/quick-replies/$id');
    if (r.ok) {
      await loadQuickReplies();
      return null;
    }
    return r.message ?? 'Não foi possível excluir';
  }

  /// Pega o próximo da fila (aberto sem dono). Devolve o erro, ou null e abre a conversa.
  Future<String?> claimNext() async {
    final r = await _api.post('/support/tickets/claim-next',
        sectorFilter != null ? {'sector_id': sectorFilter} : null);
    if (r.ok && r.data is Map) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      applyTicketUpdate(t);
      final idx = tickets.indexWhere((x) => x.id == t.id);
      openTicket(idx >= 0 ? tickets[idx] : t);
      return null;
    }
    return r.message ?? 'Fila vazia';
  }

  /// Aplica numa conversa da lista os campos devolvidos por claim/transfer/status.
  void applyTicketUpdate(TicketListItem updated) {
    final idx = tickets.indexWhere((t) => t.id == updated.id);
    if (idx >= 0) tickets[idx].applyFrom(updated);
    for (final c in open) {
      if (c.ticket.id == updated.id) c.ticket.applyFrom(updated);
    }
    notifyListeners();
  }

  /// Quantos painéis o usuário quer ver ao mesmo tempo (1..4).
  int paneCount = 1;

  Timer? _poll;

  /// Liga o auto-refresh da lista de conversas (chamado quando a tela monta).
  void startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 10), (_) => _refreshTickets());
  }

  /// Recarrega a lista sem spinner (para conversas novas aparecerem sozinhas).
  Future<void> _refreshTickets() async {
    final r = await _api.get('/support/tickets');
    if (r.ok && r.data is List) {
      tickets = (r.data as List).map((e) => TicketListItem.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// Conversas abertas (no máximo [paneCount]).
  final List<ConversationController> open = [];

  /// Índice do painel "focado" (destacado). Quando todos os slots estão
  /// ocupados, o próximo contato aberto substitui a conversa desse painel.
  int? selectedPane;

  /// Marca um painel como selecionado (foco visual + alvo do próximo contato).
  void selectPane(int index) {
    if (index >= 0 && index < open.length && selectedPane != index) {
      selectedPane = index;
      unawaited(_persist());
      notifyListeners();
    }
  }

  /// Salva os painéis abertos (para sobreviver a um reload — ex.: troca de tema).
  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _stateKey,
      jsonEncode({
        'paneCount': paneCount,
        'open': open.map((c) => c.ticket.id).toList(),
        'selected': selectedPane,
      }),
    );
  }

  bool _restored = false;

  /// Reabre os painéis que estavam abertos antes de um reload (chamado após a
  /// lista de conversas carregar). Roda só uma vez.
  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_stateKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      paneCount = (((data['paneCount'] as num?)?.toInt()) ?? 1).clamp(1, maxPanes);
      final ids = (data['open'] as List?)?.cast<String>() ?? const <String>[];
      for (final id in ids) {
        if (open.length >= paneCount) break;
        final idx = tickets.indexWhere((x) => x.id == id);
        if (idx >= 0 && !isOpen(id)) {
          open.add(ConversationController(tickets[idx]));
        }
      }
      final sel = data['selected'];
      if (sel is int && sel >= 0 && sel < open.length) selectedPane = sel;
      notifyListeners();
    } catch (_) {}
  }

  // Modelos (templates) aprovados da conta — para iniciar/furar a janela de 24h.
  List<MessageTemplate> templates = [];

  Future<void> loadTickets() async {
    loadingTickets = true;
    ticketsError = null;
    notifyListeners();
    final r = await _api.get('/support/tickets');
    loadingTickets = false;
    if (r.ok && r.data is List) {
      tickets = (r.data as List).map((e) => TicketListItem.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      ticketsError = r.message ?? 'Erro ao carregar conversas';
    }
    notifyListeners();
    if (ticketsError == null) await _restore(); // reabre os painéis de antes do reload
    loadTemplates();
    loadAIState();
    loadSectors();
    loadTeam();
    loadQuickReplies();
    loadTags();
  }

  // Atendente IA da conta: define se o controle de IA aparece no header das
  // conversas (só quando a IA está ligada na empresa).
  bool aiEnabled = false;
  bool aiProviderReady = false;

  Future<void> loadAIState() async {
    final r = await _api.get('/support/ai-state');
    if (r.ok && r.data is Map) {
      final m = r.data as Map;
      aiEnabled = m['enabled'] == true;
      aiProviderReady = m['provider_ready'] == true;
      notifyListeners();
    }
  }

  Future<void> loadTemplates() async {
    final r = await _api.get('/support/templates');
    if (r.ok && r.data is List) {
      // Na barra de envio, só os APROVADOS, LIGADOS e de uso CONVERSA — modelo
      // de campanha não aparece no atendimento (senão polui a barra).
      templates = (r.data as List)
          .map((e) => MessageTemplate.fromJson(e as Map<String, dynamic>))
          .where((t) => t.isApproved && t.enabled && !t.isCampaign)
          .toList();
      notifyListeners();
    }
  }

  // Contatos disponíveis para iniciar uma conversa nova.
  List<Contact> contacts = [];
  bool loadingContacts = false;

  bool isOpen(String ticketId) => open.any((c) => c.ticket.id == ticketId);

  Future<void> loadContacts() async {
    loadingContacts = true;
    notifyListeners();
    final r = await _api.get('/contacts');
    loadingContacts = false;
    if (r.ok && r.data is List) {
      contacts = (r.data as List).map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
    }
    notifyListeners();
  }

  /// Inicia (ou reabre) a conversa com um contato e a abre num painel.
  /// Retorna null em sucesso, ou a mensagem de erro.
  Future<String?> startWith(Contact contact) async {
    final r = await _api.post('/support/tickets', {'contact_id': contact.id});
    if (r.ok && r.data != null) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      final idx = tickets.indexWhere((x) => x.id == t.id);
      if (idx >= 0) {
        tickets[idx] = t;
      } else {
        tickets.insert(0, t);
      }
      openTicket(t);
      return null;
    }
    return r.message ?? 'Não foi possível iniciar a conversa';
  }

  /// Define quantos painéis exibir. Ao reduzir, fecha os excedentes.
  void setPaneCount(int n) {
    paneCount = n.clamp(1, maxPanes);
    while (open.length > paneCount) {
      open.removeLast().dispose();
    }
    _fixSelection();
    unawaited(_persist());
    notifyListeners();
  }

  /// Abre uma conversa. Se já estiver aberta, apenas foca o painel dela. Se há
  /// slot livre, abre num painel novo; se todos ocupados, substitui a conversa
  /// do painel SELECIONADO (ou o último, se nenhum estiver focado).
  void openTicket(TicketListItem t) {
    final existing = open.indexWhere((c) => c.ticket.id == t.id);
    if (existing >= 0) {
      selectedPane = existing;
      unawaited(_persist());
      notifyListeners();
      return;
    }
    final conv = ConversationController(t);
    if (open.length < paneCount) {
      open.add(conv);
      selectedPane = open.length - 1;
    } else {
      final idx = (selectedPane != null && selectedPane! >= 0 && selectedPane! < open.length)
          ? selectedPane!
          : open.length - 1;
      open[idx].dispose();
      open[idx] = conv;
      selectedPane = idx;
    }
    unawaited(_persist());
    notifyListeners();
  }

  /// Fecha um painel específico.
  void closePane(ConversationController c) {
    final idx = open.indexOf(c);
    if (idx >= 0) {
      open.removeAt(idx).dispose();
      _fixSelection(removedIndex: idx);
      unawaited(_persist());
      notifyListeners();
    }
  }

  /// Fecha todos (usado ao voltar no mobile).
  void closeAll() {
    for (final c in open) {
      c.dispose();
    }
    open.clear();
    selectedPane = null;
    unawaited(_persist());
    notifyListeners();
  }

  /// Mantém [selectedPane] dentro dos limites após fechar/reduzir painéis.
  void _fixSelection({int? removedIndex}) {
    if (open.isEmpty) {
      selectedPane = null;
      return;
    }
    if (selectedPane == null) return;
    if (removedIndex != null && selectedPane! > removedIndex) {
      selectedPane = selectedPane! - 1;
    }
    if (selectedPane! >= open.length) {
      selectedPane = open.length - 1;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in open) {
      c.dispose();
    }
    super.dispose();
  }
}
