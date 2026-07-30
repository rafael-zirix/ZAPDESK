import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/support.dart';

/// Estado de UMA conversa aberta num painel. Cada painel do inbox tem o seu,
/// então atualizam de forma independente (uma pode carregar/enviar sem mexer
/// nas outras). Faz polling silencioso para trazer as respostas em tempo real.
class ConversationController extends ChangeNotifier {
  ConversationController(this.ticket) {
    load();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
  }

  final _api = ApiClient.instance;
  final TicketListItem ticket;
  final composer = TextEditingController();
  Timer? _poll;

  List<Message> messages = [];
  bool loading = false;
  bool sending = false;

  /// Recarrega as mensagens sem spinner; só notifica se mudou a quantidade.
  Future<void> _refresh() async {
    if (sending) return;
    final r = await _api.get('/support/tickets/${ticket.id}/messages');
    if (r.ok && r.data is List) {
      final fresh = (r.data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
      if (fresh.length != messages.length) {
        messages = fresh;
        notifyListeners();
      }
    }
  }

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

  /// Envia um modelo (template) aprovado. Retorna false em falha.
  Future<bool> sendTemplate(String name, String language) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/template', {'name': name, 'language': language});
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
    _poll?.cancel();
    composer.dispose();
    super.dispose();
  }
}
