/// Usuário autenticado (atendente/admin da empresa, ou super-admin da plataforma).
class AppUser {
  AppUser({
    required this.id,
    required this.accountId,
    required this.fullName,
    required this.email,
    required this.role,
  });

  final String id;
  final String accountId; // vazio para super-admin
  final String fullName;
  final String email;
  final String role; // superadmin | admin | agent

  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => role == 'admin';

  /// Iniciais para o avatar.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] ?? '',
        accountId: (j['account_id'] ?? '').toString(),
        fullName: j['full_name'] ?? '',
        email: j['email'] ?? '',
        role: j['role'] ?? 'agent',
      );
}
