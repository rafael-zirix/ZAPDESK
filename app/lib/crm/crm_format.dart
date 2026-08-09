import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Helpers de formatação do CRM (dinheiro em centavos, cores hex, datas UTC-3).

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Centavos → "R$ 1.234,56".
String moneyFromCents(int cents) => _money.format(cents / 100);

/// Texto digitado ("1.234,56", "1234,56", "1234.56") → centavos. Vazio = 0.
int parseMoneyToCents(String text) {
  var t = text.trim().replaceAll('R\$', '').trim();
  if (t.isEmpty) return 0;
  // Padrão BR: ponto de milhar, vírgula decimal.
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  final v = double.tryParse(t) ?? 0;
  return (v * 100).round();
}

/// "#RRGGBB" → Color (fallback teal).
Color hexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF0E9384);
}

/// Data de retorno para o chip do card: "10/08". Vencida = destaque vermelho.
String followUpLabel(DateTime utc) =>
    DateFormat('dd/MM').format(utc.add(const Duration(hours: -3)));

/// O retorno já passou? (compara o DIA em UTC-3)
bool followUpOverdue(DateTime utc) {
  final local = utc.add(const Duration(hours: -3));
  final nowLocal = DateTime.now().toUtc().add(const Duration(hours: -3));
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  return d.isBefore(today) || d.isAtSameMomentAs(today);
}

/// Rótulo curto da origem do negócio.
String sourceLabel(String? source) => switch (source) {
      'instagram' => 'Instagram',
      'whatsapp' => 'WhatsApp',
      'site' => 'Site',
      'indicacao' => 'Indicação',
      'manual' => 'Manual',
      null || '' => '',
      _ => source,
    };

IconData sourceIcon(String? source) => switch (source) {
      'instagram' => Icons.camera_alt_outlined,
      'whatsapp' => Icons.chat_outlined,
      'site' => Icons.language_outlined,
      'indicacao' => Icons.handshake_outlined,
      _ => Icons.bolt_outlined,
    };
