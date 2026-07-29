import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/support.dart';

/// Estado de UMA conversa aberta num painel. Cada painel do inbox tem o seu,
/// então atualizam de forma independente (uma pode carregar/enviar sem mexer
/// nas outras).
class ConversationController extends ChangeNotifier {
  ConversationController(this.ticket) {
    load();
  }

  final _api = ApiClient.instance;
  final TicketListItem ticket;
  final composer = TextEditingController();

  List<Message> messages = [];
  bool loading = false;
  bool sending = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final r = await _api.get('/support/tickets/${ticket.id}/messages');
    loading = false;
    if (r.ok && r.data is List) {
      messages = (r.data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
    }
    notifyListeners();
  }

  /// Envia o que está no compositor. Retorna false em falha.
  Future<bool> send() async {
    final text = composer.text.trim();
    if (text.isEmpty) return false;
    composer.clear();
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/messages', {'content': text});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }
}
