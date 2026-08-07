import '../core/phone.dart' show formatPhone;
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
    this.assignedUserId,
    this.assignedUserName,
    this.sectorId,
    this.sectorName,
    this.tags = const [],
  });

  final String id;
  final String protocol;
  String status; // open | pending | resolved | closed (mutável p/ ações no header)
  final String contactPhone;
  final String? contactName;
  final DateTime lastMessageAt;
  bool aiPaused; // Atendente IA pausado nesta conversa (mutável p/ toggle otimista)
  int unreadCount; // mensagens recebidas não lidas (mutável p/ zerar ao abrir)
  String? assignedUserId; // atendente responsável (null = ninguém assumiu)
  String? assignedUserName;
  String? sectorId; // setor/fila (null = sem setor)
  String? sectorName;
  List<TicketTag> tags;

  /// Copia os campos mutáveis vindos de uma resposta da API (claim/transfer/status).
  void applyFrom(TicketListItem o) {
    status = o.status;
    assignedUserId = o.assignedUserId;
    assignedUserName = o.assignedUserName;
    sectorId = o.sectorId;
    sectorName = o.sectorName;
    tags = o.tags;
  }

  /// Rótulo humano do status ("Novo" quando aberta e sem dono).
  String get statusLabel => switch (status) {
        'open' => assignedUserId == null ? 'Novo' : 'Em atendimento',
        'pending' => 'Aguardando cliente',
        'resolved' => 'Resolvido',
        'closed' => 'Fechado',
        _ => status,
      };

  String get displayName => (contactName != null && contactName!.isNotEmpty) ? contactName! : contactPhone;

  /// Telefone formatado — mesmo padrão dos contatos: +55 (21) 99333-9504.
  String get prettyPhone => formatPhone(contactPhone);

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
        assignedUserId: j['assigned_user_id'],
        assignedUserName: j['assigned_user_name'],
        sectorId: j['sector_id'],
        sectorName: j['sector_name'],
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => TicketTag.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Etiqueta da empresa (aplicável às conversas).
class TicketTag {
  TicketTag({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final String color; // hex, ex.: #0E9384

  factory TicketTag.fromJson(Map<String, dynamic> j) =>
      TicketTag(id: j['id'], name: j['name'] ?? '', color: j['color'] ?? '#0E9384');
}

/// Resposta rápida (atalho de texto): /boleto → mensagem pronta.
class QuickReply {
  QuickReply({required this.id, required this.shortcut, required this.content});

  final String id;
  final String shortcut;
  final String content;

  factory QuickReply.fromJson(Map<String, dynamic> j) =>
      QuickReply(id: j['id'], shortcut: j['shortcut'] ?? '', content: j['content'] ?? '');
}

/// Um setor (fila de atendimento) da empresa.
class Sector {
  Sector({required this.id, required this.name, this.members = const [], this.adDefault = false});

  final String id;
  final String name;
  final List<String> members; // ids dos atendentes do setor

  /// Setor que recebe os leads vindos de anúncio (Click-to-WhatsApp). Um por empresa.
  final bool adDefault;

  factory Sector.fromJson(Map<String, dynamic> j) => Sector(
        id: j['id'],
        name: j['name'] ?? '',
        members: ((j['members'] as List?) ?? const []).cast<String>(),
        adDefault: j['ad_default'] ?? false,
      );
}

/// Uma entrada do histórico (timeline) da conversa.
class TicketEvent {
  TicketEvent({
    required this.kind,
    this.actorName,
    this.fromUserName,
    this.toUserName,
    this.fromSectorName,
    this.toSectorName,
    this.fromStatus,
    this.toStatus,
    this.note,
    required this.createdAt,
  });

  final String kind; // assigned | transferred | status_changed | note | reopened
  final String? actorName;
  final String? fromUserName;
  final String? toUserName;
  final String? fromSectorName;
  final String? toSectorName;
  final String? fromStatus;
  final String? toStatus;
  final String? note;
  final DateTime createdAt;

  static String _statusPt(String? s) => switch (s) {
        'open' => 'Em atendimento',
        'pending' => 'Aguardando cliente',
        'resolved' => 'Resolvido',
        'closed' => 'Fechado',
        _ => s ?? '',
      };

  /// Frase pronta para exibir na timeline.
  String get describe {
    final by = actorName != null ? ' por $actorName' : '';
    switch (kind) {
      case 'assigned':
        return '${toUserName ?? 'Atendente'} assumiu a conversa';
      case 'transferred':
        final parts = <String>[];
        if (toUserName != null) parts.add('para ${toUserName!}');
        if (toSectorName != null) parts.add('para o setor ${toSectorName!}');
        if (toUserName == null && toSectorName != null) {
          return 'Devolvida à fila do setor ${toSectorName!}$by';
        }
        return 'Transferida ${parts.join(' ')}$by';
      case 'status_changed':
        return 'Status: ${_statusPt(fromStatus)} → ${_statusPt(toStatus)}$by';
      case 'reopened':
        return 'Reaberta — o cliente respondeu depois de resolvida';
      case 'note':
        return 'Nota$by';
      default:
        return kind;
    }
  }

  factory TicketEvent.fromJson(Map<String, dynamic> j) => TicketEvent(
        kind: j['kind'] ?? '',
        actorName: j['actor_name'],
        fromUserName: j['from_user_name'],
        toUserName: j['to_user_name'],
        fromSectorName: j['from_sector_name'],
        toSectorName: j['to_sector_name'],
        fromStatus: j['from_status'],
        toStatus: j['to_status'],
        note: j['note'],
        createdAt: DateTime.tryParse(j['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
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
    this.internal = false,
    this.senderName,
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
  final bool internal; // nota interna: só a equipe vê (nunca vai ao cliente)
  final String? senderName; // atendente que enviou (exibido nas notas)

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
        internal: j['internal'] == true,
        senderName: j['sender_name'],
      );
}
