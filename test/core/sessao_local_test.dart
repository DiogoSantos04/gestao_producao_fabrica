import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/core/sessao_local.dart';

void main() {
  setUp(() {
    // O estado é estático: cada teste tem de começar com a marca limpa.
    SessaoLocal.consumirTerminoIntencional();
  });

  test('sem marca, o término é considerado involuntário', () {
    expect(SessaoLocal.consumirTerminoIntencional(), isFalse);
  });

  test('depois de marcar, o término é considerado intencional', () {
    SessaoLocal.marcarTerminoIntencional();
    expect(SessaoLocal.consumirTerminoIntencional(), isTrue);
  });

  test('a marca só serve uma vez', () {
    SessaoLocal.marcarTerminoIntencional();
    expect(SessaoLocal.consumirTerminoIntencional(), isTrue);

    // Um segundo signOut, este involuntário, não pode aproveitar a marca do
    // primeiro — senão a perda de sessão passava despercebida.
    expect(SessaoLocal.consumirTerminoIntencional(), isFalse);
  });
}
