import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/support.dart';
import 'conversation_controller.dart';

/// Estado do inbox: a lista de conversas (esquerda) e os painéis abertos
/// (direita). Suporta trabalhar com até 4 conversas simultâneas.
class InboxController extends ChangeNotifier {
  final _api = ApiClient.instance;

  static const int maxPanes = 4;

  List<TicketListItem> tickets = [];
  bool loadingTickets = false;
  String? ticketsError;

  /// Quantos painéis o usuário quer ver ao mesmo tempo (1..4).
  int paneCount = 1;

  /// Conversas abertas (no máximo [paneCount]).
  final List<ConversationController> open = [];

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
  }

  bool isOpen(String ticketId) => open.any((c) => c.ticket.id == ticketId);

  /// Define quantos painéis exibir. Ao reduzir, fecha os excedentes.
  void setPaneCount(int n) {
    paneCount = n.clamp(1, maxPanes);
    while (open.length > paneCount) {
      open.removeLast().dispose();
    }
    notifyListeners();
  }

  /// Abre uma conversa: usa um slot livre; se todos ocupados, substitui o
  /// último. Se já estiver aberta, não faz nada (já visível).
  void openTicket(TicketListItem t) {
    if (isOpen(t.id)) return;
    final conv = ConversationController(t);
    if (open.length >= paneCount && open.isNotEmpty) {
      open.removeLast().dispose();
    }
    open.add(conv);
    notifyListeners();
  }

  /// Fecha um painel específico.
  void closePane(ConversationController c) {
    if (open.remove(c)) {
      c.dispose();
      notifyListeners();
    }
  }

  /// Fecha todos (usado ao voltar no mobile).
  void closeAll() {
    for (final c in open) {
      c.dispose();
    }
    open.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in open) {
      c.dispose();
    }
    super.dispose();
  }
}
