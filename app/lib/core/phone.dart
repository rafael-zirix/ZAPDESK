/// Formatação de telefone usada em TODA a interface (contatos, conversas,
/// campanhas): +55 (21) 99333-9504. Um lugar só evita a lista mostrar um
/// formato e a conversa outro.
String formatPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  // Brasil: 55 + DDD + 9 dígitos (celular) ou 8 (fixo).
  if (d.length == 13) {
    return '+${d.substring(0, 2)} (${d.substring(2, 4)}) ${d.substring(4, 9)}-${d.substring(9)}';
  }
  if (d.length == 12) {
    return '+${d.substring(0, 2)} (${d.substring(2, 4)}) ${d.substring(4, 8)}-${d.substring(8)}';
  }
  // Sem o código do país (só DDD + número).
  if (d.length == 11) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  return phone; // formato desconhecido (internacional): mostra como veio
}
