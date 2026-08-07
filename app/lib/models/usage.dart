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
    this.marketing = 0,
    this.utility = 0,
    this.authentication = 0,
    this.serviceFree = 0,
    this.valueMarketing = 0,
    this.valueUtility = 0,
    this.valueAuthentication = 0,
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
  // Cobrança da Meta: mensagens de template ENTREGUES por categoria.
  final int marketing;
  final int utility;
  final int authentication;
  final int serviceFree; // conversas de atendimento (gratuitas na Meta)
  final double valueMarketing;
  final double valueUtility;
  final double valueAuthentication;
  final double valueWhatsApp; // soma das categorias
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
        marketing: (j['marketing'] as num?)?.toInt() ?? 0,
        utility: (j['utility'] as num?)?.toInt() ?? 0,
        authentication: (j['authentication'] as num?)?.toInt() ?? 0,
        serviceFree: (j['service_free'] as num?)?.toInt() ?? 0,
        valueMarketing: (j['value_marketing'] as num?)?.toDouble() ?? 0,
        valueUtility: (j['value_utility'] as num?)?.toDouble() ?? 0,
        valueAuthentication: (j['value_authentication'] as num?)?.toDouble() ?? 0,
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
  Pricing({
    required this.conversation,
    required this.per1kTokens,
    this.marketing = 0,
    this.utility = 0,
    this.authentication = 0,
    this.packages = const [],
  });
  final double conversation; // legado: R$ por conversa (modelo antigo da Meta)
  final double per1kTokens; // R$ por 1.000 tokens de IA
  final double marketing; // R$ por mensagem de marketing entregue
  final double utility; // R$ por mensagem de utilidade entregue
  final double authentication; // R$ por mensagem de autenticação entregue
  final List<double> packages; // valores R$ dos planos de recarga

  factory Pricing.fromJson(Map<String, dynamic>? j) => Pricing(
        conversation: (j?['price_conversation'] as num?)?.toDouble() ?? 0,
        per1kTokens: (j?['price_1k_tokens'] as num?)?.toDouble() ?? 0,
        marketing: (j?['price_marketing'] as num?)?.toDouble() ?? 0,
        utility: (j?['price_utility'] as num?)?.toDouble() ?? 0,
        authentication: (j?['price_authentication'] as num?)?.toDouble() ?? 0,
        packages: ((j?['packages'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}


/// Linha da tabela de custo da META (visão do dono da plataforma).
class MetaCategoryPrice {
  MetaCategoryPrice({required this.category, required this.price, required this.count, required this.cost});

  final String category; // MARKETING | UTILITY | AUTHENTICATION | SERVICE
  final double price; // custo unitário observado
  final int count; // conversas observadas no período
  final double cost; // custo total observado

  String get label => switch (category.toUpperCase()) {
        'MARKETING' => 'Marketing',
        'UTILITY' => 'Utilidade',
        'AUTHENTICATION' => 'Autenticação',
        'SERVICE' => 'Atendimento',
        _ => category,
      };

  factory MetaCategoryPrice.fromJson(Map<String, dynamic> j) => MetaCategoryPrice(
        category: j['category'] ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
      );
}

/// Tabela de custo da META por categoria — referência do dono da plataforma.
/// O CLIENTE nunca vê isto: a Meta cobra direto na conta de WhatsApp dele.
class MetaPricingTable {
  MetaPricingTable({
    this.currency = 'BRL',
    this.updatedAt,
    this.source = '',
    this.rows = const [],
    this.note = '',
  });

  final String currency;
  final DateTime? updatedAt;
  final String source; // meta (automática) | manual
  final List<MetaCategoryPrice> rows;
  final String note;

  factory MetaPricingTable.fromJson(Map<String, dynamic>? j) => MetaPricingTable(
        currency: j?['currency'] ?? 'BRL',
        updatedAt: DateTime.tryParse(j?['updated_at'] ?? '')?.toLocal(),
        source: j?['source'] ?? '',
        rows: ((j?['rows'] as List?) ?? const [])
            .map((e) => MetaCategoryPrice.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: j?['note'] ?? '',
      );
}


/// Custo de um modelo de IA por 1.000 tokens (o que NÓS pagamos ao provedor).
class AIModelCost {
  AIModelCost({
    required this.model,
    this.provider = '',
    this.per1k = 0,
    this.active = false,
    this.note = '',
    this.label = '',
    this.offered = false,
    this.factor = 1,
    this.baseUrl = '',
    this.keyEnv = '',
    this.context = '',
    this.intelligence = 0,
    this.speed = 0,
    this.bestFor = '',
  });

  final String model;
  final String provider;
  final double per1k; // custo NOSSO por 1k (nunca vai ao cliente)
  final bool active; // é o modelo em uso na plataforma
  final String note;

  // O que torna o modelo vendável e comparável na vitrine do cliente.
  final String label; // nome comercial
  final bool offered; // aparece para o cliente escolher
  final double factor; // multiplicador do consumo do saldo
  final String baseUrl; // endpoint do provedor
  final String keyEnv; // NOME da variável de ambiente com a chave (nunca o valor)
  final String context; // janela de contexto ("1M")
  final int intelligence; // 0-100
  final int speed; // 0-100
  final String bestFor; // no que ela é melhor

  Map<String, dynamic> toJson() => {
        'model': model,
        'provider': provider,
        'per_1k': per1k,
        'note': note,
        'label': label,
        'offered': offered,
        'factor': factor,
        'base_url': baseUrl,
        'key_env': keyEnv,
        'context': context,
        'intelligence': intelligence,
        'speed': speed,
        'best_for': bestFor,
      };

  factory AIModelCost.fromJson(Map<String, dynamic> j) => AIModelCost(
        model: j['model'] ?? '',
        provider: j['provider'] ?? '',
        per1k: (j['per_1k'] as num?)?.toDouble() ?? 0,
        active: j['active'] == true,
        note: j['note'] ?? '',
        label: j['label'] ?? '',
        offered: j['offered'] == true,
        factor: (j['factor'] as num?)?.toDouble() ?? 1,
        baseUrl: j['base_url'] ?? '',
        keyEnv: j['key_env'] ?? '',
        context: j['context'] ?? '',
        intelligence: (j['intelligence'] as num?)?.toInt() ?? 0,
        speed: (j['speed'] as num?)?.toInt() ?? 0,
        bestFor: j['best_for'] ?? '',
      );
}

/// Tabela de custos dos modelos de IA (vários provedores).
class AICostTable {
  AICostTable({this.activeModel = '', this.models = const []});

  final String activeModel;
  final List<AIModelCost> models;

  /// Custo por 1.000 tokens do modelo em uso (0 se não cadastrado).
  double get activePer1k {
    for (final m in models) {
      if (m.model.toLowerCase() == activeModel.toLowerCase()) return m.per1k;
    }
    return 0;
  }

  factory AICostTable.fromJson(Map<String, dynamic>? j) => AICostTable(
        activeModel: j?['active_model'] ?? '',
        models: ((j?['models'] as List?) ?? const [])
            .map((e) => AIModelCost.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
