import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/audio_recorder.dart';
import '../models/message_template.dart';
import '../models/support.dart';

/// Estado de UMA conversa aberta num painel. Cada painel do inbox tem o seu,
/// então atualizam de forma independente (uma pode carregar/enviar sem mexer
/// nas outras). Faz polling silencioso para trazer as respostas em tempo real.
class ConversationController extends ChangeNotifier {
  ConversationController(this.ticket) {
    aiPaused = ticket.aiPaused;
    load();
    composer.addListener(_onComposerChanged);
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
  }

  /// Atendente IA pausado NESTA conversa (controle manual no header). Espelha o
  /// backend: uma resposta de texto do atendente também pausa (handoff).
  bool aiPaused = false;
  bool _togglingAI = false;
  bool get togglingAI => _togglingAI;

  /// Liga/pausa a IA nesta conversa (otimista; reverte se a API falhar). Ao
  /// RETOMAR, o backend já dispara a resposta se a última mensagem for do cliente.
  Future<void> toggleAI() async {
    if (_togglingAI) return;
    final target = !aiPaused;
    _togglingAI = true;
    aiPaused = target;
    ticket.aiPaused = target;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/ai', {'paused': target});
    _togglingAI = false;
    if (!r.ok) {
      aiPaused = !target;
      ticket.aiPaused = !target;
    }
    notifyListeners();
  }

  DateTime? _lastTypingSent;

  /// Ao digitar, mostra "digitando…" pro cliente (throttle: 1x a cada 10s, pois
  /// o indicador dura ~25s no WhatsApp).
  void _onComposerChanged() {
    if (composer.text.trim().isNotEmpty) unawaited(markRead(typing: true));
  }

  /// Marca a conversa como lida (✓✓ azul p/ o cliente) e, se typing, mostra
  /// "digitando…". Best-effort (ignora falha).
  Future<void> markRead({bool typing = false}) async {
    if (typing) {
      final now = DateTime.now();
      if (_lastTypingSent != null && now.difference(_lastTypingSent!).inSeconds < 10) return;
      _lastTypingSent = now;
    }
    await _api.post('/support/tickets/${ticket.id}/read', {'typing': typing});
  }

  final _api = ApiClient.instance;
  final TicketListItem ticket;
  final composer = TextEditingController();
  Timer? _poll;

  List<Message> messages = [];
  bool loading = false;
  bool sending = false;

  /// Pedindo um rascunho à IA (Cmd/Ctrl+I ou o botão ✨).
  bool suggesting = false;

  /// Pede à IA um rascunho de resposta e coloca no compositor para o atendente
  /// revisar — NADA é enviado ao cliente. Devolve a mensagem de erro, ou null
  /// se deu certo. Não sobrescreve o que já estiver digitado: acrescenta.
  Future<String?> suggestReply() async {
    if (suggesting) return null;
    suggesting = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/suggest', const <String, dynamic>{});
    suggesting = false;
    if (!r.ok || r.data is! Map) {
      notifyListeners();
      return r.message ?? 'A IA não conseguiu sugerir uma resposta';
    }
    final text = ((r.data as Map)['text'] ?? '').toString().trim();
    if (text.isEmpty) {
      notifyListeners();
      return 'A IA não teve o que sugerir aqui';
    }
    final atual = composer.text.trim();
    composer.text = atual.isEmpty ? text : '$atual\n$text';
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    notifyListeners();
    return null;
  }

  /// Hora da última mensagem RECEBIDA do cliente — define a janela de 24h da Meta.
  DateTime? get lastInboundAt {
    for (final m in messages.reversed) {
      if (!m.isOutbound) return m.createdAt;
    }
    return null;
  }

  /// Janela de 24h aberta? Fora dela a Meta só aceita MODELO (template) aprovado.
  /// Sem nenhuma mensagem recebida ainda, tratamos como FECHADA (só template abre).
  bool get windowOpen {
    final t = lastInboundAt;
    return t != null && DateTime.now().difference(t) < const Duration(hours: 24);
  }

  /// Quanto falta para a janela fechar (Duration.zero se já fechada).
  Duration get windowLeft {
    final t = lastInboundAt;
    if (t == null) return Duration.zero;
    final left = const Duration(hours: 24) - DateTime.now().difference(t);
    return left.isNegative ? Duration.zero : left;
  }

  // Gravação de áudio (estilo WhatsApp).
  final AudioRecorder _recorder = AudioRecorder();
  bool recording = false;
  int recordSeconds = 0;
  Timer? _recTimer;

