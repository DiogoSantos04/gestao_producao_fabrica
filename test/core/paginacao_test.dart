import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/core/paginacao.dart';

void main() {
  group('PaginaResultado.aPartirDeSondagem', () {
    test('menos linhas do que o tamanho: não há mais nada a seguir', () {
      final p = PaginaResultado.aPartirDeSondagem([1, 2, 3], 5);
      expect(p.itens, [1, 2, 3]);
      expect(p.temMais, isFalse);
    });

    test('exatamente o tamanho pedido: a sonda não veio, logo acabou', () {
      // A query pede tamanho + 1. Se voltarem só `tamanho` linhas, a última
      // página coincide com o fim dos dados.
      final p = PaginaResultado.aPartirDeSondagem([1, 2, 3], 3);
      expect(p.itens, [1, 2, 3]);
      expect(p.temMais, isFalse);
    });

    test('a linha-sentinela é descartada e sinaliza que há mais', () {
      final p = PaginaResultado.aPartirDeSondagem([1, 2, 3, 4], 3);
      expect(p.itens, [1, 2, 3], reason: 'a sonda não é mostrada ao utilizador');
      expect(p.temMais, isTrue);
    });

    test('resposta vazia', () {
      final p = PaginaResultado.aPartirDeSondagem(<int>[], 50);
      expect(p.itens, isEmpty);
      expect(p.temMais, isFalse);
    });

    test('a página nunca devolve mais itens do que o tamanho', () {
      final p = PaginaResultado.aPartirDeSondagem(List.generate(60, (i) => i), 50);
      expect(p.itens, hasLength(50));
      expect(p.temMais, isTrue);
    });
  });

  test('PaginaResultado.vazia não tem itens nem continuação', () {
    expect(PaginaResultado.vazia.itens, isEmpty);
    expect(PaginaResultado.vazia.temMais, isFalse);
  });
}
