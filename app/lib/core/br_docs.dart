import 'package:flutter/services.dart';

/// Máscaras e validação de documentos brasileiros (CPF/CNPJ/CEP).
/// O app guarda SÓ DÍGITOS; a máscara é assunto da tela.

/// Formata CPF (000.000.000-00) ou CNPJ (00.000.000/0000-00) enquanto digita,
/// decidindo pelo tamanho: até 11 dígitos é CPF, dali em diante vira CNPJ.
class BrDocInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked = formatBrDoc(d);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Dígitos → "000.000.000-00" (CPF) ou "00.000.000/0000-00" (CNPJ).
String formatBrDoc(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  final b = StringBuffer();
  if (d.length <= 11) {
    for (var i = 0; i < d.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(d[i]);
    }
  } else {
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(d[i]);
    }
  }
  return b.toString();
}

/// CEP: 00000-000.
class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = d.length <= 5 ? d : '${d.substring(0, 5)}-${d.substring(5)}';
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// CPF válido? (dígitos verificadores; recusa sequências repetidas)
bool validCpf(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
  int calc(int len) {
    var sum = 0;
    for (var i = 0; i < len; i++) {
      sum += int.parse(d[i]) * (len + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return calc(9) == int.parse(d[9]) && calc(10) == int.parse(d[10]);
}

/// CNPJ válido? (dígitos verificadores; recusa sequências repetidas)
bool validCnpj(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length != 14) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(d)) return false;
  int calc(int len) {
    const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var sum = 0;
    for (var i = 0; i < len; i++) {
      sum += int.parse(d[i]) * weights[weights.length - len + i];
    }
    final r = sum % 11;
    return r < 2 ? 0 : 11 - r;
  }

  return calc(12) == int.parse(d[12]) && calc(13) == int.parse(d[13]);
}

/// CPF OU CNPJ válido (decide pelo tamanho). Vazio conta como válido — o
/// documento é opcional; obrigatoriedade é regra da tela.
bool validBrDoc(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return true;
  if (d.length == 11) return validCpf(d);
  if (d.length == 14) return validCnpj(d);
  return false;
}
