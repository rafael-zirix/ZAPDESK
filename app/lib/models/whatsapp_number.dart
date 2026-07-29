/// Um número de WhatsApp conectado à empresa (nunca traz o token).
class WhatsAppNumber {
  WhatsAppNumber({
    required this.id,
    required this.wabaId,
    required this.phoneNumberId,
    required this.status,
    this.displayPhone,
    this.verifiedName,
  });

  final String id;
  final String wabaId;
  final String phoneNumberId;
  final String status; // connected | disconnected | pending
  final String? displayPhone;
  final String? verifiedName;

  String get title => (verifiedName != null && verifiedName!.isNotEmpty)
      ? verifiedName!
      : (displayPhone ?? phoneNumberId);

  factory WhatsAppNumber.fromJson(Map<String, dynamic> j) => WhatsAppNumber(
        id: j['id'] ?? '',
        wabaId: j['waba_id'] ?? '',
        phoneNumberId: j['phone_number_id'] ?? '',
        status: j['status'] ?? 'connected',
        displayPhone: j['display_phone'],
        verifiedName: j['verified_name'],
      );
}
