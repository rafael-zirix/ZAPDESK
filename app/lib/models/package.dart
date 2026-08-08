/// Pacote comercial montado pelo super-admin. Dinheiro em CENTAVOS, como no
/// backend — o app converte para exibir em reais no padrão do Brasil.
class AppPackage {
  AppPackage({
    this.id,
    this.name = '',
    this.active = true,
    this.priceMonthCents = 0,
    this.incLines = 1,
    this.incAgents = 2,
    this.lineAddonCents = 0,
    this.incInstagram = false,
    this.incIA = true,
    this.incCampanhas = false,
    this.incMetricas = false,
    this.franchiseCents = 0,
    this.sort = 0,
  });

  final String? id;
  String name;
  bool active;
  int priceMonthCents;
  int incLines;
  int incAgents;
  int lineAddonCents;
  bool incInstagram;
  bool incIA;
  bool incCampanhas;
  bool incMetricas;
  int franchiseCents;
  int sort;

  AppPackage copy() => AppPackage(
        id: id,
        name: name,
        active: active,
        priceMonthCents: priceMonthCents,
        incLines: incLines,
        incAgents: incAgents,
        lineAddonCents: lineAddonCents,
        incInstagram: incInstagram,
        incIA: incIA,
        incCampanhas: incCampanhas,
        incMetricas: incMetricas,
        franchiseCents: franchiseCents,
        sort: sort,
      );

  factory AppPackage.fromJson(Map<String, dynamic> j) => AppPackage(
        id: j['id']?.toString(),
        name: (j['name'] ?? '').toString(),
        active: j['active'] == true,
        priceMonthCents: (j['price_month_cents'] ?? 0) as int,
        incLines: (j['inc_lines'] ?? 1) as int,
        incAgents: (j['inc_agents'] ?? 1) as int,
        lineAddonCents: (j['line_addon_cents'] ?? 0) as int,
        incInstagram: j['inc_instagram'] == true,
        incIA: j['inc_ia'] == true,
        incCampanhas: j['inc_campanhas'] == true,
        incMetricas: j['inc_metricas'] == true,
        franchiseCents: (j['franchise_cents'] ?? 0) as int,
        sort: (j['sort'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'active': active,
        'price_month_cents': priceMonthCents,
        'inc_lines': incLines,
        'inc_agents': incAgents,
        'line_addon_cents': lineAddonCents,
        'inc_instagram': incInstagram,
        'inc_ia': incIA,
        'inc_campanhas': incCampanhas,
        'inc_metricas': incMetricas,
        'franchise_cents': franchiseCents,
        'sort': sort,
      };
}

/// Formatação em reais no padrão do Brasil: 1234567 centavos -> "12.345,67".
String reaisFromCents(int cents) {
  final neg = cents < 0;
  final v = cents.abs();
  final intPart = (v ~/ 100).toString();
  final dec = (v % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}${buf.toString()},$dec';
}

/// Lê "12.345,67" ou "12345,67" ou "150" e devolve centavos.
int centsFromReais(String s) {
  var t = s.trim().replaceAll(RegExp(r'[^\d,.]'), '');
  if (t.isEmpty) return 0;
  t = t.replaceAll('.', '').replaceAll(',', '.');
  final v = double.tryParse(t) ?? 0;
  return (v * 100).round();
}

/// Milhar no padrão do Brasil: 1234567 -> "1.234.567".
String milhar(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
