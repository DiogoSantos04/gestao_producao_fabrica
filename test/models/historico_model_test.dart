import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/historico_model.dart';

void main() {
  group('HistoricoModel.fromJson — campos nulos', () {
    test('só com id: todas as colunas anuláveis ficam nulas', () {
      final h = HistoricoModel.fromJson({'id': 1});

      expect(h.id, 1);
      expect(h.createdAt, isNull);
      expect(h.encomendaId, isNull);
      expect(h.faseConcluidaId, isNull);
      expect(h.utilizadorId, isNull);
      expect(h.dataConclusao, isNull);
      expect(h.nomeFase, isNull);
      expect(h.ordemFase, isNull);
      expect(h.nomeUtilizador, isNull);
    });

    test('campos completos', () {
      final h = HistoricoModel.fromJson({
        'id': 5,
        'created_at': '2026-02-01T08:00:00',
        'encomenda_id': 42,
        'fase_concluida_id': 9,
        'utilizador_id': 'uuid-1',
        'data_conclusao': '2026-02-01T17:30:00',
      });

      expect(h.encomendaId, 42);
      expect(h.faseConcluidaId, 9);
      expect(h.utilizadorId, 'uuid-1');
      expect(h.dataConclusao, DateTime(2026, 2, 1, 17, 30));
    });

    test('datas inválidas ficam nulas em vez de rebentar', () {
      final h = HistoricoModel.fromJson({
        'id': 1,
        'created_at': '',
        'data_conclusao': 'não é data',
      });

      expect(h.createdAt, isNull);
      expect(h.dataConclusao, isNull);
    });
  });

  group('HistoricoModel — junções', () {
    test('fase e utilizador embebidos', () {
      final h = HistoricoModel.fromJson({
        'id': 1,
        'fases_padrao': {'nome_fase_padrao': 'Corte', 'ordem': 1},
        'utilizadores': {'nome_utilizador': 'Ana Lima'},
      });

      expect(h.nomeFase, 'Corte');
      expect(h.ordemFase, 1);
      expect(h.nomeUtilizador, 'Ana Lima');
    });

    test('junções nulas deixam os campos nulos', () {
      final h = HistoricoModel.fromJson({
        'id': 1,
        'fases_padrao': null,
        'utilizadores': null,
      });

      expect(h.nomeFase, isNull);
      expect(h.ordemFase, isNull);
      expect(h.nomeUtilizador, isNull);
    });

    test('junção que não é mapa é ignorada', () {
      final h = HistoricoModel.fromJson({'id': 1, 'fases_padrao': []});
      expect(h.nomeFase, isNull);
    });
  });

  group('HistoricoModel.momento', () {
    test('prefere a data de conclusão', () {
      final h = HistoricoModel.fromJson({
        'id': 1,
        'created_at': '2026-02-01T08:00:00',
        'data_conclusao': '2026-02-01T17:30:00',
      });
      expect(h.momento, DateTime(2026, 2, 1, 17, 30));
    });

    test('recorre ao created_at quando a conclusão não foi registada', () {
      final h = HistoricoModel.fromJson({
        'id': 1,
        'created_at': '2026-02-01T08:00:00',
      });
      expect(h.momento, DateTime(2026, 2, 1, 8));
    });

    test('nulo quando não há nenhuma das duas', () {
      expect(HistoricoModel.fromJson({'id': 1}).momento, isNull);
    });
  });
}
