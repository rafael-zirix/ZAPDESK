/// Um modelo (template) de mensagem aprovado na Meta.
class MessageTemplate {
  MessageTemplate({required this.name, required this.language, this.bodyText, this.category});

  final String name;
  final String language;
  final String? bodyText;
  final String? category;

  factory MessageTemplate.fromJson(Map<String, dynamic> j) => MessageTemplate(
        name: j['name'] ?? '',
        language: j['language'] ?? '',
        bodyText: j['body_text'],
        category: j['category'],
      );
}
