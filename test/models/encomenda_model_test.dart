import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/encomenda_model.dart';
import 'package:gestao_producao_fabrica/models/estado_ordem.dart';

/// O modelo anterior declarava tudo obrigatório e usava `as int` / `as String`
/// diretos, pelo que rebentava em qualquer ordem concluída (`fase_atual_id` é
/// nulo). Os testes de campos nulos abaixo são a rede de segurança contra a
/// regressão para esse comportamento.
void main() {
  group('EncomendaModel.fromJson — mínimo', () {
    test('só com id: nenhum campo obrigatório em falta rebenta', () {
      final e = EncomendaModel.fromJson({'id': 1});

      expect(e.id, 1);
      expect(e.createdAt, isNull);
      expect(e.codigoRastreio, isNull);
      expect(e.dataEntrega, isNull);
      expect(e.clienteId, isNull);
      expect(e.tipoProdutoId, isNull);
      expect(e.faseAtualId, isNull);
      expect(e.observacoes, isNull);
      expect(e.motivoCancelamento, isNull);
      expect(e.dataCancelamento, isNull);
      expect(e.nomeCliente, isNull);
      expect(e.nomeProduto, isNull);
      expect(e.nomeFaseAtual, isNull);
      expect(e.ordemFaseAtual, isNull);
      expect(e.postoFaseAtual, isNull);
      expect(e.postoFaseAtualId, isNull);
    });

    test('valores por omissão quando os campos vêm nulos', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'quantidade': null,
        'prioridade': null,
        'cancelada': null,
        'em_suspenso': null,
        'incidencias': null,
      });

      expect(e.quantidade, 1);
      expect(e.prioridade, 'Normal');
      expect(e.cancelada, isFalse);
      expect(e.emSuspenso, isFalse);
      expect(e.incidencias, isEmpty);
    });

    test('ordem concluída (fase_atual_id nulo) — o caso que rebentava', () {
      final e = EncomendaModel.fromJson({
        'id': 42,
        'fase_atual_id': null,
        'fase_atual': null,
        'cancelada': false,
        'em_suspenso': false,
      });

      expect(e.faseAtualId, isNull);
      expect(e.estado, EstadoOrdem.concluida);
    });
  });

  group('EncomendaModel.fromJson — conversões tolerantes', () {
    test('inteiros aceites como int, double e String', () {
      expect(EncomendaModel.fromJson({'id': 7}).id, 7);
      expect(EncomendaModel.fromJson({'id': 7.0}).id, 7);
      expect(EncomendaModel.fromJson({'id': '7'}).id, 7);
      expect(EncomendaModel.fromJson({'id': 1, 'quantidade': '250'}).quantidade, 250);
    });

    test('quantidade ilegível cai no valor por omissão em vez de rebentar', () {
      expect(EncomendaModel.fromJson({'id': 1, 'quantidade': 'abc'}).quantidade, 1);
    });

    test('datas: ISO válida, DateTime já convertido, texto inválido', () {
      final valida = EncomendaModel.fromJson({'id': 1, 'data_entrega': '2026-03-15'});
      expect(valida.dataEntrega, DateTime(2026, 3, 15));

      final jaDateTime = EncomendaModel.fromJson({
        'id': 1,
        'data_entrega': DateTime(2026, 3, 15),
      });
      expect(jaDateTime.dataEntrega, DateTime(2026, 3, 15));

      final invalida = EncomendaModel.fromJson({'id': 1, 'data_entrega': 'não é data'});
      expect(invalida.dataEntrega, isNull);
    });
  });

  group('EncomendaModel.fromJson — junções', () {
    test('fase atual pelo alias fase_atual', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'fase_atual_id': 9,
        'fase_atual': {
          'nome_fase_padrao': 'Corte',
          'ordem': 2,
          'posto_trabalho': 'Serra 1',
          'posto_trabalho_id': 5,
        },
      });

      expect(e.nomeFaseAtual, 'Corte');
      expect(e.ordemFaseAtual, 2);
      expect(e.postoFaseAtual, 'Serra 1');
      expect(e.postoFaseAtualId, 5);
    });

    test('fase atual pelo alias fases_padrao (ecrã de postos)', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'fases_padrao': {'nome_fase_padrao': 'Pintura', 'ordem': 3},
      });

      expect(e.nomeFaseAtual, 'Pintura');
      expect(e.ordemFaseAtual, 3);
    });

    test('junção devolvida como lista de um elemento é desembrulhada', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'clientes': [
          {'nome_cliente': 'Fábrica Norte'},
        ],
        'tipos_produto': [
          {'nome_tipo_produto': 'Cadeira'},
        ],
      });

      expect(e.nomeCliente, 'Fábrica Norte');
      expect(e.nomeProduto, 'Cadeira');
    });

    test('junção como lista vazia não rebenta', () {
      final e = EncomendaModel.fromJson({'id': 1, 'clientes': [], 'fase_atual': []});

      expect(e.nomeCliente, isNull);
      expect(e.nomeFaseAtual, isNull);
    });

    test('incidências: elementos não-mapa são descartados', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'incidencias': [
          {'id': 1, 'line_clearance_validado': true},
          'lixo',
          {'id': 2, 'line_clearance_validado': false},
        ],
      });

      expect(e.incidencias.length, 2);
      expect(e.incidenciaAtiva?['id'], 2);
    });

    test('incidenciaAtiva é nula quando todas têm line clearance', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'incidencias': [
          {'id': 1, 'line_clearance_validado': true},
        ],
      });

      expect(e.incidenciaAtiva, isNull);
    });
  });

  group('EncomendaModel.estado', () {
    EncomendaModel comColunas({
      bool cancelada = false,
      bool emSuspenso = false,
      int? faseAtualId,
    }) =>
        EncomendaModel.fromJson({
          'id': 1,
          'cancelada': cancelada,
          'em_suspenso': emSuspenso,
          'fase_atual_id': faseAtualId,
        });

    test('segue a mesma precedência de EstadoOrdem.derivar', () {
      expect(comColunas(faseAtualId: 3).estado, EstadoOrdem.emProducao);
      expect(comColunas().estado, EstadoOrdem.concluida);
      expect(comColunas(emSuspenso: true, faseAtualId: 3).estado, EstadoOrdem.emHold);
      expect(
        comColunas(cancelada: true, emSuspenso: true, faseAtualId: 3).estado,
        EstadoOrdem.cancelada,
      );
    });
  });

  group('EncomendaModel.dataEntregaIso', () {
    test('nulo quando não há data de entrega', () {
      expect(EncomendaModel.fromJson({'id': 1}).dataEntregaIso, isNull);
    });

    test('mês e dia com zero à esquerda', () {
      final e = EncomendaModel.fromJson({'id': 1, 'data_entrega': '2026-03-05'});
      expect(e.dataEntregaIso, '2026-03-05');
    });

    test('descarta a hora que o Postgres devolveria', () {
      final e = EncomendaModel.fromJson({
        'id': 1,
        'data_entrega': '2026-12-31T23:45:00',
      });
      expect(e.dataEntregaIso, '2026-12-31');
    });
  });

  group('EncomendaModel.progressoNoRoteiro', () {
    EncomendaModel ordem({int? faseAtualId, int? tipoProdutoId, int? ordemFase}) =>
        EncomendaModel.fromJson({
          'id': 1,
          'fase_atual_id': faseAtualId,
          'tipos_produtos_id': tipoProdutoId,
          if (ordemFase != null) 'fase_atual': {'ordem': ordemFase},
        });

    test('sem fase atual está a 100%', () {
      expect(ordem().progressoNoRoteiro(0), 1.0);
      expect(ordem().progressoNoRoteiro(5), 1.0);
    });

    test('primeira fase de um roteiro de 4 está a 0%', () {
      expect(
        ordem(faseAtualId: 1, tipoProdutoId: 2, ordemFase: 1).progressoNoRoteiro(4),
        0.0,
      );
    });

    test('terceira fase de um roteiro de 4 está a 50%', () {
      expect(
        ordem(faseAtualId: 3, tipoProdutoId: 2, ordemFase: 3).progressoNoRoteiro(4),
        0.5,
      );
    });

    test('última fase de um roteiro de 4 está a 75% — ainda não concluiu', () {
      expect(
        ordem(faseAtualId: 4, tipoProdutoId: 2, ordemFase: 4).progressoNoRoteiro(4),
        0.75,
      );
    });

    test('roteiro por carregar devolve 0.0, não uma divisão por zero', () {
      expect(
        ordem(faseAtualId: 1, tipoProdutoId: 2, ordemFase: 1).progressoNoRoteiro(0),
        0.0,
      );
    });

    test('produto desconhecido devolve 0.0', () {
      expect(ordem(faseAtualId: 1, ordemFase: 2).progressoNoRoteiro(4), 0.0);
    });

    test('ordem da fase desconhecida devolve 0.0', () {
      expect(ordem(faseAtualId: 1, tipoProdutoId: 2).progressoNoRoteiro(4), 0.0);
    });

    test('resultado nunca sai do intervalo [0, 1]', () {
      // Roteiro reduzido depois da ordem já ter avançado: sem o clamp a barra
      // passaria dos 100%.
      final avancada = ordem(faseAtualId: 9, tipoProdutoId: 2, ordemFase: 9);
      expect(avancada.progressoNoRoteiro(2), 1.0);

      // Ordem 0 (dados inconsistentes) daria um valor negativo.
      final ordemZero = ordem(faseAtualId: 9, tipoProdutoId: 2, ordemFase: 0);
      expect(ordemZero.progressoNoRoteiro(4), 0.0);
    });
  });

  group('EncomendaModel.cumpriuPrazo', () {
    test('entrega antes do prazo', () {
      expect(
        EncomendaModel.cumpriuPrazo(DateTime(2026, 5, 10), DateTime(2026, 5, 8)),
        isTrue,
      );
    });

    test('entrega no próprio dia do prazo conta como no prazo', () {
      expect(
        EncomendaModel.cumpriuPrazo(DateTime(2026, 5, 10), DateTime(2026, 5, 10)),
        isTrue,
      );
    });

    test('entrega ao fim do dia do prazo continua no prazo — compara ao dia', () {
      expect(
        EncomendaModel.cumpriuPrazo(
          DateTime(2026, 5, 10, 8, 0),
          DateTime(2026, 5, 10, 23, 59),
        ),
        isTrue,
      );
    });

    test('entrega no dia seguinte está atrasada, mesmo de madrugada', () {
      expect(
        EncomendaModel.cumpriuPrazo(
          DateTime(2026, 5, 10, 23, 0),
          DateTime(2026, 5, 11, 0, 1),
        ),
        isFalse,
      );
    });

    test('sem prazo prometido não conta como cumprido', () {
      expect(EncomendaModel.cumpriuPrazo(null, DateTime(2026, 5, 10)), isFalse);
    });

    test('atravessa a fronteira do mês e do ano', () {
      expect(
        EncomendaModel.cumpriuPrazo(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
        isFalse,
      );
      expect(
        EncomendaModel.cumpriuPrazo(DateTime(2027, 1, 1), DateTime(2026, 12, 31)),
        isTrue,
      );
    });
  });
}
