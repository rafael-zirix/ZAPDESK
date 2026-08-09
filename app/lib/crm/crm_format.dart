import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Helpers de formatação do CRM (dinheiro em centavos, cores hex, datas UTC-3).

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Centavos → "R$ 1.234,56".
String moneyFromCents(int cents) => _money.format(cents / 100);

final _moneyMask = NumberFormat('#,##0.00', 'pt_BR');

/// Máscara de dinheiro no padrão BR (X.XXX,XX), estilo app de banco: os
/// dígitos entram pelos centavos — "1" → 0,01 · "100" → 1,00 · "1000000" →
/// 10.000,00. Sempre bem-formado, impossível digitar errado.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 12 ? digits.substring(0, 12) : digits;
    if (d.isEmpty) return const TextEditingValue(text: '');
    final masked = _moneyMask.format(int.parse(d) / 100);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

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

/// Estado do retorno (compara o DIA em UTC-3):
/// 0 = agendado (futuro) · 1 = é HOJE · 2 = ATRASADO.
int followUpState(DateTime utc) {
  final local = utc.add(const Duration(hours: -3));
  final nowLocal = DateTime.now().toUtc().add(const Duration(hours: -3));
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  if (d.isBefore(today)) return 2;
  if (d.isAtSameMomentAs(today)) return 1;
  return 0;
}

/// Paleta das etapas do funil (a primeira é o teal da marca).
const kStagePalette = [
  '#0E9384', '#64748B', '#7C3AED', '#F59E0B', '#F97316',
  '#EF4444', '#2563EB', '#16A34A', '#DB2777', '#0891B2',
];

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
