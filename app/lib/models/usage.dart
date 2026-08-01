/// Consumo de um número (com custo da Meta quando disponível).
class NumberUsage {
  NumberUsage({
    required this.displayPhone,
    required this.wabaId,
    required this.metaConversations,
    required this.metaCost,
    required this.costAvailable,
  });

  final String displayPhone;
  final String wabaId;
  final int metaConversations;
  final double metaCost;
  final bool costAvailable;

  factory NumberUsage.fromJson(Map<String, dynamic> j) => NumberUsage(
        displayPhone: j['display_phone'] ?? '',
        wabaId: j['waba_id'] ?? '',
        metaConversations: j['meta_conversations'] ?? 0,
        metaCost: (j['meta_cost'] as num?)?.toDouble() ?? 0,
        costAvailable: j['cost_available'] ?? false,
      );
}

/// Consumo de uma empresa no período.
class CompanyUsage {
  CompanyUsage({
    required this.accountId,
    required this.name,
    required this.messagesOut,
    required this.messagesIn,
    required this.templates,
    required this.media,
    required this.conversations,
    required this.aiTokens,
    required this.valueWhatsApp,
    required this.valueAI,
    required this.valueTotal,
    required this.numbers,
  });

  final String accountId;
  final String name;
  final int messagesOut;
  final int messagesIn;
  final int templates;
  final int media;
  final int conversations;
  final int aiTokens; // tokens de IA consumidos no período
  final double valueWhatsApp; // R$ = conversas × preço/conversa
  final double valueAI; // R$ = tokens/1000 × preço/1k
  final double valueTotal; // R$ WhatsApp + IA
  final List<NumberUsage> numbers;

  int get messagesTotal => messagesOut + messagesIn;

  factory CompanyUsage.fromJson(Map<String, dynamic> j) => CompanyUsage(
        accountId: j['account_id'] ?? '',
        name: j['name'] ?? '',
        messagesOut: j['messages_out'] ?? 0,
        messagesIn: j['messages_in'] ?? 0,
        templates: j['templates'] ?? 0,
        media: j['media'] ?? 0,
        conversations: j['conversations'] ?? 0,
        aiTokens: (j['ai_tokens'] as num?)?.toInt() ?? 0,
        valueWhatsApp: (j['value_whatsapp'] as num?)?.toDouble() ?? 0,
        valueAI: (j['value_ai'] as num?)?.toDouble() ?? 0,
        valueTotal: (j['value_total'] as num?)?.toDouble() ?? 0,
        numbers: ((j['numbers'] as List?) ?? [])
            .map((e) => NumberUsage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Preços da plataforma (super-admin cobra pelo uso).
class Pricing {
  Pricing({required this.conversation, required this.per1kTokens});
  final double conversation; // R$ por conversa WhatsApp
  final double per1kTokens; // R$ por 1.000 tokens de IA

  factory Pricing.fromJson(Map<String, dynamic>? j) => Pricing(
        conversation: (j?['price_conversation'] as num?)?.toDouble() ?? 0,
        per1kTokens: (j?['price_1k_tokens'] as num?)?.toDouble() ?? 0,
      );
}
