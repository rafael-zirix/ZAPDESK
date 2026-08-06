/// Um modelo (template) de mensagem da Meta.
class MessageTemplate {
  MessageTemplate({
    required this.name,
    required this.language,
    this.bodyText,
    this.category,
    this.status,
    this.enabled = true,
    this.usage = 'chat',
  });

  final String name;
  final String language;
  final String? bodyText;
  final String? category;
  final String? status; // APPROVED | PENDING | REJECTED

  /// A empresa quer este modelo na barra de mensagens prontas da conversa?
  /// (preferência local; só vale para os aprovados). Default true.
  final bool enabled;

  /// Para que serve: 'chat' (mensagens prontas do atendimento) ou 'campaign'
  /// (disparo em massa). Impede um modelo de promoção poluir as conversas.
  final String usage;

  bool get isCampaign => usage == 'campaign';

  bool get isApproved => (status ?? '').toUpperCase() == 'APPROVED';

  factory MessageTemplate.fromJson(Map<String, dynamic> j) => MessageTemplate(
        name: j['name'] ?? '',
        language: j['language'] ?? '',
        bodyText: j['body_text'],
        category: j['category'],
        status: j['status'],
        enabled: j['enabled'] ?? true,
        usage: j['usage'] ?? 'chat',
      );
}
