import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/support.dart';

/// Estado do inbox: lista de conversas + thread selecionada.
class InboxController extends ChangeNotifier {
  final _api = ApiClient.instance;

  List<TicketListItem> tickets = [];
  bool loadingTickets = false;
  String? ticketsError;

  TicketListItem? selected;
  List<Message> messages = [];
  bool loadingMessages = false;
  bool sending = false;

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

  void deselect() {
    selected = null;
    messages = [];
    notifyListeners();
  }

  Future<void> select(TicketListItem t) async {
    selected = t;
    messages = [];
    loadingMessages = true;
    notifyListeners();
    final r = await _api.get('/support/tickets/${t.id}/messages');
    loadingMessages = false;
    if (r.ok && r.data is List) {
      messages = (r.data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
    }
    notifyListeners();
  }

  Future<bool> send(String text) async {
    final t = selected;
    if (t == null || text.trim().isEmpty) return false;
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${t.id}/messages', {'content': text.trim()});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }
}
