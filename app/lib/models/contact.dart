/// Um contato (cliente final) da empresa.
class Contact {
  Contact({required this.id, required this.phone, this.name});

  final String id;
  final String phone;
  final String? name;

  String get displayName => (name != null && name!.isNotEmpty) ? name! : phone;

  String get initials {
    final s = displayName.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Telefone formatado para exibição: +55 (21) 99333-9504 quando possível.
  String get prettyPhone {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 13) {
      return '+${d.substring(0, 2)} (${d.substring(2, 4)}) ${d.substring(4, 9)}-${d.substring(9)}';
    }
    if (d.length == 12) {
      return '+${d.substring(0, 2)} (${d.substring(2, 4)}) ${d.substring(4, 8)}-${d.substring(8)}';
    }
    return phone;
  }

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] ?? '',
        phone: j['phone'] ?? '',
        name: j['name'],
      );
}
