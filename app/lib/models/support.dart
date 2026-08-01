/// Uma conversa na lista do inbox.
class TicketListItem {
  TicketListItem({
    required this.id,
    required this.protocol,
    required this.status,
    required this.contactPhone,
    this.contactName,
    required this.lastMessageAt,
    this.aiPaused = false,
    this.unreadCount = 0,
  });

  final String id;
  final String protocol;
  final String status; // open | closed
  final String contactPhone;
  final String? contactName;
  final DateTime lastMessageAt;
  bool aiPaused; // Atendente IA pausado nesta conversa (mutável p/ toggle otimista)
  int unreadCount; // mensagens recebidas não lidas (mutável p/ zerar ao abrir)

  String get displayName => (contactName != null && contactName!.isNotEmpty) ? contactName! : contactPhone;

  /// Telefone formatado (+55 21 99999-9999) quando possível.
  String get prettyPhone {
    final d = contactPhone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('55') && (d.length == 12 || d.length == 13)) {
      final ddd = d.substring(2, 4);
      final rest = d.substring(4);
      if (rest.length == 9) return '+55 $ddd ${rest.substring(0, 5)}-${rest.substring(5)}';
      if (rest.length == 8) return '+55 $ddd ${rest.substring(0, 4)}-${rest.substring(4)}';
    }
    return contactPhone;
  }

  String get initials {
    final s = displayName.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory TicketListItem.fromJson(Map<String, dynamic> j) => TicketListItem(
        id: j['id'],
        protocol: j['protocol'] ?? '',
        status: j['status'] ?? 'open',
        contactPhone: j['contact_phone'] ?? '',
        contactName: j['contact_name'],
        lastMessageAt: DateTime.tryParse(j['last_message_at'] ?? '')?.toLocal() ?? DateTime.now(),
        aiPaused: j['ai_paused'] == true,
        unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      );
}

/// Uma mensagem da conversa.
class Message {
  Message({
    required this.id,
    required this.direction,
    required this.type,
    this.content,
    this.mediaUrl,
    this.mimeType,
    this.fileName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String direction; // in (cliente) | out (atendente)
  final String type; // text | image | document | audio | video | template
  final String? content;
  final String? mediaUrl;
  final String? mimeType;
  final String? fileName;
  final String status;
  final DateTime createdAt;

  bool get isOutbound => direction == 'out';
  bool get isImage => type == 'image';
  bool get isAudio => type == 'audio';
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'],
        direction: j['direction'] ?? 'in',
        type: j['type'] ?? 'text',
        content: j['content'],
        mediaUrl: j['media_url'],
        mimeType: j['mime_type'],
        fileName: j['file_name'],
        status: j['status'] ?? '',
        createdAt: DateTime.tryParse(j['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
      );
}
