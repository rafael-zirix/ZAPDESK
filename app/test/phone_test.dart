import 'package:flutter_test/flutter_test.dart';
import 'package:zapdesk_app/core/phone.dart';

void main() {
  test('celular com DDI vira +55 (21) 99333-9504', () {
    expect(formatPhone('5521993339504'), '+55 (21) 99333-9504');
  });
  test('fixo com DDI', () {
    expect(formatPhone('552127049161'), '+55 (21) 2704-9161');
  });
  test('já formatado continua igual', () {
    expect(formatPhone('+55 (21) 99333-9504'), '+55 (21) 99333-9504');
  });
  test('sem DDI usa só o DDD', () {
    expect(formatPhone('21993339504'), '(21) 99333-9504');
  });
  test('formato desconhecido volta como veio', () {
    expect(formatPhone('123'), '123');
  });
}
