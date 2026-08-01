/// Uma empresa cliente da plataforma (visão do super-admin), com a ficha completa.
class Account {
  Account({
    required this.id,
    required this.name,
    required this.status,
    this.slug,
    this.numbersCount = 0,
    this.personType,
    this.document,
    this.tradeName,
    this.email,
    this.phone,
    this.zipCode,
    this.street,
    this.number,
    this.complement,
    this.district,
    this.city,
    this.state,
    this.otpWhatsAppEnabled = true,
    this.otpEmailEnabled = true,
  });

  final String id;
  final String name;
  final String status;
  final String? slug;
  final int numbersCount;

  // Canais de OTP de login permitidos pela empresa.
  final bool otpWhatsAppEnabled;
  final bool otpEmailEnabled;

  // Ficha
  final String? personType; // pf | pj
  final String? document; // CPF/CNPJ
  final String? tradeName;
  final String? email;
  final String? phone;
  final String? zipCode;
  final String? street;
  final String? number;
  final String? complement;
  final String? district;
  final String? city;
  final String? state;

  String get personTypeLabel => switch (personType) {
        'pf' => 'Pessoa física',
        'pj' => 'Pessoa jurídica',
        _ => '—',
      };

  bool get hasAddress => (city ?? '').isNotEmpty || (street ?? '').isNotEmpty;

  String get addressLine {
    final parts = <String>[
      if ((street ?? '').isNotEmpty) [street, number].where((e) => (e ?? '').isNotEmpty).join(', '),
      if ((district ?? '').isNotEmpty) district!,
      if ((city ?? '').isNotEmpty) [city, state].where((e) => (e ?? '').isNotEmpty).join('/'),
    ].whereType<String>().toList();
    return parts.join(' · ');
  }

  static String? _s(dynamic v) => (v == null || (v is String && v.isEmpty)) ? null : v as String;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        status: j['status'] ?? 'active',
        slug: _s(j['slug']),
        numbersCount: (j['numbers_count'] ?? 0) as int,
        personType: _s(j['person_type']),
        document: _s(j['document']),
        tradeName: _s(j['trade_name']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        zipCode: _s(j['zip_code']),
        street: _s(j['street']),
        number: _s(j['number']),
        complement: _s(j['complement']),
        district: _s(j['district']),
        city: _s(j['city']),
        state: _s(j['state']),
      );
}
