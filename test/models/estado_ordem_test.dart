import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/estado_ordem.dart';

/// `EstadoOrdem.derivar` é a definição única do estado de uma ordem. A mesma
/// regra está escrita três vezes na aplicação — aqui em Dart, em SQL no
/// `EncomendasRepository._aplicarFiltroEstado`, e implicitamente no tratamento
/// de eventos realtime do painel. Estes testes fixam a versão de referência.
void main() {
  group('EstadoOrdem.derivar', () {
    test('em produção: tem fase atual, não cancelada, não suspensa', () {
      expect(
        EstadoOrdem.derivar(cancelada: false, emSuspenso: false, temFaseAtual: true),
        EstadoOrdem.emProducao,
      );
    });

    test('concluída: sem fase atual', () {
      expect(
        EstadoOrdem.derivar(cancelada: false, emSuspenso: false, temFaseAtual: false),
        EstadoOrdem.concluida,
      );
    });

    test('em hold: suspensa com fase atual', () {
      expect(
        EstadoOrdem.derivar(cancelada: false, emSuspenso: true, temFaseAtual: true),
        EstadoOrdem.emHold,
      );
    });

    test('cancelada prevalece sobre suspensa', () {
      expect(
        EstadoOrdem.derivar(cancelada: true, emSuspenso: true, temFaseAtual: true),
        EstadoOrdem.cancelada,
      );
    });

    test('cancelada prevalece sobre ausência de fase atual', () {
      expect(
        EstadoOrdem.derivar(cancelada: true, emSuspenso: false, temFaseAtual: false),
        EstadoOrdem.cancelada,
      );
    });

    test('suspensa prevalece sobre ausência de fase atual', () {
      // Uma ordem suspensa sem fase atual conta como ON HOLD, não como
      // concluída: a precedência do `derivar` avalia `em_suspenso` primeiro,
      // e o SQL do repositório tem de fazer o mesmo.
      expect(
        EstadoOrdem.derivar(cancelada: false, emSuspenso: true, temFaseAtual: false),
        EstadoOrdem.emHold,
      );
    });

    test('cobre as 8 combinações das três colunas', () {
      final resultados = <EstadoOrdem>[];
      for (final c in [false, true]) {
        for (final s in [false, true]) {
          for (final f in [false, true]) {
            resultados.add(
              EstadoOrdem.derivar(cancelada: c, emSuspenso: s, temFaseAtual: f),
            );
          }
        }
      }
      expect(resultados, [
        EstadoOrdem.concluida, // f=false, s=false, c=false
        EstadoOrdem.emProducao,
        EstadoOrdem.emHold,
        EstadoOrdem.emHold,
        EstadoOrdem.cancelada,
        EstadoOrdem.cancelada,
        EstadoOrdem.cancelada,
        EstadoOrdem.cancelada,
      ]);
    });
  });

  group('EstadoOrdem — propriedades derivadas', () {
    test('eFinal apenas para concluída e cancelada', () {
      expect(EstadoOrdem.concluida.eFinal, isTrue);
      expect(EstadoOrdem.cancelada.eFinal, isTrue);
      expect(EstadoOrdem.emProducao.eFinal, isFalse);
      expect(EstadoOrdem.emHold.eFinal, isFalse);
    });

    test('contaParaIndicadores exclui apenas as canceladas', () {
      expect(EstadoOrdem.cancelada.contaParaIndicadores, isFalse);
      expect(EstadoOrdem.concluida.contaParaIndicadores, isTrue);
      expect(EstadoOrdem.emProducao.contaParaIndicadores, isTrue);
      expect(EstadoOrdem.emHold.contaParaIndicadores, isTrue);
    });

    test('estaNaLinha para em produção e em hold', () {
      expect(EstadoOrdem.emProducao.estaNaLinha, isTrue);
      expect(EstadoOrdem.emHold.estaNaLinha, isTrue);
      expect(EstadoOrdem.concluida.estaNaLinha, isFalse);
      expect(EstadoOrdem.cancelada.estaNaLinha, isFalse);
    });

    test('todos os estados têm etiqueta não vazia', () {
      for (final e in EstadoOrdem.values) {
        expect(e.etiqueta, isNotEmpty);
      }
    });
  });

  group('FiltroEstadoOrdem', () {
    test('todos não seleciona estado nenhum', () {
      expect(FiltroEstadoOrdem.todos.estado, isNull);
    });

    test('cada filtro específico mapeia para o estado correspondente', () {
      expect(FiltroEstadoOrdem.emProducao.estado, EstadoOrdem.emProducao);
      expect(FiltroEstadoOrdem.emHold.estado, EstadoOrdem.emHold);
      expect(FiltroEstadoOrdem.concluida.estado, EstadoOrdem.concluida);
      expect(FiltroEstadoOrdem.cancelada.estado, EstadoOrdem.cancelada);
    });

    test('existe um filtro para cada estado, mais o "todos"', () {
      final cobertos =
          FiltroEstadoOrdem.values.map((f) => f.estado).whereType<EstadoOrdem>().toSet();
      expect(cobertos, EstadoOrdem.values.toSet());
      expect(FiltroEstadoOrdem.values.length, EstadoOrdem.values.length + 1);
    });
  });
}
