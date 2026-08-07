/// Um módulo do produto. O cliente contrata por módulo; o núcleo vem sempre.
///
/// O catálogo é do backend (`GET /modules`) — o app só desenha o que vier, para
/// não existirem duas listas de módulos para manter em sincronia.
class AppModule {
  AppModule({
    required this.key,
    required this.name,
    required this.description,
    this.core = false,
    this.comingSoon = false,
    this.priceCents = 0,
    this.enabled = false,
    this.trialEndsAt,
  });

  final String key;
  final String name;
  final String description;
  final bool core; // sempre ligado, não se contrata
  final bool comingSoon; // no catálogo, ainda não entregue
  final int priceCents; // preço de tabela (0 = sob consulta)
  final bool enabled; // esta empresa tem?
  final DateTime? trialEndsAt; // em teste até…

  bool get inTrial => enabled && trialEndsAt != null;

  /// Dias que faltam do teste (0 quando não está em teste).
  int get trialDaysLeft {
    if (trialEndsAt == null) return 0;
    final d = trialEndsAt!.difference(DateTime.now()).inHours / 24;
    return d <= 0 ? 0 : d.ceil();
  }

  String get priceLabel {
    if (priceCents <= 0) return 'sob consulta';
    return 'R\$ ${(priceCents / 100).toStringAsFixed(2).replaceAll('.', ',')}/mês';
  }

  factory AppModule.fromJson(Map<String, dynamic> j) => AppModule(
        key: j['key'] ?? '',
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        core: j['core'] ?? false,
        comingSoon: j['coming_soon'] ?? false,
        priceCents: (j['price_cents'] ?? 0) as int,
        enabled: j['enabled'] ?? false,
        trialEndsAt: j['trial_ends_at'] == null ? null : DateTime.tryParse(j['trial_ends_at'].toString())?.toLocal(),
      );
}