  /// Recarrega as mensagens sem spinner; só notifica se mudou a quantidade.
  Future<void> _refresh() async {
    if (sending) return;
    final r = await _api.get('/support/tickets/${ticket.id}/messages');
    if (r.ok && r.data is List) {
      final fresh = (r.data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
      if (fresh.length != messages.length) {
        final grew = fresh.length > messages.length;
        messages = fresh;
        notifyListeners();
        // Chegou mensagem nova do cliente com a conversa aberta → marca lida.
        if (grew && fresh.isNotEmpty && !fresh.last.isOutbound) unawaited(markRead());
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
      unawaited(markRead()); // abriu a conversa → marca as recebidas como lidas
    }
    notifyListeners();
  }

  /// Modelo "preparado" no campo (esperando o atendente apertar enviar). Se o
  /// texto não for editado, o envio sai como TEMPLATE (fura a janela de 24h).
  MessageTemplate? pendingTemplate;

  /// Coloca o texto do modelo no campo (não envia) — o atendente revisa e envia.
  void stageTemplate(MessageTemplate t) {
    pendingTemplate = t;
    composer.text = t.bodyText ?? '';
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    notifyListeners();
  }

  /// Envia o que está no compositor. Retorna false em falha.
  Future<bool> send() async {
    final text = composer.text.trim();
    if (text.isEmpty) return false;
    // Se veio de um modelo e o texto não mudou, envia como TEMPLATE.
    final tpl = pendingTemplate;
    if (tpl != null && text == (tpl.bodyText ?? '').trim()) {
      composer.clear();
      pendingTemplate = null;
      return sendTemplate(tpl.name, tpl.language, tpl.bodyText ?? '');
    }
    pendingTemplate = null;
    composer.clear();
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/messages', {'content': text});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      // Humano respondeu → o backend pausou a IA nesta conversa (handoff); espelha no header.
      aiPaused = true;
      ticket.aiPaused = true;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Envia um modelo (template) aprovado. Retorna false em falha.
  Future<bool> sendTemplate(String name, String language, String body) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/template',
        {'name': name, 'language': language, 'body': body});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Envia um anexo (foto/documento). Retorna false em falha.
  Future<bool> sendMedia({required List<int> bytes, required String filename, String? mimeType, String caption = ''}) async {
    sending = true;
    notifyListeners();
    final r = await _api.uploadFile(
      '/support/tickets/${ticket.id}/media',
      bytes: bytes,
      filename: filename,
      contentType: mimeType,
      fields: caption.isNotEmpty ? {'caption': caption} : null,
    );
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Começa a gravar um áudio. Retorna false se o microfone foi negado.
  Future<bool> startRecording() async {
    if (recording) return true;
    final ok = await _recorder.start();
    if (!ok) return false;
    recording = true;
    recordSeconds = 0;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordSeconds++;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  /// Para a gravação e envia o áudio. Retorna false em falha.
  Future<bool> stopAndSendRecording() async {
    if (!recording) return false;
    _recTimer?.cancel();
    recording = false;
    notifyListeners();
    final audio = await _recorder.stop();
    if (audio == null || audio.bytes.isEmpty) return false;
    final ext = audio.mimeType.contains('ogg')
        ? 'ogg'
        : audio.mimeType.contains('mp4') || audio.mimeType.contains('mpeg')
            ? 'm4a'
            : 'webm';
    return sendMedia(bytes: audio.bytes, filename: 'audio.$ext', mimeType: audio.mimeType);
  }

  /// Cancela a gravação em curso e descarta.
  void cancelRecording() {
    _recTimer?.cancel();
    recording = false;
    recordSeconds = 0;
    _recorder.cancel();
    notifyListeners();
  }

  /// Envia uma localização (pino). Retorna false em falha.
  Future<bool> sendLocation({required double lat, required double lng, String name = '', String address = ''}) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/location', {
      'latitude': lat,
      'longitude': lng,
      if (name.isNotEmpty) 'name': name,
      if (address.isNotEmpty) 'address': address,
    });
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Envia botões de resposta rápida (1 a 3). Retorna false em falha.
  Future<bool> sendButtons(String body, List<String> titles) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/interactive', {
      'kind': 'button',
      'body': body,
      'buttons': [for (final t in titles) {'title': t}],
    });
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Envia um menu de lista (1 a 10 itens). Retorna false em falha.
  Future<bool> sendList(
    String body,
    String buttonLabel,
    String sectionTitle,
    List<({String title, String description})> rows,
  ) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/interactive', {
      'kind': 'list',
      'body': body,
      if (buttonLabel.isNotEmpty) 'button_label': buttonLabel,
      if (sectionTitle.isNotEmpty) 'section_title': sectionTitle,
      'rows': [
        for (final r in rows) {'title': r.title, if (r.description.isNotEmpty) 'description': r.description},
      ],
    });
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Envia um cartão de contato. Retorna false em falha.
  Future<bool> sendContact({required String name, required String phone}) async {
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/contact', {'name': name, 'phone': phone});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Reenvia uma mensagem que havia falhado. Retorna true se saiu desta vez.
  Future<bool> retry(Message m) async {
    final r = await _api.post('/support/tickets/${ticket.id}/messages/${m.id}/retry');
    if (r.ok && r.data != null) {
      final updated = Message.fromJson(r.data as Map<String, dynamic>);
      final idx = messages.indexWhere((x) => x.id == m.id);
      if (idx >= 0) {
        messages[idx] = updated;
        messages = [...messages];
        notifyListeners();
      }
      return updated.status != 'failed';
    }
    return false;
  }

  /// Encaminha uma mensagem para a conversa de outro contato.
  Future<bool> forward(String messageId, String contactId) async {
    final r = await _api.post('/support/forward', {'source_message_id': messageId, 'contact_id': contactId});
    return r.ok;
  }

  // --- Fase 1 de atendimento: assumir, transferir, status e histórico ---

  /// Assume a conversa (puxa para si). Devolve o item atualizado ou null.
  Future<TicketListItem?> claim() async {
    final r = await _api.post('/support/tickets/${ticket.id}/claim');
    if (r.ok && r.data is Map) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      ticket.applyFrom(t);
      notifyListeners();
      return t;
    }
    return null;
  }

  /// Transfere para outro atendente e/ou setor (com nota). Null em falha.
  Future<TicketListItem?> transfer({String? userId, String? sectorId, String note = ''}) async {
    final r = await _api.post('/support/tickets/${ticket.id}/transfer', {
      'user_id': ?userId,
      'sector_id': ?sectorId,
      if (note.isNotEmpty) 'note': note,
    });
    if (r.ok && r.data is Map) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      ticket.applyFrom(t);
      notifyListeners();
      return t;
    }
    return null;
  }

  /// Muda o status (resolver/fechar/reabrir/aguardando). Null em falha.
  Future<TicketListItem?> setStatus(String status, {String note = ''}) async {
    final r = await _api.put('/support/tickets/${ticket.id}/status',
        {'status': status, if (note.isNotEmpty) 'note': note});
    if (r.ok && r.data is Map) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      ticket.applyFrom(t);
      notifyListeners();
      return t;
    }
    return null;
  }

  /// Carrega a timeline (transferências, status, notas) da conversa.
  Future<List<TicketEvent>> loadEvents() async {
    final r = await _api.get('/support/tickets/${ticket.id}/events');
    if (r.ok && r.data is List) {
      return (r.data as List).map((e) => TicketEvent.fromJson(e as Map<String, dynamic>)).toList();
    }
    return const [];
  }

  /// Modo NOTA INTERNA do compositor: envia como nota (equipe), não ao cliente.
  bool noteMode = false;

  void toggleNoteMode() {
    noteMode = !noteMode;
    notifyListeners();
  }

  /// Grava a nota interna que está no compositor. Retorna false em falha.
  Future<bool> sendNote() async {
    final text = composer.text.trim();
    if (text.isEmpty) return false;
    composer.clear();
    sending = true;
    notifyListeners();
    final r = await _api.post('/support/tickets/${ticket.id}/notes', {'content': text});
    sending = false;
    if (r.ok && r.data != null) {
      messages = [...messages, Message.fromJson(r.data as Map<String, dynamic>)];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Substitui as etiquetas da conversa. Devolve o item atualizado ou null.
  Future<TicketListItem?> setTags(List<String> tagIds) async {
    final r = await _api.put('/support/tickets/${ticket.id}/tags', {'tag_ids': tagIds});
    if (r.ok && r.data is Map) {
      final t = TicketListItem.fromJson(r.data as Map<String, dynamic>);
      ticket.applyFrom(t);
      notifyListeners();
      return t;
    }
    return null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _recTimer?.cancel();
    _recorder.cancel();
    composer.removeListener(_onComposerChanged);
    composer.dispose();
    super.dispose();
  }
}
