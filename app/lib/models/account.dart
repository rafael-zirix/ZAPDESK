/// Uma empresa cliente da plataforma (visão do super-admin).
class Account {
  Account({
    required this.id,
    required this.name,
    required this.status,
    this.slug,
    this.numbersCount = 0,
  });

  final String id;
  final String name;
  final String status;
  final String? slug;
  final int numbersCount;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        status: j['status'] ?? 'active',
        slug: j['slug'],
        numbersCount: (j['numbers_count'] ?? 0) as int,
      );
}
