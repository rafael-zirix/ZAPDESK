import 'package:flutter_test/flutter_test.dart';
import 'package:zapdesk_app/core/br_docs.dart';

void main() {
  test('CPF: válidos conhecidos passam', () {
    expect(validCpf('529.982.247-25'), isTrue); // exemplo clássico
    expect(validCpf('52998224725'), isTrue);
  });

  test('CPF: inválidos caem', () {
    expect(validCpf('529.982.247-26'), isFalse); // dígito trocado
    expect(validCpf('111.111.111-11'), isFalse); // sequência repetida
    expect(validCpf('123'), isFalse);
  });

  test('CNPJ: válidos conhecidos passam', () {
    expect(validCnpj('11.222.333/0001-81'), isTrue); // exemplo clássico
    expect(validCnpj('11222333000181'), isTrue);
  });

  test('CNPJ: inválidos caem', () {
    expect(validCnpj('11.222.333/0001-82'), isFalse);
    expect(validCnpj('00.000.000/0000-00'), isFalse);
  });

  test('validBrDoc decide pelo tamanho; vazio é válido (campo opcional)', () {
    expect(validBrDoc(''), isTrue);
    expect(validBrDoc('52998224725'), isTrue);
    expect(validBrDoc('11222333000181'), isTrue);
    expect(validBrDoc('1234567'), isFalse); // nem CPF nem CNPJ
  });

  test('máscara formata CPF e CNPJ', () {
    expect(formatBrDoc('52998224725'), '529.982.247-25');
    expect(formatBrDoc('11222333000181'), '11.222.333/0001-81');
    expect(formatBrDoc('529'), '529');
  });
}
