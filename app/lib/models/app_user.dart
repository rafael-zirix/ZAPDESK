/// Usuário autenticado (atendente/admin da empresa, ou super-admin da plataforma).
class AppUser {
  AppUser({
    required this.id,
    required this.accountId,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.presence = 'available',
    this.profileId,
    this.perms,
  });

  bool get isAway => presence == 'away';

  final String id;
  final String accountId; // vazio para super-admin
  final String fullName;
  final String email;
  final String role; // superadmin | admin | agent | vendedor
  final String? phone; // celular (WhatsApp) — usado no login por OTP
  final String presence; // available | away (informativo)

  /// Perfil de acesso (Configurações → Perfis). Nulo = sem perfil: vale o
  /// comportamento do papel (legado).
  final String? profileId;
  final Map<String, Map<String, bool>>? perms; // chave -> {view, write}

  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => role == 'admin';

  /// O usuário pode VER esta função? Admin sempre; sem perfil, vale o papel
  /// (true — o perfil só RESTRINGE, nunca abre o que o papel fecha).
  bool canView(String key) {
    if (isAdmin || isSuperAdmin) return true;
    final p = perms;
    if (p == null) return true;
    return p[key]?['view'] ?? false;
  }

  /// O usuário pode GRAVAR nesta função?
  bool canWrite(String key) {
    if (isAdmin || isSuperAdmin) return true;
    final p = perms;
    if (p == null) return true;
    return p[key]?['write'] ?? false;
  }

  /// O perfil concede uma função de ADMIN a este usuário? (delegação — sem
  /// perfil, não-admin não ganha nada)
  bool delegated(String key) {
    if (isAdmin || isSuperAdmin) return true;
    final p = perms;
    if (p == null) return false;
    return p[key]?['view'] ?? false;
  }

  /// Cópia com a presença trocada (o app alterna disponível/ausente sem
  /// recarregar o /auth/me inteiro).
  AppUser copyWith({String? presence}) => AppUser(
        id: id,
        accountId: accountId,
        fullName: fullName,
        email: email,
        role: role,
        phone: phone,
        presence: presence ?? this.presence,
        profileId: profileId,
        perms: perms,
      );

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
        phone: (j['phone'] == null || j['phone'] == '') ? null : j['phone'] as String,
        presence: j['presence'] ?? 'available',
        profileId: j['profile_id'] as String?,
        perms: j['perms'] == null
            ? null
            : {
                for (final e in (j['perms'] as Map).entries)
                  e.key as String: {
                    'view': (e.value['view'] ?? false) as bool,
                    'write': (e.value['write'] ?? false) as bool,
                  },
              },
      );
}
