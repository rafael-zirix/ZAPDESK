/// Retorno do Embedded Signup da Meta: o código de autorização (trocado por token
/// no backend) + os IDs do número/WABA conectados.
class EmbeddedResult {
  const EmbeddedResult({required this.code, required this.wabaId, required this.phoneNumberId});
  final String code;
  final String wabaId;
  final String phoneNumberId;
}
