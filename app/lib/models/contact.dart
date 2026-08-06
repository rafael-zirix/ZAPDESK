import '../core/phone.dart' show formatPhone;
import 'support.dart' show TicketTag;

/// Um contato (cliente final) da empresa.
class Contact {
  Contact({
    required this.id,
    required this.phone,
    this.name,
    this.groups = const [],
    this.tags = const [],
  });

  final String id;
  final String phone;
  final String? name;
  List<ContactGroupRef> groups; // grupos de marketing (mutável p/ atualizar em lugar)
  List<TicketTag> tags; // etiquetas do contato (filtro de campanha)

  String get displayName => (name != null && name!.isNotEmpty) ? name! : phone;

  String get initials {
    final s = displayName.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Telefone formatado para exibição: +55 (21) 99333-9504 quando possível.
  String get prettyPhone => formatPhone(phone);

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] ?? '',
        phone: j['phone'] ?? '',
        name: j['name'],
        groups: ((j['groups'] as List?) ?? const [])
            .map((e) => ContactGroupRef.fromJson(e as Map<String, dynamic>))
            .toList(),
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => TicketTag.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Referência leve de um grupo no contato (chip).
class ContactGroupRef {
  ContactGroupRef({required this.id, required this.name});

  final String id;
  final String name;

  factory ContactGroupRef.fromJson(Map<String, dynamic> j) =>
      ContactGroupRef(id: j['id'], name: j['name'] ?? '');
}

/// Grupo de contatos (lista de marketing) com a contagem de membros.
class ContactGroup {
  ContactGroup({required this.id, required this.name, this.members = 0});

  final String id;
  final String name;
  final int members;

  factory ContactGroup.fromJson(Map<String, dynamic> j) => ContactGroup(
        id: j['id'],
        name: j['name'] ?? '',
        members: (j['members'] as num?)?.toInt() ?? 0,
      );
}
