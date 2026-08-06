/// Funil de uma campanha (contagem de destinatários por status).
class CampaignFunnel {
  CampaignFunnel({
    this.total = 0,
    this.pending = 0,
    this.sent = 0,
    this.delivered = 0,
    this.read = 0,
    this.replied = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int total;
  final int pending;
  final int sent;
  final int delivered;
  final int read;
  final int replied;
  final int failed;
  final int skipped;

  /// Acumulados do funil (cada destinatário tem UM status; aqui somamos "chegou até").
  int get reachedSent => sent + delivered + read + replied;
  int get reachedDelivered => delivered + read + replied;
  int get reachedRead => read + replied;
  int get done => total - pending;

  factory CampaignFunnel.fromJson(Map<String, dynamic> j) => CampaignFunnel(
        total: (j['total'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        delivered: (j['delivered'] as num?)?.toInt() ?? 0,
        read: (j['read'] as num?)?.toInt() ?? 0,
        replied: (j['replied'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
      );
}

/// Uma campanha de disparo de template.
class Campaign {
  Campaign({
    required this.id,
    required this.name,
    required this.templateName,
    required this.templateLang,
    this.bodyText,
    required this.status,
    required this.scheduledAt,
    required this.ratePerMin,
    required this.createdAt,
    required this.funnel,
  });

  final String id;
  final String name;
  final String templateName;
  final String templateLang;
  final String? bodyText;
  final String status; // scheduled | running | paused | done | canceled
  final DateTime scheduledAt;
  final int ratePerMin;
  final DateTime createdAt;
  final CampaignFunnel funnel;

  String get statusLabel => switch (status) {
        'scheduled' => 'Agendada',
        'running' => 'Enviando',
        'paused' => 'Pausada',
        'done' => 'Concluída',
        'canceled' => 'Cancelada',
        _ => status,
      };

  bool get isActive => status == 'scheduled' || status == 'running' || status == 'paused';

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id: j['id'],
        name: j['name'] ?? '',
        templateName: j['template_name'] ?? '',
        templateLang: j['template_lang'] ?? 'pt_BR',
        bodyText: j['body_text'],
        status: j['status'] ?? 'scheduled',
        scheduledAt: DateTime.tryParse(j['scheduled_at'] ?? '')?.toLocal() ?? DateTime.now(),
        ratePerMin: (j['rate_per_min'] as num?)?.toInt() ?? 12,
        createdAt: DateTime.tryParse(j['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
        funnel: CampaignFunnel.fromJson((j['funnel'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// Destinatário de uma campanha (linha do detalhe).
class CampaignRecipient {
  CampaignRecipient({
    required this.id,
    required this.phone,
    this.contactName,
    required this.status,
    this.error,
  });

  final String id;
  final String phone;
  final String? contactName;
  final String status;
  final String? error;

  String get displayName => (contactName != null && contactName!.isNotEmpty) ? contactName! : phone;

  String get statusLabel => switch (status) {
        'pending' => 'Na fila',
        'sent' => 'Enviada',
        'delivered' => 'Entregue',
        'read' => 'Lida',
        'replied' => 'Respondeu',
        'failed' => 'Falhou',
        'skipped' => 'Pulada',
        _ => status,
      };

  factory CampaignRecipient.fromJson(Map<String, dynamic> j) => CampaignRecipient(
        id: j['id'],
        phone: j['phone'] ?? '',
        contactName: j['contact_name'],
        status: j['status'] ?? 'pending',
        error: j['error'],
      );
}
